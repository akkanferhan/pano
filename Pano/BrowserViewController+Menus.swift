import UIKit

/// Kumandayla gezilen menüler (tvOS'ta UIAlertController odak motoruyla çalışır).
extension BrowserViewController {
    // MARK: Yardımcılar

    private func sheet(_ title: String?, _ message: String? = nil) -> UIAlertController {
        UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
    }

    private func add(_ sheet: UIAlertController, _ title: String, style: UIAlertAction.Style = .default,
                     _ handler: @escaping () -> Void) {
        sheet.addAction(UIAlertAction(title: title, style: style) { _ in handler() })
    }

    private func finish(_ sheet: UIAlertController, cancel: String = "Kapat") {
        sheet.addAction(UIAlertAction(title: cancel, style: .cancel))
        present(sheet, animated: true)
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
        let videos = isWeb ? pageVideos() : []
        var message = isWeb ? t.url?.absoluteString : nil
        let blocked = AdBlocker.blockedCount - t.blockedAtStart
        if isWeb, store.adBlockEnabled, blocked > 0 {
            message = (message ?? "") + "\n\(blocked) reklam/izleyici isteği engellendi"
        }

        let s = sheet(t.title, message)
        add(s, "Adres yaz / Ara") { self.askAddress() }
        add(s, "Sekmeler (\(tabs.count))") { self.showTabs() }
        if let link {
            add(s, "Bağlantıyı yeni sekmede aç") {
                if self.addTab(url: link, activate: false) { self.showToast("Yeni sekmede açıldı") }
            }
        }
        if e.canGoBack { add(s, "Geri") { e.goBack() } }
        if e.canGoForward { add(s, "İleri") { e.goForward() } }
        add(s, "Yenile") { self.reloadCurrent() }
        if !t.isHome { add(s, "Ana Sayfa") { self.goHome() } }
        if let video = videos.first {
            add(s, "Videoyu tam ekran oynat") { self.playVideo(src: video.src, time: video.time) }
        }
        if isWeb {
            add(s, t.isReader ? "Okuma modundan çık" : "Okuma modu") { self.toggleReader() }
            add(s, "Sayfada bul…") { self.askFind() }
            if findCount > 0 {
                add(s, "Sonraki eşleşme (\(findIndex + 1)/\(findCount))") { self.stepFind(1) }
                add(s, "Aramayı temizle") { self.resetFind() }
            }
            let zoom = store.zoom(for: t.url?.host)
            add(s, "Yakınlaştırma: %\(zoom)") { self.askZoom() }
            if let url = t.url?.absoluteString {
                if store.isBookmarked(url) {
                    add(s, "Sık kullanılanlardan çıkar", style: .destructive) {
                        self.store.bookmarks.removeAll { $0.url == url }
                        self.refreshHomeTabs()
                        self.showToast("Çıkarıldı")
                    }
                } else {
                    add(s, "Sık kullanılanlara ekle") {
                        let title = t.title.isEmpty ? (t.url?.host ?? url) : t.title
                        self.store.bookmarks.append(Bookmark(title: title, url: url))
                        self.refreshHomeTabs()
                        self.showToast("Sık kullanılanlara eklendi")
                    }
                }
            }
        }
        add(s, "Sık Kullanılanlar") { self.showBookmarks() }
        add(s, "Geçmiş") { self.showHistory() }
        add(s, store.privateMode ? "Gizli gezinmeyi kapat" : "Gizli gezinme") { self.togglePrivate() }
        add(s, "Ayarlar") { self.showSettings() }
        add(s, "Kumanda Kullanımı") { self.showHelp() }
        finish(s)
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
        guard presentedViewController == nil else { return }
        let s = sheet("Sekmeler", "Oynat/Duraklat'a basılı tutarak da açabilirsin")
        for (i, t) in tabs.enumerated() {
            let host = t.isHome ? "Ana Sayfa" : ((t.url ?? t.pendingURL)?.host ?? "")
            let title = t.title == host ? t.title : "\(t.title) — \(host)"
            add(s, (i == current ? "● " : "") + title) { if i != self.current { self.activate(i) } }
        }
        add(s, "+ Yeni sekme") { self.addTab(url: nil, activate: true) }
        add(s, "Bu sekmeyi kapat", style: .destructive) { self.closeTab(self.current) }
        if tabs.count > 1 {
            add(s, "Sekme kapat…", style: .destructive) {
                self.pick("Kapatılacak sekme", self.tabs.map(\.title)) { self.closeTab($0) }
            }
            add(s, "Diğer sekmeleri kapat", style: .destructive) {
                let keep = self.current
                for i in stride(from: self.tabs.count - 1, through: 0, by: -1) where i != keep { self.closeTab(i) }
            }
        }
        finish(s)
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
        add(s, "Çerezleri ve önbelleği temizle", style: .destructive) {
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            URLCache.shared.removeAllCachedResponses()
            self.showToast("Çerezler ve önbellek temizlendi")
        }
        finish(s)
    }

    // MARK: Yardım

    func showHelp() {
        let text = """
        Dokunmatik yüzeyde kaydır: imleç (bağlantı üstünde büyür ve yavaşlar)
        İmleci kenara it: sayfa kayar
        Tıkla: tıkla · metin alanında klavye · videoda tam ekran oynatıcı
        Seçim tuşuna basılı tut: menü
        Oynat/Duraklat: imleç ↔ kaydırma modu
        Oynat/Duraklat'a çift bas: adres çubuğu
        Oynat/Duraklat'a basılı tut: sekmeler
        Yön tuşları: sayfayı kaydır (sayfada bulda ◀ ▶ eşleşmeler)
        Menü / Geri: önceki sayfa
        """
        let alert = UIAlertController(title: "Kumanda Kullanımı", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
}
