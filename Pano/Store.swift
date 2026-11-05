import Foundation

struct Bookmark: Codable, Equatable {
    var title: String
    var url: String
}

enum SearchEngine: String, CaseIterable {
    case google, duckduckgo, bing

    var name: String {
        switch self {
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing: "Bing"
        }
    }

    func url(for query: String) -> URL? {
        var c: URLComponents
        switch self {
        case .google: c = URLComponents(string: "https://www.google.com/search")!
        case .duckduckgo: c = URLComponents(string: "https://duckduckgo.com/")!
        case .bing: c = URLComponents(string: "https://www.bing.com/search")!
        }
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url
    }
}

/// Kalıcı depolama: sık kullanılanlar, geçmiş, oturum, ayarlar (UserDefaults).
final class Store {
    static let shared = Store()
    private let d = UserDefaults.standard

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    static let mobileUA = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let defaultBookmarks = [
        Bookmark(title: "Google", url: "https://www.google.com"),
        Bookmark(title: "YouTube", url: "https://www.youtube.com"),
        Bookmark(title: "Vikipedi", url: "https://tr.wikipedia.org"),
        Bookmark(title: "GitHub", url: "https://github.com"),
        Bookmark(title: "Hacker News", url: "https://news.ycombinator.com"),
        Bookmark(title: "Hava Durumu", url: "https://www.mgm.gov.tr"),
    ]

    // MARK: Sık kullanılanlar

    var bookmarks: [Bookmark] {
        get { decode("bookmarks") ?? defaultBookmarks }
        set { encode(newValue, "bookmarks") }
    }

    func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }

    func renameBookmark(at i: Int, to title: String) {
        var b = bookmarks
        guard b.indices.contains(i), !title.isEmpty else { return }
        b[i].title = title
        bookmarks = b
    }

    func moveBookmark(from i: Int, to j: Int) {
        var b = bookmarks
        guard b.indices.contains(i) else { return }
        let item = b.remove(at: i)
        b.insert(item, at: min(max(j, 0), b.count))
        bookmarks = b
    }

    // MARK: Geçmiş

    var history: [Bookmark] {
        get { decode("history") ?? [] }
        set { encode(Array(newValue.prefix(300)), "history") }
    }

    func addHistory(title: String, url: String) {
        var h = history
        h.removeAll { $0.url == url }
        h.insert(Bookmark(title: title.isEmpty ? url : title, url: url), at: 0)
        history = h
    }

    func searchHistory(_ query: String) -> [Bookmark] {
        let q = query.lowercased()
        return history.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) }
    }

    // MARK: Oturum (açık sekmeler)

    /// Her sekmenin adresi; ana sayfa için boş metin.
    var sessionTabs: [String] {
        get { d.stringArray(forKey: "sessionTabs") ?? [] }
        set { d.set(newValue, forKey: "sessionTabs") }
    }

    var sessionIndex: Int {
        get { d.integer(forKey: "sessionIndex") }
        set { d.set(newValue, forKey: "sessionIndex") }
    }

    // MARK: Ayarlar

    var desktopMode: Bool {
        get { d.object(forKey: "desktopMode") as? Bool ?? true }
        set { d.set(newValue, forKey: "desktopMode") }
    }

    var currentUA: String { desktopMode ? Self.desktopUA : Self.mobileUA }

    var cursorSpeed: Double {
        get { d.object(forKey: "cursorSpeed") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "cursorSpeed") }
    }

    var textScale: Int {
        get { d.object(forKey: "textScale") as? Int ?? 100 }
        set { d.set(newValue, forKey: "textScale") }
    }

    var defaultZoom: Int {
        get { d.object(forKey: "defaultZoom") as? Int ?? 100 }
        set { d.set(newValue, forKey: "defaultZoom") }
    }

    private var zoomByHost: [String: Int] {
        get { d.dictionary(forKey: "zoomByHost") as? [String: Int] ?? [:] }
        set { d.set(newValue, forKey: "zoomByHost") }
    }

    func zoom(for host: String?) -> Int {
        guard let host else { return defaultZoom }
        return zoomByHost[host] ?? defaultZoom
    }

    func setZoom(_ zoom: Int, for host: String) {
        var z = zoomByHost
        z[host] = zoom == defaultZoom ? nil : zoom
        zoomByHost = z
    }

    var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: d.string(forKey: "searchEngine") ?? "") ?? .google }
        set { d.set(newValue.rawValue, forKey: "searchEngine") }
    }

    var adBlockEnabled: Bool {
        get { d.object(forKey: "adBlockEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "adBlockEnabled"); AdBlocker.enabled = newValue }
    }

    var hasSeenHelp: Bool {
        get { d.bool(forKey: "hasSeenHelp") }
        set { d.set(newValue, forKey: "hasSeenHelp") }
    }

    // MARK: Gizli gezinme

    /// Gizli moddayken geçmiş ve oturum kaydedilmez; çıkarken çerezler girişteki hâline döndürülür.
    private(set) var privateMode: Bool {
        get { d.bool(forKey: "privateMode") }
        set { d.set(newValue, forKey: "privateMode") }
    }

    func beginPrivate() {
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).map { c -> [String: Any] in
            var dict: [String: Any] = [:]
            for (k, v) in c.properties ?? [:] { dict[k.rawValue] = v }
            return dict
        }
        let data = try? PropertyListSerialization.data(fromPropertyList: cookies, format: .binary, options: 0)
        d.set(data, forKey: "privateCookieSnapshot")
        privateMode = true
    }

    func endPrivate() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }
        if let data = d.data(forKey: "privateCookieSnapshot"),
           let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] {
            for dict in list {
                var props: [HTTPCookiePropertyKey: Any] = [:]
                for (k, v) in dict { props[HTTPCookiePropertyKey(k)] = v }
                if let cookie = HTTPCookie(properties: props) { storage.setCookie(cookie) }
            }
        }
        URLCache.shared.removeAllCachedResponses()
        d.removeObject(forKey: "privateCookieSnapshot")
        privateMode = false
    }

    // MARK: Yardımcılar

    /// Adres çubuğuna yazılanı URL'ye çevirir; adres gibi görünmüyorsa arama yapar.
    func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://"), let url = URL(string: text) { return url }
        let looksLikeHost = !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost"))
        if looksLikeHost, let url = URL(string: "https://" + text) { return url }
        return searchEngine.url(for: text)
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        d.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
