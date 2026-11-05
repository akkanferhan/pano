import Foundation

/// Uygulama içi HTML sayfaları (ana sayfa, hata sayfası) ve sayfalara enjekte edilen betikler.
enum Pages {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

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
    .err{max-width:1200px}
    .err p{font-size:28px;color:#aab2c4}
    </style>
    """

    private static let palettes = [
        ("#4f6bff", "#8a4fff"), ("#ff5f6d", "#ffc371"), ("#11998e", "#38ef7d"),
        ("#fc466b", "#3f5efb"), ("#f7971e", "#ffd200"), ("#00b4db", "#0083b0"),
        ("#8e2de2", "#4a00e0"), ("#e65c00", "#f9d423"),
    ]

    static func home(bookmarks: [Bookmark], engine: SearchEngine) -> String {
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
        <h1>Pano</h1>
        <div class="sub">Apple TV için kişisel tarayıcı</div>
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
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=1600">
        <title>Sayfa açılamadı</title>\(style)</head><body><div class="err">
        <h1>Sayfa açılamadı</h1>
        <p>\(esc(url))</p>
        <p>\(esc(message))</p>
        <p>Menü tuşunu basılı tutarak (ya da seçim tuşuna uzun basarak) menüyü açıp yeniden deneyebilirsin.</p>
        </div></body></html>
        """
    }

    /// Her sayfa yüklendiğinde: yeni pencere açan bağlantıları aynı sekmede açar, yazı boyutunu uygular.
    static func afterLoad(textScale: Int) -> String {
        """
        (function(){
          try {
            window.open = function(u){ if(u){ location.href = u; } return window; };
            var links = document.querySelectorAll('a[target]');
            for (var i=0;i<links.length;i++){ links[i].removeAttribute('target'); }
            document.documentElement.style.webkitTextSizeAdjust = '\(textScale)%';
          } catch(e) {}
        })();
        """
    }

    /// İmlecin altındaki öğeye tıklar. Metin alanıysa, açılır listeyse bunu bildirir (yerel klavye/liste gösterilir).
    static func click(docX: Double, docY: Double) -> String {
        """
        (function(dx,dy){
          var x = dx - (window.pageXOffset||0), y = dy - (window.pageYOffset||0);
          var el = document.elementFromPoint(x,y);
          if(!el) return JSON.stringify({kind:'none'});
          // iframe içine in (aynı kaynaklıysa)
          try {
            while (el && (el.tagName==='IFRAME'||el.tagName==='FRAME') && el.contentDocument) {
              var r = el.getBoundingClientRect();
              x -= r.left; y -= r.top;
              var inner = el.contentDocument.elementFromPoint(x,y);
              if(!inner) break; el = inner;
            }
          } catch(e) {}
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
          var a = el.closest ? el.closest('a') : null;
          if (a && a.getAttribute('target')) a.removeAttribute('target');
          var opts2 = {bubbles:true,cancelable:true,view:window,clientX:x,clientY:y};
          try {
            ['pointerover','pointerdown'].forEach(function(n){ el.dispatchEvent(new PointerEvent(n,opts2)); });
          } catch(e) {}
          ['mouseover','mousedown'].forEach(function(n){ el.dispatchEvent(new MouseEvent(n,opts2)); });
          try { el.dispatchEvent(new PointerEvent('pointerup',opts2)); } catch(e) {}
          el.dispatchEvent(new MouseEvent('mouseup',opts2));
          if (typeof el.click === 'function') { el.click(); }
          else { el.dispatchEvent(new MouseEvent('click',opts2)); }
          return JSON.stringify({kind:'click', tag:tag});
        })(\(docX),\(docY))
        """
    }

    static func setFieldValue(_ jsonString: String, submit: Bool) -> String {
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
        })(\(jsonString), \(submit))
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
}
