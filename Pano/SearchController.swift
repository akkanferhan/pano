import UIKit

/// Modern address / search screen: tvOS's native search layout (keyboard at the top, dictation supported)
/// with live suggestions below — "Go to address", "Search with <engine>", matching favorites and history.
enum AddressSearch {
    static func make(initialText: String?, onChoose: @escaping (String) -> Void) -> UIViewController {
        let results = SearchSuggestionsController()
        let search = UISearchController(searchResultsController: results)
        search.searchResultsUpdater = results
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = L("Search with %@ or enter an address", Store.shared.searchEngine.name)
        search.searchBar.text = initialText
        search.searchBar.keyboardType = .URL
        search.searchBar.autocapitalizationType = .none
        search.searchBar.autocorrectionType = .no
        let container = UISearchContainerViewController(searchController: search)
        container.modalPresentationStyle = .fullScreen
        let background = AmbientBackground()
        background.frame = container.view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.insertSubview(background, at: 0)
        results.onChoose = { [weak container] text in
            container?.dismiss(animated: true) { onChoose(text) }
        }
        results.update(query: initialText ?? "")
        return container
    }
}

/// Suggestion list under the search keyboard.
final class SearchSuggestionsController: UIViewController, UISearchResultsUpdating, UITableViewDataSource, UITableViewDelegate {
    struct Row {
        let title: String
        let detail: String?
        let symbol: String
        let value: String // address or search text passed to `open`
        let accent: Bool
    }

    var onChoose: ((String) -> Void)?
    private let table = UITableView(frame: .zero, style: .plain)
    private var rows: [Row] = []
    private let store = Store.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 96
        table.remembersLastFocusedIndexPath = false
        table.register(SuggestionCell.self, forCellReuseIdentifier: "row")
        view.addSubview(table)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = min(1300, view.bounds.width - 200)
        table.frame = CGRect(x: (view.bounds.width - w) / 2, y: 20, width: w, height: view.bounds.height - 40)
    }

    func updateSearchResults(for searchController: UISearchController) {
        update(query: searchController.searchBar.text ?? "")
    }

    func update(query raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var list: [Row] = []
        if !query.isEmpty {
            let looksLikeURL = !query.contains(" ") && (query.contains(".") || query.contains("://"))
            if looksLikeURL {
                let shown = query.contains("://") ? query : "https://" + query
                list.append(Row(title: L("Go to %@", query), detail: shown, symbol: "globe", value: query, accent: true))
            }
            list.append(Row(title: L("Search %@ for “%@”", store.searchEngine.name, query), detail: nil,
                            symbol: "magnifyingglass", value: query, accent: !looksLikeURL))
            let q = query.lowercased()
            var seen = Set<String>()
            for b in store.bookmarks where b.title.lowercased().contains(q) || b.url.lowercased().contains(q) {
                guard seen.insert(b.url).inserted else { continue }
                list.append(Row(title: b.title, detail: b.url, symbol: "star.fill", value: b.url, accent: false))
            }
            for h in store.searchHistory(query).prefix(12) {
                guard seen.insert(h.url).inserted else { continue }
                list.append(Row(title: h.title, detail: h.url, symbol: "clock", value: h.url, accent: false))
            }
        } else {
            for b in store.bookmarks.prefix(8) {
                list.append(Row(title: b.title, detail: b.url, symbol: "star.fill", value: b.url, accent: false))
            }
            for h in store.history.prefix(8) where !store.bookmarks.contains(where: { $0.url == h.url }) {
                list.append(Row(title: h.title, detail: h.url, symbol: "clock", value: h.url, accent: false))
            }
        }
        rows = Array(list.prefix(20))
        if isViewLoaded { table.reloadData() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SuggestionCell
        cell.configure(rows[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onChoose?(rows[indexPath.row].value)
    }
}

/// Glass suggestion row: icon well, title, detail.
final class SuggestionCell: UITableViewCell {
    private let card = UIView()
    private let well = UIView()
    private let gradient = GradientView()
    private let icon = UIImageView()
    private let title = UILabel()
    private let detail = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        focusStyle = .custom
        card.backgroundColor = UIColor(white: 1, alpha: 0.07)
        card.layer.cornerRadius = 24
        contentView.addSubview(card)
        well.layer.cornerRadius = 16
        well.clipsToBounds = true
        well.backgroundColor = UIColor(white: 1, alpha: 0.1)
        gradient.alpha = 0
        well.addSubview(gradient)
        icon.tintColor = .white
        icon.contentMode = .center
        well.addSubview(icon)
        card.addSubview(well)
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .white
        detail.font = .systemFont(ofSize: 20, weight: .medium)
        detail.textColor = Theme.textSecondary
        card.addSubview(title)
        card.addSubview(detail)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds.insetBy(dx: 0, dy: 6)
        let h = card.bounds.height
        well.frame = CGRect(x: 18, y: (h - 54) / 2, width: 54, height: 54)
        gradient.frame = well.bounds
        icon.frame = well.bounds
        let x = well.frame.maxX + 22, w = card.bounds.width - x - 24
        let hasDetail = detail.text?.isEmpty == false
        title.frame = CGRect(x: x, y: hasDetail ? h / 2 - 34 : 0, width: w, height: hasDetail ? 36 : h)
        detail.frame = CGRect(x: x, y: h / 2 + 3, width: w, height: 26)
    }

    func configure(_ row: SearchSuggestionsController.Row) {
        title.text = row.title
        detail.text = row.detail
        icon.image = Theme.symbol(row.symbol, size: 24)
        gradient.alpha = row.accent ? 1 : 0
        setNeedsLayout()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            self.card.transform = focused ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
            self.card.backgroundColor = focused ? UIColor(white: 1, alpha: 0.2) : UIColor(white: 1, alpha: 0.07)
        }
    }
}
