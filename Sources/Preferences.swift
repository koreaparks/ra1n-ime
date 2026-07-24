import Cocoa
import Carbon

enum InputMode: String, CaseIterable {
    case korean, english
}

// MARK: - KeyBinding

/// 한영 토글 트리거.
///
/// - `modifierTap`: 단일 modifier 키(예: Right ⌘)를 단독으로 눌렀다 뗌.
///   keyCode로 좌/우 구분; modifiers는 사용하지 않음(0).
/// - `keyCombo`: 일반 키에 modifier 조합(예: ⇧+Space, F13, ⌘+Tab).
///   modifiers는 generic 비트(좌/우 무관)를 저장해
///   어떤 Shift를 눌러도 동일하게 동작.
struct KeyBinding: Codable, Equatable {
    enum Kind: String, Codable {
        case modifierTap
        case keyCombo
    }
    let kind: Kind
    let keyCode: UInt16
    let modifiers: UInt
    /// 녹화 시점의 물리적 modifier L/R 비트(L⇧=0x02, R⇧=0x04, L⌘=0x08, R⌘=0x10, …).
    /// 0이면 좌/우 구분 기능 이전의 구형 바인딩 — generic 매칭으로 폴백.
    let deviceModifiers: UInt

    init(kind: Kind, keyCode: UInt16, modifiers: UInt, deviceModifiers: UInt = 0) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.deviceModifiers = deviceModifiers
    }

    enum CodingKeys: String, CodingKey {
        case kind, keyCode, modifiers, deviceModifiers
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        self.modifiers = try c.decode(UInt.self, forKey: .modifiers)
        self.deviceModifiers = try c.decodeIfPresent(UInt.self, forKey: .deviceModifiers) ?? 0
    }

    static let defaultBinding = KeyBinding(kind: .modifierTap, keyCode: 0x36, modifiers: 0)
    /// "토글 키 없음"을 나타내는 sentinel.
    static let empty = KeyBinding(kind: .keyCombo, keyCode: 0xFFFF, modifiers: 0)
    var isEmpty: Bool { keyCode == 0xFFFF }

    static let genericModifierMask: UInt =
        NSEvent.ModifierFlags([.shift, .control, .option, .command, .function]).rawValue
    /// IOKit이 물리적 modifier의 L/R을 저장하는 하위 비트.
    /// distinguishSidedModifiers가 켜져 있을 때 엄격 비교에 사용.
    static let deviceModifierMask: UInt = 0x10 | 0x08 | 0x04 | 0x02 | 0x40 | 0x20 | 0x2000 | 0x01
}

extension KeyBinding {

    // --- Modifier key helpers ---

