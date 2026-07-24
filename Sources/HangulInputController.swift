import Cocoa
import Carbon
import InputMethodKit
import OSLog

/// `Preferences.shared.debugLogging`을 존중하는 os.Logger 래퍼.
/// 메모리 내 작은 링 버퍼를 유지해 설정 창에서 실시간 로그를 볼 수 있게 함.
///
/// `@autoclosure` 파라미터로 인해 디버그가 꺼져 있을 때는
/// 문자열 보간 비용이 전혀 들지 않음.
///
/// 단, OSLog의 컴파일 타임 보간/Redaction 기능은 사용할 수 없음.
/// 사용자가 명시적으로 켜는 진단 로그이므로 문제 없음.
final class DebugLogger {
    static let shared = DebugLogger(subsystem: "kr.ra1n.inputmethod.ra1nime",
                                    category: "debug")

    private let logger: Logger
    private let maxLines = 500
    /// 오래된 것부터 순서대로. 메인 큐에서 읽기/쓰기.
    private(set) var lines: [String] = []
    /// 설정 창에서 설정. 창이 닫히면 nil.
    /// 항상 메인 큐에서 호출됨.
    var onAppend: ((String) -> Void)?

    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func notice(_ message: @autoclosure () -> String) {
        guard Preferences.shared.debugLogging else { return }
        // Logger가 @escaping 보간 빌더를 사용하므로,
        // 비escaping autoclosure를 넘기기 전에 문자열을 구체화.
        let msg = message()
        logger.notice("\(msg, privacy: .public)")

        // 메모리 버퍼에 추가 + UI 알림.
        // IMK 콜백은 임의 큐에서 오므로 메인 큐로 전환.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lines.append(msg)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
            self.onAppend?(msg)
        }
    }

    /// 메모리 버퍼 초기화. UI는 onAppend를 통해 별도 갱신.
    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.lines.removeAll()
        }
    }
}

private let imeLog = DebugLogger.shared

// Info.plist에 등록된 유일한 입력 모드. 한/영 전환은 낶部 처리이며
// 입력 소스 자체를 바꾸지 않으므로 시스템은 항상 동일한 활성 소스를 봄.
let kKoreanModeID = "kr.ra1n.inputmethod.ra1nime.korean"

// 재주입한 CGEvent에 찍는 마커. handle()에서 이 값을 보고
// 순환을 방지 — 그렇지 않으면 재주입 이벤트가 또다시 커밋을 유발해
// "cascade"가 발생함. 임의의 고유값.
private let kSyntheticTag: Int64 = 0x5241314E494D45  // "RA1NIME" ASCII

@objc(HangulInputController)
final class HangulInputController: IMKInputController {
    private let automaton = HangulAutomaton()

    // 제네릭 modifier 탭 감지용 상태.
    private var modDownAt: (keyCode: UInt16, time: Date)?
    private var modTapSolo: Bool = false

    // 컨트롤러 생애 1회만 로깅 — 클라이언트별 특성 비교용.
    private var attrsLogged: Bool = false

    // 현재 활성 컨트롤러/클이언트를 추적.
    // ClickMonitor가 포커스 변경 클릭 직전에 선제 커밋할 수 있게 함.
    nonisolated(unsafe) static weak var current: HangulInputController?
    private weak var currentClient: AnyObject?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        NSLog("ra1nIME.init controller")
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

        imeLog.notice("RA1N handle type=\(event.type.rawValue) kc=\(event.keyCode)")

