import Cocoa
import IOKit.hid
import ApplicationServices

/// pkg 설치 직후 postinstall이 `ra1nIME.app --args --setup` 로 실행하는 설정 도우미.
///
/// 손쉬운 사용 → 입력 모니터링 순으로 권한을 단계별 안내하고, 1초마다 허용 여부를
/// 실시간 감지해 허용되면 자동으로 다음 단계로 넘어간다. 마지막에 재로그인을 안내한다.
///
/// 이 프로세스는 IMKServer를 만들지 않으므로(입력기 인스턴스와 별개) 충돌하지 않는다.
/// 도우미가 이 앱 번들로 권한을 켜면 같은 번들 신원인 입력기가 다음 로그인에 그대로 물려받는다.
final class SetupAssistantController: NSWindowController, NSWindowDelegate {
    static let shared = SetupAssistantController()

    private enum Step: Int {
        case accessibility, inputMonitoring, done
    }
    private var step: Step = .accessibility
    private var timer: Timer?
    private var advanceScheduled = false

    // MARK: - UI
    private let progressLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let descLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let backButton = NSButton(title: "뒤로", target: nil, action: nil)
    private let nextButton = NSButton(title: "다음", target: nil, action: nil)

    private convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "ra1n IME 설정 도우미"
        w.isReleasedWhenClosed = false
        w.center()
        self.init(window: w)
        w.delegate = self
        buildUI()
    }

    func show() {
        step = firstUnsatisfiedStep()
        updateUI()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startPolling()
    }

    // MARK: - Permission state
    private func accessibilityGranted() -> Bool { PermissionChecker.accessibilityGranted() }
    private func inputMonitoringGranted() -> Bool { PermissionChecker.inputMonitoringGranted() }

    private func firstUnsatisfiedStep() -> Step {
        if !accessibilityGranted() { return .accessibility }
        if !inputMonitoringGranted() { return .inputMonitoring }
        return .done
    }

    // MARK: - Layout
    private func buildUI() {
        guard let content = window?.contentView else { return }

        progressLabel.font = .systemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor

        iconLabel.font = .systemFont(ofSize: 52)
        iconLabel.alignment = .center

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.alignment = .center

        descLabel.font = .systemFont(ofSize: 13)
        descLabel.alignment = .center
        descLabel.textColor = .labelColor
        descLabel.preferredMaxLayoutWidth = 440

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment = .center

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.target = self
        actionButton.action = #selector(actionTapped)

        let stack = NSStackView(views: [progressLabel, iconLabel, titleLabel,
                                        descLabel, actionButton, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(20, after: descLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(backTapped)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [backButton, spacer, nextButton])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
    }

    // MARK: - Step rendering
    private func updateUI() {
        switch step {
        case .accessibility:
            progressLabel.stringValue = "1 / 3 단계"
            iconLabel.stringValue = "🖐️"
            titleLabel.stringValue = "손쉬운 사용 허용"
            descLabel.stringValue = "한영 토글 키가 동작하려면 ‘손쉬운 사용’ 권한이 필요합니다.\n아래 버튼을 눌러 설정을 열고 ra1n IME를 켜주세요."
            actionButton.title = "손쉬운 사용 설정 열기"
            backButton.isHidden = true
            nextButton.title = "다음"
            statusLabel.isHidden = false
        case .inputMonitoring:
            progressLabel.stringValue = "2 / 3 단계"
            iconLabel.stringValue = "⌨️"
            titleLabel.stringValue = "입력 모니터링 허용"
            descLabel.stringValue = "전역 한/영 전환을 위해 ‘입력 모니터링’ 권한이 필요합니다.\n목록에 ra1n IME가 없으면 ＋ 버튼으로 /Library/Input Methods/ra1nIME.app 를 추가하세요."
            actionButton.title = "입력 모니터링 설정 열기"
            backButton.isHidden = false
            nextButton.title = "다음"
            statusLabel.isHidden = false
        case .done:
            progressLabel.stringValue = "3 / 3 단계"
            iconLabel.stringValue = "✅"
            titleLabel.stringValue = "설정 완료"
            descLabel.stringValue = "권한 설정이 끝났습니다. 변경사항 적용을 위해 재로그인이 필요합니다.\n재로그인 후 시스템 설정 → 키보드 → 입력 소스에서 ra1n IME를 추가하면 바로 사용할 수 있습니다."
            actionButton.title = "지금 로그아웃"
            backButton.isHidden = false
            nextButton.title = "닫기"
            statusLabel.isHidden = true
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let granted: Bool
        switch step {
        case .accessibility:   granted = accessibilityGranted()
        case .inputMonitoring: granted = inputMonitoringGranted()
        case .done:            return
        }
        if granted {
            statusLabel.stringValue = "✅ 허용됨"
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "⏳ 권한 대기 중… 허용하면 자동으로 다음 단계로 넘어갑니다"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Polling
    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollTick()
        }
    }

    private func pollTick() {
        switch step {
        case .accessibility, .inputMonitoring:
            refreshStatus()
            let granted = (step == .accessibility) ? accessibilityGranted() : inputMonitoringGranted()
            if granted { scheduleAdvance() }
        case .done:
            break
        }
    }

    /// 허용 감지 시 ✅를 잠깐 보여준 뒤 자동으로 다음 단계로.
    private func scheduleAdvance() {
        guard !advanceScheduled else { return }
        advanceScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            self.advanceScheduled = false
            switch self.step {
            case .accessibility where self.accessibilityGranted():   self.goTo(.inputMonitoring)
            case .inputMonitoring where self.inputMonitoringGranted(): self.goTo(.done)
            default: break
            }
        }
    }

    private func goTo(_ s: Step) {
        step = s
        advanceScheduled = false
        updateUI()
    }

    // MARK: - Actions
    @objc private func actionTapped() {
        switch step {
        case .accessibility:
            // 시스템 프롬프트로 목록 등록 + 안내, 그리고 해당 설정 패널 열기.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            NSWorkspace.shared.open(SystemSettingsURL.accessibility)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            NSWorkspace.shared.open(SystemSettingsURL.inputMonitoring)
        case .done:
            logout()
        }
    }

    @objc private func nextTapped() {
        switch step {
        case .accessibility:   goTo(.inputMonitoring)
        case .inputMonitoring: goTo(.done)
        case .done:            window?.performClose(nil)
        }
    }

    @objc private func backTapped() {
        switch step {
        case .accessibility:   break
        case .inputMonitoring: goTo(.accessibility)
        case .done:            goTo(.inputMonitoring)
        }
    }

    private func logout() {
        // best-effort — 자동화 권한이 없으면 조용히 실패하고 사용자가 직접 로그아웃.
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\" to log out")?
            .executeAndReturnError(&err)
    }

    // MARK: - Window lifecycle
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        // 설정 도우미는 일회성 프로세스이므로 창을 닫으면 종료.
        NSApp.terminate(nil)
    }
}
