import Foundation

/// OpenSubtitles.com REST API (v1) istemcisi. API anahtarı Ayarlar'dan girilir
/// (https://www.opensubtitles.com/consumers adresinden ücretsiz alınır). Kullanıcı adı/şifre isteğe bağlıdır;
/// girişsiz indirme kotası düşüktür.
enum OpenSubtitles {
    struct Item {
        let fileID: Int
        let release: String
        let downloads: Int
    }

    private static let base = "https://api.opensubtitles.com/api/v1/"

    static var isConfigured: Bool { Store.shared.openSubtitlesKey != nil }

    // MARK: İstekler

    private static func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                                body: [String: Any]? = nil, auth: Bool = true) -> URLRequest? {
        guard let key = Store.shared.openSubtitlesKey, var c = URLComponents(string: base + path) else { return nil }
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "Api-Key")
        r.setValue("Pano v1.0", forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth, let token = Store.shared.openSubtitlesToken {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    private static func send(_ r: URLRequest, completion: @escaping ([String: Any]?, String?) -> Void) {
        URLSession.shared.dataTask(with: r) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            var message: String?
            if let error {
                message = error.localizedDescription
            } else if !(200..<300).contains(status) {
                message = (json?["message"] as? String)
                    ?? (json?["errors"] as? [String])?.joined(separator: ", ")
                    ?? "Sunucu hatası (HTTP \(status))"
                if status == 401 || status == 403 { message = (message ?? "") + " — API anahtarını kontrol et." }
            }
            DispatchQueue.main.async { completion(message == nil ? json : nil, message) }
        }.resume()
    }

    // MARK: Arama / indirme / giriş

    static func search(query: String, season: Int?, episode: Int?,
                       completion: @escaping ([Item], String?) -> Void) {
        var q = [URLQueryItem(name: "query", value: query.lowercased()),
                 URLQueryItem(name: "languages", value: "tr"),
                 URLQueryItem(name: "order_by", value: "download_count")]
        if let season { q.append(URLQueryItem(name: "season_number", value: String(season))) }
        if let episode { q.append(URLQueryItem(name: "episode_number", value: String(episode))) }
        guard let r = request("subtitles", query: q) else { return completion([], "OpenSubtitles API anahtarı girilmemiş.") }
        send(r) { json, error in
            guard let data = json?["data"] as? [[String: Any]] else { return completion([], error ?? "Sonuç alınamadı") }
            let items: [Item] = data.compactMap { entry in
                guard let a = entry["attributes"] as? [String: Any],
                      let file = (a["files"] as? [[String: Any]])?.first,
                      let id = file["file_id"] as? Int else { return nil }
                let release = (a["release"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (file["file_name"] as? String) ?? "Altyazı \(id)"
                return Item(fileID: id, release: release, downloads: a["download_count"] as? Int ?? 0)
            }
            completion(items, nil)
        }
    }

    static func download(_ item: Item, completion: @escaping ([SubtitleCue]?, String?) -> Void) {
        guard let r = request("download", method: "POST", body: ["file_id": item.fileID, "sub_format": "srt"]) else {
            return completion(nil, "OpenSubtitles API anahtarı girilmemiş.")
        }
        send(r) { json, error in
            guard let link = (json?["link"] as? String).flatMap(URL.init(string:)) else {
                return completion(nil, error ?? (json?["message"] as? String) ?? "İndirme bağlantısı alınamadı")
            }
            URLSession.shared.dataTask(with: link) { data, _, err in
                let cues = data.flatMap(Subtitles.decode).map(Subtitles.parse)
                DispatchQueue.main.async {
                    if let cues, !cues.isEmpty { completion(cues, nil) } else { completion(nil, err?.localizedDescription ?? "Altyazı dosyası okunamadı") }
                }
            }.resume()
        }
    }

    static func login(username: String, password: String, completion: @escaping (String?) -> Void) {
        guard let r = request("login", method: "POST", body: ["username": username, "password": password], auth: false) else {
            return completion("Önce API anahtarını gir.")
        }
        send(r) { json, error in
            if let token = json?["token"] as? String {
                Store.shared.openSubtitlesToken = token
                Store.shared.openSubtitlesUser = username
                completion(nil)
            } else {
                completion(error ?? "Giriş yapılamadı")
            }
        }
    }

    // MARK: Başlık / bölüm çözümleme

    /// Sayfa başlığından film/dizi adını çıkarır ("X izle | Site" → "X").
    static func cleanTitle(_ raw: String) -> String {
        var t = raw
        for sep in [" | ", " - ", " – ", " — ", " :: "] {
            if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) }
        }
        let patterns = [
            #"\d+\.?\s*sezon.*$"#, #"\bs\d{1,2}\s*e\d{1,3}\b.*$"#, #"\d+\.?\s*b[öo]l[üu]m.*$"#,
            #"\(\d{4}\)"#,
            #"(?<![\p{L}])(full\s*hd|hd|1080p|720p|4k|[iİ]zle|t[üuÜU]rk[çcÇC]e\s*dublaj|t[üuÜU]rk[çcÇC]e\s*altyaz[ıiIİ]l[ıiIİ]|altyaz[ıiIİ]l[ıiIİ]|dublaj|tek\s*par[çcÇC]a|online|full|f[iİ]lm|d[iİ]z[iİ])(?![\p{L}])"#,
        ]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -|:,"))
    }

    /// "1. Sezon 5. Bölüm", "sezon-1-bolum-5", "1-sezon-5-bolum", "S01E05" biçimlerinden sezon/bölüm.
    static func episode(from text: String) -> (season: Int?, episode: Int?) {
        let patterns = [
            #"(\d+)\.?\s*sezon\s*(\d+)\.?\s*b[öo]l[üu]m"#,
            #"(\d+)-sezon-(\d+)-b[öo]l[üu]m"#,
            #"sezon[-\s]*(\d+)[-\s]*b[öo]l[üu]m[-\s]*(\d+)"#,
            #"\bs(\d{1,2})\s*e(\d{1,3})\b"#,
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
            return (Int(text[r1]), Int(text[r2]))
        }
        return (nil, nil)
    }

    /// Sonraki bölüm bağlantısı bulunamazsa adresteki bölüm numarasını bir artırarak tahmin eder.
    static func guessNextEpisodeURL(_ url: URL) -> URL? {
        let s = url.absoluteString
        // Önce "bolum-12" (numara sonda), sonra "5-bolum" (numara önde): "sezon-3-bolum-12"de sezon artmasın.
        let patterns = [#"(b[öo]l[üu]m|episode|ep)([-_.]?)(\d+)"#, #"(\d+)([-_.]?)(b[öo]l[üu]m|episode|ep)\b"#]
        for (i, p) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { continue }
            let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
            guard let m = matches.last else { continue }
            let numberGroup = i == 0 ? 3 : 1
            guard let r = Range(m.range(at: numberGroup), in: s), let n = Int(s[r]) else { continue }
            let digits = s[r].count
            let next = String(format: "%0\(digits)d", n + 1)
            return URL(string: s.replacingCharacters(in: r, with: next))
        }
        return nil
    }
}
