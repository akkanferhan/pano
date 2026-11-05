import AVKit
import UIKit

/// Oynatılan videonun bağlamı: hangi sayfadan açıldı, başlığı, sonraki bölüm.
struct PlaybackContext {
    var pageURL: String?
    var title: String
    var nextEpisode: URL?
    var nextEpisodeGuessed = false
    /// Bu videonun kimliği (Store.videoKey) ve aynı sayfadaki yarım kalmış kayıtlar.
    var videoKey: String?
    var resumeCandidates: [WatchProgress] = []
}

/// tvOS oynatıcısı + Pano eklemeleri:
/// - Harici altyazılar (sitenin .vtt/.srt'leri, OpenSubtitles) videonun üstünde kendi katmanımızda çizilir.
/// - Üst çubuk menüleri: Altyazı (seçim, internetten bul, zamanlama, görünüm), Hız, Sar, Sonraki bölüm.
/// - Kaldığın yer: kapanınca ve her 10 sn'de konum bildirilir.
/// - Bölüm bitince (sonraki bölüm varsa) geri sayımla sonraki bölüme geçilir.
final class VideoPlayerController: AVPlayerViewController {
    var onProgress: ((_ position: Double, _ duration: Double) -> Void)?
    var onClose: ((_ position: Double, _ duration: Double) -> Void)?
    var onNextEpisode: ((URL) -> Void)?

    private let store = Store.shared
    private let subtitleLabel = UILabel()
    private let countdownLabel = GlassCapsule(text: " ", symbol: "forward.end.fill", size: 30)
    private var sources: [SubtitleSource] = []
    private var userAgent = ""
    private var context = PlaybackContext(pageURL: nil, title: "")
    private var tracks: [SubtitleTrack] = []
    private var current: SubtitleTrack?
    private var cueIndex = 0
    private var offset: Double = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loading = 0
    private var countdown: Timer?
    private var lastProgressReport: Double = 0
    private var showingNextAction = false
    private var resumeChecked = false
    private var resumeOffer: WatchProgress?
    private var resumeOfferUntil: Double = 0
    private var shownActions = ""
    private var closed = false

