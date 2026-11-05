import Foundation

struct WatchProgress: Codable, Equatable {
    var pageURL: String
    /// Videonun kimliği (adresin host + yol kısmı; sorgu/anahtar hariç). Eski kayıtlarda yok.
    var videoKey: String?
    var title: String
    var position: Double
    var duration: Double
    var date: Date
}

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

    /// First-run favorites, adapted to the app language (Wikipedia edition, weather site).
    private var defaultBookmarks: [Bookmark] {
        let lang = AppLanguage.shortCode
        let wikiLang = ["zh", "hi", "es", "fr", "ar", "pt", "ru", "de", "ja", "tr"].contains(lang) ? lang : "en"
        return [
            Bookmark(title: "Google", url: "https://www.google.com"),
            Bookmark(title: "YouTube", url: "https://www.youtube.com"),
            Bookmark(title: L("Wikipedia"), url: "https://\(wikiLang).wikipedia.org"),
            Bookmark(title: "GitHub", url: "https://github.com"),
            Bookmark(title: "Hacker News", url: "https://news.ycombinator.com"),
            Bookmark(title: L("Weather"), url: lang == "tr" ? "https://www.mgm.gov.tr" : "https://weather.com"),
        ]
    }

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

    /// Şimdilik varsayılan olarak kapalı (bazı film oynatıcıları reklam betikleri olmadan başlamıyor).
    var adBlockEnabled: Bool {
        get {
            if !d.bool(forKey: "adBlockDefaultOffApplied") { // önceki sürümde açık kalmış olanları bir kez kapat
                d.set(true, forKey: "adBlockDefaultOffApplied")
                d.set(false, forKey: "adBlockEnabled")
            }
            return d.object(forKey: "adBlockEnabled") as? Bool ?? false
        }
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

    // MARK: İzlemeye devam

    var watchProgress: [WatchProgress] {
        get { decode("watchProgress") ?? [] }
        set { encode(Array(newValue.prefix(100)), "watchProgress") }
    }

    /// Bir sayfadaki tüm yarım kalmış videolar (aynı sayfada birden çok video olabilir).
    func progressEntries(for page: String) -> [WatchProgress] {
        watchProgress.filter { $0.pageURL == page }
    }

    /// Kayıt sayfa + video ikilisine göre tutulur. 30 sn'den kısa izlemeler kaydedilmez;
    /// bitmek üzere olanlar (son 90 sn) listeden çıkarılır.
    func saveProgress(page: String, videoKey: String?, title: String, position: Double, duration: Double) {
        guard position.isFinite else { return }
        var list = watchProgress
        list.removeAll { $0.pageURL == page && ($0.videoKey == videoKey || $0.videoKey == nil) }
        let finished = duration.isFinite && duration > 0 && duration - position < 90
        if position >= 30 && !finished {
            list.insert(WatchProgress(pageURL: page, videoKey: videoKey, title: title, position: position,
                                      duration: duration.isFinite ? duration : 0, date: Date()), at: 0)
        }
        watchProgress = list
    }

    /// Video adresinden kalıcı kimlik: host + yol (oturum anahtarı / sorgu kısmı atılır).
    static func videoKey(for url: URL) -> String {
        (url.host ?? "") + url.path
    }

    // MARK: Oynatıcı ayarları

    var playbackRate: Double {
        get { d.object(forKey: "playbackRate") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "playbackRate") }
    }

    var subtitleFontSize: Double {
        get { d.object(forKey: "subtitleFontSize") as? Double ?? 46 }
        set { d.set(newValue, forKey: "subtitleFontSize") }
    }

    /// "white" | "yellow"
    var subtitleColor: String {
        get { d.string(forKey: "subtitleColor") ?? "white" }
        set { d.set(newValue, forKey: "subtitleColor") }
    }

    /// 0 = yok (kenarlıklı yazı), 1 = yarı saydam kutu, 2 = siyah kutu
    var subtitleBackground: Int {
        get { d.object(forKey: "subtitleBackground") as? Int ?? 0 }
        set { d.set(newValue, forKey: "subtitleBackground") }
    }

    var skipStep: Int {
        get { d.object(forKey: "skipStep") as? Int ?? 10 }
        set { d.set(newValue, forKey: "skipStep") }
    }

    // MARK: OpenSubtitles

    var openSubtitlesKey: String? {
        get { d.string(forKey: "openSubtitlesKey").flatMap { $0.isEmpty ? nil : $0 } }
        set { d.set(newValue, forKey: "openSubtitlesKey") }
    }

    var openSubtitlesUser: String? {
        get { d.string(forKey: "openSubtitlesUser").flatMap { $0.isEmpty ? nil : $0 } }
        set { d.set(newValue, forKey: "openSubtitlesUser") }
    }

    var openSubtitlesToken: String? {
        get { d.string(forKey: "openSubtitlesToken").flatMap { $0.isEmpty ? nil : $0 } }
        set { d.set(newValue, forKey: "openSubtitlesToken") }
    }

    // MARK: Telefondan kontrol

    var remoteEnabled: Bool {
        get { d.bool(forKey: "remoteEnabled") }
        set { d.set(newValue, forKey: "remoteEnabled") }
    }

    /// Telefon sayfasının istediği 4 haneli kod (aynı ağdaki başkalarının tarayıcıyı yönetmesini engeller).
    var remotePIN: String {
        if let pin = d.string(forKey: "remotePIN"), pin.count == 4 { return pin }
        let pin = String(format: "%04d", Int.random(in: 0...9999))
        d.set(pin, forKey: "remotePIN")
        return pin
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
