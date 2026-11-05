import Foundation

/// Bir tarayıcı sekmesi: kendi web motoru ve durumu.
final class Tab {
    var engine: WebEngine!
    var title = "Ana Sayfa"
    /// Yüklenmiş gerçek sayfa adresi (ana sayfa / hata sayfasında nil).
    var url: URL?
    var isHome = true
    /// Henüz yüklenmemiş (oturumdan geri yüklenen veya arka planda açılan) sekmenin adresi; nil = ana sayfa.
    var pendingURL: URL?
    var needsLoad = true
    /// Ana çerçevede en son istenen adres; alt çerçeve hatalarını ayırt etmek için.
    var mainRequestURL: String?
    /// Sayfa yüklenmeye başladığındaki toplam engelleme sayısı (sayfa başına sayaç için).
    var blockedAtStart = 0
    var isReader = false
    /// Ana çerçeve gezinmesinin başladığı an (bu sayfada yakalanan video adreslerini ayırmak için).
    var loadStartedAt = Date()
    /// Sonraki bölüme geçildi: sayfa yüklenince oynatıcı otomatik başlatılsın.
    var autoPlayPending = false

    /// Oturuma kaydedilecek adres; ana sayfa için boş metin.
    var sessionURL: String {
        if isHome && pendingURL == nil { return "" }
        return (url ?? pendingURL)?.absoluteString ?? ""
    }
}