    static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E, 0x39]

    static func isModifierKey(_ kc: UInt16) -> Bool { modifierKeyCodes.contains(kc) }

    /// 해당 modifier keyCode가 flags에서 현재 눌려 있는지 확인.
    /// device-specific 비트를 사용해 좌/우 구분.
    static func isModifierKeyDown(_ kc: UInt16, in flags: NSEvent.ModifierFlags) -> Bool {
        let raw = flags.rawValue
        switch kc {
        case 0x36: return (raw & 0x0010) != 0  // R-Cmd
        case 0x37: return (raw & 0x0008) != 0  // L-Cmd
        case 0x38: return (raw & 0x0002) != 0  // L-Shift
        case 0x3C: return (raw & 0x0004) != 0  // R-Shift
        case 0x3A: return (raw & 0x0020) != 0  // L-Option
        case 0x3D: return (raw & 0x0040) != 0  // R-Option
        case 0x3B: return (raw & 0x0001) != 0  // L-Control
        case 0x3E: return (raw & 0x2000) != 0  // R-Control
        case 0x39: return flags.contains(.capsLock)
        default:   return false
        }
    }

    /// modifier 키의 플래그 비트 3종을 반환:
    /// (deviceSpecific, otherSideDevice, generic).
    /// generic(예: ⌘)는 양쪽을 모두 포함하므로,
    /// 반대쪽 modifier가 따로 눌려 있지 않을 때만 제거.
    /// Right⌘이 토글 키일 때 Left⌘+조합은 계속 동작하게 함.
    static func modifierFlagBits(_ kc: UInt16) -> (UInt64, UInt64, UInt64) {
        switch kc {
        case 0x36: return (0x10,   0x08,   0x100000)  // R-⌘ / L-⌘ / ⌘
        case 0x37: return (0x08,   0x10,   0x100000)  // L-⌘ / R-⌘
        case 0x38: return (0x02,   0x04,   0x20000)   // L-⇧ / R-⇧ / ⇧
        case 0x3C: return (0x04,   0x02,   0x20000)   // R-⇧ / L-⇧
        case 0x3A: return (0x20,   0x40,   0x80000)   // L-⌥ / R-⌥ / ⌥
        case 0x3D: return (0x40,   0x20,   0x80000)   // R-⌥ / L-⌥
        case 0x3B: return (0x01,   0x2000, 0x40000)   // L-⌃ / R-⌃ / ⌃
        case 0x3E: return (0x2000, 0x01,   0x40000)   // R-⌃ / L-⌃
        default:   return (0, 0, 0)                   // Caps Lock & unknown
        }
    }

    static func modifierKeyName(_ kc: UInt16) -> String {
        switch kc {
        case 0x36: return "Right ⌘"
        case 0x37: return "Left ⌘"
        case 0x38: return "Left ⇧"
        case 0x3C: return "Right ⇧"
        case 0x3A: return "Left ⌥"
        case 0x3D: return "Right ⌥"
        case 0x3B: return "Left ⌃"
        case 0x3E: return "Right ⌃"
        case 0x39: return "Caps Lock"
        default:   return "Key 0x\(String(kc, radix: 16))"
        }
    }

    // --- Regular key helpers ---

    static func regularKeyName(_ kc: UInt16) -> String {
        switch Int(kc) {
        case kVK_Space:           return "Space"
        case kVK_Return:          return "↩"
        case kVK_ANSI_KeypadEnter:return "⌤"
        case kVK_Tab:             return "⇥"
        case kVK_Escape:          return "⎋"
        case kVK_Delete:          return "⌫"
        case kVK_ForwardDelete:   return "⌦"
        case kVK_LeftArrow:       return "←"
        case kVK_RightArrow:      return "→"
        case kVK_DownArrow:       return "↓"
        case kVK_UpArrow:         return "↑"
        case kVK_F1:  return "F1"; case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"; case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"; case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"; case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"; case kVK_F10: return "F10"
        case kVK_F11: return "F11";case kVK_F12: return "F12"
        case kVK_F13: return "F13";case kVK_F14: return "F14"
        case kVK_F15: return "F15";case kVK_F16: return "F16"
        case kVK_F17: return "F17";case kVK_F18: return "F18"
        case kVK_F19: return "F19";case kVK_F20: return "F20"
        case kVK_JIS_Eisu:        return "英数"
        case kVK_JIS_Kana:        return "かな"
        default: break
        }
        if let s = unicodeForKey(kc), !s.isEmpty {
            return s.uppercased()
        }
        return "Key 0x\(String(kc, radix: 16))"
    }

    /// 현재 ASCII 키보드 레이아웃에서 keyCode를 대응 문자로 변환.
    /// 예: keyCode 0 → "A" ("Key 0x0" 대신).
    private static func unicodeForKey(_ kc: UInt16) -> String? {
        guard let src = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let raw = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let kbType = UInt32(LMGetKbdType())
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var charCount = 0
        let status = layoutData.withUnsafeBytes { buf -> OSStatus in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(ptr, kc, UInt16(kUCKeyActionDisplay), 0,
                                  kbType, OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, 4, &charCount, &chars)
        }
        if status == noErr, charCount > 0 {
            return String(utf16CodeUnits: chars, count: charCount)
        }
        return nil
    }

    // --- Display string ---

    var displayString: String {
        if isEmpty { return "없음" }
        let hex = String(format: "0x%X", keyCode)
        switch kind {
        case .modifierTap:
            return "\(KeyBinding.modifierKeyName(keyCode))  (탭, kc=\(hex))"
        case .keyCombo:
            let sided = Preferences.shared.distinguishSidedModifiers && deviceModifiers != 0
            let mods = sided
                ? KeyBinding.sidedModifierString(generic: modifiers, device: deviceModifiers)
                : KeyBinding.genericModifierString(generic: modifiers)
            return "\(mods)\(KeyBinding.regularKeyName(keyCode))  (kc=\(hex))"
        }
    }

    private static func genericModifierString(generic: UInt) -> String {
        var parts: [String] = []
        let m = NSEvent.ModifierFlags(rawValue: generic)
        if m.contains(.control) { parts.append("⌃") }
        if m.contains(.option)  { parts.append("⌥") }
        if m.contains(.shift)   { parts.append("⇧") }
        if m.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    /// L/R 접두사가 붙은 modifier 문자열. 예: 오른쪽 Shift만 눌렸으면 "R⇧".
    /// 양쪽 또는 어느 쪽도 아니면 기본 "⇧"로 폴백.
    private static func sidedModifierString(generic: UInt, device: UInt) -> String {
        // (genericFlag, symbol, L-deviceBit, R-deviceBit)
        let table: [(NSEvent.ModifierFlags, String, UInt, UInt)] = [
            (.control, "⌃", 0x01,   0x2000),
            (.option,  "⌥", 0x20,   0x40),
            (.shift,   "⇧", 0x02,   0x04),
            (.command, "⌘", 0x08,   0x10),
        ]
        let m = NSEvent.ModifierFlags(rawValue: generic)
        var parts: [String] = []
        for (flag, sym, lBit, rBit) in table {
            guard m.contains(flag) else { continue }
            let l = (device & lBit) != 0
            let r = (device & rBit) != 0
            if l && !r      { parts.append("L\(sym)") }
            else if r && !l { parts.append("R\(sym)") }
            else            { parts.append(sym) }
        }
        return parts.joined()
    }
}

// MARK: - Preferences

