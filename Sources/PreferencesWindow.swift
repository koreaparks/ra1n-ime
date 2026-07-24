import Cocoa
import Carbon

// MARK: - KeyRecorderView

/// 클릭하면 키 입력 대기 모드로 전환. 단일 modifier 탭(Right ⌘, Caps Lock 등) 또는
/// modifier 조합(⇧+Space, F13, ⌘+Tab 등)을 받아 바인딩으로 저장. ESC는 바인딩을 비움.
final class KeyRecorderView: NSView {
    var binding: KeyBinding { didSet { updateDisplay() } }
    var onChange: ((KeyBinding) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false { didSet { updateDisplay() } }
    private var modDownAt: (keyCode: UInt16, time: Date)?
    private var localMonitor: Any?

    init(binding: KeyBinding) {
        self.binding = binding
        super.init(frame: .zero)
        setupLayout()
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor     = NSColor.separatorColor.cgColor
        layer?.borderWidth     = 1
        layer?.cornerRadius    = 5

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func updateDisplay() {
        if isRecording {
            label.stringValue = "키 입력 대기…  (ESC: 비우기)"
            label.textColor = .systemBlue
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.borderWidth = 2
        } else {
            label.stringValue = binding.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        modDownAt = nil
        // 녹화 중에는 글로벌 탭을 일시 정지해 현재 바인딩이 자기 자신을 재발동하지 않게 함.
        GlobalKeyTap.isRecordingActive = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            self?.processCapture(e)
            return nil   // 녹화 필드가 깨끗이 캡처하도록 소비
        }
    }

    private func stopRecording() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        isRecording = false
        GlobalKeyTap.isRecordingActive = false
    }

    private func processCapture(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // ESC: 바인딩 비우기.
            if Int(event.keyCode) == kVK_Escape {
                commit(.empty)
                return
            }
            // Karabiner/IOKit sentinel — 의미 있는 바인딩이 될 수 없음.
            if event.keyCode == 0xFFFF { return }

            // NSEvent.modifierFlags는 device 비트를 제거하므로,
            // 기저 CGEvent를 통해 L/R 구분 정보를 가져옴.
            // 둘 다 저장하고 매칭 시 설정에 따라 선택.
            let raw = UInt(event.cgEvent?.flags.rawValue ?? UInt64(event.modifierFlags.rawValue))
            let generic = raw & KeyBinding.genericModifierMask
            let device  = raw & KeyBinding.deviceModifierMask
            commit(KeyBinding(kind: .keyCombo, keyCode: event.keyCode,
                              modifiers: generic, deviceModifiers: device))

        case .flagsChanged:
            let kc = event.keyCode
            guard KeyBinding.isModifierKey(kc) else { return }
            let down = KeyBinding.isModifierKeyDown(kc, in: event.modifierFlags)
            if down {
                modDownAt = (kc, Date())
            } else if let s = modDownAt, s.keyCode == kc,
                      Date().timeIntervalSince(s.time) < 0.5 {
                commit(KeyBinding(kind: .modifierTap, keyCode: kc, modifiers: 0))
                modDownAt = nil
            } else {
                modDownAt = nil
            }

        default:
            break
        }
    }

    private func commit(_ newBinding: KeyBinding) {
        binding = newBinding
        stopRecording()
        onChange?(newBinding)
    }
}

// MARK: - Preferences Window

