import UIKit

/// Telefondan kontrol komutları (RemoteServer → tarayıcı).
extension BrowserViewController {
    func setupRemote() {
        let server = RemoteServer.shared
        server.handler = { [weak self] command in self?.handleRemote(command) }
        server.stateProvider = { [weak self] in
            guard let t = self?.activeTab else { return [:] }
            return ["title": t.title, "url": t.isHome ? "" : (t.url?.absoluteString ?? "")]
        }
        if store.remoteEnabled { try? server.start() }
        #if DEBUG
        try? server.start()
        server.debugHandler = { [weak self] command, query in
            guard let self, let e = self.engine else { return "motor yok" }
            switch command {
            case "jsbench":
                return e.js(Pages.jsBenchmark) ?? "-"
            case "open":
                if let u = query["url"] { self.open(u) }
                return "açılıyor: \(query["url"] ?? "")"
            case "perf":
                let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("perf.txt")
                return (try? String(contentsOf: url, encoding: .utf8)) ?? "(boş)"
            default:
                return "komutlar: jsbench, open?url=, perf"
            }
        }
        #endif
    }

    func showRemoteInfo() {
        do {
            try RemoteServer.shared.start()
            store.remoteEnabled = true
        } catch {
            showToast("Sunucu başlatılamadı: \(error.localizedDescription)")
            return
        }
        let vc = RemoteInfoViewController()
        vc.modalPresentationStyle = .overFullScreen
        vc.onDisable = { [weak self] in
            RemoteServer.shared.stop()
            self?.store.remoteEnabled = false
            self?.showToast("Telefondan kontrol kapatıldı")
        }
        present(vc, animated: true)
    }

    private func handleRemote(_ command: RemoteServer.Command) {
        let modal = presentedViewController
        switch command {
        case let .open(text, newTab):
            guard let url = store.resolve(text) else { return }
            modal?.dismiss(animated: false)
            if newTab { addTab(url: url, activate: true) } else { open(url.absoluteString) }
        case let .type(text, submit):
            // Açık bir metin kutusu (adres, form alanı, arama) varsa oraya yaz; yoksa sayfadaki son seçilen alana.
            if let alert = modal as? UIAlertController, let field = alert.textFields?.first {
                field.text = text
            } else if modal == nil {
                engine?.evaluate(Pages.setFieldValue(text, submit: submit), in: fieldFrame)
                showToast(submit ? "Telefondan yazıldı ve gönderildi" : "Telefondan yazıldı")
            }
        case let .move(dx, dy):
            guard modal == nil else { return }
            if mode == .scroll { setMode(.cursor) }
            moveCursor(by: CGPoint(x: dx, y: dy))
            checkHover()
        case .click:
            guard modal == nil else { return }
            clickAtCursor()
        case let .scroll(dy):
            guard modal == nil else { return }
            scrollPage(by: CGPoint(x: 0, y: dy), animated: abs(dy) > 200)
        case .back:
            if let modal { modal.dismiss(animated: true); return }
            guard let t = activeTab else { return }
            if t.isReader { toggleReader() } else if t.engine.canGoBack { t.engine.goBack() } else if !t.isHome { loadHome(in: t) }
        case .home:
            modal?.dismiss(animated: false)
            goHome()
        case .menu:
            if modal == nil { showMenu() }
        case .playPause:
            if let player = (modal as? VideoPlayerController)?.player {
                if player.timeControlStatus == .paused { player.play() } else { player.pause() }
            }
        }
    }
}
