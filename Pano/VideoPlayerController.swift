import AVKit
import UIKit

/// Oynatılan videonun bağlamı: hangi sayfadan açıldı, başlığı, sonraki bölüm.
struct PlaybackContext {
    var pageURL: String?
    var title: String
    var nextEpisode: URL?
    var nextEpisodeGuessed = false
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
    private let countdownLabel = PaddedLabel()
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
            selectEmbeddedTurkish(in: player)
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
        // Son 2 dakikada ekranda "Sonraki bölüm" düğmesi
        let nearEnd = context.nextEpisode != nil && duration > 0 && duration - seconds < 120
        if nearEnd != showingNextAction {
            showingNextAction = nearEnd
            contextualActions = nearEnd ? [nextEpisodeAction()] : []
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
        countdownLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        countdownLabel.textColor = .white
        countdownLabel.backgroundColor = UIColor(white: 0, alpha: 0.75)
        countdownLabel.layer.cornerRadius = 16
        countdownLabel.layer.masksToBounds = true
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
        if select || (current == nil && Subtitles.isTurkish(track)) { self.select(track, announce: true) }
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
        if announce, let track { flash("Altyazı: \(track.label)") }
    }

    /// HLS akışının içinde Türkçe altyazı varsa ve harici altyazı seçilmediyse onu seçer.
    private func selectEmbeddedTurkish(in player: AVPlayer) {
        guard let item = player.currentItem else { return }
        Task { @MainActor [weak self] in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            let turkish = group.options.first { option in
                option.extendedLanguageTag?.lowercased().hasPrefix("tr") == true ||
                    option.locale?.language.languageCode?.identifier == "tr"
            }
            if let turkish, self?.current == nil { item.select(turkish, in: group) }
        }
    }

    // MARK: OpenSubtitles

    private func searchOnline() {
        guard OpenSubtitles.isConfigured else {
            alert("OpenSubtitles API anahtarı gerekli",
                  "Pano menüsü → Ayarlar → OpenSubtitles API anahtarı. Anahtarı opensubtitles.com/consumers adresinden ücretsiz alabilirsin.")
            return
        }
        let ep = OpenSubtitles.episode(from: context.title + " " + (context.pageURL ?? ""))
        var message = "Türkçe altyazı aranacak"
        if let s = ep.season, let e = ep.episode { message += " · \(s). sezon \(e). bölüm" }
        let prompt = UIAlertController(title: "Altyazı ara (OpenSubtitles)", message: message, preferredStyle: .alert)
        prompt.addTextField { [context] tf in
            tf.text = OpenSubtitles.cleanTitle(context.title)
            tf.placeholder = "Film / dizi adı"
        }
        prompt.addAction(UIAlertAction(title: "Ara", style: .default) { [weak self, weak prompt] _ in
            let q = prompt?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !q.isEmpty else { return }
            self?.flash("Aranıyor: \(q)…")
            OpenSubtitles.search(query: q, season: ep.season, episode: ep.episode) { items, error in
                self?.showResults(items, error: error, query: q)
            }
        })
        prompt.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(prompt, animated: true)
    }

