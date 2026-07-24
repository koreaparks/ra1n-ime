import Cocoa
import Carbon

// HangulInputController에서도 동일한 태그를 사용해
// 재주입한 이벤트를 걸러낸다.
private let kSyntheticTag: Int64 = 0x5241314E494D45  // "RA1NIME" ASCII

/// 시스템 전역 CGEventTap. 모든 키 입력을 감시하여 사용자가 지정한
/// 한영 토글 키가 눌리면 한/영 전환을 실행한다.
/// IMK의 per-controller 핸들러보다 먼저 동작하므로, 어떤 앱이 포커스를
/// 가지고 있든 토글 키가 작동한다.
///
/// 단, Input Monitoring 권한이 필요하다. 권한이 없으면 start()가 실패하고
/// 포커스가 있는 텍스트 필드에서만 IMK handle() 경로로 동작한다.
///
/// 참고: Karabiner-Elements 등은 드라이버 레벨에서 이벤트를 변경하므로
/// 이 탭에서는 이미 Karabiner가 적용된 이벤트만 볼 수 있다.
final class GlobalKeyTap {
    /// KeyRecorderView가 녹화 중일 때 true. 녹화 중에는 토글 키가
    /// 자기 자신을 다시 발동하지 않도록 이벤트를 통과시킨다.
    static var isRecordingActive: Bool = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 토글 키(예: Right ⌘)가 물리적으로 눌려 있는 동안 true.
    /// 눌림 순간에 토글을 발동하고 flagsChanged 이벤트를 삼킨다.
    /// 키가 눌린 상태에서 다른 키가 눌리면 해당 이벤트에서 토글 키의
    /// modifier 플래그를 제거해 ⌘+A가 일반 A로 전달되게 한다.
    private var bindingModHeld: Bool = false

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let machPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, type, event, info) -> Unmanaged<CGEvent>? in
                guard let info = info else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<GlobalKeyTap>.fromOpaque(info).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: userInfo)
        else {
            NSLog("ra1nIME: CGEvent.tapCreate failed — grant Input Monitoring to ra1nIME.app")
            return false
        }

        self.tap = machPort
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)
        NSLog("ra1nIME: GlobalKeyTap installed at session level")
        return true
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if GlobalKeyTap.isRecordingActive { return pass }

        // 콜백이 느리거나 권한이 해제되면 탭이 비활성화될 수 있음. 방어적으로 재활성화.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let binding = Preferences.shared.toggleBinding
        // 토글 키가 비어 있으면 모든 이벤트를 그대로 통과.
        guard !binding.isEmpty else { return pass }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

        // 복구: 포커스 변경이나 절전 등으로 modifier 해제를 놓쳤을 때
        // 플래그 상태를 보고 즉시 복구.
        if bindingModHeld, binding.kind == .modifierTap,
           !KeyBinding.isModifierKeyDown(binding.keyCode, in: flags) {
            bindingModHeld = false
        }

        switch type {
        case .flagsChanged:
            guard KeyBinding.isModifierKey(kc) else { return pass }
            let isDown = KeyBinding.isModifierKeyDown(kc, in: flags)

            if binding.kind == .modifierTap, binding.keyCode == kc {
                // 눌림 순간에 토글 발동. 이후 해제까지 양쪽 이벤트를 삼켜
                // OS가 modifier 전환을 감지하지 못하게 한다.
                if isDown {
                    bindingModHeld = true
                    DispatchQueue.main.async { Self.fireToggle() }
                } else {
                    bindingModHeld = false
                }
                return nil
            }

            // 토글 키가 눌린 상태에서 다른 modifier가 눌리면
            // 해당 modifier의 플래그에서 토글 키 비트를 제거.
            if bindingModHeld, binding.kind == .modifierTap {
                stripBindingModFlags(from: event, kc: binding.keyCode)
            }
            return pass

        case .keyDown:
            // Karabiner가 가끔 보내는 sentinel 키. 무시.
            if kc == 0xFFFF { return pass }

            // 토글 modifier가 눌린 상태에서는 후속 이벤트에서
            // 해당 modifier 비트를 제거해 단축키 오동작을 막는다.
            if bindingModHeld, binding.kind == .modifierTap {
                stripBindingModFlags(from: event, kc: binding.keyCode)
            }

            if binding.matchesCombo(keyCode: kc,
                                    rawFlags: UInt(event.flags.rawValue),
                                    distinguishSided: Preferences.shared.distinguishSidedModifiers) {
                DispatchQueue.main.async { Self.fireToggle() }
                return nil  // 삼킴
            }
            return pass

        default:
            return pass
        }
    }

    /// 이벤트 플래그에서 토글 키의 modifier 비트를 제거.
    /// 반대쪽 modifier(예: Left⌘)가 동시에 눌려 있지 않을 때만
    /// generic 비트(⌘)도 제거한다.
    private func stripBindingModFlags(from event: CGEvent, kc: UInt16) {
        let (dev, otherDev, gen) = KeyBinding.modifierFlagBits(kc)
        if dev == 0 { return }  // Caps Lock 등은 제거할 것 없음
        var f = event.flags.rawValue
        f &= ~dev
        if (f & otherDev) == 0 {
            f &= ~gen
        }
        event.flags = CGEventFlags(rawValue: f)
    }

    // MARK: - Toggle action

    static func fireToggle() {
        let switchToSelf = Preferences.shared.switchToSelfOnToggle
        let isOurs = isCurrentSourceRa1nIME()
        NSLog("ra1nIME: fireToggle switchToSelf=\(switchToSelf) isOurs=\(isOurs)")

        if switchToSelf, !isOurs {
            NSLog("ra1nIME: attempting TISSelectInputSource")
            activateRa1nIME()
            CurrentMode.shared.set(.korean)
            return
        }

        CurrentMode.shared.toggle()
    }

    // MARK: - Input source switching

    private static func isCurrentSourceRa1nIME() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else {
            return false
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        return sourceID.hasPrefix(bundleId)
    }

    private static func activateRa1nIME() {
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else {
            NSLog("ra1nIME: TISCreateInputSourceList returned nil")
            return
        }
        let count = CFArrayGetCount(list)
        NSLog("ra1nIME: TISCreateInputSourceList count=\(count)")
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: TISInputSource.self)
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            NSLog("ra1nIME: source #\(i) id=\(sourceID)")
            if sourceID.hasPrefix(bundleId) {
                let err = TISSelectInputSource(source)
                NSLog("ra1nIME: TISSelectInputSource called for \(sourceID), err=\(err)")
                refreshInputContext()
                return
            }
        }
        NSLog("ra1nIME: no source matched bundleId \(bundleId)")
    }

    /// 입력 소스를 전환해도 현재 포커스 클라이언트는 다음 포커스 변경 전까지
    /// 이전 IME와 계속 통신할 수 있다. 아무 효과 없는 키 이벤트를 보내
    /// NSTextInputContext가 활성 입력 소스를 즉시 재평가하도록 유도.
    private static func refreshInputContext() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let key: CGKeyCode = 0x3F // Function 키 — 대부분의 앱이 무시
        if let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            down.setIntegerValueField(.eventSourceUserData, value: kSyntheticTag)
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            up.setIntegerValueField(.eventSourceUserData, value: kSyntheticTag)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
        NSLog("ra1nIME: refreshInputContext sent synthetic Function key")
    }
}
