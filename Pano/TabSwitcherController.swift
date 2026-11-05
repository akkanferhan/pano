import UIKit

/// Sekme ekranı: her sekme sayfa önizlemesiyle kart olarak gösterilir.
/// Seçim: sekmeye geç · Oynat/Duraklat: sekmeyi kapat · Menü: geri.
final class TabSwitcherController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    struct Card {
        let title: String
        let host: String
        let image: UIImage?
        let isCurrent: Bool
        let isPrivate: Bool
    }

    var cards: [Card] = []
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> [Card])?   // kapatılınca güncel kart listesini döndürür
    var onNewTab: (() -> Void)?
    var onCloseOthers: (() -> Void)?

    private let background = AmbientBackground()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private var collection: UICollectionView!
    private var currentIndex: Int { cards.firstIndex { $0.isCurrent } ?? 0 }

    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .overFullScreen
        background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(background)

        titleLabel.font = .systemFont(ofSize: 60, weight: .heavy)
        titleLabel.textColor = .white
        view.addSubview(titleLabel)
        hintLabel.attributedText = hint()
        view.addSubview(hintLabel)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 560, height: 430)
        layout.minimumLineSpacing = 56
        layout.sectionInset = UIEdgeInsets(top: 0, left: 110, bottom: 0, right: 110)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.clipsToBounds = false
        collection.remembersLastFocusedIndexPath = true
        collection.register(TabCardCell.self, forCellWithReuseIdentifier: "card")
        collection.dataSource = self
        collection.delegate = self
        view.addSubview(collection)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        hold.minimumPressDuration = 0.6
        collection.addGestureRecognizer(hold)
        updateTitle()
    }

    /// Odaktaki sekme kartının sırası (yeni sekme kartı hariç).
    private var focusedTabIndex: Int? {
        let focused = UIFocusSystem.focusSystem(for: view)?.focusedItem as? UIView
        var v = focused
        while let current = v, !(current is TabCardCell) { v = current.superview }
        guard let cell = v as? TabCardCell, let path = collection.indexPath(for: cell), path.item < cards.count else { return nil }
        return path.item
    }

    #if DEBUG
    /// Oynat/Duraklat ile aynı yol (odaktaki kart).
    func debugCloseFocused() -> String {
        guard let i = focusedTabIndex else { return "odakta sekme yok" }
        closeTab(at: i)
        return "kapatıldı: \(i)"
    }
    #endif

    func closeTab(at index: Int) {
        guard let updated = onClose?(index) else { return }
        let removedOne = updated.count == cards.count - 1
        cards = updated
        updateTitle()
        if removedOne {
            collection.performBatchUpdates({ collection.deleteItems(at: [IndexPath(item: index, section: 0)]) }) { [weak self] _ in
                guard let self else { return }
                // "Şu an" etiketi başka karta geçmiş olabilir
                self.collection.reloadItems(at: self.collection.indexPathsForVisibleItems)
            }
        } else {
            collection.reloadData()
        }
    }

    /// Basılı tutma: geç / kapat / diğerlerini kapat paneli.
    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let i = focusedTabIndex else { return }
        let card = cards[i]
        let panel = MenuPanelController(title: card.title, subtitle: card.host)
        panel.addItem("Sekmeye geç", symbol: "arrow.right.circle") { [weak self] in
            self?.dismiss(animated: true) { [onSelect = self?.onSelect] in onSelect?(i) }
        }
        panel.addItem("Sekmeyi kapat", symbol: "xmark.square", destructive: true) { [weak self] in self?.closeTab(at: i) }
        if cards.count > 1 {
            panel.addItem("Diğer sekmeleri kapat", symbol: "xmark.square", destructive: true) { [weak self] in
                guard let self else { return }
                for j in stride(from: self.cards.count - 1, through: 0, by: -1) where j != i { self.closeTab(at: j) }
            }
        }
        present(panel, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        titleLabel.frame = CGRect(x: 110, y: 110, width: 1000, height: 70)
        hintLabel.frame = CGRect(x: 110, y: 186, width: view.bounds.width - 220, height: 36)
        collection.frame = CGRect(x: 0, y: 300, width: view.bounds.width, height: 520)
    }

    private func updateTitle() {
        titleLabel.text = cards.count == 1 ? "1 sekme" : "\(cards.count) sekme"
    }

    private func hint() -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(Theme.label("Seç", symbol: "hand.tap.fill", size: 22, color: Theme.textSecondary))
        s.append(NSAttributedString(string: "  sekmeye geç      "))
        s.append(Theme.label("Oynat/Duraklat", symbol: "playpause.fill", size: 22, color: Theme.textSecondary))
        s.append(NSAttributedString(string: "  kapat      "))
        s.append(Theme.label("Basılı tut", symbol: "hand.point.up.left.fill", size: 22, color: Theme.textSecondary))
        s.append(NSAttributedString(string: "  seçenekler      "))
        s.append(Theme.label("Menü", symbol: "chevron.backward.circle.fill", size: 22, color: Theme.textSecondary))
        s.append(NSAttributedString(string: "  geri"))
        s.addAttributes([.font: UIFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: Theme.textSecondary],
                        range: NSRange(location: 0, length: s.length))
        return s
    }

    // MARK: Veri

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        cards.count + 1 // son kart: yeni sekme
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "card", for: indexPath) as! TabCardCell
        if indexPath.item < cards.count {
            cell.configure(cards[indexPath.item])
        } else {
            cell.configureNewTab()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item < cards.count {
            let i = indexPath.item
            dismiss(animated: true) { [onSelect] in onSelect?(i) }
        } else {
            dismiss(animated: true) { [onNewTab] in onNewTab?() }
        }
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        IndexPath(item: currentIndex, section: 0)
    }

    // MARK: Tuşlar

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else { return super.pressesEnded(presses, with: event) }
        switch press.type {
        case .playPause:
            if let i = focusedTabIndex { closeTab(at: i) }
        case .menu:
            dismiss(animated: true)
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.first?.type == .menu || presses.first?.type == .playPause { return }
        super.pressesBegan(presses, with: event)
    }
}

