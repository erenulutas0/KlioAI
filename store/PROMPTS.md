# Görsel üretme prompt'ları

Bir görsel modeline (Gemini, Grok, ChatGPT/DALL·E, Midjourney) verilmek üzere.
İngilizce yazıldı — görsel modeller İngilizce prompt'ta belirgin şekilde daha
iyi sonuç veriyor.

---

## ÖNCE: neyi ürettirme

**Ekran görüntülerini ürettirme.** Google Play'in mağaza listesi politikası,
ekran görüntülerinin uygulamanın gerçek içeriğini göstermesini şart koşuyor.
AI ile üretilmiş sahte bir uygulama ekranı yüklemek reddedilme, tekrarında
hesap askıya alınma sebebidir. `store/play/screenshot_01..07.png` telefondan
gerçek çekim; öyle kalmalı. Bir ekranı beğenmiyorsan çözüm uygulamada o ekranı
düzeltip yeniden çekmek.

**Öne çıkan grafik (1024×500) serbest.** O bir pazarlama afişi. Aşağıdaki
prompt onun için.

**Uygulama simgesi** de serbest ama sonuçları var — en altta.

---

## 1. Öne çıkan grafik (feature graphic)

Play'de **tam 1024×500**, alfa kanalı olmadan. Çoğu model bu oranı doğrudan
vermez; 16:9 ya da 2:1 üretip 1024×500'e kırpman gerekebilir.

> A clean, modern feature banner for a mobile language-learning app called
> KlioAI. Wide horizontal composition, 2:1 aspect ratio.
>
> Background: a smooth diagonal gradient in violet, from #6C4EF5 at the top
> left to #432CB2 at the bottom right. Add a very subtle soft glow behind the
> left third. No noise, no texture, no photographic elements.
>
> Leave the left third visually calm and empty — a logo will be placed there
> afterwards. Leave the right two thirds clear enough for a product name and
> one line of subtitle to be typed over it later.
>
> Optional, kept faint and abstract: a few soft rounded shapes suggesting
> speech bubbles and an open book, at about 10% opacity, in white, arranged
> loosely in the lower right, never crossing the centre.
>
> Absolutely no text, no letters, no words, no numbers anywhere in the image.
> No mockups of phones. No people. No stock-photo look. Flat, calm, premium,
> plenty of empty space.

Metinsiz üretmesi önemli: modeller yazıyı bozuk yazıyor. Logoyu ve yazıyı ben
`make_store.py` ile üstüne net şekilde bindiririm — bana üretilen arka planı
`store/` içine koyduğunu söylemen yeterli.

Yazıyı da modele yazdırmak istersen üsttekine şunu ekle, ama harflerdeki
bozulmaya hazır ol:

> The words "KlioAI" in a bold, friendly, rounded sans-serif, in white, on the
> right side. Below it, in a lighter weight and smaller size: "İngilizceyi
> konuşarak, okuyarak ve tekrar ederek öğren". The Turkish characters ı, İ, ş,
> ğ, ö, ü, ç must be rendered exactly and correctly.

---

## 2. Uygulama simgesi — istersen

Şu anki simge zaten var ve tutarlı: mor zeminde beyaz, elle çizilmiş bir K.
Değiştirmeye karar verirsen aşağıdaki prompt aynı fikri daha temiz kurar.

> A flat vector app icon for a language-learning app called KlioAI. A single
> letter K as the only element, drawn as one continuous rounded stroke, as if
> hand-drawn with a marker but geometrically clean and perfectly balanced.
> Pure white stroke on a solid violet background, hex #6C4EF5. Uniform stroke
> weight, generously rounded stroke ends. Square canvas, the K centred with
> comfortable margins on all four sides. No gradient, no shadow, no outline,
> no 3D, no text, no extra shapes. Simple enough to stay legible at 48
> pixels.

**Değiştirirsen ne yapman gerekir:** simge üç ayrı dosyada yaşıyor ve üçü de
güncellenmeli, yoksa açılış ekranıyla ana ekran farklı görünür.

| Dosya | Ne için |
|---|---|
| `flutter_vocabmaster/assets/images/app_icon_composed.png` | 1024×1024, mağaza ve iOS simgesi |
| `flutter_vocabmaster/assets/images/flat_k_adaptive.png` | Android uyarlanabilir simge ön planı — **kenar boşluğu dolu bir kopya**: birçok launcher simgeyi daireye kırpıyor ve boşluksuz halde K'nin sol bacağı ile sağ kolu kesiliyordu |
| `flutter_vocabmaster/assets/images/flat_k_white.png` | Açılış ekranının Dart tarafında çizdiği işaret |

Sonra `flutter pub run flutter_launcher_icons` ve yeni bir AAB gerekir.
Değiştireceksen söyle, üçünü de ben hazırlayıp doğru boşluklarla keserim.

---

## 3. Diğer diller için ekran görüntüsü

Mağaza listesini İspanyolca/Portekizce/İtalyanca/Fransızca'ya açarsan o diller
için de ekran görüntüsü gerekir — ve onlar da gerçek olmak zorunda. Yolu:
uygulamayı o dile al, aynı yedi ekranı çek, `make_store.py` içindeki `SHOTS`
başlıklarını çevir. Yaklaşık on dakikalık iş; istersen ben yaparım.
