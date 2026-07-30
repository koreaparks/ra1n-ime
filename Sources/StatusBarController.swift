import Cocoa

/// 메뉴 바에 "ㄱ" / "A" 아이콘을 표시. 클릭 시 한↔영 전환.
/// 설정은 IMK 컨트롤러 메뉴에 두어 중복을 피함.
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private var modeObserver: NSObjectProtocol?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()

        modeObserver = NotificationCenter.default.addObserver(
            forName: Preferences.modeDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateIcon()
        }
    }

    deinit {
        if let m = modeObserver { NotificationCenter.default.removeObserver(m) }
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = item.button else { return }
        button.imagePosition = .noImage
        button.toolTip = "ra1n IME — 클릭: 한↔영 전환"
        button.target = self
        button.action = #selector(buttonClicked)
        updateIcon()
    }

    /// "ㄱ"(한글) ↔ "A"(영문). 한 글자 타이틀 — 시스템 메뉴 바 폰트로
    /// 자동 스타일링되며 라이트/다크 모드와 Retina 대응이 자동으로 처리됨.
    private func updateIcon() {
        guard let button = item.button else { return }
        let isKR = CurrentMode.shared.mode == .korean
        button.image = nil
        button.title = isKR ? "ㄱ" : "A"
    }

    @objc private func buttonClicked() {
        GlobalKeyTap.fireToggle()
    }
}
