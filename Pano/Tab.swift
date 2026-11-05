import UIKit

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
    /// Sekme ekranı için son anlık görüntü.
    var snapshot: UIImage?
    /// Bu gezinmede ilk ara "bitti" bildirimi işlendi mi (sonrakiler son bildirime kadar atlanır).
    var handledInterimFinish = false
    /// Yükleme bittiğindeki son işler (geçmiş, oturum, medya güvenliği) yapıldı mı.
    var finalHandled = false
    #if DEBUG
    var perfStart = Date()
    var perfFinishes = 0
    var perfOurTime: Double = 0
    var perfLogged = false
    #endif
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
