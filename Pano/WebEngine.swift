import Darwin
import UIKit

private typealias WebThreadLockFn = @convention(c) () -> Void

/// WebKit1 nesnelerine ana iş parçacığından dokunmadan önce alınması gereken kilit (WebCore'daki WebThreadLock).
private let webThreadLock: WebThreadLockFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "WebThreadLock") else { return nil }
    return unsafeBitCast(sym, to: WebThreadLockFn.self)
}()

/// tvOS'ta WebKit/WKWebView açık API olarak sunulmuyor. Ancak UIKit içindeki `UIWebView`
/// sınıfı çalışma zamanında hâlâ mevcut (tvOS SDK'sının UIKit.tbd dosyasında dışa aktarılıyor).
/// Swift bu sınıfı adıyla kullanmamıza izin vermediği için `NSClassFromString` ile oluşturup
/// Objective-C seçicileri üzerinden konuşuyoruz.
///
/// Not: Bu yöntem özel API sayılır; App Store'a gönderilemez, kişisel (Xcode ile yükleme) kullanım içindir.
final class WebEngine {
    let view: UIView
    private let bridge = DelegateBridge()

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onFail: ((NSError) -> Void)?
    /// `false` dönerse yükleme iptal edilir. İkinci parametre UIWebViewNavigationType (0 = link tıklaması).
    var shouldLoad: ((URLRequest, Int) -> Bool)?

    static var isAvailable: Bool { NSClassFromString("UIWebView") is NSObject.Type }

    init?() {
        guard let cls = NSClassFromString("UIWebView") as? NSObject.Type,
              let v = cls.init() as? UIView else { return nil }
        view = v
        bridge.owner = self
        view.setValue(bridge, forKey: "delegate")
        view.setValue(true, forKey: "scalesPageToFit")
        view.setValue(true, forKey: "allowsInlineMediaPlayback")
        // Sayfa içi video oynatma kapalı: videolar her zaman tvOS oynatıcısında açılıyor. WebKit'in kendi video
        // arayüzü tvOS'ta WebThread'den UIKit'e dokunup uygulamayı çökertebiliyor ("…is main-thread only").
        // Kumandayla gerçek dokunuş olmadığı için bu ayar web videolarının kendiliğinden başlamasını tamamen engeller.
        view.setValue(true, forKey: "mediaPlaybackRequiresUserAction")
        view.backgroundColor = .black
        view.isOpaque = false
    }

    /// UIWebView'in içindeki WebKit1 `WebView` nesnesi (belge görünümü `webView` seçicisine yanıt verir).
    var legacyWebView: NSObject? {
        guard let sv = scrollView else { return nil }
        for sub in sv.subviews where sub.responds(to: sel("webView")) {
            if let wv = sub.perform(sel("webView"))?.takeUnretainedValue() as? NSObject { return wv }
        }
        return nil
    }

    /// Kullanıcı ajanını iç `WebView` üzerinden ayarlar (`UserAgent` varsayılanı tvOS'ta etkisiz).
    @discardableResult
    func setUserAgent(_ ua: String) -> Bool {
        guard let wv = legacyWebView, wv.responds(to: sel("setCustomUserAgent:")) else { return false }
        _ = wv.perform(sel("setCustomUserAgent:"), with: ua as NSString)
        return true
    }

    // MARK: Çerçeveler (iframe)

    /// Ana çerçeve (WebFrame).
    var mainFrame: NSObject? {
        guard let wv = legacyWebView, wv.responds(to: sel("mainFrame")) else { return nil }
        webThreadLock?()
        return wv.perform(sel("mainFrame"))?.takeUnretainedValue() as? NSObject
    }

    /// Bir çerçevenin doğrudan alt çerçeveleri; sıra, o sayfadaki `window.frames` sırasıyla aynıdır.
    func childFrames(of frame: NSObject) -> [NSObject] {
        guard frame.responds(to: sel("childFrames")) else { return [] }
        webThreadLock?()
        return frame.perform(sel("childFrames"))?.takeUnretainedValue() as? [NSObject] ?? []
    }

    /// Ana çerçeve dahil tüm çerçeveler (nil = ana çerçeve), en fazla `maxDepth` derinliğe kadar.
    func allFrames(maxDepth: Int = 4) -> [NSObject?] {
        var result: [NSObject?] = [nil]
        func walk(_ f: NSObject, depth: Int) {
            guard depth < maxDepth else { return }
            for child in childFrames(of: f) {
                result.append(child)
                walk(child, depth: depth + 1)
            }
        }
        if let main = mainFrame { walk(main, depth: 0) }
        return result
    }