/// Sekme kartı: önizleme görseli (tvOS odak efektiyle büyür), başlık ve site adresi.
final class TabCardCell: UICollectionViewCell {
    private let preview = UIImageView()
    private let placeholder = AmbientBackground()
    private let symbol = UIImageView()
    private let title = UILabel()
    private let host = UILabel()
    private let badge = PaddedLabel.badge()
    private let closeHint = PaddedLabel.badge()
    private var isTab = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.adjustsImageWhenAncestorFocused = true
        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = false
        preview.layer.cornerRadius = 28
        contentView.addSubview(placeholder)
        contentView.addSubview(preview)
        symbol.tintColor = .white
        symbol.contentMode = .center
        contentView.addSubview(symbol)
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .white
        host.font = .systemFont(ofSize: 21, weight: .medium)
        host.textColor = Theme.textSecondary
        contentView.addSubview(title)
        contentView.addSubview(host)
        contentView.addSubview(badge)
        closeHint.attributedText = Theme.label("Kapat", symbol: "playpause.fill", size: 18)
        closeHint.backgroundColor = UIColor(white: 0, alpha: 0.7)
        closeHint.alpha = 0
        contentView.addSubview(closeHint)
        placeholder.layer.cornerRadius = 28
        placeholder.clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        preview.frame = CGRect(x: 0, y: 0, width: w, height: w * 9 / 16)
        placeholder.frame = preview.frame
        symbol.frame = preview.frame
        title.frame = CGRect(x: 6, y: preview.frame.maxY + 34, width: w - 12, height: 36)
        host.frame = CGRect(x: 6, y: title.frame.maxY + 2, width: w - 12, height: 28)
        let s = badge.sizeThatFits(CGSize(width: 300, height: 60))
        badge.frame = CGRect(x: 18, y: 18, width: s.width, height: s.height)
        let c = closeHint.sizeThatFits(CGSize(width: 300, height: 60))
        closeHint.frame = CGRect(x: w - c.width - 18, y: 18, width: c.width, height: c.height)
    }

    func configure(_ card: TabSwitcherController.Card) {
        preview.image = card.image
        placeholder.isHidden = card.image != nil
        symbol.image = card.image == nil ? Theme.symbol("globe", size: 64, weight: .light) : nil
        title.text = card.title
        host.text = card.host
        badge.isHidden = !card.isCurrent
        badge.attributedText = Theme.label("Şu an", symbol: "checkmark.circle.fill", size: 19)
        badge.backgroundColor = Theme.violet.withAlphaComponent(0.92)
        isTab = true
        setNeedsLayout()
    }

    func configureNewTab() {
        preview.image = nil
        placeholder.isHidden = false
        symbol.image = Theme.symbol("plus", size: 80, weight: .light)
        title.text = "Yeni sekme"
        host.text = "Ana sayfayı aç"
        badge.isHidden = true
        isTab = false
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            // Görsel yokken (yeni sekme / önizlemesiz) kendi büyütme efektimiz
            let scale: CGFloat = focused ? 1.08 : 1
            if self.preview.image == nil {
                self.placeholder.transform = CGAffineTransform(scaleX: scale, y: scale)
                self.symbol.transform = self.placeholder.transform
            }
            self.title.transform = focused ? CGAffineTransform(translationX: 0, y: 18) : .identity
            self.host.transform = self.title.transform
            self.badge.transform = focused ? CGAffineTransform(translationX: -12, y: -12) : .identity
            self.closeHint.alpha = focused && self.isTab ? 1 : 0
            self.closeHint.transform = focused ? CGAffineTransform(translationX: 12, y: -12) : .identity
        }
    }
}
