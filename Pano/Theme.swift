import UIKit

/// Pano görsel dili: koyu zemin, mor → pembe vurgu, cam (blur) yüzeyler, yuvarlak köşeler.
enum Theme {
    static let violet = UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)   // #7C3AED
    static let pink = UIColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1)     // #EC4899
    static let blue = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)     // #3B82F6
    static let teal = UIColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 1)
    static let textSecondary = UIColor(white: 1, alpha: 0.62)

    static func symbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    /// SF Symbol + metin (rozet ve bildirimler için).
    static func label(_ text: String, symbol name: String?, size: CGFloat, color: UIColor = .white) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let name, let image = symbol(name, size: size * 0.85)?.withTintColor(color, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment(image: image)
            attachment.bounds = CGRect(x: 0, y: -size * 0.12, width: image.size.width, height: image.size.height)
            result.append(NSAttributedString(attachment: attachment))
            if !text.isEmpty { result.append(NSAttributedString(string: "  ")) }
        }
        result.append(NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color,
        ]))
        return result
    }
}

/// Mor → pembe gradyan katmanlı görünüm.
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    init(colors: [UIColor] = [Theme.violet, Theme.pink]) {
        super.init(frame: .zero)
        let g = layer as! CAGradientLayer
        g.colors = colors.map(\.cgColor)
        g.startPoint = CGPoint(x: 0, y: 0)
        g.endPoint = CGPoint(x: 1, y: 1)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - İmleç

/// iPadOS işaretçisine benzer imleç: cam görünümlü yuvarlak; tıklanabilir öğe üstünde büyüyüp vurgu rengine döner.
final class CursorView: UIView {
    private let ring = UIView()
    private let dot = GradientView()
    private(set) var isHovering = false
    static let size: CGFloat = 44

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isUserInteractionEnabled = false
        ring.frame = bounds
        ring.layer.cornerRadius = Self.size / 2
        ring.backgroundColor = UIColor(white: 1, alpha: 0.88)
        ring.layer.borderColor = UIColor(white: 0, alpha: 0.18).cgColor
        ring.layer.borderWidth = 1.5
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.45
        ring.layer.shadowRadius = 10
        ring.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(ring)
        dot.frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        dot.center = CGPoint(x: bounds.midX, y: bounds.midY)
        dot.layer.cornerRadius = 7
        dot.layer.masksToBounds = true
        addSubview(dot)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setHovering(_ hovering: Bool, animated: Bool = true) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        let changes = {
            self.ring.transform = hovering ? CGAffineTransform(scaleX: 1.55, y: 1.55) : .identity
            self.ring.backgroundColor = hovering ? Theme.violet.withAlphaComponent(0.28) : UIColor(white: 1, alpha: 0.88)
            self.ring.layer.borderColor = (hovering ? Theme.pink : UIColor(white: 0, alpha: 0.18)).cgColor
            self.ring.layer.borderWidth = hovering ? 2.5 : 1.5
            self.dot.transform = hovering ? CGAffineTransform(scaleX: 0.7, y: 0.7) : .identity
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4,
                           options: [.beginFromCurrentState], animations: changes)
        } else {
            changes()
        }
    }

    func bounce() {
        UIView.animate(withDuration: 0.08, animations: { self.transform = CGAffineTransform(scaleX: 0.75, y: 0.75) }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8, options: [],
                           animations: { self.transform = .identity })
        }
    }
}

// MARK: - Bildirim