    private func showResults(_ items: [OpenSubtitles.Item], error: String?, query: String) {
        if let error { return alert("Arama başarısız", error) }
        guard !items.isEmpty else { return alert("Sonuç yok", "“\(query)” için Türkçe altyazı bulunamadı.") }
        let sheet = UIAlertController(title: "Türkçe altyazılar", message: query, preferredStyle: .actionSheet)
        for item in items.prefix(25) {
            sheet.addAction(UIAlertAction(title: "\(item.release)  ·  ⬇︎\(item.downloads)", style: .default) { [weak self] _ in
                self?.flash("İndiriliyor…")
                OpenSubtitles.download(item) { cues, error in
                    guard let self else { return }
                    if let cues {
                        let label = "OpenSubtitles: " + String(item.release.prefix(40))
                        self.add(SubtitleTrack(label: label, language: "tr", cues: cues, source: "os:\(item.fileID)"), select: true)
                    } else {
                        self.alert("İndirilemedi", error ?? "Bilinmeyen hata")
                    }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Vazgeç", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: Sonraki bölüm

    private func nextEpisodeAction() -> UIAction {
        UIAction(title: "Sonraki bölüm", image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
            self?.goToNextEpisode()
        }
    }

    private func playbackEnded() {
        guard context.nextEpisode != nil else { return }
        var remaining = 10
        countdownLabel.isHidden = false
        let update = { [weak self] in
            guard let self, let overlay = self.contentOverlayView else { return }
            self.countdownLabel.text = "Sonraki bölüm \(remaining) sn içinde başlıyor · iptal: Menü"
            let size = self.countdownLabel.sizeThatFits(CGSize(width: 1200, height: 200))
            self.countdownLabel.frame = CGRect(x: overlay.bounds.width - size.width - 80,
                                               y: 150,
                                               width: size.width, height: size.height)
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
        var items: [UIMenuElement] = [subtitleMenu(), speedMenu(), skipMenu()]
        if context.nextEpisode != nil {
            items.append(UIAction(title: context.nextEpisodeGuessed ? "Sonraki bölüm (tahmini)" : "Sonraki bölüm",
                                  image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
                self?.goToNextEpisode()
            })
        }
        transportBarCustomMenuItems = items
    }

    private func subtitleMenu() -> UIMenu {
        let off = UIAction(title: "Kapalı", state: current == nil ? .on : .off) { [weak self] _ in self?.select(nil) }
        var list: [UIMenuElement] = tracks.map { track in
            UIAction(title: track.label, subtitle: "\(track.cues.count) satır",
                     state: current?.source == track.source ? .on : .off) { [weak self] _ in
                self?.select(track, announce: true)
            }
        }
        if tracks.isEmpty {
            list = [UIAction(title: loading > 0 ? "Yükleniyor…" : "Sitede altyazı bulunamadı", attributes: .disabled) { _ in }]
        }
        let online = UIAction(title: "İnternetten bul (OpenSubtitles)…", image: UIImage(systemName: "magnifyingglass")) {
            [weak self] _ in self?.searchOnline()
        }
        let tools = UIMenu(title: "", options: .displayInline, children: [online, timingMenu(), appearanceMenu()])
        return UIMenu(title: "Altyazı", image: UIImage(systemName: "captions.bubble"), children: [off] + list + [tools])
    }

    private func timingMenu() -> UIMenu {
        var items: [UIMenuElement] = [-2.0, -0.5, 0.5, 2.0].map { step in
            UIAction(title: String(format: "%+.1f sn", step)) { [weak self] _ in
                guard let self else { return }
                self.offset += step
                self.flash(String(format: "Altyazı gecikmesi: %+.1f sn", self.offset))
                self.refreshSubtitle()
                self.rebuildMenus()
            }
        }
        items.append(UIAction(title: "Sıfırla") { [weak self] _ in
            self?.offset = 0
            self?.flash("Altyazı gecikmesi sıfırlandı")
            self?.rebuildMenus()
        })
        return UIMenu(title: String(format: "Zamanlama (%+.1f sn)", offset), image: UIImage(systemName: "clock.arrow.2.circlepath"),
                      children: items)
    }

    private func appearanceMenu() -> UIMenu {
        let sizes: [(String, Double)] = [("Küçük", 36), ("Normal", 46), ("Büyük", 58), ("Çok büyük", 72)]
        let size = UIMenu(title: "Boyut", children: sizes.map { name, value in
            UIAction(title: name, state: store.subtitleFontSize == value ? .on : .off) { [weak self] _ in
                self?.store.subtitleFontSize = value
                self?.refreshSubtitle()
                self?.rebuildMenus()
            }
        })
        let colors: [(String, String)] = [("Beyaz", "white"), ("Sarı", "yellow")]
        let color = UIMenu(title: "Renk", children: colors.map { name, value in
            UIAction(title: name, state: store.subtitleColor == value ? .on : .off) { [weak self] _ in
                self?.store.subtitleColor = value
                self?.refreshSubtitle()
                self?.rebuildMenus()
            }
        })
        let backgrounds = ["Yok (kenarlıklı)", "Yarı saydam kutu", "Siyah kutu"]
        let background = UIMenu(title: "Arka plan", children: backgrounds.enumerated().map { i, name in
            UIAction(title: name, state: store.subtitleBackground == i ? .on : .off) { [weak self] _ in
                self?.store.subtitleBackground = i
                self?.refreshSubtitle()
                self?.rebuildMenus()
            }
        })
        return UIMenu(title: "Görünüm", image: UIImage(systemName: "textformat.size"), children: [size, color, background])
    }

    private func speedMenu() -> UIMenu {
        let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        return UIMenu(title: "Hız", image: UIImage(systemName: "speedometer"), children: rates.map { rate in
            UIAction(title: rate == 1 ? "Normal (1×)" : String(format: "%g×", rate),
                     state: store.playbackRate == rate ? .on : .off) { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.store.playbackRate = rate
                player.defaultRate = Float(rate)
                if player.timeControlStatus != .paused { player.rate = Float(rate) }
                self.flash(rate == 1 ? "Normal hız" : String(format: "Hız: %g×", rate))
                self.rebuildMenus()
            }
        })
    }

    private func skipMenu() -> UIMenu {
        let step = Double(store.skipStep)
        let steps = [10, 15, 30, 60]
        let stepMenu = UIMenu(title: "Adım: \(store.skipStep) sn", children: steps.map { s in
            UIAction(title: "\(s) sn", state: store.skipStep == s ? .on : .off) { [weak self] _ in
                self?.store.skipStep = s
                self?.rebuildMenus()
            }
        })
        return UIMenu(title: "Sar", image: UIImage(systemName: "goforward"), children: [
            UIAction(title: "−\(Int(step)) sn", image: UIImage(systemName: "gobackward")) { [weak self] _ in self?.seek(by: -step) },
            UIAction(title: "+\(Int(step)) sn", image: UIImage(systemName: "goforward")) { [weak self] _ in self?.seek(by: step) },
            UIAction(title: "Jeneriği atla (+85 sn)", image: UIImage(systemName: "forward.fill")) { [weak self] _ in self?.seek(by: 85) },
            stepMenu,
        ])
    }

    private func seek(by delta: Double) {
        guard let player else { return }
        var target = max(0, position + delta)
        if duration > 0 { target = min(target, duration - 1) }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        flash(String(format: "%@%d sn", delta >= 0 ? "+" : "−", Int(abs(delta))))
    }

    // MARK: Yardımcılar

    private func alert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(a, animated: true)
    }

    /// Kısa bilgi yazısı (sağ üstte, 2 sn).
    private func flash(_ text: String) {
        guard let overlay = contentOverlayView else { return }
        let label = PaddedLabel()
        label.text = text
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0, alpha: 0.7)
        label.layer.cornerRadius = 14
        label.layer.masksToBounds = true
        let size = label.sizeThatFits(CGSize(width: 900, height: 200))
        label.frame = CGRect(x: overlay.bounds.width - size.width - 80, y: 70, width: size.width, height: size.height)
        overlay.addSubview(label)
        UIView.animate(withDuration: 0.3, delay: 2, options: [], animations: { label.alpha = 0 }) { _ in
            label.removeFromSuperview()
        }
    }
}