final class Preferences {
    static let shared = Preferences()
    static let modeDidChange         = Notification.Name("ra1nIMEModeDidChange")
    static let toggleBindingDidChange = Notification.Name("ra1nIMEToggleBindingDidChange")
    static let sidedDistinctionDidChange = Notification.Name("ra1nIMESidedDistinctionDidChange")

    private let defaults: UserDefaults

    private init() {
        // UserDefaults.standard는 이미 번들 ID 범위로 격리되어 있어
        // UserDefaults(suiteName:)으로 감싸는 것은冗長하고 경고를 발생시킴.
        self.defaults = .standard
        self.defaults.register(defaults: [
            "switchToSelfOnToggle": true,
            "activateInKorean": true,
            "rememberModePerApp": false
        ])
    }

    var startMode: InputMode {
        get { InputMode(rawValue: defaults.string(forKey: "startMode") ?? "") ?? .korean }
        set { defaults.set(newValue.rawValue, forKey: "startMode") }
    }

    /// true면 keyCombo 바인딩이 녹화 시점의 정확한 L/R과 일치해야 발동.
    /// 예: R⇧+Space로 녹화했으면 L⇧+Space는 발동하지 않음.
    /// 기본 false — 어느 쪽 Shift든 동일하게 처리(더 관대).
    /// modifierTap에는 영향 없음(이미 keyCode로 좌/우가 고정됨).
    var distinguishSidedModifiers: Bool {
        get { defaults.bool(forKey: "distinguishSidedModifiers") }
        set {
            defaults.set(newValue, forKey: "distinguishSidedModifiers")
            NotificationCenter.default.post(name: Preferences.sidedDistinctionDidChange, object: nil)
        }
    }

    /// true면 토글 키 입력 시 다른 입력기가 활성화되어 있으면
    /// ra1nIME로 전환하고 한글 모드로 시작.
    /// ra1nIME가 이미 활성화된 상태에서는 평소와 같이 내부 한/영 전환만 수행.
    /// 기본 true.
    var switchToSelfOnToggle: Bool {
        get { defaults.bool(forKey: "switchToSelfOnToggle") }
        set { defaults.set(newValue, forKey: "switchToSelfOnToggle") }
    }

    /// true면 다른 입력기에서 ra1nIME로 전환할 때 마지막 모드가 아닌
    /// 한글 모드로 시작. 기본 true.
    /// 입력 소스를 강제 전환하지는 않고, 사용자가 선택한 뒤 모드만 변경.
    var activateInKorean: Bool {
        get { defaults.bool(forKey: "activateInKorean") }
        set { defaults.set(newValue, forKey: "activateInKorean") }
    }

    /// true면 앱별로 입력 모드를 다르게 기억. 기본 false.
    var rememberModePerApp: Bool {
        get { defaults.bool(forKey: "rememberModePerApp") }
        set { defaults.set(newValue, forKey: "rememberModePerApp") }
    }

    /// true면 os_log 서브시스템 `kr.ra1n.inputmethod.ra1nime`에 상세 로그 출력.
    /// 확인: `log stream --predicate 'subsystem == "kr.ra1n.inputmethod.ra1nime"' --info`
    /// 기본 off — 진단 전용.
    var debugLogging: Bool {
        get { defaults.bool(forKey: "debugLogging") }
        set { defaults.set(newValue, forKey: "debugLogging") }
    }

    var toggleBinding: KeyBinding {
        get {
            if let data = defaults.data(forKey: "toggleBinding"),
               let b = try? JSONDecoder().decode(KeyBinding.self, from: data) {
                return b
            }
            return .defaultBinding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "toggleBinding")
                NotificationCenter.default.post(name: Preferences.toggleBindingDidChange, object: nil)
            }
        }
    }
}

// MARK: - CurrentMode

final class CurrentMode {
    static let shared = CurrentMode()
    private(set) var mode: InputMode

    // 앱별 입력 모드 저장소
    private var modePerApp: [String: InputMode] = [:]
    // 현재 활성화된 앱의 bundle identifier
    private var activeBundleID: String?

    private init() { self.mode = Preferences.shared.startMode }

    func toggle() {
        mode = (mode == .korean) ? .english : .korean
        if Preferences.shared.rememberModePerApp, let bundleID = activeBundleID {
            modePerApp[bundleID] = mode
        }
        NotificationCenter.default.post(name: Preferences.modeDidChange, object: nil)
    }

    func set(_ m: InputMode) {
        guard m != mode else { return }
        mode = m
        if Preferences.shared.rememberModePerApp, let bundleID = activeBundleID {
            modePerApp[bundleID] = mode
        }
        NotificationCenter.default.post(name: Preferences.modeDidChange, object: nil)
    }

    func appChanged(to bundleID: String?) {
        activeBundleID = bundleID
        guard Preferences.shared.rememberModePerApp, let bundleID = bundleID else { return }

        if let savedMode = modePerApp[bundleID] {
            if mode != savedMode {
                mode = savedMode
                NotificationCenter.default.post(name: Preferences.modeDidChange, object: nil)
            }
        } else {
            // First time seeing this app, save the current mode as its default
            modePerApp[bundleID] = mode
        }
    }
}