/// Alt ortada cam kapsül bildirim.
final class GlassToast: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 0
        blur.clipsToBounds = true
        addSubview(blur)
        label.numberOfLines = 2
        label.textAlignment = .center
        blur.contentView.addSubview(label)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ text: String, symbol: String? = nil, in container: UIView) {
        label.attributedText = Theme.label(text, symbol: symbol, size: 26)
        let maxWidth: CGFloat = 1200
        let size = label.sizeThatFits(CGSize(width: maxWidth - 72, height: 200))
        let w = min(maxWidth, size.width + 72), h = max(72, size.height + 34)
        frame = CGRect(x: (container.bounds.width - w) / 2, y: container.bounds.height - h - 64, width: w, height: h)
        blur.frame = bounds
        blur.layer.cornerRadius = min(h / 2, 36)
        label.frame = bounds.insetBy(dx: 36, dy: 0)
        container.bringSubviewToFront(self)
        layer.removeAllAnimations()
        transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [], animations: {
            self.alpha = 1
            self.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.35, delay: 2.2, options: [.allowUserInteraction], animations: { self.alpha = 0 })
        }
    }
}

// MARK: - Üst çubuk

/// Yüzen cam kapsül: site simgesi (kilit / küre / ev), başlık, adres, yükleniyor göstergesi ve rozetler.
/// Sayfa yüklenince kendiliğinden gizlenir; imleç üste yaklaşınca görünür.
final class ChromeBar: UIView {
    let titleLabel = UILabel()
    let hostLabel = UILabel()
    let spinner = UIActivityIndicatorView(style: .medium)
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let iconBackground = GradientView()
    private let icon = UIImageView()
    private let tint = UIView()
    let modeBadge = PaddedLabel.badge()
    let tabsBadge = PaddedLabel.badge()
    let privateBadge = PaddedLabel.badge()
    static let height: CGFloat = 88

    init() {
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 30
        layer.shadowOffset = CGSize(width: 0, height: 10)
        blur.clipsToBounds = true
        blur.layer.cornerRadius = Self.height / 2
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        addSubview(blur)
        tint.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.09, alpha: 0.55)
        blur.contentView.addSubview(tint)

        iconBackground.layer.cornerRadius = 28
        iconBackground.layer.masksToBounds = true
        icon.tintColor = .white
        icon.contentMode = .center
        spinner.color = .white
        spinner.hidesWhenStopped = true
        titleLabel.font = .systemFont(ofSize: 27, weight: .semibold)
        titleLabel.textColor = .white
        hostLabel.font = .systemFont(ofSize: 19, weight: .medium)
        hostLabel.textColor = Theme.textSecondary
        privateBadge.attributedText = Theme.label(L("Private"), symbol: "eye.slash.fill", size: 19)
        privateBadge.backgroundColor = Theme.violet.withAlphaComponent(0.9)
        tabsBadge.backgroundColor = UIColor(white: 1, alpha: 0.14)
        [iconBackground, icon, spinner, titleLabel, hostLabel, privateBadge, tabsBadge, modeBadge].forEach { blur.contentView.addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        let h = bounds.height
        iconBackground.frame = CGRect(x: 16, y: (h - 56) / 2, width: 56, height: 56)
        icon.frame = iconBackground.frame
        spinner.center = CGPoint(x: iconBackground.frame.midX, y: iconBackground.frame.midY)
        tint.frame = blur.bounds
        // Rozetler sağdan sola: mod, sekme sayısı, gizli
        var right = bounds.width - 18
        for badge in [modeBadge, tabsBadge, privateBadge] where !badge.isHidden {
            let size = badge.sizeThatFits(CGSize(width: 400, height: 60))
            badge.frame = CGRect(x: right - size.width, y: (h - size.height) / 2, width: size.width, height: size.height)
            right = badge.frame.minX - 12
        }
        let textX = iconBackground.frame.maxX + 20
        let textW = right - textX - 16
        titleLabel.frame = CGRect(x: textX, y: h / 2 - 32, width: textW, height: 34)
        hostLabel.frame = CGRect(x: textX, y: h / 2 + 3, width: textW, height: 26)
    }

    /// Simge: "house.fill" (ana sayfa), "lock.fill" (https), "globe" (diğer); yüklenirken yerine dönen gösterge.
    func update(title: String, host: String, symbol: String, loading: Bool) {
        titleLabel.text = title
        hostLabel.text = host
        icon.image = Theme.symbol(symbol, size: 24)
        setLoading(loading)
    }

