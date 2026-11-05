import Foundation

/// Reklam ve izleyici engelleyici.
/// UIWebView (WebKit1) ağ isteklerini uygulama içinde yaptığı için kayıtlı `URLProtocol`'lerden geçer;
/// bilinen reklam/izleyici alan adlarına giden her isteği (resim, betik, iframe…) burada düşürüyoruz.
/// Ek olarak sayfaya, boş kalan reklam kutularını gizleyen bir CSS enjekte edilir.
enum AdBlocker {
    static let errorDomain = "Pano.AdBlock"

    private static let lock = NSLock()
    private static var _enabled = true
    private static var _count = 0

    static var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set { lock.lock(); _enabled = newValue; lock.unlock() }
    }

    /// Uygulama açıldığından beri engellenen istek sayısı.
    static var blockedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    fileprivate static func noteBlocked() {
        lock.lock(); _count += 1; lock.unlock()
    }

    static func install() {
        enabled = Store.shared.adBlockEnabled
        URLProtocol.registerClass(AdBlockProtocol.self)
    }

    static func isBlocked(_ url: URL) -> Bool {
        guard enabled, let host = url.host?.lowercased() else { return false }
        var parts = host.split(separator: ".")
        while parts.count >= 2 {
            if domains.contains(parts.joined(separator: ".")) { return true }
            parts.removeFirst()
        }
        return false
    }

    static let cosmeticCSS = [
        "ins.adsbygoogle", ".adsbygoogle", "[id^='google_ads_']", "[id^='div-gpt-ad']", "[id*='gpt-ad']",
        "iframe[src*='doubleclick.net']", "iframe[src*='googlesyndication']", "iframe[src*='amazon-adsystem']",
        "[data-ad-slot]", "[data-ad-unit]", "[data-google-query-id]", ".ad-slot", ".ad-banner", ".ad-container",
        ".advertisement", ".adsbox", ".sponsored-ad", "[id^='taboola']", ".trc_related_container", ".OUTBRAIN",
        "[id^='outbrain']", "[class*='teads']", "[id^='criteo']",
    ].joined(separator: ",") + "{display:none!important;}"

    /// Yaygın reklam, izleme ve analiz alan adları (alt alan adları da engellenir).
    static let domains: Set<String> = [
        // Google reklam
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "pagead2.googlesyndication.com", "googletagservices.com", "google-analytics.com", "ssl.google-analytics.com",
        "googletagmanager.com", "2mdn.net", "imasdk.googleapis.com", "app-measurement.com",
        // Büyük reklam ağları
        "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net", "taboola.com",
        "outbrain.com", "outbrainimg.com", "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "indexww.com", "smartadserver.com", "adform.net", "adformdsp.net", "teads.tv", "yieldmo.com",
        "sharethrough.com", "33across.com", "triplelift.com", "3lift.com", "media.net", "contextweb.com",
        "sovrn.com", "lijit.com", "gumgum.com", "bidswitch.net", "adsafeprotected.com", "moatads.com",
        "doubleverify.com", "serving-sys.com", "flashtalking.com", "advertising.com", "adtechus.com",
        "yieldlab.net", "zemanta.com", "revcontent.com", "mgid.com", "propellerads.com", "popads.net",
        "popcash.net", "adcash.com", "exoclick.com", "juicyads.com", "trafficjunky.net", "adsterra.com",
        "hilltopads.net", "admaven.com", "onclickads.net", "adskeeper.com", "yandexadexchange.net",
        "adriver.ru", "betweendigital.com", "admatic.com.tr", "admatic.de", "seedtag.com", "unrulymedia.com",
        "spotxchange.com", "spotx.tv", "springserve.com", "lkqd.net", "connatix.com", "primis.tech",
        "vidazoo.com", "aniview.com", "adition.com", "stroeer.io", "permutive.com", "id5-sync.com",
        "liadm.com", "rlcdn.com", "bluekai.com", "demdex.net", "krxd.net", "exelator.com", "agkn.com",
        "mathtag.com", "turn.com", "eyeota.net", "tapad.com", "crwdcntrl.net", "everesttech.net",
        // Analiz / izleme
        "scorecardresearch.com", "quantserve.com", "quantcount.com", "chartbeat.com", "chartbeat.net",
        "hotjar.com", "hotjar.io", "mouseflow.com", "fullstory.com", "crazyegg.com", "luckyorange.com",
        "mc.yandex.ru", "mc.yandex.com", "clarity.ms", "newrelic.com", "nr-data.net", "segment.io",
        "mixpanel.com", "amplitude.com", "branch.io", "adjust.com", "appsflyer.com", "kochava.com",
        "connect.facebook.net", "pixel.facebook.com", "an.facebook.com", "ads.twitter.com",
        "analytics.twitter.com", "ads.linkedin.com", "px.ads.linkedin.com", "analytics.tiktok.com",
        "ads.tiktok.com", "bat.bing.com", "ads.yahoo.com", "analytics.yahoo.com", "sc-static.net",
        "tr.snapchat.com", "ct.pinterest.com", "omtrdc.net", "2o7.net", "statcounter.com", "histats.com",
        "gemius.pl", "xiti.com", "effectivemeasure.net", "cxense.com", "parsely.com", "onesignal.com",
        "pushwoosh.com", "pushcrew.com", "sumo.com", "addthis.com", "sharethis.com",
    ]
}

final class AdBlockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return AdBlocker.isBlocked(url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        AdBlocker.noteBlocked()
        let error = NSError(domain: AdBlocker.errorDomain, code: 1, userInfo: [
            NSURLErrorFailingURLStringErrorKey: request.url?.absoluteString ?? "",
            NSLocalizedDescriptionKey: "Reklam/izleyici engellendi",
        ])
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
