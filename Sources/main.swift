import Cocoa
import Carbon
import InputMethodKit

let kConnectionName = "kr.ra1n.inputmethod.ra1nime_Connection"
let bundleId = Bundle.main.bundleIdentifier ?? "kr.ra1n.inputmethod.ra1nime"

let server = IMKServer(name: kConnectionName, bundleIdentifier: bundleId)
_ = server

final class AppDelegate: NSObject, NSApplicationDelegate {
    var globalTap: GlobalKeyTap?
    var clickMonitor: ClickMonitor?
    var statusBar: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
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