    /// Not: `player` ataması AVPlayerViewController'ın görünümünü hemen yükler (viewDidLoad çalışır);
    /// bu yüzden diğer her şey ondan önce atanmalı.
    func configure(player: AVPlayer, subtitles: [SubtitleSource], userAgent: String, context: PlaybackContext) {
        self.sources = subtitles
        self.userAgent = userAgent
        self.context = context
        player.defaultRate = Float(store.playbackRate)
        self.player = player
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLabels()
        if let player {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) {
                [weak self] time in self?.tick(time.seconds)
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                                 object: player.currentItem, queue: .main) {
                [weak self] _ in self?.playbackEnded()
            }
            selectEmbeddedPreferred(in: player)
        }
        loadSources()
        rebuildMenus()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { finish() }
    }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    private var position: Double { player?.currentTime().seconds ?? 0 }
    private var duration: Double {
        let d = player?.currentItem?.duration.seconds ?? 0
        return d.isFinite ? d : 0
    }

    /// Bir kez çalışır: konumu bildirir, zamanlayıcıları durdurur.
    private func finish() {
        guard !closed else { return }
        closed = true
        countdown?.invalidate()
        onClose?(position, duration)
    }

    private func tick(_ seconds: Double) {
        render(at: seconds)
        if seconds - lastProgressReport > 10 || seconds < lastProgressReport {
            lastProgressReport = seconds
            onProgress?(seconds, duration)
        }
        checkResume(at: seconds)
        // Ekrandaki düğme: başta "Kaldığın yerden devam", son 2 dakikada "Sonraki bölüm"
        let nearEnd = context.nextEpisode != nil && duration > 0 && duration - seconds < 120
        showingNextAction = nearEnd
        let offerActive = resumeOffer != nil && seconds < resumeOfferUntil
        let wanted = offerActive ? "resume" : (nearEnd ? "next" : "")
        if wanted != shownActions {
            shownActions = wanted
            switch wanted {
            case "resume": contextualActions = [resumeAction()]
            case "next": contextualActions = [nextEpisodeAction()]
            default: contextualActions = []
            }
        }
    }

    // MARK: Katmanlar

    private func setupLabels() {
        guard let overlay = contentOverlayView else { return }
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.82),
            subtitleLabel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -70),
        ])
        countdownLabel.isHidden = true
        overlay.addSubview(countdownLabel)
    }

    private func show(_ text: String?) {
        guard let text, !text.isEmpty else {
            subtitleLabel.attributedText = nil
            return
        }
        let color: UIColor = store.subtitleColor == "yellow" ? UIColor(red: 1, green: 0.92, blue: 0.2, alpha: 1) : .white
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(store.subtitleFontSize), weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        switch store.subtitleBackground {
        case 1: attrs[.backgroundColor] = UIColor(white: 0, alpha: 0.55)
        case 2: attrs[.backgroundColor] = UIColor(white: 0, alpha: 0.92)
        default:
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = CGSize(width: 0, height: 2)
            attrs[.shadow] = shadow
            attrs[.strokeColor] = UIColor.black
            attrs[.strokeWidth] = -2.5
        }
        // Kutulu arka planda satır başı/sonuna boşluk: kutu yazıya yapışmasın
        let display = store.subtitleBackground == 0 ? text
            : text.split(separator: "\n").map { "\u{2009} \($0) \u{2009}" }.joined(separator: "\n")
        subtitleLabel.attributedText = NSAttributedString(string: display, attributes: attrs)
    }

    private func render(at seconds: Double) {
        guard let cues = current?.cues, !cues.isEmpty, seconds.isFinite else {
            show(nil)
            return
        }
        let t = seconds - offset
        if !cues.indices.contains(cueIndex) || cues[cueIndex].start > t { cueIndex = 0 }
        while cueIndex + 1 < cues.count, cues[cueIndex + 1].start <= t { cueIndex += 1 }
        let cue = cues[cueIndex]
        show(cue.start <= t && t < cue.end ? cue.text : nil)
    }

    private func refreshSubtitle() { render(at: position) }

    // MARK: Altyazı yükleme ve seçim

    private func loadSources() {
        for source in sources {
            switch source {
            case let .cues(cues, label, language):
                add(SubtitleTrack(label: label, language: language, cues: cues, source: source.key))
            case let .url(url, label, language, referer):
                loading += 1
                Subtitles.load(url, referer: referer, userAgent: userAgent) { [weak self] cues in
                    guard let self else { return }
                    self.loading -= 1
                    if let cues { self.add(SubtitleTrack(label: label, language: language, cues: cues, source: source.key)) }
                    if self.loading == 0 { self.finishLoading() }
                }
            }
        }
        if loading == 0 { finishLoading() }
    }

    private func add(_ track: SubtitleTrack, select: Bool = false) {
        let duplicate = tracks.contains { t in
            t.cues.count == track.cues.count && t.cues.first?.text == track.cues.first?.text
        }
        guard !duplicate else { return }
        tracks.append(track)
        if select || (current == nil && Subtitles.isPreferred(track)) { self.select(track, announce: true) }
        rebuildMenus()
    }

    private func finishLoading() {
        if current == nil, let first = tracks.first { select(first, announce: true) }
        rebuildMenus()
    }

    private func select(_ track: SubtitleTrack?, announce: Bool = false) {
        current = track
        cueIndex = 0
        refreshSubtitle()
        rebuildMenus()
        if announce, let track { flash(L("Subtitles: %@", track.label)) }
    }

    /// HLS akışının içinde Türkçe altyazı varsa ve harici altyazı seçilmediyse onu seçer.
    private func selectEmbeddedPreferred(in player: AVPlayer) {
        guard let item = player.currentItem else { return }
        Task { @MainActor [weak self] in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            let want = AppLanguage.shortCode
            let preferred = group.options.first { option in
                option.extendedLanguageTag?.lowercased().hasPrefix(want) == true ||
                    option.locale?.language.languageCode?.identifier == want
            }
            if let preferred, self?.current == nil { item.select(preferred, in: group) }
        }
    }

    // MARK: OpenSubtitles

    private func searchOnline() {
        guard OpenSubtitles.isConfigured else {
            alert(L("OpenSubtitles API key required"),
                  L("Pano menu → Settings → OpenSubtitles. You can get a free key at opensubtitles.com/consumers."))
            return
        }
        let ep = OpenSubtitles.episode(from: context.title + " " + (context.pageURL ?? ""))
        var message = L("Searching for %@ subtitles", Locale.current.localizedString(forLanguageCode: AppLanguage.shortCode) ?? AppLanguage.shortCode)
        if let s = ep.season, let e = ep.episode { message += " · " + L("Season %d, episode %d", s, e) }
        let prompt = UIAlertController(title: L("Search subtitles (OpenSubtitles)"), message: message, preferredStyle: .alert)
        prompt.addTextField { [context] tf in
            tf.text = OpenSubtitles.cleanTitle(context.title)
            tf.placeholder = L("Movie / series name")
        }
        prompt.addAction(UIAlertAction(title: L("Search"), style: .default) { [weak self, weak prompt] _ in
            let q = prompt?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !q.isEmpty else { return }
            self?.flash(L("Searching: %@…", q))
            OpenSubtitles.search(query: q, season: ep.season, episode: ep.episode) { items, error in
                self?.showResults(items, error: error, query: q)
            }
        })
        prompt.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
        present(prompt, animated: true)
    }

    private func showResults(_ items: [OpenSubtitles.Item], error: String?, query: String) {
        if let error { return alert(L("Search failed"), error) }
        guard !items.isEmpty else { return alert(L("No results"), L("No subtitles found for “%@”.", query)) }
        let sheet = UIAlertController(title: L("Subtitles"), message: query, preferredStyle: .actionSheet)
        for item in items.prefix(25) {
            sheet.addAction(UIAlertAction(title: "\(item.release)  ·  ⬇︎\(item.downloads)", style: .default) { [weak self] _ in
                self?.flash(L("Downloading…"))
                OpenSubtitles.download(item) { cues, error in
                    guard let self else { return }
                    if let cues {
                        let label = "OpenSubtitles: " + String(item.release.prefix(40))
                        self.add(SubtitleTrack(label: label, language: "tr", cues: cues, source: "os:\(item.fileID)"), select: true)
                    } else {
                        self.alert(L("Download failed"), error ?? L("Unknown error"))
                    }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: Kaldığın yerden devam

    /// Video süresi belli olunca bir kez: aynı sayfadaki kayıtlardan *bu videoya* ait olanı bul.
    /// Eşleşme: video kimliği aynı ya da (adres oturuma göre değişiyorsa) süre ±3 sn içinde aynı.
    private func checkResume(at seconds: Double) {
        guard !resumeChecked, duration > 0 else { return }
        resumeChecked = true
        let match = context.resumeCandidates.first { entry in
            if let key = entry.videoKey, key == context.videoKey { return true }
            return entry.duration > 0 && abs(entry.duration - duration) < 3
        }
        guard let match, match.position > 30, match.position < duration - 60, seconds < 15 else { return }
        // Aynı video: otomatik olarak kaldığı yere atla; 15 sn boyunca "Baştan başla" düğmesi göster.
        // Tam konuma atla (HLS'te varsayılan atlama en yakın parça başına iner)
        player?.seek(to: CMTime(seconds: max(0, match.position - 3), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        resumeOffer = match
        resumeOfferUntil = match.position + 15
        flash(L("Resuming from %@", BrowserViewController.clock(match.position)))
    }

    private func resumeAction() -> UIAction {
        UIAction(title: L("Start over"), image: UIImage(systemName: "backward.end.fill")) { [weak self] _ in
            guard let self else { return }
            self.resumeOffer = nil
            self.player?.seek(to: .zero)
        }
    }

    // MARK: Sonraki bölüm

    private func nextEpisodeAction() -> UIAction {
        UIAction(title: L("Next episode"), image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
            self?.goToNextEpisode()
        }
    }

    private func playbackEnded() {
        guard context.nextEpisode != nil else { return }
        var remaining = 10
        countdownLabel.isHidden = false
        let update = { [weak self] in
            guard let self, let overlay = self.contentOverlayView else { return }
            self.countdownLabel.setText(L("Next episode in %d s · Menu to cancel", remaining), symbol: "forward.end.fill", size: 30)
            self.countdownLabel.frame.origin = CGPoint(x: overlay.bounds.width - self.countdownLabel.frame.width - 80, y: 150)
        }
        update()
        countdown?.invalidate()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.goToNextEpisode()
            } else {
                update()
            }
        }
    }

    private func goToNextEpisode() {
        guard let next = context.nextEpisode else { return }
        countdown?.invalidate()
        let handler = onNextEpisode
        finish()
        dismiss(animated: true) { handler?(next) }
    }

    // MARK: Menüler (oynatıcının üst çubuğu)

    private func rebuildMenus() {
        // ±adım düğmeleri doğrudan süre çubuğunun üstündeki sırada (alt menü değil)
        let step = store.skipStep
        let back = UIAction(title: L("−%d s", step), image: Self.skipSymbol(forward: false, step: step)) { [weak self] _ in
            self?.seek(by: -Double(step))
        }
        let forward = UIAction(title: L("+%d s", step), image: Self.skipSymbol(forward: true, step: step)) { [weak self] _ in
            self?.seek(by: Double(step))
        }
        var items: [UIMenuElement] = [back, forward, subtitleMenu(), speedMenu(), skipMenu()]
        if context.nextEpisode != nil {
            items.append(UIAction(title: context.nextEpisodeGuessed ? L("Next episode (guessed)") : L("Next episode"),
                                  image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
                self?.goToNextEpisode()
            })
        }
        transportBarCustomMenuItems = items
    }

    private func subtitleMenu() -> UIMenu {
        let off = UIAction(title: L("Off"), state: current == nil ? .on : .off) { [weak self] _ in self?.select(nil) }
        var list: [UIMenuElement] = tracks.map { track in
            UIAction(title: track.label, subtitle: L("%d lines", track.cues.count),
                     state: current?.source == track.source ? .on : .off) { [weak self] _ in
                self?.select(track, announce: true)
            }
        }
        if tracks.isEmpty {
            list = [UIAction(title: loading > 0 ? L("Loading…") : L("No subtitles found on the site"), attributes: .disabled) { _ in }]
        }
        let online = UIAction(title: L("Find online (OpenSubtitles)…"), image: UIImage(systemName: "magnifyingglass")) {
            [weak self] _ in self?.searchOnline()
        }
        let tools = UIMenu(title: "", options: .displayInline, children: [online, timingMenu(), appearanceMenu()])
        return UIMenu(title: L("Subtitles"), image: UIImage(systemName: "captions.bubble"), children: [off] + list + [tools])
    }

    private func timingMenu() -> UIMenu {
        var items: [UIMenuElement] = [-2.0, -0.5, 0.5, 2.0].map { step in
            UIAction(title: String(format: "%+.1f sn", step)) { [weak self] _ in
                guard let self else { return }
                self.offset += step
                self.flash(L("Subtitle delay: %+.1f s", self.offset))
                self.refreshSubtitle()
                self.rebuildMenus()
            }
        }
        items.append(UIAction(title: L("Reset")) { [weak self] _ in
            self?.offset = 0
            self?.flash(L("Subtitle delay reset"))
            self?.rebuildMenus()
        })
        return UIMenu(title: L("Timing (%+.1f s)", offset), image: UIImage(systemName: "clock.arrow.2.circlepath"),
                      children: items)
    }

    private func appearanceMenu() -> UIMenu {
        let sizes: [(String, Double)] = [(L("Small"), 36), (L("Normal"), 46), (L("Large"), 58), (L("Extra large"), 72)]
        let size = UIMenu(title: L("Size"), children: sizes.map { name, value in
            UIAction(title: name, state: store.subtitleFontSize == value ? .on : .off) { [weak self] _ in
                self?.store.subtitleFontSize = value
                self?.refreshSubtitle()
                self?.rebuildMenus()
            }
        })
        let colors: [(String, String)] = [(L("White"), "white"), (L("Yellow"), "yellow")]
        let color = UIMenu(title: L("Color"), children: colors.map { name, value in
            UIAction(title: name, state: store.subtitleColor == value ? .on : .off) { [weak self] _ in
                self?.store.subtitleColor = value
                self?.refreshSubtitle()
                self?.rebuildMenus()
            }
        })
        let backgrounds = [L("None (outlined)"), L("Translucent box"), L("Black box")]
        let background = UIMenu(title: L("Background"), children: backgrounds.enumerated().map { i, name in
            UIAction(title: name, state: store.subtitleBackground == i ? .on : .off) { [weak self] _ in
                self?.store.subtitleBackground = i
                self?.refreshSubtitle()
                self?.rebuildMenus()
            }
        })
        return UIMenu(title: L("Appearance"), image: UIImage(systemName: "textformat.size"), children: [size, color, background])
    }

    private func speedMenu() -> UIMenu {
        let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        return UIMenu(title: L("Speed"), image: UIImage(systemName: "speedometer"), children: rates.map { rate in
            UIAction(title: rate == 1 ? L("Normal (1×)") : String(format: "%g×", rate),
                     state: store.playbackRate == rate ? .on : .off) { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.store.playbackRate = rate
                player.defaultRate = Float(rate)
                if player.timeControlStatus != .paused { player.rate = Float(rate) }
                self.flash(rate == 1 ? L("Normal speed") : L("Speed: %g×", rate))
                self.rebuildMenus()
            }
        })
    }

    private func skipMenu() -> UIMenu {
        let step = Double(store.skipStep)
        let steps = [10, 15, 30, 60]
        let stepMenu = UIMenu(title: L("Step: %d s", store.skipStep), children: steps.map { s in
            UIAction(title: L("%d s", s), state: store.skipStep == s ? .on : .off) { [weak self] _ in
                self?.store.skipStep = s
                self?.rebuildMenus()
            }
        })
        _ = step
        return UIMenu(title: L("Skip"), image: UIImage(systemName: "forward.fill"), children: [
            UIAction(title: L("Skip intro (+85 s)"), image: UIImage(systemName: "forward.fill")) { [weak self] _ in self?.seek(by: 85) },
            stepMenu,
        ])
    }

    /// SF Symbols has numbered skip icons for these steps (gobackward.10, goforward.30 …).
    private static func skipSymbol(forward: Bool, step: Int) -> UIImage? {
        let name = (forward ? "goforward" : "gobackward") + ([10, 15, 30, 45, 60].contains(step) ? ".\(step)" : "")
        return UIImage(systemName: name)
    }

    private func seek(by delta: Double) {
        guard let player else { return }
        var target = max(0, position + delta)
        if duration > 0 { target = min(target, duration - 1) }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        flash(delta >= 0 ? L("+%d s", Int(delta)) : L("−%d s", Int(abs(delta))))
    }

    // MARK: Yardımcılar

    private func alert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L("OK"), style: .default))
        present(a, animated: true)
    }

    /// Kısa bilgi (sağ üstte cam kapsül, 2 sn).
    private func flash(_ text: String) {
        guard let overlay = contentOverlayView else { return }
        let symbol = text.hasPrefix("+") ? "goforward" : text.hasPrefix("−") ? "gobackward" : "info.circle.fill"
        let capsule = GlassCapsule(text: text, symbol: symbol)
        capsule.frame.origin = CGPoint(x: overlay.bounds.width - capsule.frame.width - 80, y: 70)
        capsule.alpha = 0
        overlay.addSubview(capsule)
        UIView.animate(withDuration: 0.25, animations: { capsule.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.35, delay: 1.8, options: [], animations: { capsule.alpha = 0 }) { _ in
                capsule.removeFromSuperview()
            }
        }
    }
}