    /// Betiği verilen çerçevede çalıştırır. WebKit1'in yerel API'si aynı-köken kısıtına takılmadığı için
    /// başka sitelerden gelen iframe'lerin (ör. film oynatıcıları) içinde de çalışır. nil = ana çerçeve.
    @discardableResult
    func evaluate(_ script: String, in frame: NSObject?) -> String? {
        guard let frame else { return js(script) }
        webThreadLock?()
        guard frame.responds(to: sel("windowObject")),
              let window = frame.perform(sel("windowObject"))?.takeUnretainedValue() as? NSObject,
              window.responds(to: sel("evaluateWebScript:")) else { return nil }
        let result = window.perform(sel("evaluateWebScript:"), with: script as NSString)?.takeUnretainedValue()
        if let s = result as? String { return s }
        if let n = result as? NSNumber { return n.stringValue }
        return nil
    }

    deinit {
        view.setValue(nil, forKey: "delegate")
    }

    // MARK: Gezinme

    func load(_ url: URL) {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        _ = view.perform(sel("loadRequest:"), with: request as NSURLRequest)
    }

    func loadHTML(_ html: String, baseURL: URL?) {
        _ = view.perform(sel("loadHTMLString:baseURL:"), with: html as NSString, with: baseURL as NSURL?)
    }

    func goBack() { _ = view.perform(sel("goBack")) }
    func goForward() { _ = view.perform(sel("goForward")) }
    func reload() { _ = view.perform(sel("reload")) }
    func stopLoading() { _ = view.perform(sel("stopLoading")) }

    var canGoBack: Bool { (view.value(forKey: "canGoBack") as? Bool) ?? false }
    var canGoForward: Bool { (view.value(forKey: "canGoForward") as? Bool) ?? false }
    var isLoading: Bool { (view.value(forKey: "loading") as? Bool) ?? false }

    var scrollView: UIScrollView? { view.value(forKey: "scrollView") as? UIScrollView }

    // MARK: JavaScript

    @discardableResult
    func js(_ script: String) -> String? {
        let result = view.perform(sel("stringByEvaluatingJavaScriptFromString:"), with: script as NSString)
        return result?.takeUnretainedValue() as? String
    }

    var currentURL: URL? {
        guard let href = js("location.href"), !href.isEmpty, href != "about:blank",
              let url = URL(string: href), url.scheme != "applewebdata" else { return nil }
        return url
    }

    var title: String { js("document.title") ?? "" }

    private func sel(_ name: String) -> Selector { NSSelectorFromString(name) }
}

/// UIWebViewDelegate protokolü Swift'te tvOS için görünmüyor; aynı Objective-C
/// seçicilerini elle uyguluyoruz. UIWebView `respondsToSelector:` ile kontrol ettiği için yeterli.
private final class DelegateBridge: NSObject {
    weak var owner: WebEngine?

    /// WebKit1 bildirimleri bazen WebThread'den gelebilir; arayüze dokunan her şey ana iş parçacığında çalışmalı.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            #if DEBUG
            noteOffMain()
            #endif
            DispatchQueue.main.async(execute: work)
        }
    }

    @objc(webViewDidStartLoad:)
    func didStart(_ webView: UIView) { onMain { [weak self] in self?.owner?.onStart?() } }

    @objc(webViewDidFinishLoad:)
    func didFinish(_ webView: UIView) { onMain { [weak self] in self?.owner?.onFinish?() } }

    @objc(webView:didFailLoadWithError:)
    func didFail(_ webView: UIView, error: NSError) { onMain { [weak self] in self?.owner?.onFail?(error) } }

    /// Eşzamanlı yanıt gerektiği için iş parçacığı değiştirilemez; çağrılan kod arayüze dokunmamalı.
    @objc(webView:shouldStartLoadWithRequest:navigationType:)
    func shouldStart(_ webView: UIView, request: URLRequest, navigationType: Int) -> Bool {
        #if DEBUG
        if !Thread.isMainThread { noteOffMain() }
        #endif
        return owner?.shouldLoad?(request, navigationType) ?? true
    }

    #if DEBUG
    private func noteOffMain() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("off-main.txt")
        try? "WebView bildirimi ana iş parçacığı dışından geldi: \(Thread.current)\n\(Thread.callStackSymbols.prefix(12).joined(separator: "\n"))"
            .write(to: url, atomically: true, encoding: .utf8)
    }
    #endif
}
