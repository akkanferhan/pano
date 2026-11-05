import UIKit

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
        view.setValue(false, forKey: "mediaPlaybackRequiresUserAction")
        view.backgroundColor = .black
        view.isOpaque = false
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

    @objc(webViewDidStartLoad:)
    func didStart(_ webView: UIView) { owner?.onStart?() }

    @objc(webViewDidFinishLoad:)
    func didFinish(_ webView: UIView) { owner?.onFinish?() }

    @objc(webView:didFailLoadWithError:)
    func didFail(_ webView: UIView, error: NSError) { owner?.onFail?(error) }

    @objc(webView:shouldStartLoadWithRequest:navigationType:)
    func shouldStart(_ webView: UIView, request: URLRequest, navigationType: Int) -> Bool {
        owner?.shouldLoad?(request, navigationType) ?? true
    }
}
