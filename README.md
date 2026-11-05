# Pano

Apple TV (tvOS) için kişisel web tarayıcısı.

tvOS'ta WebKit/WKWebView açık API değil. Pano, UIKit içinde çalışma zamanında hâlâ bulunan
`UIWebView` sınıfını `NSClassFromString` ile kullanır (bkz. `Pano/WebEngine.swift`).
Bu özel API sayıldığı için **App Store'a gönderilemez**; yalnızca Xcode ile kendi cihazına yükleme içindir.

## Kurulum (Apple TV'ye yükleme)

1. Apple TV: Ayarlar → Uzaktan Uygulamalar ve Aygıtlar → Mac'teki Xcode ile eşleştir
   (Mac ve Apple TV aynı ağda olmalı; Xcode → Window → Devices and Simulators).
2. `xcodegen generate` (project.yml değişirse) → `Pano.xcodeproj`'u aç.
3. Hedef cihaz olarak Apple TV'yi seç, Run (⌘R).
   Ücretsiz Apple ID ile imzalanan uygulamalar 7 günde bir yeniden yüklenmeli; ücretli geliştirici hesabında 1 yıl.

## Özellikler

- **Sekmeler** (en fazla 8): bağlantıyı yeni sekmede açma, `window.open` açılır pencereleri arka plan sekmesine yönlendirme
- **Kaldığın yerden devam**: açık sekmeler uygulama yeniden açılınca geri gelir (sekmeler ihtiyaç anında yüklenir)
- **Yakınlaştırma**: sayfanın tamamını büyütür (%75–250), site başına hatırlanır; ayrıca varsayılan yakınlaştırma ve yazı boyutu
- **Reklam/izleyici engelleme** (şimdilik varsayılan kapalı, Ayarlar'dan açılır): `URLProtocol` ile ~170 reklam/izleme alan adı engellenir, boş reklam kutuları CSS ile gizlenir
- **Akıllı imleç**: tıklanabilir öğe üstünde büyür ve yavaşlar; açılır menüler için fare-üstü olayları gönderir
- **Okuma modu**: makalenin ana metnini büyük yazılı, koyu bir sayfada gösterir
- **Film sitesi oynatıcıları**: tıklama, başka siteden gelen oynatıcı iframe'lerinin içine iletilir (WebKit1 `WebFrame` API'si köken kısıtına takılmaz).
  Tıklamadan sonra ~12 sn içinde başlayan video ya da ağdan istenen `.m3u8`/`.mp4` adresi yakalanıp tvOS oynatıcısında,
  doğru Referer/Origin başlıklarıyla otomatik açılır. Menüde "Videoyu tam ekran oynat" bulunan tüm adayları listeler.
  Not: bu motorda `MediaSource` yok; videoyu yalnızca MSE ile oynatan (blob:) ve DRM'li oynatıcılar desteklenmez.
- **Sayfada bul**: tüm eşleşmeleri vurgular, ◀ ▶ ile gezilir
- **Sık kullanılanlar**: ekle, sil, yeniden adlandır, adresi düzenle, sırala
- **Geçmiş**: listeleme, arama, temizleme
- **Gizli gezinme**: geçmiş/oturum kaydedilmez; kapanınca (veya uygulama yeniden açılınca) çerezler girişteki hâline döner
- Masaüstü/mobil site (gerçek kullanıcı ajanı iç `WebView` üzerinden ayarlanır), arama motoru, imleç hızı

## Kumanda

| Hareket | İşlev |
|---|---|
| Dokunmatik yüzeyde kaydır | İmleci hareket ettir (kenara itince sayfa kayar) |
| Tıkla | İmlecin altına tıkla; metin alanında klavye, açılır listede seçim, videoda tam ekran oynatıcı |
| Seçim tuşuna basılı tut | Menü |
| Oynat/Duraklat | İmleç ↔ kaydırma modu |
| Oynat/Duraklat'a çift bas | Adres çubuğu |
| Oynat/Duraklat'a basılı tut | Sekmeler |
| Yön tuşları | Sayfayı kaydır (sayfada bul açıkken ◀ ▶ eşleşmeler arasında gezer) |
| Menü / Geri | Bulma vurgusunu / okuma modunu kapat → önceki sayfa → ana sayfa → çıkış |

## Debug başlatma argümanları (yalnızca DEBUG)

- `-openURL <adres>`: açılışta bu adresi aç
- `-hasSeenHelp YES`: yardım penceresini atla
- `-debugClickX <x> -debugClickY <y> [-debugType <metin>]`: 3 sn sonra o noktaya tıkla (ve metin alanına yazıp gönder)
- `-debugAction <eylem> [-debugDelay <sn>]`: `reader`, `find:kelime`, `zoom:150`, `menu`, `tabs`, `settings`, `newtab:<adres>`, `private`, `hover:x,y`, `play`, `ua`, `videos`, `blocked`