    enum Region { case tabs, mode, privateMode, address }

    /// Çubuk üzerindeki bir noktanın hangi bölgeye denk geldiği (imleçle tıklama için; çubuk koordinatlarında).
    func region(at point: CGPoint) -> Region {
        func hit(_ v: UIView) -> Bool { !v.isHidden && v.frame.insetBy(dx: -10, dy: -14).contains(point) }
        if hit(tabsBadge) { return .tabs }
        if hit(modeBadge) { return .mode }
        if hit(privateBadge) { return .privateMode }
        return .address
    }

    func setLoading(_ loading: Bool) {
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        icon.isHidden = loading
    }

    func setBadges(cursorMode: Bool, tabCount: Int, isPrivate: Bool) {
        modeBadge.attributedText = Theme.label(cursorMode ? L("Cursor") : L("Scroll"),
                                               symbol: cursorMode ? "cursorarrow" : "arrow.up.and.down", size: 19)
        modeBadge.backgroundColor = cursorMode ? Theme.violet.withAlphaComponent(0.85) : Theme.teal.withAlphaComponent(0.85)
        tabsBadge.attributedText = Theme.label("\(tabCount)", symbol: "square.on.square", size: 19)
        tabsBadge.isHidden = false
        privateBadge.isHidden = !isPrivate
        setNeedsLayout()
    }
}

// MARK: - Arka plan

/// Ana sayfadaki gibi koyu zemin üzerinde mor / mavi / pembe ışık lekeleri (radyal gradyanlar).
final class AmbientBackground: UIView {
    private let glows: [(UIColor, CGPoint, CGFloat)] = [
        (Theme.violet.withAlphaComponent(0.6), CGPoint(x: 0.05, y: -0.05), 0.75),
        (Theme.pink.withAlphaComponent(0.42), CGPoint(x: 1.02, y: 1.05), 0.7),
        (Theme.blue.withAlphaComponent(0.38), CGPoint(x: 0.62, y: -0.12), 0.55),
        (Theme.teal.withAlphaComponent(0.22), CGPoint(x: -0.04, y: 1.05), 0.5),
    ]
    private var layersAdded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.027, green: 0.027, blue: 0.06, alpha: 1)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.filter { $0 is CAGradientLayer }.forEach { $0.removeFromSuperlayer() }
        for (color, center, radius) in glows {
            let g = CAGradientLayer()
            g.type = .radial
            g.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            let r = max(bounds.width, bounds.height) * radius
            g.frame = CGRect(x: bounds.width * center.x - r, y: bounds.height * center.y - r, width: r * 2, height: r * 2)
            layer.insertSublayer(g, at: 0)
        }
    }
}

/// Cam kapsül içinde kısa bilgi (oynatıcı üstü bildirimler için).
final class GlassCapsule: UIView {
    let label = UILabel()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

    init(text: String, symbol: String?, size: CGFloat = 26) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        blur.clipsToBounds = true
        addSubview(blur)
        label.attributedText = Theme.label(text, symbol: symbol, size: size)
        blur.contentView.addSubview(label)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 20
        let s = label.sizeThatFits(CGSize(width: 1200, height: 200))
        frame.size = CGSize(width: s.width + 56, height: s.height + 30)
        blur.frame = bounds
        blur.layer.cornerRadius = bounds.height / 2
        label.frame = bounds.insetBy(dx: 28, dy: 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String, symbol: String?, size: CGFloat = 26) {
        label.attributedText = Theme.label(text, symbol: symbol, size: size)
        let s = label.sizeThatFits(CGSize(width: 1200, height: 200))
        frame.size = CGSize(width: s.width + 56, height: s.height + 30)
        blur.frame = bounds
        blur.layer.cornerRadius = bounds.height / 2
        label.frame = bounds.insetBy(dx: 28, dy: 0)
    }
}
