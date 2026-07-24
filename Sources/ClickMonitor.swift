import Cocoa
import QuartzCore

/// 시스템 전역 마우스 클릭 감시. 사용자가 어디를 클릭하든
/// (활성 IME 클라이언트 밖 포함) 현재 조합 중인 글자를 선제 커밋한다.
/// Chromium 계열(VSCode 등)에서 포커스 변경 시 조합 중복("안녕녕")을 막기 위함.
final class ClickMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // 콜백이 느리거나 권한이 해제되면 시스템이 비활성화할 수 있음.
                // 이벤트는 통과시키고, 나중에 재시작으로 복구.
                return Unmanaged.passUnretained(event)
            }
            // IME가 유휴 상태이거나 영문 모드일 때는 할 일이 없으므로 nil 체크만.
            guard let controller = HangulInputController.current else {
                return Unmanaged.passUnretained(event)
            }
            DebugLogger.shared.notice("ClickMonitor fire type=\(type.rawValue)")
            // insertText를 탭 콜백 안에서 동기 호출하면 포커스 변경 중인 클라이언트와
            // 재진입 위험이 있으므로, 다음 메인 루프 턴으로 비동기 처리.
            DispatchQueue.main.async {
                controller.commitCurrent()
            }
            return Unmanaged.passUnretained(event)
        }

        // .cgSessionEventTap 사용 (GlobalKeyTap과 동일 레벨).
        // .cghidEventTap는 더 강력한 Input Monitoring 권한이 필요해 여기선 실패함.
        // .listenOnly: 관찰만 하고 이벤트를 수정/삼키지 않음.
        guard let machPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            NSLog("ra1nIME: ClickMonitor.tapCreate failed — grant Input Monitoring permission")
            return
        }

        self.tap = machPort
        self.source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)
        NSLog("ra1nIME: ClickMonitor installed at session level")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        if let source {
            CFRunLoopSourceInvalidate(source)
            self.source = nil
        }
    }
}
