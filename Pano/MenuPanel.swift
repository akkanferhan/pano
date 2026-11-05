import UIKit

/// Sağdan kayan cam menü paneli (UIAlertController action sheet yerine).
/// Başlık + alt başlık, isteğe bağlı yuvarlak hızlı işlem düğmeleri ve bölümlere ayrılmış simgeli satırlar.
final class MenuPanelController: UIViewController, UIViewControllerTransitioningDelegate {
    struct Item {
        var title: String
        var subtitle: String?
        var value: String?
        var symbol: String?
        var destructive = false
        var checked = false
        var action: () -> Void
    }

    private enum Entry {
        case header(String)
        case item(Item)
    }

    private let headerTitle: String?
    private let headerSubtitle: String?
    private var entries: [Entry] = []
    private var quickActions: [Item] = []

    private let dim = UIView()
    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var firstRow: UIView?
    private var closing = false
    static let panelWidth: CGFloat = 760

    init(title: String?, subtitle: String? = nil) {
        headerTitle = title
        headerSubtitle = subtitle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        transitioningDelegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Oluşturma

    func addHeader(_ text: String) { entries.append(.header(text)) }

    func addItem(_ title: String, subtitle: String? = nil, value: String? = nil, symbol: String? = nil,
                 destructive: Bool = false, checked: Bool = false, action: @escaping () -> Void) {
        entries.append(.item(Item(title: title, subtitle: subtitle, value: value, symbol: symbol,
                                  destructive: destructive, checked: checked, action: action)))
    }

    func addQuickAction(_ title: String, symbol: String, action: @escaping () -> Void) {
        quickActions.append(Item(title: title, symbol: symbol, action: action))
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: Görünüm

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dim.backgroundColor = UIColor(white: 0, alpha: 0.5)
        dim.frame = view.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dim)

        panel.layer.cornerRadius = 48
        panel.clipsToBounds = true
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        let tint = UIView()
        tint.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.09, alpha: 0.45)
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.contentView.addSubview(tint)
        let glow = AmbientBackground()
        glow.backgroundColor = .clear
        glow.alpha = 0.55
        glow.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.contentView.addSubview(glow)
        view.addSubview(panel)

        stack.axis = .vertical
        stack.spacing = 10
        scroll.addSubview(stack)
        scroll.clipsToBounds = false
        scroll.showsVerticalScrollIndicator = false
        panel.contentView.addSubview(scroll)
        buildContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = Self.panelWidth
        // bounds + center (not frame): the panel carries a transform during the transition
        panel.bounds = CGRect(x: 0, y: 0, width: w, height: view.bounds.height - 80)
        panel.center = CGPoint(x: view.bounds.width - w / 2 - 40, y: view.bounds.height / 2)
        panel.contentView.subviews.first?.frame = panel.bounds
        panel.contentView.subviews.dropFirst().first?.frame = panel.bounds
        scroll.frame = panel.bounds.insetBy(dx: 40, dy: 0)
        let width = scroll.bounds.width
        let size = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                 withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 0, y: 46, width: width, height: size.height)
        scroll.contentSize = CGSize(width: width, height: size.height + 90)
    }

    private func buildContent() {
        if let headerTitle {
            let t = UILabel()
            t.text = headerTitle
            t.font = .systemFont(ofSize: 40, weight: .heavy)
            t.textColor = .white
            t.numberOfLines = 2
            stack.addArrangedSubview(t)
        }
        if let headerSubtitle, !headerSubtitle.isEmpty {
            let s = UILabel()
            s.text = headerSubtitle
            s.font = .systemFont(ofSize: 22, weight: .medium)
            s.textColor = Theme.textSecondary
            s.numberOfLines = 3
            stack.addArrangedSubview(s)
        }
        if headerTitle != nil || headerSubtitle != nil { stack.setCustomSpacing(26, after: stack.arrangedSubviews.last!) }

        if !quickActions.isEmpty {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .equalSpacing
            row.alignment = .top
            for item in quickActions {
                let b = QuickActionButton(title: item.title, symbol: item.symbol ?? "circle")
                b.addAction(UIAction { [weak self] _ in self?.close(then: item.action) }, for: .primaryActionTriggered)
                row.addArrangedSubview(b)
            }
            stack.addArrangedSubview(row)
            stack.setCustomSpacing(30, after: row)
        }

        for entry in entries {
            switch entry {
            case let .header(text):
                let l = UILabel()
                l.text = text.uppercased()
                l.font = .systemFont(ofSize: 19, weight: .bold)
                l.textColor = UIColor(white: 1, alpha: 0.42)
                let wrap = UIView()
                l.translatesAutoresizingMaskIntoConstraints = false
                wrap.addSubview(l)
                NSLayoutConstraint.activate([
                    l.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
                    l.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 18),
                    l.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
                ])
                stack.addArrangedSubview(wrap)
            case let .item(item):
                let row = MenuRowButton(item: item)
                row.addAction(UIAction { [weak self] _ in self?.close(then: item.action) }, for: .primaryActionTriggered)
                stack.addArrangedSubview(row)
                if firstRow == nil { firstRow = row }
            }
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let checked = stack.arrangedSubviews.first(where: { ($0 as? MenuRowButton)?.isChecked == true }) { return [checked] }
        return firstRow.map { [$0] } ?? []
    }

    // MARK: Opening / closing (custom transition, coordinated by UIKit)

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PanelTransition(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PanelTransition(presenting: false)
    }

    /// Off-screen state: panel slid out to the right and slightly scaled, background undimmed.
    fileprivate func setHidden(_ hidden: Bool) {
        panel.transform = hidden
            ? CGAffineTransform(translationX: Self.panelWidth + 80, y: 0).scaledBy(x: 0.96, y: 0.96)
            : .identity
        dim.alpha = hidden ? 0 : 1
    }

    /// Closes the panel, then runs the action (if any).
    func close(then action: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        dismiss(animated: true) { action?() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.first?.type == .menu || presses.first?.type == .playPause { return }
        super.pressesBegan(presses, with: event)
    }

    /// Menu and Play/Pause (the key that opens the menu) close the panel.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.first?.type == .menu || presses.first?.type == .playPause { close(); return }
        super.pressesEnded(presses, with: event)
    }
}

