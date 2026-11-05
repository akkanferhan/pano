import ObjectiveC
import UIKit

/// Eski WebKit (UIWebView) sayfayı kendi iş parçacığında (WebThread) işler ve Core Animation işlemini de orada yapar.
/// Bu işlem penceredeki *bütün* görünümlerin yerleşimini tetikleyebilir; Auto Layout kullanan bir görünüm
/// (menü, oynatıcı, uyarı…) ana iş parçacığı dışında yerleşirse tvOS uygulamayı kapatır:
/// "intrinsicContentSize loop detection is main-thread only".
///
/// Koruma: WebKit'in kendi görünümleri dışındaki görünümler için ana iş parçacığı dışında gelen yerleşim isteği
/// atlanır ve ana iş parçacığına ertelenir (`setNeedsLayout`). Web görünümünün iç katmanları eskisi gibi çalışır.
enum LayoutGuard {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(UIView.layoutSublayers(of:))
        let replacement = #selector(UIView.pano_layoutSublayers(of:))
        guard let m1 = class_getInstanceMethod(UIView.self, original),
              let m2 = class_getInstanceMethod(UIView.self, replacement) else { return }
        method_exchangeImplementations(m1, m2)
    }

    /// WebKit'in kendi görünümleri (UIWebView, UIWebBrowserView, _UIWebViewScrollView, döşeme görünümleri…).
    static func isWebKitInternal(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.contains("Web") || name.hasPrefix("WAK") || name.contains("Tile")
    }
}

extension UIView {
    @objc fileprivate func pano_layoutSublayers(of layer: CALayer) {
        if !Thread.isMainThread && !LayoutGuard.isWebKitInternal(self) {
            DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() }
            return
        }
        pano_layoutSublayers(of: layer) // yöntemler değiştirildiği için bu, asıl uygulamayı çağırır
    }
}
