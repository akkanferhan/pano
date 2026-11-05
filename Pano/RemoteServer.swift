import Foundation
import Network

/// Telefondan kontrol: Apple TV'de aynı Wi-Fi ağındaki telefonların açabileceği küçük bir web sunucusu.
/// Telefon sayfası (QR ile açılır) adres/metin gönderir, dokunmatik alanla imleci yönetir.
/// Her istek 4 haneli PIN ister (QR bağlantısında hazır gelir).
final class RemoteServer {
    static let shared = RemoteServer()
    static let port: UInt16 = 8765

    enum Command {
        case open(String, newTab: Bool)
        case type(String, submit: Bool)
        case move(dx: Double, dy: Double)
        case click
        case scroll(dy: Double)
        case back
        case home
        case menu
        case playPause
    }

    /// Komutları işler (ana iş parçacığında çağrılır). `state` için geçerli sayfa bilgisini döndürür.
    var handler: ((Command) -> Void)?
    var stateProvider: (() -> [String: Any])?
    #if DEBUG
    /// Yalnızca debug: GET /debug/<komut>?… (PIN'siz) — cihazda performans ölçümü için.
    var debugHandler: ((String, [String: String]) -> String)?
    #endif

    private var listener: NWListener?
    private(set) var isRunning = false

    var pin: String { Store.shared.remotePIN }

    /// Telefonun açacağı adres (ör. http://192.168.1.20:8765/?k=1234).
    var address: String? {
        guard let ip = Self.localIPAddress() else { return nil }
        return "http://\(ip):\(Self.port)/?k=\(pin)"
    }

    func start() throws {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
        l.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.isRunning = true
            case .failed, .cancelled: self?.isRunning = false; self?.listener = nil
            default: break
            }
        }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: Bağlantılar

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                let response = self.respond(to: request)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil || buffer.count > 1_000_000 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to r: HTTPRequest) -> Data {
        #if DEBUG
        if r.method == "GET", r.path.hasPrefix("/debug/") {
            let out = debugHandler?(String(r.path.dropFirst(7)), r.query) ?? "yok"
            return Self.http(200, "text/plain; charset=utf-8", out)
        }
        #endif
        guard r.query["k"] == pin else {
            return Self.http(403, "text/html; charset=utf-8",
                             "<meta name=viewport content='width=device-width'><h2 style='font-family:sans-serif'>Pano: PIN hatalı. Apple TV'deki QR kodu yeniden okut.</h2>")
        }
        if r.method == "GET" && r.path == "/" {
            return Self.http(200, "text/html; charset=utf-8", RemotePage.html)
        }
        guard r.method == "POST", r.path.hasPrefix("/api/") else { return Self.http(404, "text/plain", "yok") }
        let body = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
        let num = { (k: String) in (body[k] as? NSNumber)?.doubleValue ?? 0 }
        switch r.path.dropFirst(5) {
        case "open": handler?(.open(body["url"] as? String ?? "", newTab: body["newTab"] as? Bool ?? false))
        case "type": handler?(.type(body["text"] as? String ?? "", submit: body["submit"] as? Bool ?? false))
        case "move": handler?(.move(dx: num("dx"), dy: num("dy")))
        case "click": handler?(.click)
        case "scroll": handler?(.scroll(dy: num("dy")))
        case "back": handler?(.back)
        case "home": handler?(.home)
        case "menu": handler?(.menu)
        case "playpause": handler?(.playPause)
        case "state": break
        default: return Self.http(404, "text/plain", "yok")
        }
        let state = stateProvider?() ?? [:]
        let json = (try? JSONSerialization.data(withJSONObject: state)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Self.http(200, "application/json; charset=utf-8", json)
    }

    private static func http(_ status: Int, _ type: String, _ body: String) -> Data {
        let bodyData = Data(body.utf8)
        let reason = status == 200 ? "OK" : (status == 403 ? "Forbidden" : "Not Found")
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(bodyData.count)\r\n" +
            "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + bodyData
    }

    // MARK: Yerel IP

    static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254") { candidates.append((name, ip)) }
            }
        }
        return candidates.sorted { $0.name < $1.name }.first?.ip
    }
}

/// Çok basit HTTP isteği ayrıştırıcı (başlık + Content-Length gövdesi tamamlanınca oluşur).
private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ").map(String.init) ?? []
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = parts[0]
        let comps = URLComponents(string: parts[1])
        path = comps?.path ?? parts[1]
        var q: [String: String] = [:]
        for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        query = q
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}