// MARK: - Satır

final class MenuRowButton: UIButton {
    private let background = UIView()
    private let iconWell = UIView()
    private let iconGradient = GradientView()
    private let iconView = UIImageView()
    private let titleText = UILabel()
    private let subtitleText = UILabel()
    private let valueText = UILabel()
    private let check = UIImageView(image: Theme.symbol("checkmark.circle.fill", size: 30))
    private let destructive: Bool
    let isChecked: Bool

    init(item: MenuPanelController.Item) {
        destructive = item.destructive
        isChecked = item.checked
        super.init(frame: .zero)
        let hasSubtitle = item.subtitle?.isEmpty == false
        heightAnchor.constraint(equalToConstant: hasSubtitle ? 104 : 86).isActive = true

        background.isUserInteractionEnabled = false
        background.layer.cornerRadius = 26
        background.backgroundColor = UIColor(white: 1, alpha: 0.06)
        addSubview(background)

        iconWell.isUserInteractionEnabled = false
        iconWell.layer.cornerRadius = 16
        iconWell.clipsToBounds = true
        iconWell.backgroundColor = UIColor(white: 1, alpha: 0.1)
        iconGradient.alpha = 0
        iconGradient.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        iconWell.addSubview(iconGradient)
        iconView.contentMode = .center
        iconView.image = item.symbol.flatMap { Theme.symbol($0, size: 24) }
        iconView.tintColor = item.destructive ? UIColor(red: 1, green: 0.42, blue: 0.48, alpha: 1) : .white
        iconWell.addSubview(iconView)
        iconWell.isHidden = item.symbol == nil
        addSubview(iconWell)

        titleText.text = item.title
        titleText.font = .systemFont(ofSize: 28, weight: .semibold)
        titleText.textColor = item.destructive ? UIColor(red: 1, green: 0.5, blue: 0.55, alpha: 1) : .white
        subtitleText.text = item.subtitle
        subtitleText.font = .systemFont(ofSize: 20, weight: .medium)
        subtitleText.textColor = Theme.textSecondary
        valueText.text = item.value
        valueText.font = .systemFont(ofSize: 23, weight: .semibold)
        valueText.textColor = UIColor(white: 1, alpha: 0.55)
        valueText.textAlignment = .right
        check.tintColor = Theme.pink
        check.isHidden = !item.checked
        [titleText, subtitleText, valueText, check].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        let h = bounds.height
        var x: CGFloat = 22
        if !iconWell.isHidden {
            iconWell.frame = CGRect(x: x, y: (h - 54) / 2, width: 54, height: 54)
            iconView.frame = iconWell.bounds
            x = iconWell.frame.maxX + 22
        }
        var right = bounds.width - 24
        if !check.isHidden {
            check.frame = CGRect(x: right - 34, y: (h - 34) / 2, width: 34, height: 34)
            right = check.frame.minX - 14
        }
        if let v = valueText.text, !v.isEmpty {
            let w = min(260, valueText.sizeThatFits(CGSize(width: 400, height: 40)).width)
            valueText.frame = CGRect(x: right - w, y: 0, width: w, height: h)
            right = valueText.frame.minX - 16
        }
        let hasSubtitle = subtitleText.text?.isEmpty == false
        titleText.frame = CGRect(x: x, y: hasSubtitle ? h / 2 - 34 : 0, width: right - x, height: hasSubtitle ? 36 : h)
        subtitleText.frame = CGRect(x: x, y: h / 2 + 4, width: right - x, height: 28)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            self.transform = focused ? CGAffineTransform(scaleX: 1.035, y: 1.035) : .identity
            self.background.backgroundColor = focused ? UIColor(white: 1, alpha: 0.2) : UIColor(white: 1, alpha: 0.06)
            self.iconGradient.alpha = focused && !self.destructive ? 1 : 0
            self.layer.shadowOpacity = focused ? 0.35 : 0
        }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)
    }
}

