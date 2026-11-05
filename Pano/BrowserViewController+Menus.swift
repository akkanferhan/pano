import UIKit

/// Remote-driven menus: a glass side panel (MenuPanelController). Text input uses UIAlertController.
extension BrowserViewController {
    // MARK: Helpers

    func prompt(_ title: String, message: String? = nil, text: String? = nil, placeholder: String? = nil,
                keyboard: UIKeyboardType = .default, action: String? = nil, done: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = text
            tf.placeholder = placeholder
            tf.keyboardType = keyboard
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: action ?? L("OK"), style: .default) { [weak alert] _ in
            done(alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? "")
        })
        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    /// Simple choice list (the selected option gets a check mark).
    func pick(_ title: String, _ options: [String], selected: Int? = nil, symbol: String? = nil,
              _ done: @escaping (Int) -> Void) {
        let s = MenuPanelController(title: title)
        for (i, o) in options.enumerated() {
            s.addItem(o, symbol: symbol, checked: i == selected) { done(i) }
        }
        present(s, animated: true)
    }

    // MARK: Main menu

    func showMenu() {
        guard presentedViewController == nil, let t = activeTab else { return }
        let e = t.engine!
        let isWeb = !t.isHome && t.url != nil
        let link = linkAtCursor()
        let videos = isWeb ? videoCandidates() : []
        var subtitle = isWeb ? t.url.map { ($0.host ?? "") + $0.path } : (store.privateMode ? L("Private browsing") : nil)
        let blocked = AdBlocker.blockedCount - t.blockedAtStart
        if isWeb, store.adBlockEnabled, blocked > 0 { subtitle = (subtitle ?? "") + " · " + L("%d ads blocked", blocked) }

        let s = MenuPanelController(title: t.title, subtitle: subtitle)
        if e.canGoBack { s.addQuickAction(L("Back"), symbol: "chevron.backward") { e.goBack() } }
        if e.canGoForward { s.addQuickAction(L("Forward"), symbol: "chevron.forward") { e.goForward() } }
        s.addQuickAction(L("Reload"), symbol: "arrow.clockwise") { self.reloadCurrent() }
        if !t.isHome { s.addQuickAction(L("Home"), symbol: "house.fill") { self.goHome() } }
        s.addQuickAction(L("Tabs"), symbol: "square.on.square") { self.showTabSwitcher() }

        s.addItem(L("Enter address or search"), subtitle: L("Searches with %@", store.searchEngine.name), symbol: "magnifyingglass") {
            self.askAddress()
        }
        if let link {
            s.addItem(L("Open link in new tab"), subtitle: link.host, symbol: "arrow.up.forward.square") {
                if self.addTab(url: link, activate: false) { self.showToast(L("Opened in a new tab"), symbol: "plus.square.on.square") }
            }
        }

        if isWeb {
            s.addHeader(L("This page"))
            if videos.count == 1, let v = videos.first {
                s.addItem(L("Play video full screen"), subtitle: v.title, symbol: "play.rectangle.fill") {
                    self.playVideo(src: v.src, time: v.time, referer: v.referer)
                }
            } else if videos.count > 1 {
                s.addItem(L("Play video full screen"), value: L("%d videos", videos.count), symbol: "play.rectangle.fill") {
                    self.pick(L("Which video?"), videos.map(\.title), symbol: "play.rectangle") { i in
                        let v = videos[i]
                        self.playVideo(src: v.src, time: v.time, referer: v.referer)
                    }
                }
            }
            let sources = pageSources()
            if !sources.isEmpty {
                s.addItem(L("Sources / players"), value: "\(sources.count)", symbol: "list.bullet.rectangle") {
                    self.pick(L("Choose a source"), sources.map(\.text), selected: sources.firstIndex { $0.active },
                              symbol: "play.rectangle") { i in
                        self.selectSource(i, title: sources[i].text)
                    }
                }
            }
            if let next = nextEpisode() {
                s.addItem(L("Next episode"), subtitle: next.guessed ? L("Guessed from the address") : nil, symbol: "forward.end.fill") {
                    self.openNextEpisode(next.url)
                }
            }
            s.addItem(t.isReader ? L("Exit reader mode") : L("Reader mode"), symbol: "doc.plaintext") { self.toggleReader() }
            s.addItem(L("Find on page"), value: findCount > 0 ? "\(findIndex + 1)/\(findCount)" : nil, symbol: "text.magnifyingglass") {
                self.askFind()
            }
            if findCount > 0 {
                s.addItem(L("Next match"), symbol: "arrow.down.circle") { self.stepFind(1) }
                s.addItem(L("Clear search"), symbol: "xmark.circle") { self.resetFind() }
            }
            s.addItem(L("Zoom"), value: "\(store.zoom(for: t.url?.host))%", symbol: "plus.magnifyingglass") { self.askZoom() }
            if let url = t.url?.absoluteString {
                if store.isBookmarked(url) {
                    s.addItem(L("Remove from favorites"), symbol: "star.slash", destructive: true) {
                        self.store.bookmarks.removeAll { $0.url == url }
                        self.refreshHomeTabs()
                        self.showToast(L("Removed from favorites"), symbol: "star.slash")
                    }
                } else {
                    s.addItem(L("Add to favorites"), symbol: "star") {
                        let title = t.title.isEmpty ? (t.url?.host ?? url) : t.title
                        self.store.bookmarks.append(Bookmark(title: title, url: url))
                        self.refreshHomeTabs()
                        self.showToast(L("Added to favorites"), symbol: "star.fill")
                    }
                }
            }
        }

        s.addHeader(L("Library"))
        s.addItem(L("Favorites"), value: "\(store.bookmarks.count)", symbol: "star.fill") { self.showBookmarks() }
        s.addItem(L("History"), symbol: "clock.arrow.circlepath") { self.showHistory() }

        s.addHeader("Pano")
        s.addItem(store.privateMode ? L("Turn off private browsing") : L("Private browsing"), symbol: "eye.slash") { self.togglePrivate() }
        s.addItem(L("Phone control"), subtitle: L("Use your phone as a remote via QR code"), symbol: "iphone") { self.showRemoteInfo() }
        s.addItem(L("Settings"), symbol: "gearshape.fill") { self.showSettings() }
        s.addItem(L("Remote control guide"), symbol: "appletvremote.gen4") { self.showHelp() }
        present(s, animated: true)
    }

    func askAddress() {
        guard presentedViewController == nil else { return }
        let current = activeTab.flatMap { $0.isHome ? nil : $0.url?.absoluteString }
        present(AddressSearch.make(initialText: current) { [weak self] text in self?.open(text) }, animated: true)
    }

    private func askFind() {
        prompt(L("Find on page"), text: findQuery, action: L("Find")) { self.startFind($0) }
    }

    private func askZoom() {
        let levels = [75, 90, 100, 110, 125, 150, 175, 200, 250]
        let currentZoom = store.zoom(for: activeTab?.url?.host)
        pick(L("Zoom (this site)"), levels.map { "\($0)%" }, selected: levels.firstIndex(of: currentZoom), symbol: "plus.magnifyingglass") {
            self.setZoom(levels[$0])
        }
    }

    // MARK: Tabs

    func showTabs() {
        showTabSwitcher()
    }

    // MARK: Favorites

    func showBookmarks() {
        let list = store.bookmarks
        let s = MenuPanelController(title: L("Favorites"), subtitle: list.isEmpty ? L("None yet") : nil)
        for b in list {
            s.addItem(b.title, subtitle: URL(string: b.url)?.host, symbol: "star.fill") { self.open(b.url) }
        }
        if !list.isEmpty {
            s.addItem(L("Edit (name, order, delete)…"), symbol: "pencil") { self.editBookmarks() }
        }
        present(s, animated: true)
    }

    private func editBookmarks() {
        pick(L("Site to edit"), store.bookmarks.map(\.title), symbol: "star") { self.bookmarkActions($0) }
    }

    private func bookmarkActions(_ i: Int) {
        let list = store.bookmarks
        guard list.indices.contains(i) else { return }
        let b = list[i]
        let s = MenuPanelController(title: b.title, subtitle: b.url)
        s.addItem(L("Rename"), symbol: "pencil") {
            self.prompt(L("New name"), text: b.title) { name in
                self.store.renameBookmark(at: i, to: name)
                self.bookmarksChanged()
            }
        }
        s.addItem(L("Edit address"), symbol: "link") {
            self.prompt(L("Address"), text: b.url, keyboard: .URL) { text in
                guard let url = self.store.resolve(text) else { return }
                var all = self.store.bookmarks
                guard all.indices.contains(i) else { return }
                all[i].url = url.absoluteString
                self.store.bookmarks = all
                self.bookmarksChanged()
            }
        }
        if i > 0 {
            s.addItem(L("Move to top"), symbol: "arrow.up.to.line") { self.store.moveBookmark(from: i, to: 0); self.bookmarksChanged() }
            s.addItem(L("Move up"), symbol: "arrow.up") { self.store.moveBookmark(from: i, to: i - 1); self.bookmarksChanged() }
        }
        if i < list.count - 1 {
            s.addItem(L("Move down"), symbol: "arrow.down") { self.store.moveBookmark(from: i, to: i + 1); self.bookmarksChanged() }
            s.addItem(L("Move to bottom"), symbol: "arrow.down.to.line") {
                self.store.moveBookmark(from: i, to: list.count - 1)
                self.bookmarksChanged()
            }
        }
        s.addItem(L("Delete"), symbol: "trash", destructive: true) {
            self.store.bookmarks.remove(at: i)
            self.bookmarksChanged()
            self.showToast(L("%@ deleted", b.title), symbol: "trash")
        }
        present(s, animated: true)
    }

    private func bookmarksChanged() {
        refreshHomeTabs()
        showToast(L("Favorites updated"), symbol: "star.fill")
    }

    // MARK: History

    func showHistory() {
        let list = Array(store.history.prefix(30))
        let empty = store.privateMode ? L("History isn't saved in private browsing") : L("None yet")
        let s = MenuPanelController(title: L("History"), subtitle: list.isEmpty ? empty : nil)
        if !list.isEmpty {
            s.addItem(L("Search history…"), symbol: "magnifyingglass") {
                self.prompt(L("Search history"), placeholder: L("Site name or address"), action: L("Search")) { q in
                    self.showHistoryResults(q)
                }
            }
        }
        for h in list {
            s.addItem(h.title, subtitle: URL(string: h.url)?.host, symbol: "clock") { self.open(h.url) }
        }
        if !list.isEmpty {
            s.addItem(L("Clear history"), symbol: "trash", destructive: true) {
                self.store.history = []
                self.showToast(L("History cleared"), symbol: "trash")
            }
        }
        present(s, animated: true)
    }

    private func showHistoryResults(_ query: String) {
        guard !query.isEmpty else { return }
        let results = Array(store.searchHistory(query).prefix(40))
        let s = MenuPanelController(title: "“\(query)”", subtitle: results.isEmpty ? L("No results") : L("%d results", results.count))
        for h in results {
            s.addItem(h.title, subtitle: URL(string: h.url)?.host, symbol: "clock") { self.open(h.url) }
        }
        present(s, animated: true)
    }

    // MARK: Settings

    func showSettings() {
        let s = MenuPanelController(title: L("Settings"))
        let languageName = AppLanguage.override.map(AppLanguage.name(for:)) ?? L("System")
        s.addItem(L("Language"), value: languageName, symbol: "globe") { self.chooseLanguage() }
        s.addItem(L("Site view"), value: store.desktopMode ? L("Desktop") : L("Mobile"), symbol: "desktopcomputer") {
            self.pick(L("Site view"), [L("Desktop"), L("Mobile")], selected: self.store.desktopMode ? 0 : 1) { i in
                let desktop = i == 0
                guard desktop != self.store.desktopMode else { return }
                self.store.desktopMode = desktop
                self.recreateEngines() // the user agent only applies to a new web view
                self.showToast(desktop ? L("Desktop sites") : L("Mobile sites"), symbol: "desktopcomputer")
            }
        }
        s.addItem(L("Ad blocking"), value: store.adBlockEnabled ? L("On") : L("Off"), symbol: "shield.lefthalf.filled") {
            self.store.adBlockEnabled.toggle()
            self.reloadCurrent()
            self.showToast(self.store.adBlockEnabled
                ? L("Ad blocking on (%d requests blocked)", AdBlocker.blockedCount)
                : L("Ad blocking off"), symbol: "shield.lefthalf.filled")
        }
        let speeds: [(String, Double)] = [(L("Slow"), 0.6), (L("Normal"), 1.0), (L("Fast"), 1.5), (L("Very fast"), 2.2)]
        let speedIndex = speeds.firstIndex { $0.1 == store.cursorSpeed }
        s.addItem(L("Cursor speed"), value: speedIndex.map { speeds[$0].0 } ?? L("Normal"), symbol: "cursorarrow.motionlines") {
            self.pick(L("Cursor speed"), speeds.map(\.0), selected: speedIndex) { self.store.cursorSpeed = speeds[$0].1 }
        }
        let zooms = [75, 90, 100, 110, 125, 150, 175, 200]
        s.addItem(L("Default zoom"), value: "\(store.defaultZoom)%", symbol: "plus.magnifyingglass") {
            self.pick(L("Default zoom (all sites)"), zooms.map { "\($0)%" }, selected: zooms.firstIndex(of: self.store.defaultZoom)) { i in
                self.store.defaultZoom = zooms[i]
                if let t = self.activeTab, !t.isHome { t.engine.js(Pages.applyZoom(self.store.zoom(for: t.url?.host))) }
            }
        }
        let scales = [100, 125, 150, 175, 200]
        s.addItem(L("Text size"), value: "\(store.textScale)%", symbol: "textformat.size") {
            self.pick(L("Text size"), scales.map { "\($0)%" }, selected: scales.firstIndex(of: self.store.textScale)) { i in
                self.store.textScale = scales[i]
                self.engine?.js("document.documentElement.style.webkitTextSizeAdjust='\(scales[i])%'")
            }
        }
        s.addItem(L("Search engine"), value: store.searchEngine.name, symbol: "magnifyingglass.circle") {
            let engines = SearchEngine.allCases
            self.pick(L("Search engine"), engines.map(\.name), selected: engines.firstIndex(of: self.store.searchEngine)) { i in
                self.store.searchEngine = engines[i]
                self.refreshHomeTabs()
            }
        }
        let osValue = OpenSubtitles.isConfigured ? (store.openSubtitlesUser ?? L("Key entered")) : L("Not set up")
        s.addItem("OpenSubtitles", value: osValue, symbol: "captions.bubble") { self.openSubtitlesSettings() }
        s.addItem(L("Phone control"), value: RemoteServer.shared.isRunning ? L("On") : L("Off"), symbol: "iphone") {
            if RemoteServer.shared.isRunning {
                RemoteServer.shared.stop()
                self.store.remoteEnabled = false
                self.showToast(L("Phone control turned off"), symbol: "iphone.slash")
            } else {
                self.showRemoteInfo()
            }
        }
        if !store.watchProgress.isEmpty {
            s.addItem(L("Clear “Continue watching”"), symbol: "trash", destructive: true) {
                self.store.watchProgress = []
                self.refreshHomeTabs()
                self.showToast(L("Watch history cleared"), symbol: "trash")
            }
        }
        s.addItem(L("Clear cookies and cache"), symbol: "trash", destructive: true) {
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            URLCache.shared.removeAllCachedResponses()
            self.showToast(L("Cookies and cache cleared"), symbol: "trash")
        }
        present(s, animated: true)
    }

    /// Language: system language by default; an override applies after restarting the app.
    private func chooseLanguage() {
        let s = MenuPanelController(title: L("Language"), subtitle: L("Takes effect after restarting the app."))
        s.addItem(L("System language"), symbol: "gearshape", checked: AppLanguage.override == nil) {
            AppLanguage.override = nil
            self.showToast(L("Restart the app to apply the language"), symbol: "globe")
        }
        for lang in AppLanguage.supported {
            s.addItem(lang.name, checked: AppLanguage.override == lang.code) {
                AppLanguage.override = lang.code
                self.showToast(L("Restart the app to apply the language"), symbol: "globe")
            }
        }
        present(s, animated: true)
    }

    private func openSubtitlesSettings() {
        let s = MenuPanelController(title: "OpenSubtitles",
                                    subtitle: L("Searching subtitles needs a free API key: opensubtitles.com/consumers. Signing in is optional (raises the download limit)."))
        s.addItem(store.openSubtitlesKey == nil ? L("Enter API key") : L("Change API key"), symbol: "key.fill") {
            self.prompt(L("OpenSubtitles API key"), text: self.store.openSubtitlesKey) { key in
                self.store.openSubtitlesKey = key
                self.showToast(key.isEmpty ? L("Key removed") : L("Key saved"), symbol: "key.fill")
            }
        }
        s.addItem(store.openSubtitlesUser.map { L("Signed in: %@ — sign in again", $0) } ?? L("Sign in (optional)"),
                  symbol: "person.crop.circle") {
            self.prompt(L("OpenSubtitles username"), text: self.store.openSubtitlesUser) { user in
                guard !user.isEmpty else { return }
                let alert = UIAlertController(title: L("Password"), message: user, preferredStyle: .alert)
                alert.addTextField { $0.isSecureTextEntry = true }
                alert.addAction(UIAlertAction(title: L("Sign in"), style: .default) { [weak alert] _ in
                    OpenSubtitles.login(username: user, password: alert?.textFields?.first?.text ?? "") { error in
                        self.showToast(error.map { L("Sign-in failed: %@", $0) } ?? L("Signed in to OpenSubtitles"),
                                       symbol: "person.crop.circle")
                    }
                })
                alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
                self.present(alert, animated: true)
            }
        }
        if store.openSubtitlesToken != nil {
            s.addItem(L("Sign out"), symbol: "rectangle.portrait.and.arrow.right", destructive: true) {
                self.store.openSubtitlesToken = nil
                self.store.openSubtitlesUser = nil
                self.showToast(L("Signed out of OpenSubtitles"), symbol: "person.crop.circle")
            }
        }
        present(s, animated: true)
    }

    // MARK: Help

    func showHelp() {
        let lines = [
            L("Swipe on the touch surface: cursor (grows and slows down over links)"),
            L("Push the cursor to the edge: the page scrolls"),
            L("Click: click · keyboard in text fields · clicking a player opens the video full screen"),
            L("Play/Pause: menu"),
            L("Hold Play/Pause: tabs"),
            L("Hold the select button: cursor ↔ scroll mode"),
            L("Arrow buttons: scroll the page (◀ ▶ jump between matches when finding)"),
            L("Menu / Back: previous page"),
            L("In a video (swipe down): Subtitles · Speed · Skip · Next episode"),
            L("Phone control: Menu → Phone control (QR)"),
        ]
        let alert = UIAlertController(title: L("Remote control guide"), message: lines.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("OK"), style: .default))
        present(alert, animated: true)
    }
}