/// Telefonda açılan kontrol sayfası.
enum RemotePage {
    static let html = #"""
    <!doctype html><html lang="tr"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes"><title>Pano Kumanda</title>
    <style>
    *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
    body{margin:0;font-family:-apple-system,sans-serif;color:#f4f5fa;padding:18px;padding-bottom:30px;min-height:100vh;background:radial-gradient(500px 400px at 0% 0%,rgba(124,58,237,.55),transparent 70%),radial-gradient(500px 420px at 100% 100%,rgba(236,72,153,.4),transparent 70%),#07070f;background-attachment:fixed}
    h1{font-size:26px;font-weight:800;margin:4px 0 2px;letter-spacing:-.5px;display:flex;align-items:center;gap:10px} h1 i{width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,#7c3aed,#ec4899);display:inline-flex;align-items:center;justify-content:center} h1 i:after{content:'';width:10px;height:10px;border-radius:50%;background:#fff} .now{color:#8a93a6;font-size:13px;margin-bottom:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .row{display:flex;gap:8px;margin-bottom:10px}
    input,textarea{flex:1;font-size:16px;padding:14px 16px;border-radius:16px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.07);-webkit-backdrop-filter:blur(20px);color:#fff;min-width:0;outline:none}
    textarea{height:70px;resize:none;width:100%}
    button{font-size:15px;padding:13px 14px;border-radius:16px;border:1px solid rgba(255,255,255,.1);background:rgba(255,255,255,.09);color:#fff;font-weight:600}
    button.p{background:linear-gradient(135deg,#7c3aed,#ec4899);border:0} button:active{opacity:.6}
    #pad{height:300px;border-radius:24px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);display:flex;align-items:center;justify-content:center;color:#5a6378;font-size:14px;touch-action:none;user-select:none;-webkit-user-select:none;margin-bottom:10px;text-align:center;line-height:1.5}
    .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
    .sec{font-size:13px;color:#8a93a6;margin:16px 0 8px;text-transform:uppercase;letter-spacing:.5px}
    </style></head><body>
    <h1><i></i>Pano Kumanda</h1><div class="now" id="now">Bağlanıyor…</div>
    <div class="sec">Adres / arama</div>
    <div class="row"><input id="url" type="url" placeholder="site.com veya aranacak kelime" autocapitalize="off" autocorrect="off"></div>
    <div class="row"><button class="p" style="flex:1" onclick="openUrl(false)">Aç</button><button style="flex:1" onclick="openUrl(true)">Yeni sekmede aç</button></div>
    <div class="sec">Dokunmatik alan</div>
    <div id="pad">Kaydır: imleç · Dokun: tıkla<br>İki parmak: sayfayı kaydır</div>
    <div class="grid">
      <button onclick="send('back')">◀︎ Geri</button><button onclick="send('scroll',{dy:-500})">▲ Yukarı</button><button onclick="send('home')">⌂ Ana sayfa</button>
      <button onclick="send('menu')">☰ Menü</button><button onclick="send('scroll',{dy:500})">▼ Aşağı</button><button onclick="send('playpause')">⏯ Oynat/Dur</button>
    </div>
    <div class="sec">Metin yaz (seçili alana)</div>
    <textarea id="text" placeholder="Önce TV'de bir metin alanına tıkla, sonra buraya yaz"></textarea>
    <div class="row" style="margin-top:8px"><button style="flex:1" onclick="typeText(false)">Yaz</button><button class="p" style="flex:1" onclick="typeText(true)">Yaz ve gönder</button></div>
    <script>
    var K = new URLSearchParams(location.search).get('k');
    function send(cmd, body){
      return fetch('/api/' + cmd + '?k=' + K, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body||{})})
        .then(function(r){ return r.json(); }).then(function(s){
          document.getElementById('now').textContent = s.title ? (s.title + (s.url ? ' — ' + s.url : '')) : 'Bağlı';
        }).catch(function(){ document.getElementById('now').textContent = 'Bağlantı yok — Apple TV açık ve aynı ağda mı?'; });
    }
    function openUrl(newTab){ var u = document.getElementById('url'); if (!u.value.trim()) return; send('open', {url:u.value.trim(), newTab:newTab}); u.blur(); }
    function typeText(submit){ var t = document.getElementById('text'); send('type', {text:t.value, submit:submit}); if (submit) t.value=''; }
    document.getElementById('url').addEventListener('keydown', function(e){ if (e.key === 'Enter') openUrl(false); });
    // Dokunmatik alan
    var pad = document.getElementById('pad'), last = null, start = null, moved = 0, acc = {x:0,y:0}, scrollAcc = 0, two = false;
    function flush(){
      if (acc.x || acc.y) { send('move', {dx:acc.x, dy:acc.y}); acc = {x:0,y:0}; }
      if (scrollAcc) { send('scroll', {dy:scrollAcc}); scrollAcc = 0; }
    }
    setInterval(flush, 45);
    pad.addEventListener('touchstart', function(e){
      e.preventDefault(); two = e.touches.length > 1;
      var t = e.touches[0]; last = {x:t.clientX, y:t.clientY}; start = {t:Date.now()}; moved = 0;
    }, {passive:false});
    pad.addEventListener('touchmove', function(e){
      e.preventDefault(); var t = e.touches[0]; if (!last) return;
      var dx = t.clientX - last.x, dy = t.clientY - last.y; last = {x:t.clientX, y:t.clientY}; moved += Math.abs(dx) + Math.abs(dy);
      if (e.touches.length > 1 || two) { two = true; scrollAcc += -dy * 4; } else { acc.x += dx * 3; acc.y += dy * 3; }
    }, {passive:false});
    pad.addEventListener('touchend', function(e){
      e.preventDefault();
      if (e.touches.length === 0) { if (!two && moved < 10 && Date.now() - start.t < 300) { flush(); send('click'); } last = null; two = false; }
    }, {passive:false});
    send('state');
    </script></body></html>
    """#
}
