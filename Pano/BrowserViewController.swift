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
    let cursor = UIImageView(image: BrowserViewController.cursorImage())
    let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    let titleLabel = UILabel()
    let hostLabel = UILabel()
    let modeBadge = PaddedLabel.badge()
    let tabsBadge = PaddedLabel.badge()
    let privateBadge = PaddedLabel.badge()
    let spinner = UIActivityIndicatorView(style: .medium)
    let toast = PaddedLabel()

    var mode: Mode = .cursor
    private var lastTouch: CGPoint?
    private var lastTouchTime: TimeInterval = 0
    private var velocity: CGPoint = .zero
    private var momentum: CADisplayLink?
    private var selectHold: DispatchWorkItem?
    private var selectHoldFired = false
    private var playHold: DispatchWorkItem?
    private var playHoldFired = false
    private var playSingle: DispatchWorkItem?
    private var hovering = false
    private var lastHoverCheck: TimeInterval = 0

    var findQuery: String?
    var findCount = 0
    var findIndex = 0
    /// Son tıklanan metin alanının / açılır listenin bulunduğu çerçeve (nil = ana çerçeve).
    weak var fieldFrame: NSObject?
    private var videoWatch: Timer?

    static let barHeight: CGFloat = 76
    static let maxTabs = 8

    // MARK: Yaşam döngüsü

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        container.frame = view.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        setupTopBar()
        setupToast()

        guard WebEngine.isAvailable else {
            showUnavailable()
            return
        }
        if store.privateMode { store.endPrivate() } // gizli oturum uygulama kapanınca biter
        restoreSession()

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
        let w = view.bounds.width
        topBar.frame = CGRect(x: 0, y: 0, width: w, height: Self.barHeight)
        activeTab?.engine.view.frame = CGRect(x: 0, y: Self.barHeight, width: w, height: view.bounds.height - Self.barHeight)

        let pad: CGFloat = 60
        spinner.center = CGPoint(x: pad + 20, y: Self.barHeight / 2)
        var right = w - pad
        for badge in [modeBadge, tabsBadge, privateBadge] where !badge.isHidden {
            let size = badge.sizeThatFits(CGSize(width: 400, height: 50))
            badge.frame = CGRect(x: right - size.width, y: (Self.barHeight - size.height) / 2, width: size.width, height: size.height)
            right = badge.frame.minX - 14
        }
        let textX = pad + 50
        let textW = right - textX - 16
        titleLabel.frame = CGRect(x: textX, y: 8, width: textW, height: 36)
        hostLabel.frame = CGRect(x: textX, y: 42, width: textW, height: 26)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [] }

    // MARK: Kurulum

    private func setupTopBar() {
        view.addSubview(topBar)
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = .white
        hostLabel.font = .systemFont(ofSize: 20)
        hostLabel.textColor = UIColor(white: 1, alpha: 0.6)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        privateBadge.text = "Gizli"
        privateBadge.backgroundColor = UIColor(red: 0.36, green: 0.17, blue: 0.84, alpha: 0.9)
        tabsBadge.backgroundColor = UIColor(white: 1, alpha: 0.18)
        [titleLabel, hostLabel, spinner, modeBadge, tabsBadge, privateBadge].forEach { topBar.contentView.addSubview($0) }
        updateBadges()
    }

    private func setupToast() {
        toast.font = .systemFont(ofSize: 26, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor(white: 0.1, alpha: 0.88)
        toast.layer.cornerRadius = 18
        toast.layer.masksToBounds = true
        toast.numberOfLines = 0
        toast.textAlignment = .center
        toast.alpha = 0
        view.addSubview(toast)
    }

    private func showUnavailable() {
        let label = UILabel()
        label.text = "Bu tvOS sürümünde web motoru (UIWebView) bulunamadı."
        label.textColor = .white
        label.font = .systemFont(ofSize: 34, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = view.bounds.insetBy(dx: 120, dy: 120)
        view.addSubview(label)
    }

    func makeEngine(for tab: Tab) -> WebEngine {
        let e = WebEngine()!
        if !e.setUserAgent(store.currentUA) { NSLog("Pano: kullanıcı ajanı ayarlanamadı") }
        e.view.isUserInteractionEnabled = false
        e.view.insetsLayoutMarginsFromSafeArea = false
        e.scrollView?.contentInsetAdjustmentBehavior = .never
        e.scrollView?.contentInset = .zero
        e.onStart = { [weak self, weak tab] in
            guard let self, let tab, tab === self.activeTab else { return }
            self.spinner.startAnimating()
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
            showToast("En fazla \(Self.maxTabs) sekme açılabilir")
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
        activeTab?.engine.view.removeFromSuperview()
        current = index
        let t = tabs[index]
        container.addSubview(t.engine.view)
        t.engine.view.frame = CGRect(x: 0, y: Self.barHeight, width: view.bounds.width,
                                     height: view.bounds.height - Self.barHeight)
        if t.needsLoad {
            t.needsLoad = false
            if let url = t.pendingURL { t.engine.load(url) } else { loadHome(in: t) }
        }
        hovering = false
        cursor.transform = .identity
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
            case "newtab":
                if let s = items.first(where: { $0.name == "url" })?.value, let target = URL(string: s) {
                    DispatchQueue.main.async {
                        if self.addTab(url: target, activate: false) {
                            self.showToast("Yeni sekmede açıldı — sekmeler için Oynat/Duraklat'a basılı tut")
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
            DispatchQueue.main.async { self.showToast("Bu bağlantı türü açılamıyor: \(scheme)") }
            return false
        }
        if request.mainDocumentURL == nil || request.mainDocumentURL == url { // ana çerçeve gezinmesi
            t.mainRequestURL = url.absoluteString
            t.blockedAtStart = AdBlocker.blockedCount
            t.loadStartedAt = Date()
            if t === activeTab { stopVideoWatch() }
            t.isReader = false
            if t === activeTab { resetFind() }
        }
        return true
    }

    private func pageFinished(_ t: Tab) {
        let e = t.engine!
        if t === activeTab { refreshSpinnerSoon() }
        let marker = e.js("document.documentElement.getAttribute('data-pano')") ?? ""
        e.js(Pages.afterLoad(textScale: store.textScale, adBlock: store.adBlockEnabled))
        let url = e.currentURL
        t.isHome = marker == "home"
        if t.isHome {
            t.title = "Ana Sayfa"
            t.url = nil
            t.pendingURL = nil
        } else if marker == "error" {
            t.title = "Sayfa açılamadı"
        } else if let url {
            let title = e.title
            t.title = title.isEmpty ? (url.host ?? url.absoluteString) : title
            t.url = url
            t.pendingURL = nil
            if !store.privateMode { store.addHistory(title: title, url: url.absoluteString) }
            let zoom = store.zoom(for: url.host)
            if zoom != 100 { e.js(Pages.applyZoom(zoom)) }
        }
        if t === activeTab { updateBar() }
        saveSession()
    }

    private func pageFailed(_ t: Tab, _ error: NSError) {
        if t === activeTab, !t.engine.isLoading { spinner.stopAnimating() }
        // -999: iptal; WebKit 102: çerçeve yüklemesi kesildi; 204: eklenti (video) yüklemeyi üstlendi
        if error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204) { return }
        let failing = (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? ""
        guard failing.isEmpty || failing == t.mainRequestURL else { return } // alt kaynak / iframe hatası
        if error.domain == AdBlocker.errorDomain {
            if t === activeTab { showToast("Reklam/izleyici adresi engellendi") }
            return
        }
        t.engine.loadHTML(Pages.error(url: failing, message: error.localizedDescription), baseURL: nil)
        t.title = "Sayfa açılamadı"
        if t === activeTab {
            titleLabel.text = t.title
            hostLabel.text = failing
        }
    }

    // MARK: Gezinme

    func loadHome(in t: Tab) {
        t.isHome = true
        t.url = nil
        t.title = "Ana Sayfa"
        t.engine.loadHTML(Pages.home(bookmarks: store.bookmarks, engine: store.searchEngine, isPrivate: store.privateMode),
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
        titleLabel.text = t.title
        if t.isHome {
            hostLabel.text = store.privateMode ? "Pano · gizli gezinme" : "Pano"
        } else {
            hostLabel.text = (t.url ?? t.pendingURL)?.absoluteString ?? ""
        }
        if t.engine.isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    func updateBadges() {
        modeBadge.text = mode == .cursor ? "İmleç" : "Kaydırma"
        modeBadge.backgroundColor = mode == .cursor
            ? UIColor(red: 0.31, green: 0.42, blue: 1, alpha: 0.85)
            : UIColor(red: 0.07, green: 0.6, blue: 0.56, alpha: 0.85)
        tabsBadge.text = "\(tabs.count) sekme"
        tabsBadge.isHidden = tabs.count < 2
        privateBadge.isHidden = !store.privateMode
        view.setNeedsLayout()
    }

    // MARK: Kumanda: dokunmatik yüzey

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        stopMomentum()
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
            if touch.timestamp - lastHoverCheck > 0.06 {
                lastHoverCheck = touch.timestamp
                checkHover()
            }
        case .scroll:
            let f = 1.6 * store.cursorSpeed
            let d = CGPoint(x: delta.x * f, y: delta.y * f)
            scrollPage(by: d)
            velocity = CGPoint(x: d.x / dt, y: d.y / dt)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouch = nil
        if mode == .scroll, hypot(velocity.x, velocity.y) > 200 { startMomentum() }
        if mode == .cursor { checkHover() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouch = nil
    }

    private func moveCursor(by delta: CGPoint) {
        let area = CGRect(x: 0, y: Self.barHeight, width: view.bounds.width, height: view.bounds.height - Self.barHeight)
            .insetBy(dx: 4, dy: 4)
        let target = CGPoint(x: cursor.center.x + delta.x, y: cursor.center.y + delta.y)
        let clamped = CGPoint(x: min(max(target.x, area.minX), area.maxX),
                              y: min(max(target.y, area.minY), area.maxY))
        cursor.center = clamped
        let overflow = CGPoint(x: target.x - clamped.x, y: target.y - clamped.y)
        if overflow != .zero { scrollPage(by: CGPoint(x: overflow.x * 2.5, y: overflow.y * 2.5)) }
    }

    private func checkHover() {
        guard mode == .cursor, let e = engine, let p = pointer() else { return }
        let h = e.js(Pages.hover(p)) == "1"
        guard h != hovering else { return }
        hovering = h
        UIView.animate(withDuration: 0.12) {
            self.cursor.transform = h ? CGAffineTransform(scaleX: 1.4, y: 1.4) : .identity
        }
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

    private func startMomentum() {
        stopMomentum()
        let link = CADisplayLink(target: self, selector: #selector(momentumTick(_:)))
        link.add(to: .main, forMode: .common)
        momentum = link
    }

    private func stopMomentum() {
        momentum?.invalidate()
        momentum = nil
    }

    @objc private func momentumTick(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp
        let moved = scrollPage(by: CGPoint(x: velocity.x * dt, y: velocity.y * dt))
        velocity = CGPoint(x: velocity.x * 0.95, y: velocity.y * 0.95)
        if !moved || hypot(velocity.x, velocity.y) < 30 { stopMomentum() }
    }

    // MARK: Kumanda: tuşlar

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else { return super.pressesBegan(presses, with: event) }
        switch press.type {
        case .select:
            selectHoldFired = false
            let work = DispatchWorkItem { [weak self] in
                self?.selectHoldFired = true
                self?.showMenu()
            }
            selectHold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        case .playPause:
            playHoldFired = false
            let work = DispatchWorkItem { [weak self] in
                self?.playHoldFired = true
                self?.playSingle?.cancel()
                self?.playSingle = nil
                self?.showTabs()
            }
            playHold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        case .menu, .upArrow, .downArrow, .leftArrow, .rightArrow:
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
            selectHold?.cancel()
            if selectHoldFired { return }
            if mode == .scroll { setMode(.cursor) } else { clickAtCursor() }
        case .playPause:
            playHold?.cancel()
            if playHoldFired { return }
            if let single = playSingle { // çift basış
                single.cancel()
                playSingle = nil
                askAddress()
            } else {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.playSingle = nil
                    self.setMode(self.mode == .cursor ? .scroll : .cursor)
                }
                playSingle = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        case .menu:
            handleBack(presses, event)
        case .upArrow: scrollPage(by: CGPoint(x: 0, y: -page), animated: true)
        case .downArrow: scrollPage(by: CGPoint(x: 0, y: page), animated: true)
        case .leftArrow:
            if findCount > 0 { stepFind(-1) } else { scrollPage(by: CGPoint(x: -page, y: 0), animated: true) }
        case .rightArrow:
            if findCount > 0 { stepFind(1) } else { scrollPage(by: CGPoint(x: page, y: 0), animated: true) }
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        selectHold?.cancel()
        playHold?.cancel()
        super.pressesCancelled(presses, with: event)
    }

    /// Menü/Geri: önce bulma vurgusunu, sonra okuma modunu kapatır; sonra geri gider, sonra ana sayfa, en son çıkış.
    private func handleBack(_ presses: Set<UIPress>, _ event: UIPressesEvent?) {
        guard let t = activeTab else { return super.pressesEnded(presses, with: event) }
        if findCount > 0 {
            resetFind()
            showToast("Arama temizlendi")
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
        showToast(newMode == .cursor ? "İmleç modu" : "Kaydırma modu — tıklayınca imlece dön")
    }

    // MARK: Tıklama ve form alanları

    private func clickAtCursor() {
        guard let e = engine, let p = pointer() else { return }
        bounceCursor()
        stopVideoWatch()
        // Tıklamadan önceki videolar: tıklamadan sonra yeni çıkan ya da oynamaya başlayan video aranır.
        var baseline: [String: Bool] = [:]
        for v in allVideos() where baseline[v.src] == nil { baseline[v.src] = v.paused }
        let clickTime = Date()

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
        let alert = UIAlertController(title: label.isEmpty ? "Metin gir" : label, message: nil, preferredStyle: .alert)
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
        alert.addAction(UIAlertAction(title: "Gönder", style: .default) { _ in apply(true) })
        alert.addAction(UIAlertAction(title: "Yalnızca yaz", style: .default) { _ in apply(false) })
        alert.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(alert, animated: true)
    }

    private func chooseOption(options: [String], selected: Int, label: String) {
        guard !options.isEmpty else { return }
        let sheet = UIAlertController(title: label.isEmpty ? "Seç" : label, message: nil, preferredStyle: .actionSheet)
        for (i, option) in options.enumerated() {
            sheet.addAction(UIAlertAction(title: (i == selected ? "✓ " : "") + option, style: .default) { [weak self] _ in
                guard let self else { return }
                self.engine?.evaluate(Pages.setSelectIndex(i), in: self.fieldFrame)
            })
        }
        sheet.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(sheet, animated: true)
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
            showToast("Okuma modu kapandı")
            return
        }
        if t.engine.js(Pages.reader) == "ok" {
            t.isReader = true
            scrollPage(to: .zero, animated: false)
            showToast("Okuma modu — çıkmak için Menü tuşu")
        } else {
            showToast("Bu sayfada okunacak bir makale bulunamadı")
        }
    }

    // MARK: Yakınlaştırma

    func setZoom(_ zoom: Int) {
        guard let t = activeTab, let host = t.url?.host else { return }
        store.setZoom(zoom, for: host)
        t.engine.js(Pages.applyZoom(zoom))
        showToast("Yakınlaştırma %\(zoom) — \(host) için hatırlanacak")
    }

    // MARK: Sayfada bul

    func startFind(_ query: String) {
        guard let e = engine, !query.isEmpty else { return }
        resetFind()
        let count = Int(e.js(Pages.findAll(query)) ?? "") ?? 0
        guard count > 0 else {
            showToast("“\(query)” bulunamadı")
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
        showToast("\(findIndex + 1) / \(findCount)  ·  ◀ ▶ yön tuşlarıyla gez, Menü ile kapat")
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
            result.append(("Video · \(URL(string: v.src)?.host ?? "")\(v.paused ? "" : " (oynuyor)")", v.src, v.time, v.referer))
        }
        if let since = activeTab?.loadStartedAt {
            let sniffed = MediaSniffer.items(since: since)
            for m in sniffed.filter(\.isPlaylist) + sniffed.filter({ !$0.isPlaylist }) where !seen.contains(m.url.absoluteString) {
                seen.insert(m.url.absoluteString)
                result.append(("\(m.isPlaylist ? "Akış (HLS)" : "Dosya") · \(m.url.host ?? "")", m.url.absoluteString, 0, m.referer))
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
            let started = videos.first { v in
                v.playable && (baseline[v.src] == nil || (baseline[v.src] == true && !v.paused))
            }
            if let v = started {
                self.stopVideoWatch()
                self.showToast("Video oynatıcıda açılıyor…")
                self.playVideo(src: v.src, time: v.time, referer: v.referer)
                return
            }
            let sniffed = MediaSniffer.items(since: since)
            if let m = sniffed.first(where: \.isPlaylist) ?? (ticks >= 6 ? sniffed.first : nil) {
                self.stopVideoWatch()
                self.showToast("Video oynatıcıda açılıyor…")
                self.playVideo(src: m.url.absoluteString, time: 0, referer: m.referer)
                return
            }
            if ticks == 24, videos.contains(where: { $0.blob }) {
                self.showToast("Video bulundu ama doğrudan oynatılabilir bir adresi yok (korumalı akış)")
            }
        }
    }

    func stopVideoWatch() {
        videoWatch?.invalidate()
        videoWatch = nil
    }

    /// Videoyu tvOS'un kendi oynatıcısında tam ekran açar (kumandanın oynat/sar tuşları çalışır).
    /// Film sitelerindeki akışlar çoğu zaman Referer/Origin başlığı ister; videonun bulunduğu sayfanın adresi gönderilir.
    func playVideo(src: String, time: Double, referer: String? = nil) {
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
        if let e = engine { for frame in e.allFrames() { e.evaluate(Pages.pauseVideos, in: frame) } }
        let vc = AVPlayerViewController()
        vc.player = player
        present(vc, animated: true) { player.play() }
    }

    // MARK: Gizli gezinme

    func togglePrivate() {
        if store.privateMode {
            store.endPrivate()
            saveSession()
            showToast("Gizli gezinme kapandı — bu sürede oluşan çerezler silindi")
        } else {
            saveSession()
            store.beginPrivate()
            showToast("Gizli gezinme açık — geçmiş kaydedilmiyor")
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
                if e.isLoading { self.spinner.startAnimating() } else { self.spinner.stopAnimating() }
            }
        }
    }

    func showToast(_ text: String) {
        toast.text = text
        let size = toast.sizeThatFits(CGSize(width: 1100, height: 400))
        toast.frame = CGRect(x: (view.bounds.width - size.width) / 2, y: view.bounds.height - size.height - 70,
                             width: size.width, height: size.height)
        view.bringSubviewToFront(toast)
        toast.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.2, animations: { self.toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 2.2, options: [], animations: { self.toast.alpha = 0 })
        }
    }

    private func bounceCursor() {
        let rest: CGAffineTransform = hovering ? CGAffineTransform(scaleX: 1.4, y: 1.4) : .identity
        UIView.animate(withDuration: 0.08, animations: {
            self.cursor.transform = rest.scaledBy(x: 0.7, y: 0.7)
        }) { _ in
            UIView.animate(withDuration: 0.12) { self.cursor.transform = rest }
        }
    }

    func parseObject(_ json: String?) -> [String: Any]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func cursorImage() -> UIImage {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor.black.withAlphaComponent(0.6).cgColor)
            let outer = CGRect(x: 8, y: 8, width: 28, height: 28)
            c.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            c.fillEllipse(in: outer)
            c.setShadow(offset: .zero, blur: 0)
            c.setStrokeColor(UIColor(white: 0.1, alpha: 0.9).cgColor)
            c.setLineWidth(3)
            c.strokeEllipse(in: outer.insetBy(dx: 1.5, dy: 1.5))
            c.setFillColor(UIColor(red: 0.31, green: 0.42, blue: 1, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: 18, y: 18, width: 8, height: 8))
        }
    }

    // MARK: Debug

    #if DEBUG
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
            DispatchQueue.main.asyncAfter(deadline: .now() + (d.object(forKey: "debugDelay") as? Double ?? 5)) { [weak self] in
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
        l.insets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        l.font = .systemFont(ofSize: 20, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 10
        l.layer.masksToBounds = true
        return l
    }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(CGSize(width: size.width - insets.left - insets.right, height: size.height))
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}
