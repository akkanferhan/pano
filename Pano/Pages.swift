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

    private static let style = """
    <style>
    *{box-sizing:border-box}
    html,body{margin:0;background:#0d0f14;color:#eef1f7;font-family:-apple-system,Helvetica,sans-serif}
    body{padding:70px 110px}
    h1{font-size:64px;font-weight:700;margin:0 0 8px;letter-spacing:-1px}
    .sub{color:#8a93a6;font-size:24px;margin-bottom:44px}
    form{margin-bottom:56px}
    input{width:100%;font-size:34px;padding:24px 30px;border-radius:20px;border:2px solid #2a3040;background:#171b24;color:#fff;outline:none}
    h2{font-size:28px;color:#8a93a6;font-weight:600;margin:0 0 20px}
    .grid{display:flex;flex-wrap:wrap;gap:26px}
    a.tile{display:flex;flex-direction:column;justify-content:flex-end;width:300px;height:170px;padding:22px;border-radius:22px;text-decoration:none;color:#fff;background:linear-gradient(135deg,var(--a),var(--b));}
    a.tile b{font-size:30px;line-height:38px}
    a.tile span{font-size:18px;line-height:26px;opacity:.75;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .letter{font-size:56px;font-weight:800;opacity:.9;flex:1}
    .private{display:inline-block;background:#5b2bd6;color:#fff;font-size:22px;padding:6px 16px;border-radius:12px;margin-left:16px;vertical-align:middle}
    .err{max-width:1200px}
    .err p{font-size:28px;color:#aab2c4}
    </style>
    """

    private static let palettes = [
        ("#4f6bff", "#8a4fff"), ("#ff5f6d", "#ffc371"), ("#11998e", "#38ef7d"),
        ("#fc466b", "#3f5efb"), ("#f7971e", "#ffd200"), ("#00b4db", "#0083b0"),
        ("#8e2de2", "#4a00e0"), ("#e65c00", "#f9d423"),
    ]

    static func home(bookmarks: [Bookmark], engine: SearchEngine, isPrivate: Bool) -> String {
        let tiles = bookmarks.enumerated().map { i, b -> String in
            let p = palettes[i % palettes.count]
            let host = URL(string: b.url)?.host ?? b.url
            let letter = b.title.first.map { String($0).uppercased() } ?? "•"
            return """
            <a class="tile" style="--a:\(p.0);--b:\(p.1)" href="\(esc(b.url))"><div class="letter">\(esc(letter))</div><b>\(esc(b.title))</b><span>\(esc(host))</span></a>
            """
        }.joined()
        return """
        <!doctype html><html data-pano="home"><head><meta charset="utf-8"><meta name="viewport" content="width=1600">
        <title>Ana Sayfa</title>\(style)</head><body>
        <h1>Pano\(isPrivate ? "<span class=\"private\">Gizli gezinme</span>" : "")</h1>
        <div class="sub">\(isPrivate ? "Geçmiş kaydedilmiyor; gizli moddan çıkınca çerezler eski hâline döner." : "Apple TV için kişisel tarayıcı")</div>
        <form action="pano://search" method="get">
        <input type="search" name="q" placeholder="\(esc(engine.name)) ile ara veya adres yaz">
        </form>
        <h2>Sık Kullanılanlar</h2>
        <div class="grid">\(tiles.isEmpty ? "<div class=\"sub\">Henüz sık kullanılan yok. Bir sitedeyken menüden ekleyebilirsin.</div>" : tiles)</div>
        </body></html>
        """
    }

    static func error(url: String, message: String) -> String {
        """
        <!doctype html><html data-pano="error"><head><meta charset="utf-8"><meta name="viewport" content="width=1600">
        <title>Sayfa açılamadı</title>\(style)</head><body><div class="err">
        <h1>Sayfa açılamadı</h1>
        <p>\(esc(url))</p>
        <p>\(esc(message))</p>
        <p>Seçim tuşuna basılı tutarak menüyü açıp yeniden deneyebilirsin.</p>
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

    /// İmlecin altındaki öğeye tıklar. Metin alanı / açılır liste / video ise bunu bildirir.
    static func click(_ p: Pointer) -> String {
        """
        (function(){
          \(prelude)
          var hit = __panoAt(\(p.args)); var el = hit.el, x = hit.x, y = hit.y;
          if (!el) return JSON.stringify({kind:'none'});
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
            for (var i=0;i<el.options.length;i++){ opts.push(el.options[i].text); }
            return JSON.stringify({kind:'select', options:opts, selected:el.selectedIndex, label:label});
          }
          var vid = __panoVideo(el);
          if (vid) return JSON.stringify({kind:'video', src:vid.src, t:vid.t});
          var a = el.closest ? el.closest('a') : null;
          if (a && a.getAttribute('target')) a.removeAttribute('target');
          var o = {bubbles:true,cancelable:true,view:window,clientX:x,clientY:y};
          try { ['pointerover','pointerdown'].forEach(function(n){ el.dispatchEvent(new PointerEvent(n,o)); }); } catch(e) {}
          ['mouseover','mousedown'].forEach(function(n){ el.dispatchEvent(new MouseEvent(n,o)); });
          try { el.dispatchEvent(new PointerEvent('pointerup',o)); } catch(e) {}
          el.dispatchEvent(new MouseEvent('mouseup',o));
          if (typeof el.click === 'function') { el.click(); } else { el.dispatchEvent(new MouseEvent('click',o)); }
          return JSON.stringify({kind:'click', tag:tag});
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

    /// Sayfadaki doğrudan oynatılabilir (http/https kaynaklı) videolar.
    static let videos = """
    (function(){
      var out = [], vs = document.querySelectorAll('video');
      for (var i=0;i<vs.length;i++){
        var v = vs[i], s = v.currentSrc || v.src;
        if (!s) { var so = v.querySelector('source'); if (so) s = so.src; }
        if (s && /^https?:/i.test(s)) out.push({src:s, t:v.currentTime||0});
      }
      return JSON.stringify(out);
    })()
    """

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
