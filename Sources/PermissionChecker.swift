import Cocoa
import IOKit.hid
import ApplicationServices

/// 설정 창과 실행 시 권한 알림에서 동일한 URL을 사용.
enum SystemSettingsURL {
    static let inputMonitoring  = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    static let accessibility    = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}

enum PermissionChecker {

    static func inputMonitoringGranted() -> Bool {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func accessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 실행 직후 호출. 입력 모니터링 또는 손쉬운 사용 권한이 없으면
    /// 알림창을 띄우고 확인 시 해당 설정 패널을 연다.
    static func checkAndPrompt(globalTapFailed: Bool = false) {
        let accessGranted = accessibilityGranted()

        // 1. 입력 모니터링 권한만 없는 경우 (손쉬운 사용은 부여됨)
        if globalTapFailed && accessGranted {
            showCustomAlert(missingInputMonitoring: true, missingAccessibility: false)
            return
        }

        // 2. 손쉬운 사용 권한만 없는 경우 (입력 모니터링은 정상)
        if !globalTapFailed && !accessGranted {
            // 시스템 프롬프트(OS 네이티브 팝업)만 띄우고 앱 자체 커스텀 알림은 띄우지 않음.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }

        // 3. 둘 다 없는 경우
        if globalTapFailed && !accessGranted {
            // 시스템 프롬프트는 띄우지 않고(false) 목록에 등록만 한 뒤,
            // 앱 커스텀 알림창에서 두 권한이 모두 필요하다고 통합 안내함.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            showCustomAlert(missingInputMonitoring: true, missingAccessibility: true)
            return
        }
    }

    private static func showCustomAlert(missingInputMonitoring: Bool, missingAccessibility: Bool) {
        var missing: [(name: String, url: URL)] = []
        if missingInputMonitoring {
            missing.append((name: "입력 모니터링 (Input Monitoring)", url: SystemSettingsURL.inputMonitoring))
        }
        if missingAccessibility {
            missing.append((name: "손쉬운 사용 (Accessibility)", url: SystemSettingsURL.accessibility))
        }

        guard !missing.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "ra1n IME 권한 필요"
        let bullets = missing.map { "• " + $0.name }.joined(separator: "\n")
        alert.informativeText = """
            한영 토글 키가 시스템 전역에서 동작하려면 다음 권한이 필요합니다:

            \(bullets)

            ⚠️ 입력 모니터링은 자동으로 추가되지 않습니다.
            "시스템 설정 열기"를 눌러 이동한 뒤, 화면 하단의 ＋ 버튼을 누르고
            /Library/Input Methods/ra1nIME.app 를 직접 선택해 추가해주세요.
            """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let first = missing.first {
            NSWorkspace.shared.open(first.url)
        }
    }
}
