import AVKit
import UIKit

/// Siri Remote ile kullanılan tarayıcı ekranı.
/// - İmleç modu: dokunmatik yüzeyde kaydırınca imleç hareket eder; tıklanabilir öğe üstünde büyür ve yavaşlar.
///   Ekran kenarına itilirse sayfa kayar.
/// - Kaydırma modu: dokunmatik yüzey sayfayı ataletli kaydırır.
/// - Seçim tuşuna basılı tutma: menü. Oynat/Duraklat: mod değiştir; çift bas: adres; basılı tut: sekmeler.
final class BrowserViewController: UIViewController {
    enum Mode { case cursor, scroll }

    let store = Store.shared
    var tabs: [Tab] = []
    var current = 0
    var activeTab: Tab? { tabs.indices.contains(current) ? tabs[current] : nil }
    var engine: WebEngine? { activeTab?.engine }

    let container = UIView()
    let cursor = CursorView()
    let chrome = ChromeBar()
    let toast = GlassToast()
    var titleLabel: UILabel { chrome.titleLabel }
    var hostLabel: UILabel { chrome.hostLabel }
    var spinner: UIActivityIndicatorView { chrome.spinner }
    private var chromeHide: DispatchWorkItem?
    private var chromeShown = true

    var mode: Mode = .cursor
    private var lastTouch: CGPoint?
    private var lastTouchTime: TimeInterval = 0
    private var velocity: CGPoint = .zero
    private var smoothLink: CADisplayLink?
    private var smoothTarget: CGPoint?
    private var playHold: DispatchWorkItem?
    private var playHoldFired = false
    private var hovering = false
    private var lastHoverCheck: TimeInterval = 0

    var findQuery: String?
    var findCount = 0
    var findIndex = 0
    /// Son tıklanan metin alanının / açılır listenin bulunduğu çerçeve (nil = ana çerçeve).
    weak var fieldFrame: NSObject?
    private var videoWatch: Timer?

    /// Web görünümü artık tam ekran; üst çubuk sayfanın üstünde yüzer ve kendiliğinden gizlenir.
    static let barHeight: CGFloat = 0
    static let maxTabs = 8

    // MARK: Yaşam döngüsü

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        container.frame = view.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        setupChrome()
        view.addSubview(toast)

        guard WebEngine.isAvailable else {
            showUnavailable()
            return
        }
        if store.privateMode { store.endPrivate() } // gizli oturum uygulama kapanınca biter
        restoreSession()
        setupRemote()

        cursor.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        view.addSubview(cursor)

        #if DEBUG
        runDebugLaunchArguments()
        #endif

        if !store.hasSeenHelp {
            store.hasSeenHelp = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showHelp() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        activeTab?.engine.view.frame = view.bounds
        chrome.frame = CGRect(x: 80, y: 34, width: view.bounds.width - 160, height: ChromeBar.height)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [] }

    // MARK: Kurulum

    private func setupChrome() {
        view.addSubview(chrome)
        updateBadges()
    }

