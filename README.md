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

## Kumanda

| Hareket | İşlev |
|---|---|
| Dokunmatik yüzeyde kaydır | İmleci hareket ettir (kenara itince sayfa kayar) |
| Tıkla | İmlecin altına tıkla; metin alanında klavye, açılır listede seçim penceresi açılır |
| Tıklayıp basılı tut | Menü: adres/arama, ana sayfa, geri/ileri, sık kullanılanlar, geçmiş, ayarlar |
| Oynat/Duraklat | İmleç ↔ kaydırma modu |
| Yön tuşları | Sayfayı kaydır |
| Menü / Geri | Önceki sayfa, sonra ana sayfa, sonra çıkış |

Ayarlar: masaüstü/mobil site, imleç hızı, yazı boyutu, arama motoru, çerez/önbellek temizleme.

## Debug başlatma argümanları (yalnızca DEBUG)

- `-openURL <adres>`: açılışta bu adresi aç
- `-hasSeenHelp YES`: yardım penceresini atla
- `-debugClickX <x> -debugClickY <y> [-debugType <metin>]`: 3 sn sonra o noktaya tıkla (ve metin alanına yazıp gönder)
