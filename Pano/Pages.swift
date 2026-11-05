import Foundation

/// İmlecin ekrandaki yeri ve web görünümünün kaydırma durumu. JS tarafında sayfa koordinatına çevrilir.
struct Pointer {
    var viewWidth: Double
    var offsetX: Double
    var offsetY: Double
    var x: Double
    var y: Double

    var args: String { "\(viewWidth),\(offsetX),\(offsetY),\(x),\(y)" }
}

/// Uygulama içi HTML sayfaları ve sayfalara enjekte edilen betikler.
enum Pages {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Swift metnini güvenli bir JS metin sabitine çevirir.
    static func jsString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) else { return "\"\"" }
        return str
    }

    // MARK: Ana sayfa / hata

    /// Ortak tema: koyu zemin, mor/mavi/pembe ışık lekeleri, cam yüzeyler.
    private static let style = """
    <style>
    *{box-sizing:border-box}
    html{background:#07070f}
    html,body{margin:0;min-height:100%;color:#f4f5fa;font-family:-apple-system,"SF Pro Display",Helvetica,sans-serif;-webkit-font-smoothing:antialiased}
    body{padding:96px 120px 90px;position:relative;overflow-x:hidden;background:transparent}
    .bg{position:fixed;top:0;left:0;right:0;bottom:0;z-index:-1;background:
      radial-gradient(1000px 760px at 6% -4%, rgba(124,58,237,.60), rgba(124,58,237,0) 70%),
      radial-gradient(900px 760px at 102% 104%, rgba(236,72,153,.42), rgba(236,72,153,0) 70%),
      radial-gradient(760px 520px at 62% -12%, rgba(59,130,246,.38), rgba(59,130,246,0) 70%),
      radial-gradient(700px 560px at -4% 104%, rgba(20,184,166,.22), rgba(20,184,166,0) 70%), #07070f}
    header{display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:46px}
    .hello{font-size:68px;font-weight:800;letter-spacing:-1.5px;line-height:1.05}
    .date{font-size:26px;color:rgba(255,255,255,.55);margin-top:10px;font-weight:500}
    .clock{font-size:84px;font-weight:200;letter-spacing:-2px;color:rgba(255,255,255,.92);font-variant-numeric:tabular-nums}
    .brand{display:inline-flex;align-items:center;gap:14px;font-size:24px;font-weight:700;color:rgba(255,255,255,.85);margin-bottom:22px}
    .logo{width:44px;height:44px;border-radius:13px;background:linear-gradient(135deg,#7c3aed,#ec4899);display:flex;align-items:center;justify-content:center;box-shadow:0 8px 24px rgba(124,58,237,.45)}
    .logo b{width:16px;height:16px;border-radius:50%;background:#fff}
    .pill{display:inline-block;margin-left:14px;padding:6px 16px;border-radius:999px;background:rgba(124,58,237,.85);font-size:20px;font-weight:700;vertical-align:middle}
    form{margin:0 0 64px}
    .search{position:relative}
    .search svg{position:absolute;left:38px;top:50%;margin-top:-17px;width:34px;height:34px;opacity:.6;z-index:2}
    input{width:100%;font-size:34px;padding:30px 36px 30px 94px;border-radius:999px;border:1.5px solid rgba(255,255,255,.14);
      background:rgba(255,255,255,.08);-webkit-backdrop-filter:blur(30px);color:#fff;outline:none;font-family:inherit;
      box-shadow:0 20px 60px rgba(0,0,0,.35),inset 0 1px 0 rgba(255,255,255,.12)}
    input::-webkit-input-placeholder{color:rgba(255,255,255,.45)}
    h2{font-size:30px;font-weight:700;margin:0 0 24px;color:rgba(255,255,255,.9);letter-spacing:-.3px}
    .row{display:flex;flex-wrap:wrap;gap:28px;margin-bottom:60px}
    a.cw{position:relative;display:flex;flex-direction:column;justify-content:flex-end;width:520px;height:190px;padding:26px 30px;border-radius:28px;
      text-decoration:none;color:#fff;overflow:hidden;background:linear-gradient(135deg,rgba(124,58,237,.55),rgba(236,72,153,.35));
      border:1.5px solid rgba(255,255,255,.14);box-shadow:0 20px 50px rgba(0,0,0,.35)}
    a.cw .play{position:absolute;right:26px;top:24px;width:58px;height:58px;border-radius:50%;background:rgba(255,255,255,.95);display:flex;align-items:center;justify-content:center}
    a.cw .play:after{content:"";margin-left:5px;border-left:18px solid #7c3aed;border-top:11px solid transparent;border-bottom:11px solid transparent}
    a.cw b{font-size:28px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:70px}
    a.cw span{font-size:19px;color:rgba(255,255,255,.7);margin-top:6px}
    a.cw .bar{position:absolute;left:0;right:0;bottom:0;height:7px;background:rgba(255,255,255,.18)}
    a.cw .bar i{display:block;height:100%;background:linear-gradient(90deg,#a78bfa,#f472b6)}
    a.tile{width:236px;text-decoration:none;color:#fff;text-align:center}
    a.tile .ic{width:236px;height:180px;border-radius:30px;display:flex;align-items:center;justify-content:center;position:relative;overflow:hidden;
      background:rgba(255,255,255,.07);border:1.5px solid rgba(255,255,255,.12);box-shadow:0 18px 44px rgba(0,0,0,.35),inset 0 1px 0 rgba(255,255,255,.1)}
    a.tile .ic:before{content:"";position:absolute;inset:0;background:radial-gradient(circle at 30% 20%,var(--g),transparent 70%);opacity:.55}
    a.tile img{position:relative;width:84px;height:84px;border-radius:22px;background:#fff;padding:12px;box-shadow:0 8px 24px rgba(0,0,0,.3)}
    a.tile .lt{position:relative;width:84px;height:84px;border-radius:22px;background:linear-gradient(135deg,var(--g),rgba(255,255,255,.15));
      display:none;align-items:center;justify-content:center;font-size:44px;font-weight:800}
    a.tile .t{display:block;font-size:24px;font-weight:600;margin-top:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    a.tile .h{display:block;font-size:17px;color:rgba(255,255,255,.45);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .empty{font-size:24px;color:rgba(255,255,255,.5)}
    .hints{display:flex;gap:34px;flex-wrap:wrap;color:rgba(255,255,255,.45);font-size:20px;margin-top:10px}
    .hints span b{display:inline-block;padding:4px 12px;margin-right:10px;border-radius:10px;background:rgba(255,255,255,.1);color:rgba(255,255,255,.8);font-weight:600}
    .err{max-width:1300px;margin-top:80px}
    .err .icon{width:110px;height:110px;border-radius:32px;background:linear-gradient(135deg,#7c3aed,#ec4899);display:flex;align-items:center;justify-content:center;font-size:62px;font-weight:800;margin-bottom:40px;box-shadow:0 20px 50px rgba(124,58,237,.4)}
    .err h1{font-size:64px;font-weight:800;letter-spacing:-1px;margin:0 0 20px}
    .err p{font-size:28px;color:rgba(255,255,255,.65);margin:10px 0;line-height:1.45;word-break:break-all}
    .err .url{display:inline-block;padding:12px 22px;border-radius:16px;background:rgba(255,255,255,.08);font-size:24px;color:rgba(255,255,255,.8)}
    </style>
    """

    private static let glows = ["#7c3aed", "#ec4899", "#3b82f6", "#14b8a6", "#f59e0b", "#8b5cf6", "#ef4444", "#06b6d4"]

    private static let searchIcon = """
    <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.4" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="7"/><path d="M20 20l-4.3-4.3"/></svg>
    """

    static func home(bookmarks: [Bookmark], engine: SearchEngine, isPrivate: Bool, continueWatching: [WatchProgress] = []) -> String {
        let tiles = bookmarks.enumerated().map { i, b -> String in
            let host = URL(string: b.url)?.host ?? b.url
            let letter = b.title.first.map { String($0).uppercased() } ?? "•"
            let favicon = "https://www.google.com/s2/favicons?domain=\(host)&sz=128"
            return """
            <a class="tile" href="\(esc(b.url))" style="--g:\(glows[i % glows.count])"><div class="ic">\
            <img src="\(esc(favicon))" onerror="this.style.display='none';this.nextSibling.style.display='flex'"><div class="lt">\(esc(letter))</div>\
            </div><span class="t">\(esc(b.title))</span><span class="h">\(esc(host.replacingOccurrences(of: "www.", with: "")))</span></a>
            """
        }.joined()
        let watching = continueWatching.prefix(6).map { w -> String in
            let host = (URL(string: w.pageURL)?.host ?? "").replacingOccurrences(of: "www.", with: "")
            let pct = w.duration > 0 ? min(100, max(3, Int(w.position / w.duration * 100))) : 3
            let pos = Int(w.position)
            let time = pos >= 3600 ? String(format: "%d:%02d:%02d", pos / 3600, pos / 60 % 60, pos % 60)
                : String(format: "%d:%02d", pos / 60, pos % 60)
            return """
            <a class="cw" href="\(esc(w.pageURL))"><div class="play"></div><b>\(esc(w.title))</b>\
            <span>\(esc(host)) · \(esc(L("Resume at %@", time)))</span><div class="bar"><i style="width:\(pct)%"></i></div></a>
            """
        }.joined()
        let watchingSection = watching.isEmpty ? "" : "<h2>\(esc(L("Continue watching")))</h2><div class=\"row\">\(watching)</div>"
        let direction = AppLanguage.current.hasPrefix("ar") ? "rtl" : "ltr"
        let greetingsJSON = "[" + [L("Good morning"), L("Good afternoon"), L("Good evening"), L("Good night")].map(jsString).joined(separator: ",") + "]"
        let privatePill = isPrivate ? "<span class=\"pill\">\(esc(L("Private browsing")))</span>" : ""
        return """
        <!doctype html><html data-pano="home" lang="\(AppLanguage.current)" dir="\(direction)"><head><meta charset="utf-8"><meta name="viewport" content="width=1600">
        <title>\(esc(L("Home")))</title>\(style)</head><body><div class="bg"></div>
        <header><div><div class="brand"><div class="logo"><b></b></div>Pano\(privatePill)</div>
        <div class="hello" id="hello">\(esc(L("Hello")))</div><div class="date" id="date"></div></div>
        <div class="clock" id="clock"></div></header>
        <form action="pano://search" method="get"><div class="search">\(searchIcon)
        <input type="search" name="q" placeholder="\(esc(L("Search with %@ or enter an address", engine.name)))"></div></form>
        \(watchingSection)
        <h2>\(esc(L("Favorites")))</h2>
        <div class="row">\(tiles.isEmpty ? "<div class=\"empty\">\(esc(L("No favorites yet — add one from the menu while on a site.")))</div>" : tiles)</div>
        <div class="hints"><span><b>\(esc(L("Play")))</b>\(esc(L("Menu")))</span><span><b>\(esc(L("Play hold")))</b>\(esc(L("Tabs")))</span><span><b>\(esc(L("Hold")))</b>\(esc(L("Cursor / scroll")))</span><span><b>\(esc(L("Menu")))</b>\(esc(L("Back")))</span></div>
        <script>
        (function(){
          var lang = \(jsString(AppLanguage.current));
          var greet = \(greetingsJSON);
          function tick(){
            var d = new Date(), h = d.getHours();
            document.getElementById('hello').textContent = h < 5 ? greet[3] : h < 12 ? greet[0] : h < 18 ? greet[1] : h < 22 ? greet[2] : greet[3];
            var date = '';
            try { date = d.toLocaleDateString(lang, {weekday:'long', day:'numeric', month:'long'}); } catch(e) { date = d.toDateString(); }
            document.getElementById('date').textContent = date;
            document.getElementById('clock').textContent = ('0'+h).slice(-2) + ':' + ('0'+d.getMinutes()).slice(-2);
          }
          tick(); setInterval(tick, 15000);
        })();
        </script>
        </body></html>
        """
    }

    static func error(url: String, message: String) -> String {
        let dir = AppLanguage.current.hasPrefix("ar") ? "rtl" : "ltr"
        return """
        <!doctype html><html data-pano="error" lang="\(AppLanguage.current)" dir="\(dir)"><head><meta charset="utf-8"><meta name="viewport" content="width=1600">
        <title>\(esc(L("Couldn't open the page")))</title>\(style)</head><body><div class="bg"></div><div class="err">
        <div class="icon">!</div>
        <h1>\(esc(L("Couldn't open the page")))</h1>
        <p>\(esc(message))</p>
        <p><span class="url">\(esc(url))</span></p>
        <p style="margin-top:40px">\(esc(L("Hold the select button and choose Reload from the menu to try again.")))</p>
        </div></body></html>
        """
    }

    // MARK: Sayfa yüklenince

    /// Yeni pencereleri sekmeye yönlendirir, hedefli bağlantıları aynı sekmede açar,
    /// yazı boyutunu ve (açıksa) reklam gizleme CSS'ini uygular.
    static func afterLoad(textScale: Int, adBlock: Bool) -> String {
        """
        (function(){
          try {
            if (!window.__panoPatched) {
              window.__panoPatched = true;
              window.open = function(u){
                try { if (u) { location.href = 'pano://newtab?url=' + encodeURIComponent(new URL(u, location.href).href); } } catch(e) {}
                return { closed:false, close:function(){}, focus:function(){}, blur:function(){}, postMessage:function(){}, location:{}, document:document };
              };
            }
            var links = document.querySelectorAll('a[target]');
            for (var i=0;i<links.length;i++){ links[i].removeAttribute('target'); }
            document.documentElement.style.webkitTextSizeAdjust = '\(textScale)%';
            if (\(adBlock) && !document.getElementById('__pano_ab')) {
              var s = document.createElement('style'); s.id = '__pano_ab';
              s.textContent = \(jsString(AdBlocker.cosmeticCSS));
              (document.head || document.documentElement).appendChild(s);
            }
          } catch(e) {}
        })();
        """
    }

    /// Sayfanın tamamını yakınlaştırır: görünüm alanı (viewport) genişliği daraltılınca
    /// web görünümü sayfayı ekrana sığdırmak için büyütür. %100 orijinal hâline döndürür.
    static func applyZoom(_ zoom: Int) -> String {
        """
        (function(z){
          var de = document.documentElement;
          if (!de || de.getAttribute('data-pano') || de.getAttribute('data-pano-reader')) return 'skip';
          if (!window.__panoBaseW) window.__panoBaseW = window.innerWidth;
          var m = document.querySelector('meta[name="viewport"]');
          if (!m) {
            if (z === 100) return 'same';
            m = document.createElement('meta'); m.setAttribute('name', 'viewport');
            (document.head || de).appendChild(m);
          }
          if (window.__panoOrigVP === undefined) window.__panoOrigVP = m.getAttribute('content') || '';
          if (z === 100) { m.setAttribute('content', window.__panoOrigVP || ('width=' + window.__panoBaseW)); return 'reset'; }
          m.setAttribute('content', 'width=' + Math.round(window.__panoBaseW * 100 / z));
          return 'ok';
        })(\(zoom))
        """
    }

    // MARK: İmleç

    /// Ortak yardımcı: imleç konumunu sayfa içindeki öğeye çevirir (aynı kaynaklı iframe'lere de iner).
    private static let prelude = """
    function __panoAt(vw, ox, oy, px, py){
      var s = vw / (window.innerWidth || vw);
      var x = (ox + px) / s - (window.pageXOffset||0), y = (oy + py) / s - (window.pageYOffset||0);
      var el = document.elementFromPoint(x, y);
      try {
        while (el && (el.tagName==='IFRAME'||el.tagName==='FRAME') && el.contentDocument) {
          var r = el.getBoundingClientRect(); x -= r.left; y -= r.top;
          var inner = el.contentDocument.elementFromPoint(x, y);
          if (!inner) break; el = inner;
        }
      } catch(e) {}
      return { el: el, x: x, y: y };
    }
    function __panoVideo(el){
      var v = el && (el.tagName==='VIDEO' ? el : (el.closest ? el.closest('video') : null));
      if (!v) return null;
      var s = v.currentSrc || v.src;
      if (!s) { var so = v.querySelector('source'); if (so) s = so.src; }
      return (s && /^https?:/i.test(s)) ? { src: s, t: v.currentTime || 0 } : null;
    }
    var __panoClickable = 'a,button,input,select,textarea,label,summary,video,[onclick],[role=button],[role=link],[role=tab],[role=menuitem],[tabindex]';
    """

    /// Bir çerçevenin içinde, o çerçevenin görünüm koordinatlarındaki (x, y) noktasına tıklar.
    /// iframe'e denk gelirse içine girmez; `{kind:'frame', index, x, y}` döndürür ve tıklama Swift tarafında
    /// o iframe'in kendi çerçevesine iletilir (başka siteden gelen oynatıcılar dahil).
    private static let clickCore = """
    function __panoClickAt(x, y){
      var el = document.elementFromPoint(x, y);
      if (!el) return JSON.stringify({kind:'none'});
      if (el.tagName==='IFRAME' || el.tagName==='FRAME') {
        var idx = -1;
        for (var i=0;i<window.frames.length;i++){ try { if (window.frames[i] === el.contentWindow) { idx = i; break; } } catch(e) {} }
        if (idx >= 0) {
          var r = el.getBoundingClientRect();
          return JSON.stringify({kind:'frame', index:idx, x: x - r.left - (el.clientLeft||0), y: y - r.top - (el.clientTop||0)});
        }
      }
      var tag = (el.tagName||'').toLowerCase();
      var type = (el.getAttribute && (el.getAttribute('type')||'') || '').toLowerCase();
      var textTypes = ['','text','search','email','url','tel','password','number'];
      var label = el.getAttribute && (el.getAttribute('placeholder')||el.getAttribute('aria-label')||el.getAttribute('name')||'') || '';
      if ((tag==='input' && textTypes.indexOf(type)>=0) || tag==='textarea' || el.isContentEditable) {
        window.__panoField = el;
        try { el.focus(); } catch(e) {}
        var val = el.isContentEditable ? el.innerText : el.value;
        return JSON.stringify({kind:'input', type:type, value:val||'', label:label});
      }
      if (tag==='select') {
        window.__panoField = el;
        var opts = [];
        for (var k=0;k<el.options.length;k++){ opts.push(el.options[k].text); }
        return JSON.stringify({kind:'select', options:opts, selected:el.selectedIndex, label:label});
      }
      var vid = __panoVideo(el);
      if (vid) return JSON.stringify({kind:'video', src:vid.src, t:vid.t, href:location.href});
      var a = el.closest ? el.closest('a') : null;
      if (a && a.getAttribute('target')) a.removeAttribute('target');
      var o = {bubbles:true,cancelable:true,view:window,clientX:x,clientY:y};
      try { ['pointerover','pointerdown'].forEach(function(n){ el.dispatchEvent(new PointerEvent(n,o)); }); } catch(e) {}
      ['mouseover','mousedown'].forEach(function(n){ el.dispatchEvent(new MouseEvent(n,o)); });
      try { el.dispatchEvent(new PointerEvent('pointerup',o)); } catch(e) {}
      el.dispatchEvent(new MouseEvent('mouseup',o));
      if (typeof el.click === 'function') { el.click(); } else { el.dispatchEvent(new MouseEvent('click',o)); }
      return JSON.stringify({kind:'click', tag:tag});
    }
    """

    /// Medya güvenliği: (1) Eski WebKit, `crossorigin` öznitelikli video CORS hatası alınca çöküyor; altyazıları kendimiz
    /// yüklediğimiz için bu öznitelik kaldırılır. (2) Videolar sayfada oynatılmaz (`play()` yalnızca işaret bırakır,
    /// autoplay kaldırılır); Pano işareti görüp videoyu tvOS oynatıcısında açar.
    static let mediaSafety = """
    (function(){
      try {
        if (!window.__panoMediaSafe) {
          window.__panoMediaSafe = true;
          var MP = window.HTMLMediaElement && HTMLMediaElement.prototype;
          if (MP) {
            try { Object.defineProperty(MP, 'crossOrigin', { configurable: true, get: function(){ return null; }, set: function(){} }); } catch(e) {}
            // play(): web motorunda oynatma yerine isteği işaretle; Pano videoyu tvOS oynatıcısında açar.
            MP.play = function(){ this.__panoPlayRequested = Date.now(); return Promise.resolve(); };
            try { MP.webkitEnterFullscreen = function(){ this.__panoPlayRequested = Date.now(); }; } catch(e) {}
            var origSet = Element.prototype.setAttribute;
            Element.prototype.setAttribute = function(n, v){
              if (this instanceof HTMLMediaElement && String(n).toLowerCase() === 'crossorigin') return;
              return origSet.apply(this, arguments);
            };
          }
        }
        var ms = document.querySelectorAll('video[crossorigin],audio[crossorigin]');
        for (var i=0;i<ms.length;i++){ ms[i].removeAttribute('crossorigin'); }
        var as = document.querySelectorAll('video[autoplay],audio[autoplay]');
        for (var j=0;j<as.length;j++){ as[j].removeAttribute('autoplay'); try { as[j].autoplay = false; } catch(e) {} }
      } catch(e) {}
    })()
    """

    /// Ana çerçevede, imleç konumuna tıklar.
    static func click(_ p: Pointer) -> String {
        """
        (function(){
          \(prelude)
          \(clickCore)
          var s = \(p.viewWidth) / (window.innerWidth || \(p.viewWidth));
          var x = (\(p.offsetX) + \(p.x)) / s - (window.pageXOffset||0);
          var y = (\(p.offsetY) + \(p.y)) / s - (window.pageYOffset||0);
          return __panoClickAt(x, y);
        })()
        """
    }

    /// Bir alt çerçevede (iframe), çerçevenin kendi koordinatlarıyla tıklar.
    static func clickInFrame(x: Double, y: Double) -> String {
        """
        (function(){
          \(prelude)
          \(clickCore)
          return __panoClickAt(\(x), \(y));
        })()
        """
    }

    /// İmleç tıklanabilir bir şeyin üstünde mi? Ayrıca açılır menüler çalışsın diye fare-üstü olayları gönderir.
    static func hover(_ p: Pointer) -> String {
        """
        (function(){
          \(prelude)
          var hit = __panoAt(\(p.args)); var el = hit.el;
          var o = {bubbles:true,cancelable:true,view:window,clientX:hit.x,clientY:hit.y};
          if (el !== window.__panoHover) {
            try { if (window.__panoHover) window.__panoHover.dispatchEvent(new MouseEvent('mouseout',o)); } catch(e) {}
            window.__panoHover = el;
            try { if (el) el.dispatchEvent(new MouseEvent('mouseover',o)); } catch(e) {}
          }
          try { if (el) el.dispatchEvent(new MouseEvent('mousemove',o)); } catch(e) {}
          if (!el || !el.closest) return '0';
          var c = el.closest(__panoClickable);
          if (c && c !== document.body) return '1';
          try { if (getComputedStyle(el).cursor === 'pointer') return '1'; } catch(e) {}
          return '0';
        })()
        """
    }

    /// İmlecin altındaki bağlantının adresi (yoksa boş).
    static func linkAt(_ p: Pointer) -> String {
        """
        (function(){
          \(prelude)
          var el = __panoAt(\(p.args)).el;
          var a = el && el.closest ? el.closest('a[href]') : null;
          if (!a) return '';
          var h = a.href || '';
          return /^https?:/i.test(h) ? h : '';
        })()
        """
    }

    // MARK: Formlar

    static func setFieldValue(_ value: String, submit: Bool) -> String {
        """
        (function(v, submit){
          var f = window.__panoField; if(!f) return;
          try { f.focus(); } catch(e) {}
          if (f.isContentEditable) { f.innerText = v; }
          else {
            var proto = f.tagName==='TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            var d = Object.getOwnPropertyDescriptor(proto,'value');
            if (d && d.set) d.set.call(f, v); else f.value = v;
          }
          f.dispatchEvent(new Event('input',{bubbles:true}));
          f.dispatchEvent(new Event('change',{bubbles:true}));
          if (submit) {
            ['keydown','keypress','keyup'].forEach(function(n){
              f.dispatchEvent(new KeyboardEvent(n,{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true,cancelable:true}));
            });
            if (f.form) { if (f.form.requestSubmit) f.form.requestSubmit(); else f.form.submit(); }
          }
        })(\(jsString(value)), \(submit))
        """
    }

    static func setSelectIndex(_ index: Int) -> String {
        """
        (function(i){ var f = window.__panoField; if(!f) return;
          f.selectedIndex = i;
          f.dispatchEvent(new Event('input',{bubbles:true}));
          f.dispatchEvent(new Event('change',{bubbles:true}));
        })(\(index))
        """
    }

    // MARK: Video

    /// Bu çerçevedeki videolar: kaynak adresi, oynuyor mu, konum, blob (MSE) mi, sayfa adresi (Referer için).
    static let videos = """
    (function(){
      var out = [], vs = document.querySelectorAll('video');
      for (var i=0;i<vs.length;i++){
        var v = vs[i], s = v.currentSrc || v.src;
        if (!s) { var so = v.querySelector('source'); if (so) s = so.src; }
        if (!s) continue;
        out.push({src:s, t:v.currentTime||0, paused:!!v.paused && !v.__panoPlayRequested, req:v.__panoPlayRequested||0, blob:/^blob:/i.test(s), playable:/^https?:/i.test(s), href:location.href});
      }
      return JSON.stringify(out);
    })()
    """

    /// Bu çerçevedeki altyazılar: videoların metin izleri (satırlarıyla), `<track>` dosyaları ve sayfa
    /// kaynağında / oynatıcı ayarlarında geçen .vtt/.srt adresleri.
    static let subtitles = #"""
    (function(){
      var out = {tracks:[], urls:[], href: location.href};
      var vs = document.querySelectorAll('video');
      for (var i=0;i<vs.length;i++){
        var v = vs[i];
        try {
          for (var j=0;j<v.textTracks.length;j++){
            var tt = v.textTracks[j];
            if (tt.kind !== 'subtitles' && tt.kind !== 'captions') continue;
            if (tt.mode === 'disabled') tt.mode = 'hidden';
            var cues = [], c = tt.cues;
            if (c) for (var k=0;k<c.length && k<5000;k++){ cues.push([c[k].startTime, c[k].endTime, c[k].text || '']); }
            if (cues.length) out.tracks.push({label: tt.label || '', lang: tt.language || '', cues: cues});
          }
        } catch(e) {}
        var trs = v.querySelectorAll('track[src]');
        for (var t=0;t<trs.length;t++){ out.urls.push({src: trs[t].src, label: trs[t].label || '', lang: trs[t].srclang || ''}); }
      }
      try {
        var html = document.documentElement.outerHTML.replace(/\\\//g, '/');
        var re = /["'(=]((?:https?:)?[^"'()\s<>=]*?\.(?:vtt|srt)(?:\?[^"'()\s<>]*)?)["')\s]/gi, m, n = 0;
        while ((m = re.exec(html)) && n < 40) {
          n++;
          try {
            var u = new URL(m[1], location.href).href;
            var around = html.substr(Math.max(0, m.index - 160), 320);
            var lm = around.match(/label["']?\s*[:=]\s*["']([^"']{1,40})["']/i);
            var gm = around.match(/(?:srclang|language|lang)["']?\s*[:=]\s*["']([^"']{1,10})["']/i);
            out.urls.push({src: u, label: lm ? lm[1] : '', lang: gm ? gm[1] : ''});
          } catch(e) {}
        }
      } catch(e) {}
      return JSON.stringify(out);
    })()
    """#

    /// Sayfadaki "sonraki bölüm" bağlantısı (yoksa boş).
    static let nextEpisode = #"""
    (function(){
      var as = document.querySelectorAll('a[href]'), best = '', score = 0;
      for (var i=0;i<as.length;i++){
        var a = as[i], href = a.href || '';
        if (!/^https?:/i.test(href) || href.split('#')[0] === location.href.split('#')[0]) continue;
        var t = ((a.innerText||'') + ' ' + (a.getAttribute('title')||'') + ' ' + (a.getAttribute('aria-label')||'') + ' ' +
                 (a.className||'') + ' ' + (a.id||'')).toLowerCase();
        var rel = (a.getAttribute('rel')||'').toLowerCase();
        var s = 0;
        if (/sonraki\s*b[öo]l[üu]m|next\s*episode|sonraki-bolum|next-episode|nextep/.test(t)) s = 10;
        else if (/(sonraki|next|ileri)/.test(t) && /(b[öo]l[üu]m|bolum|episode|\bep\b)/.test(t + ' ' + href.toLowerCase())) s = 8;
        else if (rel === 'next' && /(b[öo]l[üu]m|bolum|episode)/.test(href.toLowerCase())) s = 6;
        if (s > score) { score = s; best = href; }
      }
      return best;
    })()
    """#

    /// Alternatif oynatıcı / kaynak düğmeleri ("Kaynak 1", "Alternatif", "Türkçe Dublaj", data-frame…).
    /// Bulunanlar window.__panoSources'a kaydedilir; seçim `selectSource(i)` ile yapılır.
    static let sources = #"""
    (function(){
      // Yalnızca oynatıcısı olan sayfalarda (iframe / video) — diğer sitelerde dil bağlantıları vb. karışmasın
      if (!document.querySelector('iframe, video, [class*="player"], [id*="player"]')) { window.__panoSources = []; return '[]'; }
      var strong = /(kaynak|alternatif|player|oynat[ıi]c[ıi]|sunucu|server|partition|part\s*\d)/i;
      var weak = /(dublaj|altyaz[ıi]|t[üu]rk[çc]e|orijinal|ingilizce|720|1080|\bhd\b)/i;
      var avoid = /(film|dizi|kategori|filmler|diziler|t[üu]r[üu]|giri[şs]|kay[ıi]t|ileti[şs]im|yorum|payla[şs])/i;
      var dataAttrs = ['data-frame','data-src','data-url','data-video','data-embed','data-link','data-iframe','data-player'];
      var els = document.querySelectorAll('a,button,li,span,div,option');
      var out = [], seen = {};
      window.__panoSources = [];
      for (var i=0;i<els.length && out.length<25;i++){
        var el = els[i];
        if (!el.getClientRects().length && el.tagName !== 'OPTION') continue;
        var text = (el.innerText || el.textContent || '').replace(/\s+/g,' ').trim();
        var data = '';
        for (var k=0;k<dataAttrs.length;k++){ var v = el.getAttribute(dataAttrs[k]); if (v) { data = v; break; } }
        var hasData = !!data && /(\/\/|embed|player|video|\.php|\?)/i.test(data);
        if (text.length > 40 || (!text && !hasData)) continue;
        var tag = el.tagName;
        if ((tag === 'DIV' || tag === 'SPAN' || tag === 'LI') && el.querySelector('a,button,li,div,span') && !hasData) continue;
        var href = tag === 'A' ? (el.getAttribute('href') || '') : '';
        var navigates = href && href !== '#' && !/^javascript:/i.test(href);
        var ok = hasData || strong.test(text) || (!navigates && weak.test(text));
        if (!ok || (avoid.test(text) && !strong.test(text))) continue;
        if (navigates && !strong.test(text) && !hasData) continue;
        var key = text + '|' + data;
        if (seen[key]) continue;
        seen[key] = 1;
        var cls = (el.className && el.className.baseVal === undefined ? el.className : '') + ' ' + (el.parentElement ? el.parentElement.className : '');
        window.__panoSources.push(el);
        out.push({ text: text || data, active: /(^|\s)(active|selected|current|aktif)(\s|$)/i.test(String(cls)) });
      }
      return JSON.stringify(out);
    })()
    """#

    static func selectSource(_ index: Int) -> String {
        """
        (function(i){
          var el = (window.__panoSources || [])[i]; if (!el) return 'yok';
          if (el.tagName === 'OPTION') { var sel = el.parentElement; sel.value = el.value; sel.dispatchEvent(new Event('change',{bubbles:true})); return 'ok'; }
          try { el.scrollIntoView({block:'center'}); } catch(e) {}
          var r = el.getBoundingClientRect(), o = {bubbles:true,cancelable:true,view:window,clientX:r.left+r.width/2,clientY:r.top+r.height/2};
          ['mouseover','mousedown','mouseup'].forEach(function(n){ el.dispatchEvent(new MouseEvent(n,o)); });
          if (typeof el.click === 'function') el.click(); else el.dispatchEvent(new MouseEvent('click',o));
          return 'ok';
        })(\(index))
        """
    }

    /// Sayfadaki en büyük oynatıcı alanı (iframe / video / "player" sınıflı öğe): görünüm koordinatları + kaydırma.
    static let playerRect = #"""
    (function(){
      var best = null, area = 0;
      var els = document.querySelectorAll('iframe, video, [class*="player"], [id*="player"], [class*="video"], [id*="video"]');
      for (var i=0;i<els.length;i++){
        var r = els[i].getBoundingClientRect();
        if (r.width < 250 || r.height < 140) continue;
        var a = r.width * r.height;
        if (els[i].tagName === 'IFRAME' || els[i].tagName === 'VIDEO') a *= 1.5;
        if (a > area) { area = a; best = r; }
      }
      if (!best) return '';
      return JSON.stringify({x: best.left + best.width/2, y: best.top + best.height/2,
        px: window.pageXOffset||0, py: window.pageYOffset||0, iw: window.innerWidth});
    })()
    """#

    #if DEBUG
    static let jsBenchmark = """
    (function(){ var t0 = Date.now(), x = 0; for (var i = 0; i < 30000000; i++) { x = (x + i * 7) % 1000003; }
      var t1 = Date.now(); return 'dongu=' + (t1 - t0) + 'ms wasm=' + (typeof WebAssembly) + ' x=' + x; })()
    """
    #endif

    static let pauseVideos = "(function(){var v=document.querySelectorAll('video');for(var i=0;i<v.length;i++){try{v[i].pause()}catch(e){}}})()"

    // MARK: Okuma modu

    /// Sayfadaki ana metni bulur (en çok paragraf metni içeren kapsayıcı), geri kalan her şeyi atar
    /// ve TV'de rahat okunacak büyük yazılı, koyu bir sayfa olarak yeniden çizer.
    static let reader = """
    (function(){
      var de = document.documentElement;
      if (de.getAttribute('data-pano-reader')) return 'already';
      function esc(s){ return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
      var ps = document.querySelectorAll('p, pre, blockquote, li');
      var scored = [], best = null, bestScore = 0;
      function add(el, v){ if (!el || el === document.body || el === de) return; if (el.__panoScore === undefined) { el.__panoScore = 0; scored.push(el); } el.__panoScore += v; }
      for (var i=0;i<ps.length;i++){
        var t = (ps[i].textContent||'').replace(/\\s+/g,' ').trim().length;
        if (t < 40) continue;
        if (ps[i].tagName === 'LI') t = t / 3;
        var par = ps[i].parentElement;
        add(par, t); if (par) add(par.parentElement, t/2);
      }
      for (var j=0;j<scored.length;j++){ if (scored[j].__panoScore > bestScore) { bestScore = scored[j].__panoScore; best = scored[j]; } }
      if (!best || bestScore < 500) return 'fail';
      var c = best.cloneNode(true);
      var kill = c.querySelectorAll('script,style,noscript,iframe,form,button,input,select,textarea,nav,aside,footer,svg,canvas,video,audio,object,embed,[role=navigation],[aria-hidden=true],.ad,.ads,.advert,.advertisement,.share,.social,.related,.comments,.newsletter');
      for (var k=0;k<kill.length;k++){ if (kill[k].parentNode) kill[k].parentNode.removeChild(kill[k]); }
      var imgs = c.querySelectorAll('img');
      for (var m=0;m<imgs.length;m++){
        var im = imgs[m];
        var src = im.getAttribute('data-src') || im.getAttribute('data-lazy-src') || im.getAttribute('data-original') || im.getAttribute('src');
        if (src) { try { im.setAttribute('src', new URL(src, location.href).href); } catch(e) {} }
      }
      var as = c.querySelectorAll('a[href]');
      for (var n=0;n<as.length;n++){ try { as[n].setAttribute('href', new URL(as[n].getAttribute('href'), location.href).href); } catch(e) {} }
      var keep = {src:1, href:1, alt:1};
      var all = c.querySelectorAll('*');
      for (var q=0;q<all.length;q++){
        var at = all[q].attributes;
        for (var r=at.length-1;r>=0;r--){ if (!keep[at[r].name]) all[q].removeAttribute(at[r].name); }
      }
      var h1 = document.querySelector('h1');
      var title = (h1 && h1.textContent.trim()) || document.title;
      var firstH1 = c.querySelector('h1'); if (firstH1 && firstH1.textContent.trim() === title) firstH1.parentNode.removeChild(firstH1);
      var css = 'html,body{margin:0;background:#15171c;color:#e8e6e1}' +
        'body{font-family:Georgia,"Times New Roman",serif;font-size:30px;line-height:1.65}' +
        'article{max-width:1150px;margin:0 auto;padding:60px 60px 160px}' +
        '.site{font-family:-apple-system,Helvetica,sans-serif;color:#8b919c;font-size:22px;margin-bottom:12px}' +
        'h1{font-size:46px;line-height:1.25;margin:0 0 36px;color:#fff}' +
        'h2,h3,h4{color:#fff;line-height:1.3}' +
        'img,figure{max-width:100%;height:auto;margin:20px 0;border-radius:12px}' +
        'a{color:#8ab4ff}pre,code{font-size:24px;white-space:pre-wrap}' +
        'blockquote{border-left:6px solid #3a3f4b;margin:0;padding-left:30px;color:#c8c5bf}';
      de.innerHTML = '<head><meta charset="utf-8"><meta name="viewport" content="width=1400"><title>' + esc(document.title) +
        '</title><style>' + css + '</style></head><body><article><div class="site">' + esc(location.hostname) +
        '</div><h1>' + esc(title) + '</h1>' + c.innerHTML + '</article></body>';
      de.setAttribute('data-pano-reader', '1');
      window.scrollTo(0, 0);
      return 'ok';
    })()
    """

    // MARK: Sayfada bul

    static let findClear = """
    (function(){
      var ms = document.querySelectorAll('mark.__pano_hl');
      for (var i=0;i<ms.length;i++){ var m = ms[i], p = m.parentNode; if (!p) continue; p.replaceChild(document.createTextNode(m.textContent), m); p.normalize(); }
    })()
    """

    /// Eşleşmeleri sarı vurgular, eşleşme sayısını döndürür (en fazla 300).
    static func findAll(_ query: String) -> String {
        """
        (function(q){
          \(findClear);
          if (!q || !document.body) return 0;
          var ql = q.toLowerCase();
          var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode: function(n){
            var p = n.parentNode; if (!p) return 2;
            var t = p.nodeName; if (t==='SCRIPT'||t==='STYLE'||t==='NOSCRIPT'||t==='TEXTAREA') return 2;
            return n.nodeValue.toLowerCase().indexOf(ql) >= 0 ? 1 : 2;
          }});
          var nodes = []; while (w.nextNode()) nodes.push(w.currentNode);
          var count = 0;
          for (var i=0;i<nodes.length && count<300;i++){
            var n = nodes[i], idx;
            while (n && (idx = n.nodeValue.toLowerCase().indexOf(ql)) >= 0 && count < 300) {
              var hit = n.splitText(idx); var rest = hit.splitText(q.length);
              var m = document.createElement('mark'); m.className = '__pano_hl';
              m.style.cssText = 'background:#ffe14d;color:#000;border-radius:3px';
              hit.parentNode.replaceChild(m, hit); m.appendChild(hit);
              n = rest; count++;
            }
          }
          return count;
        })(\(jsString(query)))
        """
    }

    /// i. eşleşmeyi turuncu yapar ve sayfa içindeki konumunu döndürür.
    static func findFocus(_ index: Int) -> String {
        """
        (function(i){
          var ms = document.querySelectorAll('mark.__pano_hl'); if (!ms.length) return '';
          for (var j=0;j<ms.length;j++){ ms[j].style.background = (j===i) ? '#ff8c1a' : '#ffe14d'; }
          var r = ms[i].getBoundingClientRect();
          return JSON.stringify({x: r.left + (window.pageXOffset||0), y: r.top + (window.pageYOffset||0), iw: window.innerWidth});
        })(\(index))
        """
    }
}
