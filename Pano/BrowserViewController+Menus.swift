import UIKit

/// Kumandayla gezilen menüler: sağdan kayan cam panel (MenuPanelController). Metin girişleri UIAlertController.
extension BrowserViewController {
    // MARK: Yardımcılar

    private func sheet(_ title: String?, _ message: String? = nil) -> MenuPanelController {
        MenuPanelController(title: title, subtitle: message)
    }

    /// Satır ekler. "Başlık: değer" biçimi sağda değer olarak, "✓ " / "● " öneki seçili işaret olarak gösterilir.
    private func add(_ sheet: MenuPanelController, _ title: String, style: UIAlertAction.Style = .default,
                     _ handler: @escaping () -> Void) {
        var text = title
        var checked = false
        for prefix in ["✓ ", "● "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            checked = true
        }
        var value: String?
        if let r = text.range(of: ": "), text.distance(from: text.startIndex, to: r.lowerBound) < 34 {
            value = String(text[r.upperBound...])
            text = String(text[..<r.lowerBound])
        }
        sheet.addItem(text, value: value, symbol: MenuSymbols.symbol(for: text), destructive: style == .destructive,
                      checked: checked, action: handler)
    }

    private func finish(_ sheet: MenuPanelController, cancel: String = "Kapat") {
        present(sheet, animated: false)
    }

