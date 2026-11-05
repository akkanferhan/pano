import Foundation

/// Sayfaların ağ isteklerinden video adreslerini (HLS .m3u8, .mp4, .m4v, .mov) yakalar.
/// Film sitelerinin oynatıcıları videoyu çoğunlukla JavaScript ile çektiği için `<video>` öğesinde
/// doğrudan bir adres görünmeyebilir; bu durumda buradaki adres tvOS oynatıcısında açılır.
enum MediaSniffer {
    struct Item {
        let url: URL
        let referer: String?
        let date: Date
        var isPlaylist: Bool { url.absoluteString.lowercased().contains(".m3u8") }
    }

    private static let lock = NSLock()
    private static var items: [Item] = []

    static func note(_ request: URLRequest) {
        guard let url = request.url, isMedia(url) else { return }
        let item = Item(url: url, referer: request.value(forHTTPHeaderField: "Referer"), date: Date())
        lock.lock()
        if !items.contains(where: { $0.url == url }) {
            items.append(item)
            if items.count > 200 { items.removeFirst(items.count - 200) }
        }
        lock.unlock()
    }

    /// Belirtilen andan sonra istenen video adresleri (eskiden yeniye).
    static func items(since date: Date) -> [Item] {
        lock.lock(); defer { lock.unlock() }
        return items.filter { $0.date >= date }
    }

    private static func isMedia(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        if s.contains(".m3u8") { return true }
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov"].contains(ext)
    }
}
