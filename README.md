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

## Tasarım

Koyu zemin üzerinde mor → pembe vurgular ve cam (blur) yüzeyler. Katmanlı (parallax) tvOS ikonu ve Top Shelf görselleri
`scripts/make-icons.py` ile üretilir (`python3 scripts/make-icons.py . onizleme.png`, Pillow gerekir); aynı görsel dil ana sayfada (selamlama, saat, site simgeli kutucuklar),
kendiliğinden gizlenen yüzen üst çubukta, iPadOS tarzı imleçte, cam bildirimlerde ve telefon kumanda sayfasında kullanılır
(`Pano/Theme.swift`).

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
  Oynatıcı açılırken sitenin harici altyazıları (`<track>`, sayfadaki oynatıcının yüklediği satırlar, ağdan istenen
  `.vtt`/`.srt` dosyaları, oynatıcı ayarlarında geçen adresler) toplanır ve videonun üstünde gösterilir; Türkçe olan
  otomatik seçilir, Windows-1254 SRT'ler doğru çözülür. Oynatıcının üst çubuğunda altyazı seçimi, zamanlama kaydırma
  (±0,5 / ±2 sn) ve yazı boyutu menüleri var. HLS akışına gömülü Türkçe altyazı varsa o seçilir.
  Not: bu motorda `MediaSource` yok; videoyu yalnızca MSE ile oynatan (blob:) ve DRM'li oynatıcılar desteklenmez.
- **Sayfada bul**: tüm eşleşmeleri vurgular, ◀ ▶ ile gezilir
- **Kaldığın yerden izle**: oynatıcı kapanınca (ve her 10 sn'de) konum sayfa adresine göre kaydedilir; aynı sayfada video açılınca
  "Devam et / Baştan başla" sorulur. Ana sayfada "İzlemeye devam" bölümü (ilerleme çubuklu).
- **Sonraki bölüm**: sayfadaki "sonraki bölüm" bağlantısı (yoksa adresteki bölüm numarası +1, "tahmini") bulunur; oynatıcı menüsünde,
  son 2 dakikada ekranda düğme, bölüm bitince 10 sn geri sayım. Yeni sayfada oynatıcı bulunup otomatik tıklanır.
- **Kaynak seçici**: "Kaynak 1 / Alternatif / Türkçe Dublaj / data-frame…" düğmeleri menüde listelenir (kategori bağlantıları hariç).
- **Oynatıcı**: Hız (0,75–2×), Sar (adım 10/15/30/60 sn, "Jeneriği atla +85 sn"), altyazı görünümü (boyut, beyaz/sarı, kutu arka plan).
- **OpenSubtitles**: oynatıcı → Altyazı → İnternetten bul. Ayarlar'dan API anahtarı (opensubtitles.com/consumers), isteğe bağlı giriş.
  Başlıktan film/dizi adı ve sezon/bölüm çıkarılır.
- **Telefondan kontrol**: Menü → Telefondan kontrol (QR). Apple TV'de `:8765` portunda küçük bir web sunucusu açılır (PIN'li);
  telefondan adres/arama gönderme, seçili alana metin yazma, dokunmatik alanla imleç ve kaydırma, geri/ana sayfa/menü, oynat/duraklat.
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
- `-debugAction <eylem> [-debugDelay <sn>]`: `remote`, `next`, `sources`, `subs`, `reader`, `find:kelime`, `zoom:150`, `menu`, `tabs`, `settings`, `newtab:<adres>`, `private`, `hover:x,y`, `play`, `ua`, `videos`, `blocked`
