import UIKit

/// Siri Remote ile kullanılan tarayıcı ekranı.
/// - İmleç modu: dokunmatik yüzeyde kaydırınca imleç hareket eder, tıklayınca altındaki öğeye tıklanır.
///   İmleç ekran kenarına itilirse sayfa kayar.
/// - Kaydırma modu: dokunmatik yüzey sayfayı kaydırır (ataletli).
/// - Oynat/Duraklat: mod değiştirir. Seçim tuşuna uzun basma: menü. Menü/Geri tuşu: önceki sayfa.
final class BrowserViewController: UIViewController {
    private enum Mode { case cursor, scroll }

    private let store = Store.shared
    private var engine: WebEngine?
    private let container = UIView()
    private let cursor = UIImageView(image: BrowserViewController.cursorImage())
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let modeLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let toast = PaddedLabel()

    private var mode: Mode = .cursor
    private var lastTouch: CGPoint?
    private var lastTouchTime: TimeInterval = 0
    private var velocity: CGPoint = .zero
    private var momentum: CADisplayLink?
    private var longPressWork: DispatchWorkItem?
    private var longPressFired = false
    private var showingHome = false

    private static let barHeight: CGFloat = 76

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
        createEngine()

        cursor.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        view.addSubview(cursor)

        #if DEBUG
        if let debugURL = UserDefaults.standard.string(forKey: "openURL") { open(debugURL) } else { goHome() }
        #else
        goHome()
        #endif
        #if DEBUG
        let d = UserDefaults.standard
        if d.object(forKey: "debugClickX") != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.cursor.center = CGPoint(x: d.double(forKey: "debugClickX"), y: d.double(forKey: "debugClickY"))
                self?.clickAtCursor()
                if let text = d.string(forKey: "debugType") {
                    self?.dismiss(animated: false)
                    let enc = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
                    self?.engine?.js(Pages.setFieldValue(enc, submit: true))
                }
            }
        }
        #endif
        if !store.hasSeenHelp {
            store.hasSeenHelp = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showHelp() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        topBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: Self.barHeight)
        engine?.view.frame = CGRect(x: 0, y: Self.barHeight, width: view.bounds.width,
                                    height: view.bounds.height - Self.barHeight)
        let pad: CGFloat = 60
        spinner.center = CGPoint(x: pad + 20, y: Self.barHeight / 2)
        modeLabel.sizeToFit()
        modeLabel.frame = CGRect(x: view.bounds.width - pad - modeLabel.bounds.width - 24, y: 18,
                                 width: modeLabel.bounds.width + 24, height: Self.barHeight - 36)
        let textX = pad + 50
        let textW = modeLabel.frame.minX - textX - 30
        titleLabel.frame = CGRect(x: textX, y: 8, width: textW, height: 36)
        hostLabel.frame = CGRect(x: textX, y: 42, width: textW, height: 26)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [] }

    // MARK: Kurulum

    private func createEngine() {
        let previousURL = engine?.currentURL
        engine?.view.removeFromSuperview()
        store.applyUserAgent()
        guard let engine = WebEngine() else { showUnavailable(); return }
        self.engine = engine
        engine.view.isUserInteractionEnabled = false
        engine.view.insetsLayoutMarginsFromSafeArea = false
        engine.scrollView?.contentInsetAdjustmentBehavior = .never
        engine.scrollView?.contentInset = .zero
        container.addSubview(engine.view)
        view.setNeedsLayout()

        engine.onStart = { [weak self] in
            self?.spinner.startAnimating()
        }
        engine.onFinish = { [weak self] in self?.pageFinished() }
        engine.onFail = { [weak self] error in self?.pageFailed(error) }
        engine.shouldLoad = { [weak self] request, _ in self?.shouldLoad(request) ?? true }

        if let previousURL { engine.load(previousURL) }
    }

    private func setupTopBar() {
        view.addSubview(topBar)
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = .white
        hostLabel.font = .systemFont(ofSize: 20)
        hostLabel.textColor = UIColor(white: 1, alpha: 0.6)
        modeLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        modeLabel.textColor = .white
        modeLabel.textAlignment = .center
        modeLabel.layer.cornerRadius = 10
        modeLabel.layer.masksToBounds = true
        spinner.color = .white
        spinner.hidesWhenStopped = true
        [titleLabel, hostLabel, modeLabel, spinner].forEach { topBar.contentView.addSubview($0) }
        updateModeLabel()
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

    // MARK: Sayfa olayları

    private func shouldLoad(_ request: URLRequest) -> Bool {
        guard let url = request.url else { return true }
        if url.scheme == "pano" {
            if url.host == "search" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
                DispatchQueue.main.async { self.open(q) }
            } else if url.host == "home" {
                DispatchQueue.main.async { self.goHome() }
            }
            return false
        }
        if let scheme = url.scheme, !["http", "https", "about", "data", "blob", "javascript"].contains(scheme) {
            DispatchQueue.main.async { self.showToast("Bu bağlantı türü açılamıyor: \(scheme)") }
            return false
        }
        return true
    }

    private func pageFinished() {
        guard let engine else { return }
        if !engine.isLoading { spinner.stopAnimating() }
        engine.js(Pages.afterLoad(textScale: store.textScale))
        let url = engine.currentURL
        showingHome = engine.js("document.documentElement.getAttribute('data-pano')") == "home"
        if showingHome {
            titleLabel.text = "Ana Sayfa"
            hostLabel.text = "Pano"
        } else if url == nil {
            titleLabel.text = engine.title
        } else if let url {
            let title = engine.title
            titleLabel.text = title.isEmpty ? url.host : title
            hostLabel.text = url.absoluteString
            store.addHistory(title: title, url: url.absoluteString)
            store.lastURL = url.absoluteString
        }
    }

    private func pageFailed(_ error: NSError) {
        spinner.stopAnimating()
        // -999: iptal edildi, 102: çerçeve yüklemesi kesildi (ör. pano:// yakalandı) — hata değil
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) { return }
        let failing = (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? ""
        engine?.loadHTML(Pages.error(url: failing, message: error.localizedDescription), baseURL: nil)
        titleLabel.text = "Sayfa açılamadı"
        hostLabel.text = failing
    }

    // MARK: Gezinme

    private func goHome() {
        showingHome = true
        engine?.loadHTML(Pages.home(bookmarks: store.bookmarks, engine: store.searchEngine), baseURL: nil)
        titleLabel.text = "Ana Sayfa"
        hostLabel.text = "Pano"
    }

    private func open(_ input: String) {
        guard let url = store.resolve(input) else { return }
        engine?.load(url)
        hostLabel.text = url.absoluteString
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
            moveCursor(by: CGPoint(x: delta.x * store.cursorSpeed, y: delta.y * store.cursorSpeed))
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
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouch = nil
    }

    private func moveCursor(by delta: CGPoint) {
        let area = webArea()
        let target = CGPoint(x: cursor.center.x + delta.x, y: cursor.center.y + delta.y)
        let clamped = CGPoint(x: min(max(target.x, area.minX), area.maxX),
                              y: min(max(target.y, area.minY), area.maxY))
        cursor.center = clamped
        // Kenara dayanınca sayfayı kaydır
        let overflow = CGPoint(x: target.x - clamped.x, y: target.y - clamped.y)
        if overflow != .zero { scrollPage(by: CGPoint(x: overflow.x * 2.5, y: overflow.y * 2.5)) }
    }

    private func webArea() -> CGRect {
        CGRect(x: 0, y: Self.barHeight, width: view.bounds.width, height: view.bounds.height - Self.barHeight)
            .insetBy(dx: 4, dy: 4)
    }

    @discardableResult
    private func scrollPage(by delta: CGPoint, animated: Bool = false) -> Bool {
        guard let sv = engine?.scrollView else { return false }
        let inset = sv.adjustedContentInset
        let maxX = max(-inset.left, sv.contentSize.width - sv.bounds.width + inset.right)
        let maxY = max(-inset.top, sv.contentSize.height - sv.bounds.height + inset.bottom)
        let new = CGPoint(x: min(max(sv.contentOffset.x + delta.x, -inset.left), maxX),
                          y: min(max(sv.contentOffset.y + delta.y, -inset.top), maxY))
        let moved = new != sv.contentOffset
        sv.setContentOffset(new, animated: animated)
        return moved
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
            longPressFired = false
            let work = DispatchWorkItem { [weak self] in
                self?.longPressFired = true
                self?.showMenu()
            }
            longPressWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        case .playPause, .menu, .upArrow, .downArrow, .leftArrow, .rightArrow:
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
            longPressWork?.cancel()
            if longPressFired { return }
            if mode == .scroll { setMode(.cursor) } else { clickAtCursor() }
        case .playPause:
            setMode(mode == .cursor ? .scroll : .cursor)
        case .menu:
            if let engine, engine.canGoBack {
                engine.goBack()
            } else if !showingHome {
                goHome()
            } else {
                super.pressesEnded(presses, with: event) // ana ekrana çık
            }
        case .upArrow: scrollPage(by: CGPoint(x: 0, y: -page), animated: true)
        case .downArrow: scrollPage(by: CGPoint(x: 0, y: page), animated: true)
        case .leftArrow: scrollPage(by: CGPoint(x: -page, y: 0), animated: true)
        case .rightArrow: scrollPage(by: CGPoint(x: page, y: 0), animated: true)
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        longPressWork?.cancel()
        super.pressesCancelled(presses, with: event)
    }

    private func setMode(_ newMode: Mode) {
        mode = newMode
        stopMomentum()
        UIView.animate(withDuration: 0.2) { self.cursor.alpha = newMode == .cursor ? 1 : 0 }
        updateModeLabel()
        showToast(newMode == .cursor ? "İmleç modu" : "Kaydırma modu — tıklayınca imlece dön")
    }

    private func updateModeLabel() {
        modeLabel.text = mode == .cursor ? "  İmleç  " : "  Kaydırma  "
        modeLabel.backgroundColor = mode == .cursor
            ? UIColor(red: 0.31, green: 0.42, blue: 1, alpha: 0.85)
            : UIColor(red: 0.07, green: 0.6, blue: 0.56, alpha: 0.85)
        view.setNeedsLayout()
    }

    // MARK: Tıklama ve form alanları

    private func clickAtCursor() {
        guard let engine, let sv = engine.scrollView else { return }
        bounceCursor()
        let p = view.convert(cursor.center, to: engine.view)
        let innerWidth = Double(engine.js("window.innerWidth") ?? "") ?? 0
        let scale = innerWidth > 0 ? Double(engine.view.bounds.width) / innerWidth : Double(sv.zoomScale)
        let docX = (Double(sv.contentOffset.x) + Double(p.x)) / scale
        let docY = (Double(sv.contentOffset.y) + Double(p.y)) / scale
        guard let json = engine.js(Pages.click(docX: docX, docY: docY)),
              let data = json.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = info["kind"] as? String else { return }
        switch kind {
        case "input":
            askForText(type: info["type"] as? String ?? "",
                       value: info["value"] as? String ?? "",
                       label: info["label"] as? String ?? "")
        case "select":
            chooseOption(options: info["options"] as? [String] ?? [],
                         selected: info["selected"] as? Int ?? -1,
                         label: info["label"] as? String ?? "")
        default:
            break
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
            let text = alert?.textFields?.first?.text ?? ""
            guard let data = try? JSONEncoder().encode(text), let encoded = String(data: data, encoding: .utf8) else { return }
            self?.engine?.js(Pages.setFieldValue(encoded, submit: submit))
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
                self?.engine?.js(Pages.setSelectIndex(i))
            })
        }
        sheet.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: Menü

    private func showMenu() {
        guard presentedViewController == nil, let engine else { return }
        let url = engine.currentURL
        let isWeb = url.map { $0.scheme == "http" || $0.scheme == "https" } ?? false
        let sheet = UIAlertController(title: "Pano", message: isWeb ? url?.absoluteString : nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Adres yaz / Ara", style: .default) { [weak self] _ in self?.askAddress() })
        sheet.addAction(UIAlertAction(title: "Ana Sayfa", style: .default) { [weak self] _ in self?.goHome() })
        if engine.canGoBack {
            sheet.addAction(UIAlertAction(title: "Geri", style: .default) { _ in engine.goBack() })
        }
        if engine.canGoForward {
            sheet.addAction(UIAlertAction(title: "İleri", style: .default) { _ in engine.goForward() })
        }
        sheet.addAction(UIAlertAction(title: "Yenile", style: .default) { [weak self] _ in
            if self?.showingHome == true { self?.goHome() } else { engine.reload() }
        })
        if isWeb, let url {
            let str = url.absoluteString
            if store.isBookmarked(str) {
                sheet.addAction(UIAlertAction(title: "Sık kullanılanlardan çıkar", style: .destructive) { [weak self] _ in
                    self?.store.bookmarks.removeAll { $0.url == str }
                    self?.showToast("Çıkarıldı")
                })
            } else {
                sheet.addAction(UIAlertAction(title: "Sık kullanılanlara ekle", style: .default) { [weak self] _ in
                    let title = engine.title
                    self?.store.bookmarks.append(Bookmark(title: title.isEmpty ? (url.host ?? str) : title, url: str))
                    self?.showToast("Sık kullanılanlara eklendi")
                })
            }
        }
        sheet.addAction(UIAlertAction(title: "Sık Kullanılanlar", style: .default) { [weak self] _ in self?.showBookmarks() })
        sheet.addAction(UIAlertAction(title: "Geçmiş", style: .default) { [weak self] _ in self?.showHistory() })
        sheet.addAction(UIAlertAction(title: mode == .cursor ? "Kaydırma moduna geç" : "İmleç moduna geç", style: .default) { [weak self] _ in
            guard let self else { return }
            self.setMode(self.mode == .cursor ? .scroll : .cursor)
        })
        sheet.addAction(UIAlertAction(title: "Ayarlar", style: .default) { [weak self] _ in self?.showSettings() })
        sheet.addAction(UIAlertAction(title: "Kumanda Kullanımı", style: .default) { [weak self] _ in self?.showHelp() })
        sheet.addAction(UIAlertAction(title: "Kapat", style: .cancel))
        present(sheet, animated: true)
    }

    private func askAddress() {
        let alert = UIAlertController(title: "Adres veya arama", message: "\(store.searchEngine.name) ile aranır", preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.showingHome == true ? "" : self?.engine?.currentURL?.absoluteString
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Git", style: .default) { [weak self, weak alert] _ in
            self?.open(alert?.textFields?.first?.text ?? "")
        })
        alert.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(alert, animated: true)
    }

    private func showBookmarks() {
        let list = store.bookmarks
        let sheet = UIAlertController(title: "Sık Kullanılanlar", message: list.isEmpty ? "Henüz yok" : nil, preferredStyle: .actionSheet)
        for b in list {
            sheet.addAction(UIAlertAction(title: b.title, style: .default) { [weak self] _ in self?.open(b.url) })
        }
        if !list.isEmpty {
            sheet.addAction(UIAlertAction(title: "Düzenle (sil)…", style: .destructive) { [weak self] _ in self?.editBookmarks() })
        }
        sheet.addAction(UIAlertAction(title: "Kapat", style: .cancel))
        present(sheet, animated: true)
    }

    private func editBookmarks() {
        let sheet = UIAlertController(title: "Silmek için seç", message: nil, preferredStyle: .actionSheet)
        for b in store.bookmarks {
            sheet.addAction(UIAlertAction(title: b.title, style: .destructive) { [weak self] _ in
                self?.store.bookmarks.removeAll { $0 == b }
                if self?.showingHome == true { self?.goHome() }
                self?.showToast("\(b.title) silindi")
            })
        }
        sheet.addAction(UIAlertAction(title: "Bitti", style: .cancel))
        present(sheet, animated: true)
    }

    private func showHistory() {
        let list = store.history.prefix(30)
        let sheet = UIAlertController(title: "Geçmiş", message: list.isEmpty ? "Henüz yok" : nil, preferredStyle: .actionSheet)
        for h in list {
            sheet.addAction(UIAlertAction(title: h.title, style: .default) { [weak self] _ in self?.open(h.url) })
        }
        if !list.isEmpty {
            sheet.addAction(UIAlertAction(title: "Geçmişi temizle", style: .destructive) { [weak self] _ in
                self?.store.history = []
                self?.showToast("Geçmiş temizlendi")
            })
        }
        sheet.addAction(UIAlertAction(title: "Kapat", style: .cancel))
        present(sheet, animated: true)
    }

    private func showSettings() {
        let sheet = UIAlertController(title: "Ayarlar", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Site görünümü: \(store.desktopMode ? "Masaüstü" : "Mobil") → değiştir", style: .default) { [weak self] _ in
            guard let self else { return }
            self.store.desktopMode.toggle()
            self.createEngine() // kullanıcı ajanı yalnızca yeni web görünümünde geçerli
            if self.showingHome { self.goHome() }
            self.showToast(self.store.desktopMode ? "Masaüstü siteler" : "Mobil siteler")
        })
        let speeds: [(String, Double)] = [("Yavaş", 0.6), ("Normal", 1.0), ("Hızlı", 1.5), ("Çok hızlı", 2.2)]
        let currentSpeed = speeds.first { $0.1 == store.cursorSpeed }?.0 ?? "Normal"
        sheet.addAction(UIAlertAction(title: "İmleç hızı: \(currentSpeed)", style: .default) { [weak self] _ in
            self?.pick("İmleç hızı", speeds.map { $0.0 }) { i in self?.store.cursorSpeed = speeds[i].1 }
        })
        let scales = [100, 125, 150, 175, 200]
        sheet.addAction(UIAlertAction(title: "Yazı boyutu: %\(store.textScale)", style: .default) { [weak self] _ in
            self?.pick("Yazı boyutu", scales.map { "%\($0)" }) { i in
                self?.store.textScale = scales[i]
                self?.engine?.js("document.documentElement.style.webkitTextSizeAdjust='\(scales[i])%'")
            }
        })
        sheet.addAction(UIAlertAction(title: "Arama motoru: \(store.searchEngine.name)", style: .default) { [weak self] _ in
            let engines = SearchEngine.allCases
            self?.pick("Arama motoru", engines.map { $0.name }) { i in
                self?.store.searchEngine = engines[i]
                if self?.showingHome == true { self?.goHome() }
            }
        })
        sheet.addAction(UIAlertAction(title: "Çerezleri ve önbelleği temizle", style: .destructive) { [weak self] _ in
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            URLCache.shared.removeAllCachedResponses()
            self?.showToast("Çerezler ve önbellek temizlendi")
        })
        sheet.addAction(UIAlertAction(title: "Kapat", style: .cancel))
        present(sheet, animated: true)
    }

    private func pick(_ title: String, _ options: [String], _ done: @escaping (Int) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (i, o) in options.enumerated() {
            sheet.addAction(UIAlertAction(title: o, style: .default) { _ in done(i) })
        }
        sheet.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(sheet, animated: true)
    }

    private func showHelp() {
        let text = """
        Dokunmatik yüzeyde kaydır: imleci hareket ettir
        İmleci kenara it: sayfa kayar
        Tıkla: bağlantıya / düğmeye tıkla, metin alanında klavye açılır
        Tıklayıp basılı tut: menü (adres, sık kullanılanlar, ayarlar)
        Oynat/Duraklat: imleç ↔ kaydırma modu
        Yön tuşları: sayfayı aşağı/yukarı kaydır
        Menü / Geri: önceki sayfa
        """
        let alert = UIAlertController(title: "Kumanda Kullanımı", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }

    // MARK: Görsel yardımcılar

    private func showToast(_ text: String) {
        toast.text = text
        let size = toast.sizeThatFits(CGSize(width: 900, height: 400))
        toast.frame = CGRect(x: (view.bounds.width - size.width) / 2, y: view.bounds.height - size.height - 70,
                             width: size.width, height: size.height)
        view.bringSubviewToFront(toast)
        toast.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.2, animations: { self.toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 1.8, options: [], animations: { self.toast.alpha = 0 })
        }
    }

    private func bounceCursor() {
        UIView.animate(withDuration: 0.08, animations: {
            self.cursor.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        }) { _ in
            UIView.animate(withDuration: 0.12) { self.cursor.transform = .identity }
        }
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
}

final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 18, left: 30, bottom: 18, right: 30)

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(CGSize(width: size.width - insets.left - insets.right, height: size.height))
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}