// MARK: - Hızlı işlem düğmesi

final class QuickActionButton: UIButton {
    private let circle = UIView()
    private let gradient = GradientView()
    private let iconView = UIImageView()
    private let caption = UILabel()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: 112).isActive = true
        heightAnchor.constraint(equalToConstant: 140).isActive = true
        circle.isUserInteractionEnabled = false
        circle.backgroundColor = UIColor(white: 1, alpha: 0.12)
        circle.layer.cornerRadius = 46
        circle.clipsToBounds = true
        gradient.alpha = 0
        circle.addSubview(gradient)
        iconView.image = Theme.symbol(symbol, size: 30)
        iconView.tintColor = .white
        iconView.contentMode = .center
        circle.addSubview(iconView)
        addSubview(circle)
        caption.text = title
        caption.font = .systemFont(ofSize: 19, weight: .semibold)
        caption.textColor = UIColor(white: 1, alpha: 0.75)
        caption.textAlignment = .center
        caption.isUserInteractionEnabled = false
        addSubview(caption)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        circle.frame = CGRect(x: (bounds.width - 92) / 2, y: 0, width: 92, height: 92)
        gradient.frame = circle.bounds
        iconView.frame = circle.bounds
        caption.frame = CGRect(x: -10, y: 104, width: bounds.width + 20, height: 26)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            self.circle.transform = focused ? CGAffineTransform(scaleX: 1.14, y: 1.14) : .identity
            self.gradient.alpha = focused ? 1 : 0
            self.caption.textColor = focused ? .white : UIColor(white: 1, alpha: 0.75)
        }
    }
}

/// Panel slide transition: in with a soft spring, out with a short ease-in — one coordinated animation each way.
private final class PanelTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        presenting ? 0.5 : 0.3
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        if presenting {
            guard let panel = context.viewController(forKey: .to) as? MenuPanelController else { return context.completeTransition(false) }
            panel.view.frame = context.finalFrame(for: panel)
            context.containerView.addSubview(panel.view)
            panel.view.layoutIfNeeded()
            panel.setHidden(true)
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0, usingSpringWithDamping: 0.88,
                           initialSpringVelocity: 0.2, options: [.curveEaseOut, .allowUserInteraction]) {
                panel.setHidden(false)
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
        } else {
            guard let panel = context.viewController(forKey: .from) as? MenuPanelController else { return context.completeTransition(false) }
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
                panel.setHidden(true)
            } completion: { _ in
                panel.view.removeFromSuperview()
                context.completeTransition(!context.transitionWasCancelled)
            }
        }
    }
}