        // 우리가 재주입한 이벤트인지 확인.
        // 맞다면 다시 처리하지 않고 그대로 통과 — 그렇지 않으면 중간에
        // 조합된 내용이 또 커밋되는 순환(cascade)이 생김.
        let isSynthetic = (event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0) == kSyntheticTag
        if isSynthetic { return false }

        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event, sender: sender)
        case .keyDown:
            return handleKeyDown(event, sender: sender)
        default:
            return false
        }
    }

    // MARK: - Toggle key handling

    private func handleFlagsChanged(_ event: NSEvent, sender: Any!) -> Bool {
        let kc = event.keyCode
        let modsRaw = event.modifierFlags.rawValue
        imeLog.notice("RA1N flagsChanged kc=\(kc) mods=0x\(String(modsRaw, radix: 16))")
        guard KeyBinding.isModifierKey(kc) else {
            imeLog.notice("RA1N flagsChanged: not a modifier key, return")
            return false
        }

        let binding = Preferences.shared.toggleBinding
        let isDown = KeyBinding.isModifierKeyDown(kc, in: event.modifierFlags)
        imeLog.notice("RA1N flagsChanged isDown=\(isDown)")

        // NSEvent.modifierFlags.contains(.command)로 직접 확인.
        // isDown 헬퍼는 device-specific 비트(0x0008 등)를 보는데,
        // NSEvent에는 generic 비트(0x100000)만 있으므로 여기서는 직접 체크.
        let isCmdKey = (kc == kVK_Command || kc == kVK_RightCommand)
        let cmdAsserted = event.modifierFlags.contains(.command)
        if isCmdKey && cmdAsserted {
            imeLog.notice("RA1N cmd-down → preemptive commit")
            endComposition(sender: sender)
        }

        if isDown {
            if modDownAt != nil { modTapSolo = false }
            modDownAt = (kc, Date())
            modTapSolo = (modDownAt?.keyCode == kc)
        } else {
            defer { modDownAt = nil; modTapSolo = false }
            guard binding.kind == .modifierTap, binding.keyCode == kc else { return false }
            guard modTapSolo, let state = modDownAt, state.keyCode == kc else { return false }
            guard Date().timeIntervalSince(state.time) < 0.4 else { return false }
            toggleMode(sender: sender)
        }
        return false
    }

    private func handleKeyDown(_ event: NSEvent, sender: Any!) -> Bool {
        if event.keyCode == 0xFFFF { return false }
        modTapSolo = false

        let flags = event.modifierFlags
        let keyCode = event.keyCode
        let shift = flags.contains(.shift)

        let mods = flags.intersection(.deviceIndependentFlagsMask).rawValue
        imeLog.notice("RA1N kd kc=\(keyCode) mods=0x\(String(mods, radix: 16))")

        if !attrsLogged, let client = sender as? IMKTextInput {
            attrsLogged = true
            let attrs = (client.validAttributesForMarkedText() as? [String]) ?? []
            let bundleID = client.bundleIdentifier() ?? "?"
            imeLog.notice("RA1N CLIENT bundle=\(bundleID) attrs=[\(attrs.joined(separator: ","))]")
        }

        // 키 콤보 토글 바인딩 매칭. GlobalKeyTap 로직과 동일.
        let binding = Preferences.shared.toggleBinding
        if binding.kind == .keyCombo, binding.keyCode == keyCode {
            let raw = UInt(event.cgEvent?.flags.rawValue ?? UInt64(flags.rawValue))
            let evGen = raw & KeyBinding.genericModifierMask
            let bindGen = binding.modifiers & KeyBinding.genericModifierMask
            var matches = (evGen == bindGen)
            if matches, Preferences.shared.distinguishSidedModifiers,
               binding.deviceModifiers != 0 {
                let evDev = raw & KeyBinding.deviceModifierMask
                let bindDev = binding.deviceModifiers & KeyBinding.deviceModifierMask
                matches = (evDev == bindDev)
            }
            if matches {
                toggleMode(sender: sender)
                return true
            }
        }

        if CurrentMode.shared.mode == .english {
            endComposition(sender: sender)
            return false
        }

        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            // Cmd+Tab만 예외: 합성 이벤트 재주입이 포커스 복귀 후
            // Monaco의 stale-marker 상태를 유발함. 그냥 조합을 닫고 이벤트 통과.
            // 나머지 Cmd/Ctrl 조합은 조합 중일 때 선제 커밋 후 재주입.
            // Monaco 등은 커밋이 먼저 정착한 뒤 단축키가 등록되길 기대함.
            if Int(keyCode) == kVK_Tab && flags.contains(.command) {
                endComposition(sender: sender)
                return false
            }
            if commitAndRepost(event: event, sender: sender, delay: 0.03) { return true }
            return false
        }

        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter,
             kVK_Tab,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            // Terminal 등은 raw stdin으로 키를 먼저 소비해,
            // IME 커밋이 늦게 도착하면 키를 두 번 눌러야 동작하는 문제가 있음.
            // IntelliJ의 Shift+Arrow 선택 확장도 동일.
            // 선제 커밋 후 짧은 딜레이로 원본 키를 재주입.
            // 조합 중이 아니면 commitAndRepost가 false를 반환하고 자연스럽게 통과.
            if commitAndRepost(event: event, sender: sender, delay: 0.03) { return true }
            return false

        case kVK_Space, kVK_Escape:
            // 타이밍에 덜 민감한 키: 조합만 닫고 이벤트는 통과.
            endComposition(sender: sender)
            return false

        case kVK_Delete:
            if let updated = automaton.backspace() {
                if updated.isEmpty {
                    // 조합이 완전히 지워짐. 마커가 실제 문서에 커밋된 적 없으므로
                    // 명시적으로 지우고, BS가 앞 글자를 삭제하지 않도록 소비.
                    clearMarker(sender: sender)
                    automaton.reset()
                    return true
                } else {
                    setMarker(updated, sender: sender)
                    return true
                }
            }
            return false

        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers, let first = chars.first else {
            endComposition(sender: sender)
            return false
        }

        guard let jamo = Keymap.toJamo(first, shift: shift) else {
            endComposition(sender: sender)
            return false
        }

        switch automaton.input(jamo) {
        case .composing(let s):
            setMarker(s, sender: sender)
        case .commit(let committed, let composing):
            commitMarker(committed: committed, composing: composing, sender: sender)
        }
        return true
    }

    private func toggleMode(sender: Any!) {
        endComposition(sender: sender)
        CurrentMode.shared.toggle()
    }

    override func commitComposition(_ sender: Any!) {
        imeLog.notice("RA1N commitComposition")
        endComposition(sender: sender)
    }

    override func activateServer(_ sender: Any!) {
        imeLog.notice("RA1N activateServer")
        super.activateServer(sender)
        automaton.reset()
        // 포커스 이동 시 새 클라이언트의 속성을 다시 로깅.
        attrsLogged = false
        // ClickMonitor가 선제 커밋할 수 있도록 현재 컨트롤러 등록.
        HangulInputController.current = self
        currentClient = sender as AnyObject?

        if let client = sender as? IMKTextInput {
            let bundleID = client.bundleIdentifier()
            CurrentMode.shared.appChanged(to: bundleID)
        }
    }

    override func deactivateServer(_ sender: Any!) {
        imeLog.notice("RA1N deactivateServer")
        endComposition(sender: sender)
        if HangulInputController.current === self {
            HangulInputController.current = nil
        }
        currentClient = nil
        super.deactivateServer(sender)
    }

    /// 시스템 수준 마우스 다운 훅에서 호출.
    /// 포커스 변경 클릭이 전파되기 전에 진행 중인 조합을 먼저 커밋.
    /// handleFlagsChanged의 Cmd-down 선제 커밋과 대응하는 마우스 버전.
    func commitCurrent() {
        guard let sender = currentClient else {
            imeLog.notice("RA1N commitCurrent: no currentClient")
            return
        }
        // 포커스를 잃으려는 클라이언트에게 이유 없는 insertText를 호출하면
        // VSCode가 크래시난 적이 있으므로, 실제로 조합 중일 때만 호출.
        guard !automaton.currentComposition().isEmpty else {
            imeLog.notice("RA1N commitCurrent: nothing composing")
            return
        }
        imeLog.notice("RA1N commitCurrent: committing")
        endComposition(sender: sender)
    }

    // IMK에게 마우스 다운 이벤트도 받고 싶다고 알림.
    //
    // 기본 IMK 마우스 처리(NSKeyDownMask만 선언한 IME)는
    // 마커 밖에 찍힌 클릭을 삼킴 — 커밋은 하지만 클릭이 클라이언트의
    // 커서 이동까지 전달되지 않아 "첫 클릭은 커밋, 두 번째 클릭이 커서 이동"이 됨.
    override func recognizedEvents(_ sender: Any!) -> Int {
        // .flagsChanged: modifier 전환(Cmd down 등)을 handle()로 받기 위해 필요.
        // 없으면 IMK가 modifier 이벤트를 전달하지 않아 Cmd-down 선제 커밋이 동작하지 않음.
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .flagsChanged]
        return Int(bitPattern: UInt(mask.rawValue))
    }

    override func mouseDown(onCharacterIndex index: Int,
                            coordinate point: NSPoint,
                            withModifier flags: Int,
                            continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!,
                            client sender: Any!) -> Bool {
        imeLog.notice("RA1N mouseDown idx=\(index)")
        endComposition(sender: sender)
        if let kt = keepTracking { kt.pointee = false }
        return false  // 클릭이 클라이언트에 전파되도록 허용.
    }

    // MARK: - Status bar menu

    override func menu() -> NSMenu! {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(title: "ra1n IME 설정",
                                   action: #selector(menuOpenPreferences),
                                   keyEquivalent: ",")
        // ⌘⌥, — 상태 표시줄 메뉴와 일치. IME 활성 중에도 입력할 가능성이 낮음.
        prefsItem.keyEquivalentModifierMask = [.command, .option]
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(title: "ra1n IME 정보", action: #selector(menuShowAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        return menu
    }

    @objc private func menuOpenPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func menuShowAbout() {
        AboutSheet.show()
    }

    // MARK: - Marker-based composition
    //
    // IMK 표준 마커 흐름(setMarkedText / insertText) 사용.
    // 시스템 한국어 IME와 동일한 패턴이며,
    // NSTextView, NSTextField, WKWebView 등이 기본적으로 지원하는 방식.
    //
    //   - setMarkedText(s, replacementRange: NSNotFound): 활성 선택 영역을 마커로 교체.
    //     Cmd+A 후 한글 입력이 선택 영역을 깔끔히 대체함.
    //   - insertText(s, replacementRange: NSNotFound): 활성 마커를 커밋하고
    //     s를 일반 문서 텍스트로 기록.
    //   - Chromium contenteditable 등은 실제 IMK 조합 생명주기를 보고
    //     포커스 변경 시 깔끔하게 커밋 — 이중 커밋 없음.

    /// 진행 중 음절을 IMK 마커로 표시.
    /// replacementRange: NSNotFound로 두면 현재 선택 영역(또는 커서) 위치에 배치.
    private func setMarker(_ s: String, sender: Any?) {
        guard let client = sender as? IMKTextInput else { return }
        // backgroundColor: .clear만 지정.
        // NSMarkedClauseSegment나 NSUnderlineStyle은 제외해
        // Monaco 등에서 포커스 복귀 시 stale-state 문제를 방지.
        // selectionRange도 기본값(defaultRange) 사용.
        let attrs: [NSAttributedString.Key: Any] = [.backgroundColor: NSColor.clear]
        let attributed = NSAttributedString(string: s, attributes: attrs)
        client.setMarkedText(attributed,
                             selectionRange: NSRange(location: NSNotFound, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        imeLog.notice("RA1N setMarker s=\(s)")
    }

    /// 마커 오버레이 제거. 백스페이스로 조합을 완전히 지웠을 때 사용.
    /// 안 하면 마지막 자모가 클라이언트에 그대로 남음.
    private func clearMarker(sender: Any?) {
        guard let client = sender as? IMKTextInput else { return }
        client.setMarkedText("",
                             selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        imeLog.notice("RA1N clearMarker")
    }

    /// 현재 마커를 일반 문서 텍스트로 커밋한 뒤, 다음 음절 마커가 있으면 설정.
    /// insertText가 활성 마커 범위를 자동 교체하므로
    /// Chromium 등의 포커스 변경 시 이중 커밋을 방지.
    private func commitMarker(committed: String, composing: String, sender: Any?) {
        guard let client = sender as? IMKTextInput else { return }
        imeLog.notice("RA1N commit committed=\(committed) composing=\(composing)")
        client.insertText(committed, replacementRange: NSRange(location: NSNotFound, length: 0))
        if !composing.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.setMarker(composing, sender: sender)
            }
        }
    }

    /// 진행 중인 조합을 즉시 커밋하고 원본 키 이벤트를 `delay` 초 후 재주입.
    /// 실제로 커밋이 일어났을 때만 true를 반환 — 호출처는 이를 보고
    /// 원본 이벤트를 소비할지 결정.
    @discardableResult
    private func commitAndRepost(event: NSEvent, sender: Any!, delay: TimeInterval) -> Bool {
        let composing = automaton.currentComposition()
        guard !composing.isEmpty else { return false }
        endComposition(sender: sender)
        let mods = event.modifierFlags
        let key = CGKeyCode(event.keyCode)
        imeLog.notice("RA1N commitAndRepost kc=\(event.keyCode) delay=\(delay)")
        let post: () -> Void = { [weak self] in
            self?.repostKey(modifierFlags: mods, keyCode: key)
        }
        if delay <= 0 {
            DispatchQueue.main.async(execute: post)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: post)
        }
        return true
    }

    private func repostKey(modifierFlags: NSEvent.ModifierFlags, keyCode: CGKeyCode) {
        // 이벤트 소스에 태그를 찍어 handle()의 isSynthetic 체크에서 걸러내게 함.
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.userData = kSyntheticTag
        var cgFlags: CGEventFlags = []
        if modifierFlags.contains(.shift)   { cgFlags.insert(.maskShift) }
        if modifierFlags.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if modifierFlags.contains(.command) { cgFlags.insert(.maskCommand) }
        if modifierFlags.contains(.control) { cgFlags.insert(.maskControl) }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.setIntegerValueField(.eventSourceUserData, value: kSyntheticTag)
            down.flags = cgFlags
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.setIntegerValueField(.eventSourceUserData, value: kSyntheticTag)
            up.flags = cgFlags
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// 조합 종료(Enter, Space, Cmd 조합, 포커스 변경, 모드 전환, 마우스 클릭 등).
    /// 마커가 있으면 insertText로 일반 텍스트로 커밋.
    ///
    /// IMK 사양상 insertText는 활성 마커를 자동 커밋하고 해제함.
    /// 추가로 setMarkedText("")를 호출하면 Chromium contenteditable이
    /// 이를 별도 조합 생명주기로 해석해 포커스 복귀 시 mirror buffer를
    /// 자동 커밋하여 "마마" 중복이 발생할 수 있으므로 하지 않음.
    private func endComposition(sender: Any?) {
        defer { automaton.reset() }
        guard let client = sender as? IMKTextInput else { return }
        let composing = automaton.currentComposition()
        imeLog.notice("RA1N endComposition composing=\(composing)")
        if !composing.isEmpty {
            client.insertText(composing, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }
}
