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

/// Basit kalıcı depolama: sık kullanılanlar, geçmiş ve ayarlar (UserDefaults).
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

    var bookmarks: [Bookmark] {
        get { decode("bookmarks") ?? defaultBookmarks }
        set { encode(newValue, "bookmarks") }
    }

    var history: [Bookmark] {
        get { decode("history") ?? [] }
        set { encode(Array(newValue.prefix(150)), "history") }
    }

    var desktopMode: Bool {
        get { d.object(forKey: "desktopMode") as? Bool ?? true }
        set { d.set(newValue, forKey: "desktopMode") }
    }

    var cursorSpeed: Double {
        get { d.object(forKey: "cursorSpeed") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "cursorSpeed") }
    }

    var textScale: Int {
        get { d.object(forKey: "textScale") as? Int ?? 100 }
        set { d.set(newValue, forKey: "textScale") }
    }

    var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: d.string(forKey: "searchEngine") ?? "") ?? .google }
        set { d.set(newValue.rawValue, forKey: "searchEngine") }
    }

    var hasSeenHelp: Bool {
        get { d.bool(forKey: "hasSeenHelp") }
        set { d.set(newValue, forKey: "hasSeenHelp") }
    }

    var lastURL: String? {
        get { d.string(forKey: "lastURL") }
        set { d.set(newValue, forKey: "lastURL") }
    }

    /// UIWebView kullanıcı ajanını "UserAgent" varsayılanından okur; web görünümü oluşturulmadan önce ayarlanmalı.
    func applyUserAgent() {
        d.set(desktopMode ? Self.desktopUA : Self.mobileUA, forKey: "UserAgent")
    }

    func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }

    func addHistory(title: String, url: String) {
        var h = history
        h.removeAll { $0.url == url }
        h.insert(Bookmark(title: title.isEmpty ? url : title, url: url), at: 0)
        history = h
    }

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