    func prompt(_ title: String, message: String? = nil, text: String? = nil, placeholder: String? = nil,
                keyboard: UIKeyboardType = .default, action: String = "Tamam", done: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = text
            tf.placeholder = placeholder
            tf.keyboardType = keyboard
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: action, style: .default) { [weak alert] _ in
            done(alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? "")
        })
        alert.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(alert, animated: true)
    }

    func pick(_ title: String, _ options: [String], selected: Int? = nil, _ done: @escaping (Int) -> Void) {
        let s = sheet(title)
        for (i, o) in options.enumerated() {
            add(s, (i == selected ? "✓ " : "") + o) { done(i) }
        }
        finish(s, cancel: "Vazgeç")
    }

    // MARK: Ana menü

    func showMenu() {
        guard presentedViewController == nil, let t = activeTab else { return }
        let e = t.engine!
        let isWeb = !t.isHome && t.url != nil
        let link = linkAtCursor()
        let videos = isWeb ? videoCandidates() : []
        var subtitle = isWeb ? t.url.map { ($0.host ?? "") + $0.path } : (store.privateMode ? "Gizli gezinme" : "Ana sayfa")
        let blocked = AdBlocker.blockedCount - t.blockedAtStart
        if isWeb, store.adBlockEnabled, blocked > 0 { subtitle = (subtitle ?? "") + " · \(blocked) reklam engellendi" }

        let s = MenuPanelController(title: t.title, subtitle: subtitle)
        if e.canGoBack { s.addQuickAction("Geri", symbol: "chevron.backward") { e.goBack() } }
        if e.canGoForward { s.addQuickAction("İleri", symbol: "chevron.forward") { e.goForward() } }
        s.addQuickAction("Yenile", symbol: "arrow.clockwise") { self.reloadCurrent() }
        if !t.isHome { s.addQuickAction("Ana sayfa", symbol: "house.fill") { self.goHome() } }
        s.addQuickAction("Sekmeler", symbol: "square.on.square") { self.showTabSwitcher() }

        s.addItem("Adres yaz veya ara", subtitle: "\(store.searchEngine.name) ile aranır", symbol: "magnifyingglass") { self.askAddress() }
        if let link {
            s.addItem("Bağlantıyı yeni sekmede aç", subtitle: link.host, symbol: "arrow.up.forward.square") {
                if self.addTab(url: link, activate: false) { self.showToast("Yeni sekmede açıldı") }
            }
        }

        if isWeb {
            s.addHeader("Bu sayfa")
            if videos.count == 1, let v = videos.first {
                s.addItem("Videoyu tam ekran oynat", subtitle: v.title, symbol: "play.rectangle.fill") {
                    self.playVideo(src: v.src, time: v.time, referer: v.referer)
                }
            } else if videos.count > 1 {
                s.addItem("Videoyu tam ekran oynat", value: "\(videos.count) video", symbol: "play.rectangle.fill") {
                    self.pick("Hangi video?", videos.map(\.title)) { i in
                        let v = videos[i]
                        self.playVideo(src: v.src, time: v.time, referer: v.referer)
                    }
                }
            }
            let sources = pageSources()
            if !sources.isEmpty {
                s.addItem("Kaynaklar / oynatıcılar", value: "\(sources.count)", symbol: "list.bullet.rectangle") {
                    self.pick("Kaynak seç", sources.map { ($0.active ? "● " : "") + $0.text }) { i in
                        self.selectSource(i, title: sources[i].text)
                    }
                }
            }
            if let next = nextEpisode() {
                s.addItem("Sonraki bölüm", subtitle: next.guessed ? "Adresten tahmin edildi" : nil, symbol: "forward.end.fill") {
                    self.openNextEpisode(next.url)
                }
            }
            s.addItem(t.isReader ? "Okuma modundan çık" : "Okuma modu", symbol: "doc.plaintext") { self.toggleReader() }
            s.addItem("Sayfada bul", value: findCount > 0 ? "\(findIndex + 1)/\(findCount)" : nil, symbol: "text.magnifyingglass") {
                self.askFind()
            }
            if findCount > 0 {
                s.addItem("Sonraki eşleşme", symbol: "arrow.down.circle") { self.stepFind(1) }
                s.addItem("Aramayı temizle", symbol: "xmark.circle") { self.resetFind() }
            }
            s.addItem("Yakınlaştırma", value: "%\(store.zoom(for: t.url?.host))", symbol: "plus.magnifyingglass") { self.askZoom() }
            if let url = t.url?.absoluteString {
                if store.isBookmarked(url) {
                    s.addItem("Sık kullanılanlardan çıkar", symbol: "star.slash", destructive: true) {
                        self.store.bookmarks.removeAll { $0.url == url }
                        self.refreshHomeTabs()
                        self.showToast("Sık kullanılanlardan çıkarıldı")
                    }
                } else {
                    s.addItem("Sık kullanılanlara ekle", symbol: "star") {
                        let title = t.title.isEmpty ? (t.url?.host ?? url) : t.title
                        self.store.bookmarks.append(Bookmark(title: title, url: url))
                        self.refreshHomeTabs()
                        self.showToast("Sık kullanılanlara eklendi")
                    }
                }
            }
        }

        s.addHeader("Kitaplık")
        s.addItem("Sık kullanılanlar", value: "\(store.bookmarks.count)", symbol: "star.fill") { self.showBookmarks() }
        s.addItem("Geçmiş", symbol: "clock.arrow.circlepath") { self.showHistory() }

        s.addHeader("Pano")
        s.addItem(store.privateMode ? "Gizli gezinmeyi kapat" : "Gizli gezinme", symbol: "eye.slash") { self.togglePrivate() }
        s.addItem("Telefondan kontrol", subtitle: "QR kodla telefonu kumanda yap", symbol: "iphone") { self.showRemoteInfo() }
        s.addItem("Ayarlar", symbol: "gearshape.fill") { self.showSettings() }
        s.addItem("Kumanda kullanımı", symbol: "appletvremote.gen4") { self.showHelp() }
        present(s, animated: false)
    }

    func askAddress() {
        guard presentedViewController == nil else { return }
        let current = activeTab.flatMap { $0.isHome ? nil : $0.url?.absoluteString }
        prompt("Adres veya arama", message: "\(store.searchEngine.name) ile aranır", text: current,
               keyboard: .URL, action: "Git") { self.open($0) }
    }

    private func askFind() {
        prompt("Sayfada bul", text: findQuery, action: "Bul") { self.startFind($0) }
    }

    private func askZoom() {
        let levels = [75, 90, 100, 110, 125, 150, 175, 200, 250]
        let currentZoom = store.zoom(for: activeTab?.url?.host)
        pick("Yakınlaştırma (bu site için)", levels.map { "%\($0)" }, selected: levels.firstIndex(of: currentZoom)) {
            self.setZoom(levels[$0])
        }
    }

    // MARK: Sekmeler

    func showTabs() {
        showTabSwitcher()
    }

    // MARK: Sık kullanılanlar

    func showBookmarks() {
        let list = store.bookmarks
        let s = sheet("Sık Kullanılanlar", list.isEmpty ? "Henüz yok" : nil)
        for b in list {
            add(s, b.title) { self.open(b.url) }
        }
        if !list.isEmpty {
            add(s, "Düzenle (ad, sıra, sil)…") { self.editBookmarks() }
        }
        finish(s)
    }

    private func editBookmarks() {
        pick("Düzenlenecek site", store.bookmarks.map(\.title)) { self.bookmarkActions($0) }
    }

    private func bookmarkActions(_ i: Int) {
        let list = store.bookmarks
        guard list.indices.contains(i) else { return }
        let b = list[i]
        let s = sheet(b.title, b.url)
        add(s, "Yeniden adlandır") {
            self.prompt("Yeni ad", text: b.title) { name in
                self.store.renameBookmark(at: i, to: name)
                self.bookmarksChanged()
            }
        }
        add(s, "Adresi düzenle") {
            self.prompt("Adres", text: b.url, keyboard: .URL) { text in
                guard let url = self.store.resolve(text) else { return }
                var all = self.store.bookmarks
                guard all.indices.contains(i) else { return }
                all[i].url = url.absoluteString
                self.store.bookmarks = all
                self.bookmarksChanged()
            }
        }
        if i > 0 {
            add(s, "En başa taşı") { self.store.moveBookmark(from: i, to: 0); self.bookmarksChanged() }
            add(s, "Yukarı taşı") { self.store.moveBookmark(from: i, to: i - 1); self.bookmarksChanged() }
        }
        if i < list.count - 1 {
            add(s, "Aşağı taşı") { self.store.moveBookmark(from: i, to: i + 1); self.bookmarksChanged() }
            add(s, "En sona taşı") { self.store.moveBookmark(from: i, to: list.count - 1); self.bookmarksChanged() }
        }
        add(s, "Sil", style: .destructive) {
            self.store.bookmarks.remove(at: i)
            self.bookmarksChanged()
            self.showToast("\(b.title) silindi")
        }
        finish(s, cancel: "Geri")
    }

    private func bookmarksChanged() {
        refreshHomeTabs()
        showToast("Sık kullanılanlar güncellendi")
    }

    // MARK: Geçmiş

    func showHistory() {
        let list = Array(store.history.prefix(30))
        let s = sheet("Geçmiş", list.isEmpty ? (store.privateMode ? "Gizli gezinmede geçmiş kaydedilmez" : "Henüz yok") : nil)
        if !list.isEmpty {
            add(s, "🔍 Geçmişte ara…") {
                self.prompt("Geçmişte ara", placeholder: "Site adı veya adresi", action: "Ara") { q in
                    self.showHistoryResults(q)
                }
            }
        }
        for h in list {
            add(s, h.title) { self.open(h.url) }
        }
        if !list.isEmpty {
            add(s, "Geçmişi temizle", style: .destructive) {
                self.store.history = []
                self.showToast("Geçmiş temizlendi")
            }
        }
        finish(s)
    }

    private func showHistoryResults(_ query: String) {
        guard !query.isEmpty else { return }
        let results = Array(store.searchHistory(query).prefix(40))
        let s = sheet("“\(query)”", results.isEmpty ? "Sonuç yok" : "\(results.count) sonuç")
        for h in results {
            add(s, h.title) { self.open(h.url) }
        }
        finish(s)
    }

    // MARK: Ayarlar

    func showSettings() {
        let s = sheet("Ayarlar")
        add(s, "Site görünümü: \(store.desktopMode ? "Masaüstü" : "Mobil")") {
            self.pick("Site görünümü", ["Masaüstü", "Mobil"], selected: self.store.desktopMode ? 0 : 1) { i in
                let desktop = i == 0
                guard desktop != self.store.desktopMode else { return }
                self.store.desktopMode = desktop
                self.recreateEngines() // kullanıcı ajanı yalnızca yeni web görünümünde geçerli
                self.showToast(desktop ? "Masaüstü siteler" : "Mobil siteler")
            }
        }
        add(s, "Reklam engelleme: \(store.adBlockEnabled ? "Açık" : "Kapalı")") {
            self.store.adBlockEnabled.toggle()
            self.reloadCurrent()
            self.showToast(self.store.adBlockEnabled
                ? "Reklam engelleme açık (\(AdBlocker.blockedCount) istek engellendi)"
                : "Reklam engelleme kapalı")
        }
        let speeds: [(String, Double)] = [("Yavaş", 0.6), ("Normal", 1.0), ("Hızlı", 1.5), ("Çok hızlı", 2.2)]
        let speedIndex = speeds.firstIndex { $0.1 == store.cursorSpeed }
        add(s, "İmleç hızı: \(speedIndex.map { speeds[$0].0 } ?? "Normal")") {
            self.pick("İmleç hızı", speeds.map(\.0), selected: speedIndex) { self.store.cursorSpeed = speeds[$0].1 }
        }
        let zooms = [75, 90, 100, 110, 125, 150, 175, 200]
        add(s, "Varsayılan yakınlaştırma: %\(store.defaultZoom)") {
            self.pick("Varsayılan yakınlaştırma (tüm siteler)", zooms.map { "%\($0)" },
                      selected: zooms.firstIndex(of: self.store.defaultZoom)) { i in
                self.store.defaultZoom = zooms[i]
                if let t = self.activeTab, !t.isHome { t.engine.js(Pages.applyZoom(self.store.zoom(for: t.url?.host))) }
            }
        }
        let scales = [100, 125, 150, 175, 200]
        add(s, "Yazı boyutu: %\(store.textScale)") {
            self.pick("Yazı boyutu", scales.map { "%\($0)" }, selected: scales.firstIndex(of: self.store.textScale)) { i in
                self.store.textScale = scales[i]
                self.engine?.js("document.documentElement.style.webkitTextSizeAdjust='\(scales[i])%'")
            }
        }
        add(s, "Arama motoru: \(store.searchEngine.name)") {
            let engines = SearchEngine.allCases
            self.pick("Arama motoru", engines.map(\.name), selected: engines.firstIndex(of: self.store.searchEngine)) { i in
                self.store.searchEngine = engines[i]
                self.refreshHomeTabs()
            }
        }
        add(s, "OpenSubtitles: \(OpenSubtitles.isConfigured ? (store.openSubtitlesUser.map { "anahtar + \($0)" } ?? "anahtar girildi") : "ayarlanmadı")") {
            self.openSubtitlesSettings()
        }
        add(s, "Telefondan kontrol: \(RemoteServer.shared.isRunning ? "Açık" : "Kapalı")") {
            if RemoteServer.shared.isRunning {
                RemoteServer.shared.stop()
                self.store.remoteEnabled = false
                self.showToast("Telefondan kontrol kapatıldı")
            } else {
                self.showRemoteInfo()
            }
        }
        if !store.watchProgress.isEmpty {
            add(s, "“İzlemeye devam” listesini temizle", style: .destructive) {
                self.store.watchProgress = []
                self.refreshHomeTabs()
                self.showToast("İzleme geçmişi temizlendi")
            }
        }
        add(s, "Çerezleri ve önbelleği temizle", style: .destructive) {
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            URLCache.shared.removeAllCachedResponses()
            self.showToast("Çerezler ve önbellek temizlendi")
        }
        finish(s)
    }

    private func openSubtitlesSettings() {
        let s = sheet("OpenSubtitles", "Altyazı aramak için ücretsiz API anahtarı gerekir: opensubtitles.com/consumers\nKullanıcı girişi isteğe bağlı (indirme kotasını artırır).")
        add(s, store.openSubtitlesKey == nil ? "API anahtarı gir" : "API anahtarını değiştir") {
            self.prompt("OpenSubtitles API anahtarı", text: self.store.openSubtitlesKey) { key in
                self.store.openSubtitlesKey = key
                self.showToast(key.isEmpty ? "Anahtar silindi" : "Anahtar kaydedildi")
            }
        }
        add(s, store.openSubtitlesUser.map { "Giriş yapıldı: \($0) — yeniden giriş" } ?? "Kullanıcı girişi (isteğe bağlı)") {
            self.prompt("OpenSubtitles kullanıcı adı", text: self.store.openSubtitlesUser) { user in
                guard !user.isEmpty else { return }
                let alert = UIAlertController(title: "Şifre", message: user, preferredStyle: .alert)
                alert.addTextField { $0.isSecureTextEntry = true }
                alert.addAction(UIAlertAction(title: "Giriş yap", style: .default) { [weak alert] _ in
                    OpenSubtitles.login(username: user, password: alert?.textFields?.first?.text ?? "") { error in
                        self.showToast(error.map { "Giriş başarısız: \($0)" } ?? "OpenSubtitles girişi yapıldı")
                    }
                })
                alert.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
                self.present(alert, animated: true)
            }
        }
        if store.openSubtitlesToken != nil {
            add(s, "Çıkış yap", style: .destructive) {
                self.store.openSubtitlesToken = nil
                self.store.openSubtitlesUser = nil
                self.showToast("OpenSubtitles çıkışı yapıldı")
            }
        }
        finish(s)
    }

    // MARK: Yardım

    func showHelp() {
        let text = """
        Dokunmatik yüzeyde kaydır: imleç (bağlantı üstünde büyür ve yavaşlar)
        İmleci kenara it: sayfa kayar
        Tıkla: tıkla · metin alanında klavye · oynatıcıya tıklayınca video tam ekran açılır
        Seçim tuşuna basılı tut: menü
        Oynat/Duraklat: imleç ↔ kaydırma modu
        Oynat/Duraklat'a çift bas: adres çubuğu
        Oynat/Duraklat'a basılı tut: sekmeler
        Yön tuşları: sayfayı kaydır (sayfada bulda ◀ ▶ eşleşmeler)
        Menü / Geri: önceki sayfa
        Videoda (aşağı kaydır): Altyazı · Hız · Sar · Sonraki bölüm
        Telefondan kontrol: Menü → Telefondan kontrol (QR)
        """
        let alert = UIAlertController(title: "Kumanda Kullanımı", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
}