/// Esc 키로 창을 닫도록 함. 기본 responder 체인은 cancelOperation:을
/// NSWindowController에 자동 라우팅하지 않으므로 NSWindow에서 직접 오버라이드.
private final class PrefsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private let recorder = KeyRecorderView(binding: Preferences.shared.toggleBinding)
    private let startModeSeg = NSSegmentedControl(labels: ["한글", "영문"],
                                                  trackingMode: .selectOne,
                                                  target: nil, action: nil)
    private let sidedCheckbox = NSButton(checkboxWithTitle: "조합 키 좌/우 구분 (예: L⇧+Space ≠ R⇧+Space)",
                                         target: nil, action: nil)
    private let switchSelfCheckbox = NSButton(
        checkboxWithTitle: "다른 입력기에서 토글 키 입력 시 ra1n 입력기로 전환",
        target: nil, action: nil)
    private let activateKoreanCheckbox = NSButton(
        checkboxWithTitle: "다른 입력기에서 전환 시 한글 모드로 시작",
        target: nil, action: nil)
    private let rememberModePerAppCheckbox = NSButton(
        checkboxWithTitle: "앱별 입력 모드 기억하기 (A앱 영문, B앱 한글 자동 전환)",
        target: nil, action: nil)
    private let debugCheckbox = NSButton(checkboxWithTitle: "디버그 로그",
                                         target: nil, action: nil)
    private let debugLogScroll = NSScrollView()
    private let debugLogText = NSTextView()
    private let debugClearBtn = NSButton(title: "비우기", target: nil, action: nil)

    private convenience init() {
        let window = PrefsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "ra1n IME 환경설정"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        loadFromPrefs()
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        // 제목
        let titleLabel = NSTextField(labelWithString: "ra1n IME 설정")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        root.addArrangedSubview(titleLabel)
        root.setCustomSpacing(16, after: titleLabel)

        // --- 토글 키 ---
        root.addArrangedSubview(formLabel("한영 토글 키"))
        root.setCustomSpacing(4, after: root.arrangedSubviews.last!)

        recorder.onChange = { binding in
            Preferences.shared.toggleBinding = binding
        }
        recorder.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(recorder)
        root.setCustomSpacing(12, after: root.arrangedSubviews.last!)

        // --- 시작 모드 ---
        root.addArrangedSubview(formLabel("시작 모드"))
        root.setCustomSpacing(4, after: root.arrangedSubviews.last!)

        startModeSeg.target = self
        startModeSeg.action = #selector(startModeChanged(_:))
        root.addArrangedSubview(startModeSeg)
        root.setCustomSpacing(16, after: root.arrangedSubviews.last!)

        // --- 구분선 ---
        root.addArrangedSubview(divider())
        root.setCustomSpacing(16, after: root.arrangedSubviews.last!)

        // --- 옵션 ---
        root.addArrangedSubview(formLabel("옵션"))
        root.setCustomSpacing(8, after: root.arrangedSubviews.last!)

        sidedCheckbox.target = self
        sidedCheckbox.action = #selector(sidedDistinctionChanged(_:))
        switchSelfCheckbox.target = self
        switchSelfCheckbox.action = #selector(switchSelfChanged(_:))
        activateKoreanCheckbox.target = self
        activateKoreanCheckbox.action = #selector(activateKoreanChanged(_:))
        rememberModePerAppCheckbox.target = self
        rememberModePerAppCheckbox.action = #selector(rememberModePerAppChanged(_:))

        root.addArrangedSubview(sidedCheckbox)
        root.addArrangedSubview(switchSelfCheckbox)
        root.addArrangedSubview(activateKoreanCheckbox)
        root.addArrangedSubview(rememberModePerAppCheckbox)
        root.setCustomSpacing(16, after: root.arrangedSubviews.last!)

        // --- 구분선 ---
        root.addArrangedSubview(divider())
        root.setCustomSpacing(16, after: root.arrangedSubviews.last!)

        // --- 권한 ---
        root.addArrangedSubview(formLabel("권한"))
        root.setCustomSpacing(8, after: root.arrangedSubviews.last!)

        let permRow = NSStackView()
        permRow.orientation = .horizontal
        permRow.spacing = 8
        permRow.addArrangedSubview(button("입력 모니터링", #selector(openInputMonitoring)))
        permRow.addArrangedSubview(button("손쉬운 사용", #selector(openAccessibility)))
        root.addArrangedSubview(permRow)
        root.setCustomSpacing(16, after: root.arrangedSubviews.last!)

        // --- 구분선 ---
        root.addArrangedSubview(divider())
        root.setCustomSpacing(16, after: root.arrangedSubviews.last!)

        // --- 디버그 ---
        root.addArrangedSubview(formLabel("디버그"))
        root.setCustomSpacing(8, after: root.arrangedSubviews.last!)

        debugCheckbox.target = self
        debugCheckbox.action = #selector(debugLoggingChanged(_:))
        debugClearBtn.target = self
        debugClearBtn.action = #selector(clearDebugLog(_:))
        debugClearBtn.bezelStyle = .rounded
        debugClearBtn.controlSize = .small

        let debugHeader = NSStackView()
        debugHeader.orientation = .horizontal
        debugHeader.alignment = .centerY
        debugHeader.spacing = 8
        debugHeader.addArrangedSubview(debugCheckbox)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        debugHeader.addArrangedSubview(spacer)
        debugHeader.addArrangedSubview(debugClearBtn)
        root.addArrangedSubview(debugHeader)
        root.setCustomSpacing(4, after: root.arrangedSubviews.last!)

        debugLogScroll.hasVerticalScroller = true
        debugLogScroll.borderType = .bezelBorder
        debugLogScroll.autohidesScrollers = false
        debugLogScroll.translatesAutoresizingMaskIntoConstraints = false
        debugLogScroll.documentView = debugLogText

        debugLogText.isEditable = false
        debugLogText.isSelectable = true
        debugLogText.isRichText = false
        debugLogText.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        debugLogText.textContainerInset = NSSize(width: 4, height: 4)
        debugLogText.isVerticallyResizable = true
        debugLogText.isHorizontallyResizable = false
        debugLogText.autoresizingMask = [.width]
        debugLogText.textContainer?.widthTracksTextView = true
        debugLogText.textContainer?.containerSize = NSSize(
            width: 360,
            height: CGFloat.greatestFiniteMagnitude)

        root.addArrangedSubview(debugLogScroll)
        root.setCustomSpacing(4, after: root.arrangedSubviews.last!)
        debugLogScroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        debugLogScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true

        // 닫기
        let closeRow = NSStackView()
        closeRow.orientation = .horizontal
        let flex = NSView()
        flex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        closeRow.addArrangedSubview(flex)
        let closeBtn = NSButton(title: "닫기", target: self, action: #selector(closeWindow))
        closeBtn.keyEquivalent = "\r"
        closeBtn.bezelStyle = .rounded
        closeRow.addArrangedSubview(closeBtn)
        root.addArrangedSubview(closeRow)

        window?.contentView = root
    }

    private func formLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func loadFromPrefs() {
        recorder.binding = Preferences.shared.toggleBinding
        startModeSeg.selectedSegment = (Preferences.shared.startMode == .korean) ? 0 : 1
        sidedCheckbox.state = Preferences.shared.distinguishSidedModifiers ? .on : .off
        switchSelfCheckbox.state = Preferences.shared.switchToSelfOnToggle ? .on : .off
        activateKoreanCheckbox.state = Preferences.shared.activateInKorean ? .on : .off
        rememberModePerAppCheckbox.state = Preferences.shared.rememberModePerApp ? .on : .off
        debugCheckbox.state = Preferences.shared.debugLogging ? .on : .off
    }

    func show() {
        loadFromPrefs()
        // 현재까지의 로그를 스냅샷으로 가져오고 창이 열린 동안 실시간 업데이트 수신.
        debugLogText.string = DebugLogger.shared.lines.joined(separator: "\n")
        scrollDebugLogToEnd()
        DebugLogger.shared.onAppend = { [weak self] line in
            // DebugLogger가 이미 메인 큐로 전환 후 호출함.
            self?.appendDebugLine(line)
        }
        // 설정 창이 열린 동안만 에이전트(LSUIElement)에서 일반 앱으로 승격.
        // Dock 타일과 ⌘Tab에 표시되며, Apple의 메뉴 바 앱 "설정…"과 동일한 방식.
        // windowWillClose에서 되돌림.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DebugLogger.shared.onAppend = nil
        // Dock 슬롯을 영구 차지하지 않도록 에이전트로 복귀.
        NSApp.mainMenu = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func appendDebugLine(_ line: String) {
        let suffix = debugLogText.string.isEmpty ? line : "\n" + line
        if let storage = debugLogText.textStorage {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: debugLogText.font ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            storage.append(NSAttributedString(string: suffix, attributes: attrs))
        } else {
            debugLogText.string += suffix
        }
        scrollDebugLogToEnd()
    }

    private func scrollDebugLogToEnd() {
        let end = NSRange(location: debugLogText.string.utf16.count, length: 0)
        debugLogText.scrollRangeToVisible(end)
    }

    /// 설정 창이 열린 동안만 존재하는 최소 메인 메뉴.
    /// 없으면 AppKit이 ⌘W/⌘M 등을 responder로 라우팅하지 못해 삼킴.
    /// Quit은 의도적으로 제외 — 설정 창을 닫아도 IME 프로세스는 종료되지 않아야 함.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        // 앱 서브메뉴 (맨 왼쪽 볼드체 — 제목은 AppKit이 CFBundleName에서 읽음)
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "ra1n IME 정보",
                                   action: #selector(menuAbout),
                                   keyEquivalent: ""))

        // 파일 메뉴: 닫기 ⌘W
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "파일")
        fileItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(title: "닫기",
                                    action: #selector(NSWindow.performClose(_:)),
                                    keyEquivalent: "w"))

        // 편집 메뉴: 디버그 로그 뷰(및 기타 NSTextView)의 복사/붙여넣기/전체선택 단축키 제공.
        // 이 메뉴가 없으면 AppKit이 ⌘C/⌘V/⌘A 키 이퀴밸런트를 연결하지 않음.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "편집")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "잘라내기",
                                    action: #selector(NSText.cut(_:)),
                                    keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "복사",
                                    action: #selector(NSText.copy(_:)),
                                    keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "붙여넣기",
                                    action: #selector(NSText.paste(_:)),
                                    keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "모두 선택",
                                    action: #selector(NSText.selectAll(_:)),
                                    keyEquivalent: "a"))

        // 윈도우 메뉴: ⌘M(최소화)를 자동 제공. NSApp.windowsMenu로 연결하면
        // AppKit이 윈도우 목록을 자동으로 채움.
        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "윈도우")
        winItem.submenu = winMenu
        winMenu.addItem(NSMenuItem(title: "최소화",
                                   action: #selector(NSWindow.performMiniaturize(_:)),
                                   keyEquivalent: "m"))
        NSApp.windowsMenu = winMenu

        return main
    }

    @objc private func menuAbout() { AboutSheet.show() }

    @objc private func startModeChanged(_ sender: NSSegmentedControl) {
        Preferences.shared.startMode = (sender.selectedSegment == 0) ? .korean : .english
    }
    @objc private func sidedDistinctionChanged(_ sender: NSButton) {
        Preferences.shared.distinguishSidedModifiers = (sender.state == .on)
        // displayString이 L/R 접두사를 읽어오므로,
        // 설정 변경 후 recorder 라벨을 강제 갱신.
        recorder.binding = Preferences.shared.toggleBinding
    }
    @objc private func switchSelfChanged(_ sender: NSButton) {
        Preferences.shared.switchToSelfOnToggle = (sender.state == .on)
    }
    @objc private func activateKoreanChanged(_ sender: NSButton) {
        Preferences.shared.activateInKorean = (sender.state == .on)
    }
    @objc private func rememberModePerAppChanged(_ sender: NSButton) {
        Preferences.shared.rememberModePerApp = (sender.state == .on)
    }
    @objc private func debugLoggingChanged(_ sender: NSButton) {
        Preferences.shared.debugLogging = (sender.state == .on)
    }
    @objc private func clearDebugLog(_ sender: NSButton) {
        DebugLogger.shared.clear()
        debugLogText.string = ""
    }
    @objc private func openInputMonitoring() {
        NSWorkspace.shared.open(SystemSettingsURL.inputMonitoring)
    }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(SystemSettingsURL.accessibility)
    }
    @objc private func closeWindow() { window?.performClose(nil) }
}

enum AboutSheet {
    static func show() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build   = info["CFBundleVersion"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "ra1n IME"
        alert.informativeText = """
            버전 \(version) (build \(build))
            한글 입력기 — 두벌식, 조합 중 Enter 한 번에 처리
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
