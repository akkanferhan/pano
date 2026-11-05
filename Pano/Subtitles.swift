import Foundation

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

/// Yüklenmiş (satırları hazır) altyazı.
struct SubtitleTrack {
    let label: String
    let language: String?
    let cues: [SubtitleCue]
    let source: String // tekrarları ayıklamak için (address or "page:<label>")
}

/// Henüz yüklenmemiş altyazı kaynağı: bir dosya adresi ya da sayfadaki oynatıcıdan okunmuş satırlar.
enum SubtitleSource {
    case url(URL, label: String, language: String?, referer: String?)
    case cues([SubtitleCue], label: String, language: String?)

    var key: String {
        switch self {
        case let .url(url, _, _, _): return url.absoluteString
        case let .cues(_, label, language): return "page:\(label)|\(language ?? "")"
        }
    }
}

enum Subtitles {
    // MARK: Dil tahmini

    /// Etiket / dil kodu / dosya adından okunabilir ad ve dil kodu üretir.
    static func describe(label: String, language: String?, url: URL?) -> (label: String, language: String?) {
        let lang = (language?.isEmpty == false ? language : guessLanguage(label + " " + (url?.lastPathComponent ?? "")))
        if !label.isEmpty { return (label, lang) }
        if let lang, let name = Locale.current.localizedString(forLanguageCode: lang) {
            return (name.prefix(1).uppercased() + name.dropFirst(), lang)
        }
        return (url?.lastPathComponent ?? L("Subtitle"), lang)
    }

    static func guessLanguage(_ text: String) -> String? {
        let s = text.lowercased()
        let tokens = s.split { !$0.isLetter }.map(String.init)
        if s.contains("türk") || s.contains("turk") || tokens.contains("tr") || tokens.contains("tur") { return "tr" }
        if s.contains("ingiliz") || s.contains("english") || tokens.contains("en") || tokens.contains("eng") { return "en" }
        return nil
    }

    /// Is the track in the app's language? (e.g. Turkish subtitles are preferred in a Turkish UI.)
    static func isPreferred(_ track: SubtitleTrack) -> Bool {
        let want = AppLanguage.shortCode
        if let l = track.language?.lowercased(), l.hasPrefix(want) || (want == "tr" && l == "tur") { return true }
        if guessLanguage(track.label) == want { return true }
        let name = Locale.current.localizedString(forLanguageCode: want)?.lowercased() ?? want
        return track.label.lowercased().contains(name)
    }

    // MARK: Yükleme

    /// Altyazı dosyasını indirir ve çözer. Türkçe SRT'ler sık sık Windows-1254 olduğu için o kodlama da denenir.
    static func load(_ url: URL, referer: String?, userAgent: String, completion: @escaping ([SubtitleCue]?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer, let ref = URL(string: referer), let scheme = ref.scheme, let host = ref.host {
            request.setValue(referer, forHTTPHeaderField: "Referer")
            request.setValue("\(scheme)://\(host)" + (ref.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Origin")
        }
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let cues = data.flatMap(decode).map(parse)
            DispatchQueue.main.async { completion(cues?.isEmpty == false ? cues : nil) }
        }.resume()
    }

    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        let cp1254 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
        if let s = String(data: data, encoding: cp1254) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    // MARK: Ayrıştırma (SRT / WebVTT)

    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTime(parts[0]),
                  let end = parseTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
            else { continue }
            let body = lines[(timeIndex + 1)...].joined(separator: "\n")
            let clean = cleanText(body)
            if !clean.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: clean)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "01:02:03,456", "01:02:03.456", "02:03.456" biçimlerini saniyeye çevirir.
    static func parseTime(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let v = Double(part) else { return nil }
            seconds = seconds * 60 + v
        }
        return seconds
    }

    static func cleanText(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\\N", with: "\n")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        return s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
