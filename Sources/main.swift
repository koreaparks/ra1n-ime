import Cocoa
import Carbon
import InputMethodKit

let kConnectionName = "kr.ra1n.inputmethod.ra1nime_Connection"
let bundleId = Bundle.main.bundleIdentifier ?? "kr.ra1n.inputmethod.ra1nime"

// pkg 설치 직후 postinstall이 `--setup` 인자로 실행하는 설정 도우미 모드.
// 이 모드에서는 IMKServer를 만들지 않아(입력기 인스턴스와 충돌 방지) 도우미 창만 띄운다.
let isSetupMode = CommandLine.arguments.contains("--setup")

/// 이미 실행 중인 입력기 인스턴스가 있고 이 프로세스가 나중에 뜬 쪽이면 true.
///
/// 중복 인스턴스는 `IMKServer` 연결 등록에 실패해도 프로세스가 살아남아
/// 자기 상태 표시줄 아이콘과 자기 `CurrentMode` 싱글톤을 갖는다. 전역 키 탭은
/// `headInsertEventTap`이라 나중에 뜬 쪽이 토글 키를 독점하므로, 아이콘은 바뀌지만
/// 실제 입력을 처리하는 인스턴스의 모드는 그대로인 상태가 만들어진다. 더 나쁜
/// 경우 다른 앱의 IMK 클라이언트 연결을 가로채고, 그 인스턴스가 사라지면 해당
/// 앱의 키 입력이 통째로 유실된다(한글·영문·방향키 전부).
///
/// launchDate가 이른 쪽을 살린다. 먼저 뜬 인스턴스가 IMKServer 연결을 소유하고
/// 있을 가능성이 높기 때문이다. 같은 시각이면 pid로 순서를 정해 양쪽이 동시에
/// 물러나는 일을 막는다.
func shouldYieldToRunningInstance() -> Bool {
    let myPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        .filter { $0.processIdentifier != myPID }
    guard !others.isEmpty else { return false }

    // 자신의 실행 시각을 알 수 없으면 가장 늦게 뜬 쪽으로 취급해 물러난다.
    let myLaunch = NSRunningApplication.current.launchDate ?? .distantFuture
    return others.contains { other in
        guard let theirLaunch = other.launchDate else { return true }
        if theirLaunch != myLaunch { return theirLaunch < myLaunch }
        return other.processIdentifier < myPID
    }
}

// 설정 도우미(--setup)는 IMKServer를 만들지 않는 별개 용도이므로 이 검사에서 제외.
// pkg 설치 직후 입력기 인스턴스가 이미 떠 있는 상태로 실행되는 것이 정상이다.
if !isSetupMode, shouldYieldToRunningInstance() {
    DebugLogger.shared.event(
        "중복 인스턴스 감지 — 종료 (pid=\(ProcessInfo.processInfo.processIdentifier))")
    exit(0)
}

let server: IMKServer? = isSetupMode ? nil : IMKServer(name: kConnectionName, bundleIdentifier: bundleId)

// 연결 등록에 실패한 채로 계속 실행되면 위에 적은 좀비 인스턴스가 된다.
// 살아남아도 입력을 처리할 수 없으므로 즉시 물러난다.
if !isSetupMode, server == nil {
    DebugLogger.shared.event("IMKServer 생성 실패 — 종료")
    exit(1)
}
_ = server

final class AppDelegate: NSObject, NSApplicationDelegate {
    var globalTap: GlobalKeyTap?
    var clickMonitor: ClickMonitor?
    var statusBar: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 설정 도우미 모드: 일반 앱 창으로 승격해 도우미만 표시하고 입력기 초기화는 건너뜀.
        if isSetupMode {
            NSApp.setActivationPolicy(.regular)
            SetupAssistantController.shared.show()
            return
        }

        globalTap = GlobalKeyTap()
        let tapStarted = globalTap?.start() ?? false
        clickMonitor = ClickMonitor()
        clickMonitor?.start()
        statusBar = StatusBarController()

        // 시스템 입력 소스가 우리 것으로 전환될 때(한국어 IME, ABC 등에서)
        // 한글 모드로 시작할지 여부를 결정.
        // 관찰만 하며 TISSelectInputSource를 직접 호출하지 않음.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil)

        // 메뉴 바가 나타난 뒤 권한 확인을 지연시켜,
            // 실행 직후 경고창으로 사용자를 놀라게 하지 않음.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            PermissionChecker.checkAndPrompt(globalTapFailed: !tapStarted)
        }
    }

    @objc func inputSourceChanged() {
        guard Preferences.shared.activateInKorean else { return }
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else {
            return
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        // 등록된 입력 소스 ID는 모두 번들 ID로 시작.
        if sourceID.hasPrefix(bundleId) {
            CurrentMode.shared.set(.korean)
        }
    }
}

// NSApplication.shared를 직접 사용. NSApp을 .shared보다 먼저 참조하면
// nil이 되어 첫 접근 시 크래시가 발생할 수 있음.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
