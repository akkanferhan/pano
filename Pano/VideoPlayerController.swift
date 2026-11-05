import AVKit
import UIKit

/// tvOS oynatıcısı + harici altyazı katmanı.
/// Film sitelerinin ayrı dosya olarak verdiği altyazılar (.vtt/.srt) AVPlayer'a gömülü olmadığı için
/// videonun üstüne kendi katmanımızda, oynatma zamanına göre çizilir. Üst menüde (aşağı kaydırınca)
/// altyazı seçimi, zamanlama kaydırma ve yazı boyutu bulunur. Akışın kendi içindeki altyazılar (HLS)
/// AVPlayer tarafından gösterilir; Türkçe varsa otomatik seçilir.
final class VideoPlayerController: AVPlayerViewController {
    private let subtitleLabel = UILabel()
    private var sources: [SubtitleSource] = []
    private var userAgent = ""
    private var tracks: [SubtitleTrack] = []
    private var current: SubtitleTrack?
    private var cueIndex = 0
    private var offset: Double = 0
    private var timeObserver: Any?
    private var loading = 0

    private static var fontSize: CGFloat = 46
    private static let fontSizes: [(String, CGFloat)] = [("Küçük", 36), ("Normal", 46), ("Büyük", 58), ("Çok büyük", 72)]

    /// Not: `player` ataması AVPlayerViewController'ın görünümünü hemen yükler (viewDidLoad çalışır);
    /// bu yüzden altyazı kaynakları ondan önce atanmalı.
    func configure(player: AVPlayer, subtitles: [SubtitleSource], userAgent: String) {
        self.sources = subtitles
        self.userAgent = userAgent
        self.player = player
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLabel()
        if let player {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) {
                [weak self] time in self?.render(at: time.seconds)
            }
            selectEmbeddedTurkish(in: player)
        }
        loadSources()
        rebuildMenus()
    }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
    }

    // MARK: Katman

    private func setupLabel() {
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
    }

    private func show(_ text: String?) {
        guard let text, !text.isEmpty else {
            subtitleLabel.attributedText = nil
            return
        }
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        subtitleLabel.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: Self.fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.5,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ])
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

    // MARK: Yükleme ve seçim

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

    private func add(_ track: SubtitleTrack) {
        // Aynı içerik farklı yollardan gelebilir (sayfadaki satırlar + dosya); ilk satırlar aynıysa tekrar ekleme.
        let duplicate = tracks.contains { t in
            t.cues.count == track.cues.count && t.cues.first?.text == track.cues.first?.text
        }
        guard !duplicate else { return }
        tracks.append(track)
        if current == nil, Subtitles.isTurkish(track) { select(track, announce: true) }
        rebuildMenus()
    }

    private func finishLoading() {
        if current == nil, let first = tracks.first { select(first, announce: true) }
        rebuildMenus()
    }

    private func select(_ track: SubtitleTrack?, announce: Bool = false) {
        current = track
        cueIndex = 0
        if let t = player?.currentTime().seconds { render(at: t) }
        rebuildMenus()
        if announce, let track { flash("Altyazı: \(track.label)") }
    }

    /// HLS akışının içinde altyazı varsa ve harici altyazı yoksa Türkçe seçeneği seçer.
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

    // MARK: Menüler (oynatıcının üst çubuğu)

    private func rebuildMenus() {
        let off = UIAction(title: "Kapalı", state: current == nil ? .on : .off) { [weak self] _ in self?.select(nil) }
        var trackActions: [UIMenuElement] = tracks.map { track in
            UIAction(title: track.label, subtitle: "\(track.cues.count) satır",
                     state: current?.source == track.source ? .on : .off) { [weak self] _ in
                self?.select(track, announce: true)
            }
        }
        if tracks.isEmpty {
            trackActions = [UIAction(title: loading > 0 ? "Yükleniyor…" : "Harici altyazı bulunamadı",
                                     attributes: .disabled) { _ in }]
        }
        let subtitleMenu = UIMenu(title: "Altyazı", image: UIImage(systemName: "captions.bubble"),
                                  children: [off] + trackActions)

        let steps: [Double] = [-2, -0.5, 0.5, 2]
        var timing: [UIMenuElement] = steps.map { step in
            UIAction(title: (step > 0 ? "+" : "") + String(format: "%.1f sn", step)) { [weak self] _ in
                guard let self else { return }
                self.offset += step
                self.flash(String(format: "Altyazı gecikmesi: %+.1f sn", self.offset))
                self.rebuildMenus()
            }
        }
        timing.append(UIAction(title: "Sıfırla (\(String(format: "%+.1f", offset)) sn)") { [weak self] _ in
            self?.offset = 0
            self?.flash("Altyazı gecikmesi sıfırlandı")
            self?.rebuildMenus()
        })
        let timingMenu = UIMenu(title: "Altyazı zamanlaması", image: UIImage(systemName: "clock.arrow.2.circlepath"),
                                children: timing)

        let sizeMenu = UIMenu(title: "Altyazı boyutu", image: UIImage(systemName: "textformat.size"),
                              children: Self.fontSizes.map { name, size in
                                  UIAction(title: name, state: Self.fontSize == size ? .on : .off) { [weak self] _ in
                                      Self.fontSize = size
                                      if let t = self?.player?.currentTime().seconds { self?.render(at: t) }
                                      self?.rebuildMenus()
                                  }
                              })
        transportBarCustomMenuItems = [subtitleMenu, timingMenu, sizeMenu]
    }

    /// Kısa bilgi yazısı (altyazı katmanının üstünde, 2 sn).
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