    /// Üst çubuğu gösterir; `autoHide` ise birkaç saniye sonra (yükleme bitmişse ve imleç üstte değilse) gizler.
    func showChrome(autoHide: Bool = true, after delay: Double = 2.8) {
        chromeHide?.cancel()
        if !chromeShown {
            chromeShown = true
            view.bringSubviewToFront(chrome)
            view.bringSubviewToFront(cursor)
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.beginFromCurrentState]) {
                self.chrome.alpha = 1
                self.chrome.transform = .identity
            }
        }
        if autoHide { scheduleChromeHide(after: delay) }
    }

    private func scheduleChromeHide(after delay: Double) {
        chromeHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideChromeIfIdle() }
        chromeHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Gizler; yalnızca imleç çubuğun tam üzerindeyse (rozetlere tıklamak için) açık bırakır.
    private func hideChromeIfIdle() {
        guard chromeShown else { return }
        if mode == .cursor && chrome.frame.insetBy(dx: -10, dy: -10).contains(cursor.center) {
            scheduleChromeHide(after: 1.5)
            return
        }
        hideChromeNow()
    }

    /// Çubuğu hemen gizler (aşağı kaydırırken içerik çubuğun altında kalmasın).
    func hideChromeNow() {
        chromeHide?.cancel()
        guard chromeShown else { return }
        chromeShown = false
        UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            self.chrome.alpha = 0
            self.chrome.transform = CGAffineTransform(translationX: 0, y: -30).scaledBy(x: 0.97, y: 0.97)
        }
    }

    private func showUnavailable() {
        let label = UILabel()
        label.text = L("The web engine (UIWebView) is not available on this tvOS version.")
        label.textColor = .white
        label.font = .systemFont(ofSize: 34, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = view.bounds.insetBy(dx: 120, dy: 120)
        view.addSubview(label)
    }

    func makeEngine(for tab: Tab) -> WebEngine {
        let e = WebEngine()!
        if !e.setUserAgent(store.currentUA) { NSLog("Pano: could not set the user agent") }
        e.view.isUserInteractionEnabled = false
        e.view.insetsLayoutMarginsFromSafeArea = false
        e.scrollView?.contentInsetAdjustmentBehavior = .never
        e.scrollView?.contentInset = .zero
        e.onStart = { [weak self, weak tab] in
            guard let self, let tab, tab === self.activeTab else { return }
            self.chrome.setLoading(true) // iframe yüklemeleri de buraya düşer: çubuğu burada açma
        }
        e.onFinish = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.pageFinished(tab)
        }
        e.onFail = { [weak self, weak tab] error in
            guard let self, let tab else { return }
            self.pageFailed(tab, error)
        }
        e.shouldLoad = { [weak self, weak tab] request, _ in
            guard let self, let tab else { return true }
            return self.shouldLoad(request, in: tab)
        }
        return e
    }

    // MARK: Sekmeler

    private func restoreSession() {
        let saved = store.sessionTabs
        guard !saved.isEmpty else {
            addTab(url: nil, activate: true)
            return
        }
        for item in saved.prefix(Self.maxTabs) {
            let t = Tab()
            t.engine = makeEngine(for: t)
            if !item.isEmpty, let url = URL(string: item) {
                t.pendingURL = url
                t.isHome = false
                t.title = url.host ?? item
            }
            tabs.append(t)
        }
        activate(min(max(store.sessionIndex, 0), tabs.count - 1))
    }

    @discardableResult
    func addTab(url: URL?, activate: Bool) -> Bool {
        guard tabs.count < Self.maxTabs else {
            showToast(L("You can open up to %d tabs", Self.maxTabs), symbol: "square.on.square")
            return false
        }
        let t = Tab()
        t.engine = makeEngine(for: t)
        if let url {
            t.pendingURL = url
            t.isHome = false
            t.title = url.host ?? url.absoluteString
        }
        tabs.append(t)
        if activate { self.activate(tabs.count - 1) } else { updateBadges(); saveSession() }
        return true
    }

    func activate(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        resetFind()
        if let old = activeTab, old.engine.view.window != nil { old.snapshot = snapshot(of: old) }
        activeTab?.engine.view.removeFromSuperview()
        current = index
        let t = tabs[index]
        container.addSubview(t.engine.view)
        t.engine.view.frame = view.bounds
        if t.needsLoad {
            t.needsLoad = false
            if let url = t.pendingURL { t.engine.load(url) } else { loadHome(in: t) }
        }
        hovering = false
        cursor.setHovering(false, animated: false)
        showChrome()
        updateBar()
        updateBadges()
        saveSession()
    }

    func closeTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let t = tabs[index]
        t.engine.stopLoading()
        t.engine.view.removeFromSuperview()
        tabs.remove(at: index)
        if tabs.isEmpty {
            current = 0
            addTab(url: nil, activate: true)
        } else if index == current {
            activate(min(index, tabs.count - 1))
        } else {
            if index < current { current -= 1 }
            updateBadges()
            saveSession()
        }
    }

    func saveSession() {
        guard !store.privateMode else { return }
        store.sessionTabs = tabs.map(\.sessionURL)
        store.sessionIndex = current
    }

    /// Kullanıcı ajanı değişince tüm web motorlarını yeni ajanla yeniden oluşturur ve sayfaları yeniden yükler.
    func recreateEngines() {
        for (i, t) in tabs.enumerated() {
            let url = t.isHome ? nil : (t.url ?? t.pendingURL)
            t.engine.stopLoading()
            t.engine.view.removeFromSuperview()
            t.engine = makeEngine(for: t)
            t.pendingURL = url
            t.url = nil
            t.isHome = url == nil
            t.needsLoad = i != current
        }
        let i = current
        current = -1
        tabs[i].needsLoad = true
        activate(i)
    }

    // MARK: Sayfa olayları

    private func shouldLoad(_ request: URLRequest, in t: Tab) -> Bool {
        guard let url = request.url else { return true }
        if url.scheme == "pano" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch url.host {
            case "search":
                let q = items.first { $0.name == "q" }?.value ?? ""
                DispatchQueue.main.async { self.open(q, in: t) }
            case "resume": // "İzlemeye devam" kartı: sayfayı aç, oynatıcıyı otomatik başlat (oynatıcı kaldığı yere atlar)
                if let s = items.first(where: { $0.name == "url" })?.value, let target = URL(string: s) {
                    DispatchQueue.main.async {
                        t.autoPlayPending = true
                        t.engine.load(target)
                        self.showToast(L("Opening the video…"), symbol: "play.rectangle.fill")
                    }
                }
            case "newtab":
                if let s = items.first(where: { $0.name == "url" })?.value, let target = URL(string: s) {
                    DispatchQueue.main.async {
                        if self.addTab(url: target, activate: false) {
                            self.showToast(L("Opened in a new tab — hold Play/Pause to see tabs"), symbol: "plus.square.on.square")
                        }
                    }
                }
            default:
                break
            }
            return false
        }
        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob", "javascript", "applewebdata"].contains(scheme) {
            DispatchQueue.main.async { self.showToast(L("This kind of link can't be opened: %@", scheme), symbol: "exclamationmark.triangle.fill") }
            return false
        }
        if request.mainDocumentURL == nil || request.mainDocumentURL == url { // ana çerçeve gezinmesi
            t.mainRequestURL = url.absoluteString
            t.blockedAtStart = AdBlocker.blockedCount
            t.loadStartedAt = Date()
            t.handledInterimFinish = false
            t.finalHandled = false
            DispatchQueue.main.async { [weak self, weak t] in
                guard let self, let t, t === self.activeTab else { return }
                self.showChrome(autoHide: true, after: 3) // yeni sayfa: adres kısa süre görünsün
            }
            #if DEBUG
            t.perfStart = Date(); t.perfFinishes = 0; t.perfOurTime = 0; t.perfLogged = false
            #endif
            t.isReader = false
            // Bu yöntem WebThread'den çağrılabilir: arayüz / zamanlayıcı işleri ana iş parçacığına.
            DispatchQueue.main.async { [weak self, weak t] in
                guard let self, let t, t === self.activeTab else { return }
                self.stopVideoWatch()
                self.resetFind()
            }
        }
        return true
    }

    private func pageFinished(_ t: Tab) {
        #if DEBUG
        let perfT0 = CFAbsoluteTimeGetCurrent()
        defer {
            t.perfFinishes += 1
            t.perfOurTime += CFAbsoluteTimeGetCurrent() - perfT0
            if !t.engine.isLoading, !t.perfLogged, let u = t.url?.host {
                t.perfLogged = true
                let line = String(format: "%@ load=%.2fs finish-events=%d our-code=%.0fms\n", u,
                                  Date().timeIntervalSince(t.perfStart), t.perfFinishes, t.perfOurTime * 1000)
                Self.debugAppend("perf.txt", line)
            }
        }
        #endif
        let e = t.engine!
        if t === activeTab { refreshSpinnerSoon() }
        // Ağır sayfalar onlarca ara "bitti" bildirimi gönderir (her iframe için). Ağır işler yalnızca
        // ilk bildirimde ve yükleme tamamen bittiğinde yapılır; arada yalnızca yükleme göstergesi güncellenir.
        let finalFinish = !e.isLoading
        if !finalFinish && t.handledInterimFinish { return }
        t.handledInterimFinish = true
        if finalFinish { t.finalHandled = true }
        let marker = e.js("document.documentElement.getAttribute('data-pano')") ?? ""
        e.js(Pages.afterLoad(textScale: store.textScale, adBlock: store.adBlockEnabled))
        if finalFinish { for f in e.allFrames() { e.evaluate(Pages.mediaSafety, in: f) } }
        let url = e.currentURL
        t.isHome = marker == "home"
        if t.isHome {
            t.title = L("Home")
            t.url = nil
            t.pendingURL = nil
        } else if marker == "error" {
            t.title = L("Couldn't open the page")
        } else if let url {
            let title = e.title
            t.title = title.isEmpty ? (url.host ?? url.absoluteString) : title
            t.url = url
            t.pendingURL = nil
            if finalFinish && !store.privateMode { store.addHistory(title: title, url: url.absoluteString) }
            let zoom = store.zoom(for: url.host)
            if zoom != 100 { e.js(Pages.applyZoom(zoom)) }
        }
        if t === activeTab { updateBar() }
        if finalFinish { saveSession() }
        if t.autoPlayPending, t === activeTab, !t.isHome {
            t.autoPlayPending = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak t] in
                guard let self, let t, t === self.activeTab else { return }
                self.autoPlayAttempt()
            }
        }
    }

    private func pageFailed(_ t: Tab, _ error: NSError) {
        if t === activeTab, !t.engine.isLoading { chrome.setLoading(false) }
        // -999: iptal; WebKit 102: çerçeve yüklemesi kesildi; 204: eklenti (video) yüklemeyi üstlendi
        if error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204) { return }
        let failing = (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? ""
        guard failing.isEmpty || failing == t.mainRequestURL else { return } // alt kaynak / iframe hatası
        if error.domain == AdBlocker.errorDomain {
            if t === activeTab { showToast(L("Blocked an ad/tracker address"), symbol: "shield.lefthalf.filled") }
            return
        }
        t.engine.loadHTML(Pages.error(url: failing, message: error.localizedDescription), baseURL: nil)
        t.title = L("Couldn't open the page")
        if t === activeTab {
            titleLabel.text = t.title
            hostLabel.text = failing
        }
    }

    // MARK: Gezinme

    func loadHome(in t: Tab) {
        t.isHome = true
        t.url = nil
        t.title = L("Home")
        t.engine.loadHTML(Pages.home(bookmarks: store.bookmarks, engine: store.searchEngine, isPrivate: store.privateMode,
                                     continueWatching: store.watchProgress),
                          baseURL: nil)
        if t === activeTab { updateBar() }
    }

    func goHome() {
        guard let t = activeTab else { return }
        loadHome(in: t)
    }

    /// Ana sayfası açık olan sekmeleri yeniler (sık kullanılanlar / arama motoru / gizli mod değişince).
    func refreshHomeTabs() {
        for t in tabs where t.isHome && !t.needsLoad { loadHome(in: t) }
    }

    func open(_ input: String, in t: Tab? = nil) {
        guard let t = t ?? activeTab, let url = store.resolve(input) else { return }
        t.engine.load(url)
        if t === activeTab { hostLabel.text = url.absoluteString }
    }

    func reloadCurrent() {
        guard let t = activeTab else { return }
        if t.isHome { loadHome(in: t) } else { t.isReader = false; t.engine.reload() }
    }

    // MARK: Üst çubuk

    func updateBar() {
        guard let t = activeTab else { return }
        let url = t.url ?? t.pendingURL
        let host: String
        let symbol: String
        if t.isHome {
            host = store.privateMode ? L("Pano · private browsing") : "Pano"
            symbol = store.privateMode ? "eye.slash.fill" : "house.fill"
        } else {
            host = url.map { ($0.host ?? $0.absoluteString) + ($0.path.count > 1 ? $0.path : "") } ?? ""
            symbol = t.isReader ? "doc.plaintext" : (url?.scheme == "https" ? "lock.fill" : "globe")
        }
        chrome.update(title: t.title, host: host, symbol: symbol, loading: t.engine.isLoading)
        if t.isHome { scheduleChromeHide(after: 1.2) } // ana sayfanın kendi başlığı var
        // Çubuk yalnızca yeni sayfaya geçişte, sekme/mod değişince ve yukarı kaydırınca açılır.
    }

    func updateBadges() {
        chrome.setBadges(cursorMode: mode == .cursor, tabCount: tabs.count, isPrivate: store.privateMode)
    }

    // MARK: Kumanda: dokunmatik yüzey

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // Kaydırma modunda yeni dokunuş süzülmeyi durdurur (parmak sayfayı "yakalar")
        if mode == .scroll, let sv = engine?.scrollView { smoothTarget = sv.contentOffset }
        lastTouch = touch.location(in: view)
        lastTouchTime = touch.timestamp
        velocity = .zero
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let last = lastTouch else { return }
        let p = touch.location(in: view)
        let dt = max(touch.timestamp - lastTouchTime, 0.001)
        let delta = CGPoint(x: p.x - last.x, y: p.y - last.y)
        lastTouch = p
        lastTouchTime = touch.timestamp

        switch mode {
        case .cursor:
            // Tıklanabilir bir öğenin üstündeyken imleç yavaşlar; küçük bağlantılara isabet kolaylaşır.
            let f = store.cursorSpeed * (hovering ? 0.55 : 1)
            moveCursor(by: CGPoint(x: delta.x * f, y: delta.y * f))
            if touch.timestamp - lastHoverCheck > 0.12 {
                lastHoverCheck = touch.timestamp
                checkHover()
            }
        case .scroll:
            let f = 1.6 * store.cursorSpeed
            let d = CGPoint(x: delta.x * f, y: delta.y * f)
            smoothScroll(by: d)
            // hız: üstel ortalama (ani sıçramalar yumuşasın)
            let v = CGPoint(x: d.x / dt, y: d.y / dt)
            velocity = CGPoint(x: velocity.x * 0.6 + v.x * 0.4, y: velocity.y * 0.6 + v.y * 0.4)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouch = nil
        // Parmak kalkınca süzülme: hedefi hızla orantılı ileri taşı, yumuşatıcı yavaşlayarak götürür
        if mode == .scroll, hypot(velocity.x, velocity.y) > 200 {
            smoothScroll(by: CGPoint(x: velocity.x * 0.28, y: velocity.y * 0.28))
        }
        if mode == .cursor { checkHover() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouch = nil
    }

    func moveCursor(by delta: CGPoint) {
        let area = view.bounds.insetBy(dx: 4, dy: 4)
        let target = CGPoint(x: cursor.center.x + delta.x, y: cursor.center.y + delta.y)
        let clamped = CGPoint(x: min(max(target.x, area.minX), area.maxX),
                              y: min(max(target.y, area.minY), area.maxY))
        cursor.center = clamped
        let overflow = CGPoint(x: target.x - clamped.x, y: target.y - clamped.y)
        // Kenara itince yumuşak kaydırma: ne kadar itilirse o kadar hızlı
        if overflow != .zero { smoothScroll(by: CGPoint(x: overflow.x * 3, y: overflow.y * 3)) }
    }

    func checkHover() {
        guard mode == .cursor, let e = engine, let p = pointer() else { return }
        let overChrome = chromeShown && chrome.alpha > 0.5 && chrome.frame.contains(cursor.center)
        let h = overChrome || e.js(Pages.hover(p)) == "1"
        guard h != hovering else { return }
        hovering = h
        cursor.setHovering(h)
    }

    /// İmlecin web görünümündeki konumu ve kaydırma durumu.
    func pointer() -> Pointer? {
        guard let e = engine, let sv = e.scrollView else { return nil }
        let p = view.convert(cursor.center, to: e.view)
        return Pointer(viewWidth: Double(e.view.bounds.width), offsetX: Double(sv.contentOffset.x),
                       offsetY: Double(sv.contentOffset.y), x: Double(p.x), y: Double(p.y))
    }

    private func clampedOffset(_ p: CGPoint, in sv: UIScrollView) -> CGPoint {
        let inset = sv.adjustedContentInset
        let maxX = max(-inset.left, sv.contentSize.width - sv.bounds.width + inset.right)
        let maxY = max(-inset.top, sv.contentSize.height - sv.bounds.height + inset.bottom)
        return CGPoint(x: min(max(p.x, -inset.left), maxX), y: min(max(p.y, -inset.top), maxY))
    }

    @discardableResult
    func scrollPage(by delta: CGPoint, animated: Bool = false) -> Bool {
        guard let sv = engine?.scrollView else { return false }
        let new = clampedOffset(CGPoint(x: sv.contentOffset.x + delta.x, y: sv.contentOffset.y + delta.y), in: sv)
        let moved = new != sv.contentOffset
        sv.setContentOffset(new, animated: animated)
        return moved
    }

    func scrollPage(to point: CGPoint, animated: Bool = true) {
        guard let sv = engine?.scrollView else { return }
        sv.setContentOffset(clampedOffset(point, in: sv), animated: animated)
    }

    // MARK: Yumuşak kaydırma

    /// Her kaydırma isteği yalnızca hedefi değiştirir; ekran yenilemesiyle senkron bir döngü sayfayı
    /// hedefe yavaşlayarak götürür (kenara itme, kaydırma modu, süzülme, yön tuşları, telefon).
    func smoothScroll(by delta: CGPoint) {
        guard let sv = engine?.scrollView else { return }
        // Safari gibi: aşağı kaydırınca üst çubuk gizlenir, yukarı kaydırınca geri gelir
        if delta.y > 3 { hideChromeNow() } else if delta.y < -3 { showChrome() }
        let base = smoothTarget ?? sv.contentOffset
        smoothTarget = clampedOffset(CGPoint(x: base.x + delta.x, y: base.y + delta.y), in: sv)
        if smoothLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(smoothTick(_:)))
            link.add(to: .main, forMode: .common)
            smoothLink = link
        }
    }

    private func stopMomentum() {
        smoothLink?.invalidate()
        smoothLink = nil
        smoothTarget = nil
    }

    @objc private func smoothTick(_ link: CADisplayLink) {
        guard let sv = engine?.scrollView, let target = smoothTarget else { return stopMomentum() }
        let current = sv.contentOffset
        let dx = target.x - current.x, dy = target.y - current.y
        if abs(dx) < 0.5 && abs(dy) < 0.5 {
            sv.contentOffset = target
            if lastTouch == nil || mode == .cursor { stopMomentum() }
            return
        }
        // Kare hızından bağımsız üstel yaklaşma (60 fps'de her karede mesafenin ~%16'sı)
        let dt = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        let k = CGFloat(1 - pow(1 - 0.16, dt * 60))
        sv.contentOffset = CGPoint(x: current.x + dx * k, y: current.y + dy * k)
    }

    // MARK: Kumanda: tuşlar

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else { return super.pressesBegan(presses, with: event) }
        switch press.type {
        case .playPause:
            playHoldFired = false
            let work = DispatchWorkItem { [weak self] in
                self?.playHoldFired = true
                self?.showTabs()
            }
            playHold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        case .select, .menu, .upArrow, .downArrow, .leftArrow, .rightArrow:
            break // pressesEnded'de işlenir
        default:
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else { return super.pressesEnded(presses, with: event) }
        let page = (engine?.scrollView?.bounds.height ?? 800) * 0.6
        switch press.type {
        case .select:
            // İmleç ↔ kaydırma modu yalnızca adres çubuğundaki mod rozetinden değişir.
            if mode == .scroll { setMode(.cursor) } else { clickAtCursor() }
        case .playPause:
            playHold?.cancel()
            if playHoldFired { return }
            showMenu() // Oynat/Duraklat: menü (panel açıkken aynı tuş kapatır)
        case .menu:
            handleBack(presses, event)
        case .upArrow: smoothScroll(by: CGPoint(x: 0, y: -page))
        case .downArrow: smoothScroll(by: CGPoint(x: 0, y: page))
        case .leftArrow:
            if findCount > 0 { stepFind(-1) } else { smoothScroll(by: CGPoint(x: -page, y: 0)) }
        case .rightArrow:
            if findCount > 0 { stepFind(1) } else { smoothScroll(by: CGPoint(x: page, y: 0)) }
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        playHold?.cancel()
        super.pressesCancelled(presses, with: event)
    }

    /// Menü/Geri: önce bulma vurgusunu, sonra okuma modunu kapatır; sonra geri gider, sonra ana sayfa, en son çıkış.
    private func handleBack(_ presses: Set<UIPress>, _ event: UIPressesEvent?) {
        guard let t = activeTab else { return super.pressesEnded(presses, with: event) }
        if findCount > 0 {
            resetFind()
            showToast(L("Search cleared"), symbol: "xmark.circle")
        } else if t.isReader {
            toggleReader()
        } else if t.engine.canGoBack {
            t.engine.goBack()
        } else if !t.isHome {
            loadHome(in: t)
        } else {
            super.pressesEnded(presses, with: event) // ana ekrana çık
        }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        stopMomentum()
        UIView.animate(withDuration: 0.2) { self.cursor.alpha = newMode == .cursor ? 1 : 0 }
        updateBadges()
        showToast(newMode == .cursor ? L("Cursor mode") : L("Scroll mode — click to return to the cursor"),
                  symbol: newMode == .cursor ? "cursorarrow" : "arrow.up.and.down")
        showChrome()
    }

    // MARK: Tıklama ve form alanları

    func clickAtCursor() {
        if chromeShown, chrome.alpha > 0.5, chrome.frame.contains(cursor.center) {
            bounceCursor()
            switch chrome.region(at: view.convert(cursor.center, to: chrome)) {
            case .tabs: showTabSwitcher()
            case .mode: setMode(mode == .cursor ? .scroll : .cursor)
            case .privateMode: showToast(L("Private browsing is on — you can turn it off from the menu"), symbol: "eye.slash.fill")
            case .address: askAddress()
            }
            return
        }
        guard let e = engine, let p = pointer() else { return }
        bounceCursor()
        stopVideoWatch()
        // Tıklamadan önceki videolar: tıklamadan sonra yeni çıkan ya da oynamaya başlayan video aranır.
        var baseline: [String: Bool] = [:]
        for v in allVideos() where baseline[v.src] == nil { baseline[v.src] = v.paused }
        let clickTime = Date()
        for f in e.allFrames() { e.evaluate(Pages.mediaSafety, in: f) } // WebKit çökmesine karşı (bkz. Pages.mediaSafety)

        // Tıklama bir iframe'e denk gelirse, o iframe'in çerçevesinde (gerekirse iç içe) tekrar tıkla.
        var frame: NSObject?
        var info = parseObject(e.js(Pages.click(p)))
        var depth = 0
        while let current = info, current["kind"] as? String == "frame", depth < 6 {
            guard let parent = frame ?? e.mainFrame, let index = current["index"] as? Int,
                  let x = current["x"] as? Double, let y = current["y"] as? Double else { break }
            let children = e.childFrames(of: parent)
            guard children.indices.contains(index) else { break }
            frame = children[index]
            info = parseObject(e.evaluate(Pages.clickInFrame(x: x, y: y), in: frame))
            depth += 1
        }
        guard let info, let kind = info["kind"] as? String else { return }
        fieldFrame = frame
        switch kind {
        case "input" where activeTab?.isHome == true:
            askAddress() // ana sayfadaki arama kutusu: modern arama ekranı
        case "input":
            askForText(type: info["type"] as? String ?? "", value: info["value"] as? String ?? "",
                       label: info["label"] as? String ?? "")
        case "select":
            chooseOption(options: info["options"] as? [String] ?? [], selected: info["selected"] as? Int ?? -1,
                         label: info["label"] as? String ?? "")
        case "video":
            if let src = info["src"] as? String {
                playVideo(src: src, time: info["t"] as? Double ?? 0, referer: info["href"] as? String)
            }
        default:
            watchForVideo(baseline: baseline, since: clickTime)
        }
    }

    private func askForText(type: String, value: String, label: String) {
        let alert = UIAlertController(title: label.isEmpty ? L("Enter text") : label, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = value
            tf.isSecureTextEntry = type == "password"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            switch type {
            case "email": tf.keyboardType = .emailAddress
            case "url": tf.keyboardType = .URL
            case "number", "tel": tf.keyboardType = .numbersAndPunctuation
            default: tf.keyboardType = .default
            }
        }
        let apply: (Bool) -> Void = { [weak self, weak alert] submit in
            guard let self else { return }
            self.engine?.evaluate(Pages.setFieldValue(alert?.textFields?.first?.text ?? "", submit: submit), in: self.fieldFrame)
        }
        alert.addAction(UIAlertAction(title: L("Send"), style: .default) { _ in apply(true) })
        alert.addAction(UIAlertAction(title: L("Type only"), style: .default) { _ in apply(false) })
        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func chooseOption(options: [String], selected: Int, label: String) {
        guard !options.isEmpty else { return }
        let panel = MenuPanelController(title: label.isEmpty ? L("Choose") : label, subtitle: L("%d options", options.count))
        for (i, option) in options.enumerated() {
            panel.addItem(option, checked: i == selected) { [weak self] in
                guard let self else { return }
                self.engine?.evaluate(Pages.setSelectIndex(i), in: self.fieldFrame)
            }
        }
        present(panel, animated: true)
    }

    // MARK: Sekme ekranı

    /// Sekmenin web görünümünden küçük bir anlık görüntü.
    func snapshot(of t: Tab) -> UIImage? {
        let v = t.engine.view
        guard v.bounds.width > 0 else { return t.snapshot }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.5
        return UIGraphicsImageRenderer(bounds: v.bounds, format: format).image { _ in
            v.drawHierarchy(in: v.bounds, afterScreenUpdates: false)
        }
    }

    private func tabCards() -> [TabSwitcherController.Card] {
        tabs.enumerated().map { i, t in
            let url = t.url ?? t.pendingURL
            let host = t.isHome ? L("Home") : ((url?.host ?? "").replacingOccurrences(of: "www.", with: ""))
            return TabSwitcherController.Card(title: t.title, host: host, image: t.snapshot, isCurrent: i == current,
                                              isPrivate: store.privateMode)
        }
    }

    func showTabSwitcher() {
        guard presentedViewController == nil else { return }
        if let t = activeTab { t.snapshot = snapshot(of: t) }
        let vc = TabSwitcherController()
        vc.modalPresentationStyle = .overFullScreen
        vc.cards = tabCards()
        vc.onSelect = { [weak self] i in
            guard let self else { return }
            if i != self.current { self.activate(i) }
        }
        vc.onNewTab = { [weak self] in self?.addTab(url: nil, activate: true) }
        vc.onClose = { [weak self] i in
            guard let self else { return [] }
            self.closeTab(i)
            return self.tabCards()
        }
        present(vc, animated: true)
    }

    func linkAtCursor() -> URL? {
        guard let e = engine, let p = pointer(), let s = e.js(Pages.linkAt(p)), !s.isEmpty else { return nil }
        return URL(string: s)
    }

    // MARK: Okuma modu

    func toggleReader() {
        guard let t = activeTab else { return }
        if t.isReader {
            t.isReader = false
            t.engine.reload()
            showToast(L("Reader mode off"), symbol: "doc.plaintext")
            return
        }
        if t.engine.js(Pages.reader) == "ok" {
            t.isReader = true
            scrollPage(to: .zero, animated: false)
            showToast(L("Reader mode — press Menu to exit"), symbol: "doc.plaintext")
        } else {
            showToast(L("No article found on this page"), symbol: "doc.plaintext")
        }
    }

    // MARK: Yakınlaştırma

    func setZoom(_ zoom: Int) {
        guard let t = activeTab, let host = t.url?.host else { return }
        store.setZoom(zoom, for: host)
        t.engine.js(Pages.applyZoom(zoom))
        showToast(L("Zoom %d%% — remembered for %@", zoom, host), symbol: "plus.magnifyingglass")
    }

    // MARK: Sayfada bul

    func startFind(_ query: String) {
        guard let e = engine, !query.isEmpty else { return }
        resetFind()
        let count = Int(e.js(Pages.findAll(query)) ?? "") ?? 0
        guard count > 0 else {
            showToast(L("“%@” not found", query), symbol: "magnifyingglass")
            return
        }
        findQuery = query
        findCount = count
        findIndex = 0
        focusFind()
    }

    func stepFind(_ step: Int) {
        guard findCount > 0 else { return }
        findIndex = (findIndex + step + findCount) % findCount
        focusFind()
    }

    private func focusFind() {
        guard let e = engine, let sv = e.scrollView, let info = parseObject(e.js(Pages.findFocus(findIndex))),
              let y = info["y"] as? Double, let iw = info["iw"] as? Double, iw > 0 else { return }
        let x = info["x"] as? Double ?? 0
        let scale = Double(e.view.bounds.width) / iw
        let targetX = x * scale > Double(sv.bounds.width) * 0.8 ? x * scale - Double(sv.bounds.width) * 0.3 : 0
        scrollPage(to: CGPoint(x: targetX, y: y * scale - Double(sv.bounds.height) * 0.35))
        showToast(L("%d of %d  ·  ◀ ▶ to move, Menu to close", findIndex + 1, findCount), symbol: "text.magnifyingglass")
    }

    func resetFind() {
        if findQuery != nil { engine?.js(Pages.findClear) }
        findQuery = nil
        findCount = 0
        findIndex = 0
    }

    // MARK: Video

    struct FoundVideo {
        let src: String
        let time: Double
        let paused: Bool
        /// Sayfanın bu video için en son play() istediği an (ms, 0 = hiç).
        let playRequested: Double
        let playable: Bool
        let blob: Bool
        let referer: String?
    }

    /// Ana çerçeve ve tüm iframe'lerdeki `<video>` öğeleri.
    func allVideos() -> [FoundVideo] {
        guard let e = engine else { return [] }
        var out: [FoundVideo] = []
        for frame in e.allFrames() {
            guard let json = e.evaluate(Pages.videos, in: frame), let data = json.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for item in list {
                guard let src = item["src"] as? String else { continue }
                out.append(FoundVideo(src: src, time: item["t"] as? Double ?? 0, paused: item["paused"] as? Bool ?? true,
                                      playRequested: item["req"] as? Double ?? 0,
                                      playable: item["playable"] as? Bool ?? false, blob: item["blob"] as? Bool ?? false,
                                      referer: item["href"] as? String))
            }
        }
        return out
    }

    /// Menüdeki "Videoyu tam ekran oynat" için adaylar: sayfadaki videolar + bu sayfada ağdan yakalanan video adresleri.
    func videoCandidates() -> [(title: String, src: String, time: Double, referer: String?)] {
        var result: [(title: String, src: String, time: Double, referer: String?)] = []
        var seen = Set<String>()
        for v in allVideos() where v.playable && !seen.contains(v.src) {
            seen.insert(v.src)
            result.append((L("Video · %@", URL(string: v.src)?.host ?? "") + (v.paused ? "" : " " + L("(playing)")), v.src, v.time, v.referer))
        }
        if let since = activeTab?.loadStartedAt {
            let sniffed = MediaSniffer.items(since: since)
            for m in sniffed.filter(\.isPlaylist) + sniffed.filter({ !$0.isPlaylist }) where !seen.contains(m.url.absoluteString) {
                seen.insert(m.url.absoluteString)
                result.append(((m.isPlaylist ? L("Stream (HLS)") : L("File")) + " · " + (m.url.host ?? ""), m.url.absoluteString, 0, m.referer))
            }
        }
        return result
    }

    /// Tıklamadan sonra ~12 sn boyunca yeni başlayan videoyu ya da ağdan istenen video adresini bekler;
    /// bulunca tvOS oynatıcısında açar. (Film sitelerinde oynatıcı genelde başka siteden gelen bir iframe'dir.)
    private func watchForVideo(baseline: [String: Bool], since: Date) {
        var ticks = 0
        videoWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            ticks += 1
            if self.presentedViewController != nil || ticks > 24 {
                self.stopVideoWatch()
                return
            }
            let videos = self.allVideos()
            // Tıklamadan sonra yeni çıkan ya da oynatılması istenen (play()) video.
            let clickMs = since.timeIntervalSince1970 * 1000 - 100
            let started = videos.first { v in
                v.playable && (baseline[v.src] == nil || v.playRequested >= clickMs ||
                    (baseline[v.src] == true && !v.paused))
            }
            if let v = started {
                self.stopVideoWatch()
                self.showToast(L("Opening the video in the player…"), symbol: "play.rectangle.fill")
                self.playVideo(src: v.src, time: v.time, referer: v.referer)
                return
            }
            let sniffed = MediaSniffer.items(since: since)
            if let m = sniffed.first(where: \.isPlaylist) ?? (ticks >= 6 ? sniffed.first : nil) {
                self.stopVideoWatch()
                self.showToast(L("Opening the video in the player…"), symbol: "play.rectangle.fill")
                self.playVideo(src: m.url.absoluteString, time: 0, referer: m.referer)
                return
            }
            if ticks == 24, videos.contains(where: { $0.blob }) {
                self.showToast(L("Found a video, but it has no directly playable address (protected stream)"), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func stopVideoWatch() {
        videoWatch?.invalidate()
        videoWatch = nil
    }

    /// Videoyu tvOS'un kendi oynatıcısında tam ekran açar (kumandanın oynat/sar tuşları çalışır).
    /// Film sitelerindeki akışlar çoğu zaman Referer/Origin başlığı ister; videonun bulunduğu sayfanın adresi gönderilir.
    /// Videoyu açar. Yarım kalmış izleme varsa oynatıcı, video süresi belli olunca *aynı video* olduğunu
    /// doğrulayıp "Kaldığın yerden devam" düğmesi gösterir (aynı sayfadaki başka videolarda sormaz).
    func playVideo(src: String, time: Double, referer: String? = nil) {
        guard presentedViewController == nil else { return }
        presentPlayer(src: src, time: time, referer: referer)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.isFinite ? seconds : 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// tvOS oynatıcısını açar (Referer/Origin başlıkları, altyazılar, ilerleme kaydı, sonraki bölüm).
    private func presentPlayer(src: String, time: Double, referer: String?) {
        guard let url = URL(string: src), presentedViewController == nil else { return }
        var headers = ["User-Agent": store.currentUA]
        if let ref = referer ?? activeTab?.url?.absoluteString, let refURL = URL(string: ref),
           let scheme = refURL.scheme, let host = refURL.host {
            headers["Referer"] = ref
            headers["Origin"] = "\(scheme)://\(host)" + (refURL.port.map { ":\($0)" } ?? "")
        }
        let options: [String: Any] = [
            AVURLAssetHTTPCookiesKey: HTTPCookieStorage.shared.cookies ?? [],
            "AVURLAssetHTTPHeaderFieldsKey": headers,
        ]
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url, options: options)))
        if time > 1 { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
        let subtitles = subtitleSources()
        let next = nextEpisode()
        if let e = engine { for frame in e.allFrames() { e.evaluate(Pages.pauseVideos, in: frame) } }

        let page = activeTab?.url?.absoluteString
        let title = activeTab?.title ?? ""
        let videoKey = Store.videoKey(for: url)
        let context = PlaybackContext(pageURL: page, title: title, nextEpisode: next?.url, nextEpisodeGuessed: next?.guessed ?? false,
                                      videoKey: videoKey, resumeCandidates: page.map { store.progressEntries(for: $0) } ?? [])
        let vc = VideoPlayerController()
        let save: (Double, Double) -> Void = { [weak self] position, duration in
            guard let self, let page, !self.store.privateMode else { return }
            self.store.saveProgress(page: page, videoKey: videoKey, title: title, position: position, duration: duration)
        }
        vc.onProgress = save
        vc.onClose = { [weak self] position, duration in
            save(position, duration)
            self?.refreshHomeTabs()
        }
        vc.onNextEpisode = { [weak self] url in self?.openNextEpisode(url) }
        vc.configure(player: player, subtitles: subtitles, userAgent: store.currentUA, context: context)
        present(vc, animated: true) { player.play() }
    }

    // MARK: Sonraki bölüm

    /// Sayfadaki "sonraki bölüm" bağlantısı; yoksa adresteki bölüm numarasından tahmin.
    func nextEpisode() -> (url: URL, guessed: Bool)? {
        guard let e = engine, let page = activeTab?.url else { return nil }
        if let s = e.js(Pages.nextEpisode), !s.isEmpty, let url = URL(string: s) { return (url, false) }
        if let guess = OpenSubtitles.guessNextEpisodeURL(page) { return (guess, true) }
        return nil
    }

    /// Sonraki bölüme gider; sayfa yüklenince oynatıcıyı kendisi başlatmayı dener.
    func openNextEpisode(_ url: URL) {
        guard let t = activeTab else { return }
        t.autoPlayPending = true
        t.engine.load(url)
        showToast(L("Opening the next episode…"), symbol: "forward.end.fill")
    }

    /// Sayfadaki en büyük oynatıcıyı bulup ortasına tıklar (sonraki bölüm otomatik başlatma).
    func autoPlayAttempt() {
        guard presentedViewController == nil, let e = engine, let sv = e.scrollView,
              let info = parseObject(e.js(Pages.playerRect)),
              let x = info["x"] as? Double, let y = info["y"] as? Double,
              let iw = info["iw"] as? Double, iw > 0 else {
            showToast(L("Player not found — click the video yourself"), symbol: "play.rectangle")
            return
        }
        let px = info["px"] as? Double ?? 0, py = info["py"] as? Double ?? 0
        let scale = Double(e.view.bounds.width) / iw
        let docX = (x + px) * scale, docY = (y + py) * scale
        scrollPage(to: CGPoint(x: sv.contentOffset.x, y: docY - Double(sv.bounds.height) / 2), animated: false)
        let screen = CGPoint(x: docX - Double(sv.contentOffset.x), y: docY - Double(sv.contentOffset.y) + Double(Self.barHeight))
        cursor.center = screen
        showToast(L("Starting the player…"), symbol: "play.rectangle.fill")
        clickAtCursor()
    }

    // MARK: Kaynaklar

    func pageSources() -> [(text: String, active: Bool)] {
        guard let json = engine?.js(Pages.sources), let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let text = item["text"] as? String else { return nil }
            return (text, item["active"] as? Bool ?? false)
        }
    }

    func selectSource(_ index: Int, title: String) {
        guard engine?.js(Pages.selectSource(index)) == "ok" else { return showToast(L("Couldn't select the source"), symbol: "exclamationmark.triangle.fill") }
        showToast(L("“%@” selected — click the player", title), symbol: "list.bullet.rectangle")
    }

    /// Sayfadaki (tüm iframe'ler dahil) ve bu sayfada ağdan istenen altyazılar.
    func subtitleSources() -> [SubtitleSource] {
        guard let e = engine else { return [] }
        var result: [SubtitleSource] = []
        var seen = Set<String>()
        func append(_ source: SubtitleSource) {
            guard !seen.contains(source.key) else { return }
            seen.insert(source.key)
            result.append(source)
        }
        for frame in e.allFrames() {
            guard let info = parseObject(e.evaluate(Pages.subtitles, in: frame)) else { continue }
            let href = info["href"] as? String
            for track in info["tracks"] as? [[String: Any]] ?? [] {
                let raw = track["cues"] as? [[Any]] ?? []
                let cues = raw.compactMap { c -> SubtitleCue? in
                    guard c.count == 3, let start = c[0] as? Double, let end = c[1] as? Double,
                          let text = c[2] as? String else { return nil }
                    let clean = Subtitles.cleanText(text)
                    return clean.isEmpty ? nil : SubtitleCue(start: start, end: end, text: clean)
                }
                guard !cues.isEmpty else { continue }
                let d = Subtitles.describe(label: track["label"] as? String ?? "", language: track["lang"] as? String, url: nil)
                append(.cues(cues, label: d.label, language: d.language))
            }
            for item in info["urls"] as? [[String: Any]] ?? [] {
                guard let src = item["src"] as? String, let url = URL(string: src),
                      url.scheme == "http" || url.scheme == "https" else { continue }
                let d = Subtitles.describe(label: item["label"] as? String ?? "", language: item["lang"] as? String, url: url)
                append(.url(url, label: d.label, language: d.language, referer: href))
            }
        }
        if let since = activeTab?.loadStartedAt {
            for item in MediaSniffer.subtitles(since: since) {
                let d = Subtitles.describe(label: "", language: nil, url: item.url)
                append(.url(item.url, label: d.label, language: d.language, referer: item.referer))
            }
        }
        // Aynı ada sahip altyazıları ayırt et
        var counts: [String: Int] = [:]
        return result.map { source in
            guard case let .url(url, label, language, referer) = source else { return source }
            counts[label, default: 0] += 1
            let n = counts[label]!
            return n > 1 ? .url(url, label: "\(label) (\(n))", language: language, referer: referer) : source
        }
    }

    // MARK: Gizli gezinme

    func togglePrivate() {
        if store.privateMode {
            store.endPrivate()
            saveSession()
            showToast(L("Private browsing off — cookies from this session were deleted"), symbol: "eye")
        } else {
            saveSession()
            store.beginPrivate()
            showToast(L("Private browsing on — history isn't saved"), symbol: "eye.slash.fill")
        }
        updateBadges()
        updateBar()
        refreshHomeTabs()
    }

    // MARK: Görsel yardımcılar

    /// UIWebView bazen son "bitti" bildiriminde hâlâ yükleniyor der; kısa aralıklarla tekrar bakar.
    private func refreshSpinnerSoon() {
        for delay in [0.0, 1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let e = self.engine else { return }
                self.chrome.setLoading(e.isLoading)
                if !e.isLoading {
                    // Son "bitti" bildirimi hâlâ yükleniyor derken geldiyse son işleri şimdi tamamla
                    if let t = self.activeTab, !t.finalHandled, t.handledInterimFinish { self.pageFinished(t) }
                    self.updateBar()
                }
            }
        }
    }

    func showToast(_ text: String, symbol: String? = nil) {
        toast.show(text, symbol: symbol ?? "info.circle.fill", in: view)
    }

    private func bounceCursor() {
        cursor.bounce()
    }

    func parseObject(_ json: String?) -> [String: Any]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Debug

    #if DEBUG
    static func debugAppend(_ file: String, _ text: String) {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(file)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// Simülatörde kumanda olmadan test için: -openURL, -debugClickX/-debugClickY [-debugType], -debugAction.
    private func runDebugLaunchArguments() {
        let d = UserDefaults.standard
        if let s = d.string(forKey: "openURL") { open(s) }
        if d.object(forKey: "debugClickX") != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.cursor.center = CGPoint(x: d.double(forKey: "debugClickX"), y: d.double(forKey: "debugClickY"))
                self?.clickAtCursor()
                if let text = d.string(forKey: "debugType") {
                    self?.dismiss(animated: false)
                    self?.engine?.evaluate(Pages.setFieldValue(text, submit: true), in: self?.fieldFrame)
                }
            }
        }
        // ör. -debugAction "reader" | "find:kelime" | "zoom:150" | "menu" | "tabs" | "newtab:https://..." | "hover:x,y"
        if let action = d.string(forKey: "debugAction") {
            DispatchQueue.main.asyncAfter(deadline: .now() + (d.object(forKey: "debugDelay") != nil ? d.double(forKey: "debugDelay") : 5)) { [weak self] in
                guard let self else { return }
                let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                switch parts[0] {
                case "reader": self.toggleReader()
                case "find": self.startFind(arg)
                case "zoom": self.setZoom(Int(arg) ?? 150)
                case "menu": self.showMenu()
                case "tabs": self.showTabs()
                case "settings": self.showSettings()
                case "newtab": self.addTab(url: URL(string: arg), activate: false)
                case "private": self.togglePrivate()
                case "hover":
                    let xy = arg.split(separator: ",").compactMap { Double($0) }
                    if xy.count == 2 { self.cursor.center = CGPoint(x: xy[0], y: xy[1]); self.checkHover() }
                case "videos":
                    let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("debug-videos.txt")
                    try? self.videoCandidates().map { "\($0.title) | \($0.src) | ref=\($0.referer ?? "-")" }.joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
                case "play": if let v = self.videoCandidates().first { self.playVideo(src: v.src, time: v.time, referer: v.referer) }
                case "ua":
                    self.store.desktopMode.toggle(); self.recreateEngines()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("debug-ua.txt")
                        try? "\(self.store.desktopMode) \(self.engine?.js("navigator.userAgent") ?? "")".write(to: f, atomically: true, encoding: .utf8)
                    }
                case "subs":
                    let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("debug-subs.txt")
                    try? self.subtitleSources().map { src -> String in
                        switch src {
                        case let .url(u, l, g, r): return "url \(l) [\(g ?? "-")] \(u.absoluteString) ref=\(r ?? "-")"
                        case let .cues(c, l, g): return "cues \(l) [\(g ?? "-")] \(c.count) lines"
                        }
                    }.joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
                case "remote": self.showRemoteInfo()
                case "next": if let n = self.nextEpisode() { self.openNextEpisode(n.url) }
                case "sources":
                    let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("debug-sources.txt")
                    let next = self.nextEpisode().map { "\($0.url.absoluteString) guessed=\($0.guessed)" } ?? "none"
                    try? (self.pageSources().map { "\($0.active ? "*" : "-") \($0.text)" } + ["next: \(next)"])
                        .joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
                case "jsbench":
                    let r = self.engine?.js(Pages.jsBenchmark) ?? "-"
                    Self.debugAppend("perf.txt", "JS: \(r)\n")
                case "closefocused":
                    self.showTabSwitcher()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let r = (self.presentedViewController as? TabSwitcherController)?.debugCloseFocused() ?? "no tab switcher"
                        Self.debugAppend("perf.txt", "close-tab: \(r)\n")
                    }
                case "opentabs": // virgülle ayrılmış adresleri 4 sn arayla yeni sekmelerde aç, sonra sekme ekranı
                    for (i, u) in arg.split(separator: ",").enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 4) {
                            if let url = URL(string: String(u)) { self.addTab(url: url, activate: true) }
                        }
                    }
                    let n = Double(arg.split(separator: ",").count)
                    DispatchQueue.main.asyncAfter(deadline: .now() + n * 4 + 1) { self.showTabSwitcher() }
                case "search":
                    self.present(AddressSearch.make(initialText: arg) { [weak self] text in self?.open(text) }, animated: true)
                case "blocked": UserDefaults.standard.set(AdBlocker.blockedCount, forKey: "debugBlockedCount")
                default: break
                }
            }
        }
    }
    #endif
}

final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 18, left: 30, bottom: 18, right: 30)

    static func badge() -> PaddedLabel {
        let l = PaddedLabel()
        l.insets = UIEdgeInsets(top: 9, left: 18, bottom: 9, right: 18)
        l.font = .systemFont(ofSize: 19, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 22
        l.layer.masksToBounds = true
        return l
    }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(CGSize(width: size.width - insets.left - insets.right, height: size.height))
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}
