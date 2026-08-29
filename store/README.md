# Play Console görselleri — 1.4.0

`play/` içindekiler doğrudan Play Console'a yüklenebilir. `raw/` ise telefondan
alınan ham ekran görüntüleri; grafiği yeniden üretmek gerekirse kaynak onlar.

Hepsi **gerçek** ekran görüntüsü. Play zaten uydurma görsel istemiyor: mağaza
görselleri uygulamanın gerçek içeriğini göstermek zorunda. Buradaki tek
düzenleme, Play'in kabul ettiği ölçülere oturtmak ve üstüne bir satır Türkçe
başlık koymak.

## Ne nereye

| Dosya | Ölçü | Play Console'da yeri |
|---|---|---|
| `icon_512.png` | 512×512 | Ana mağaza girişi → **Uygulama simgesi** |
| `feature_graphic_1024x500.png` | 1024×500 | Ana mağaza girişi → **Öne çıkan grafik** |
| `screenshot_01..07.png` | 1080×1920 | **Türkçe** girişin telefon ekran görüntüleri |
| `screenshot_en_01..06.png` | 1080×1920 | **İngilizce** (varsayılan) girişin ekran görüntüleri |
| `feature_graphic_1024x500_en.png` | 1024×500 | İngilizce girişin öne çıkan grafiği |

Simge dile göre değişmiyor; öne çıkan grafik ve ekran görüntüleri değişiyor.

Play telefon ekran görüntüsünde 16:9 veya 9:16 istiyor. Bu telefonun ham
çekimi 1080×2340, yani 9:19.5 — **olduğu gibi yüklenirse reddedilir.** Bu
yüzden 1080×1920 tuvale çerçevelendi; durum çubuğu ve gezinme çubuğu da
kırpıldı, çünkü oradaki saat, pil ve bildirim ikonları uygulamaya ait değil.

## Ekran görüntülerinin sırası

Play, listedeki ilk 2–3 kareyi arama sonuçlarında gösteriyor, o yüzden sıra
önemli:

1. **Bugün ne yapacağın belli** — günlük plan
2. **Kafede sipariş ver** — sesli rol yapma sahneleri (Emma, kahve siparişi)
3. **Kelimelerin nerede duruyor** — güç çubuğu, kaynak filtreleri
4. **Unutmadan hemen önce** — aralıklı tekrar kartı
5. **Gerçek kitaplar** — kitaplık, seviyelere göre
6. **Bilmediğin kelimeye dokun** — okuyucu, `gilded` → "altın yaprakla kaplanmış"
7. **Her yol tek yerde** — pratik modları

## Yeniden üretmek

`make_store.py` bunları `raw/` içindeki karelerden kurar. Yeni bir kare
eklemek için ham görüntüyü `raw/` içine koyup betikteki `SHOTS` listesine
dosya adı, başlık ve alt başlığıyla eklemek yeterli.

## İngilizce set neden altı kare

Arayüz çevriliyor, **kayıtlı kelime anlamları çevrilmiyor** — onlar hesabın
ana dili Türkçeyken yazılmış veri. Bu yüzden İngilizce arayüzde Kelimeler
ekranı "puzzled / Kafa karışık, şaşkın" gösteriyor: doğru ama Türkçe
okumayan birine gösterilecek bir liste değil. O kare İngilizce setten çıkarıldı.

Sıra da farklı. Play arama sonuçlarında ilk iki-üç kareyi gösteriyor ve bir
yabancıya bu uygulamayı ikinci kez baktıracak şey konuşma sahneleri ile kitap
okuyucusu, günlük plan değil.

## Diğer diller

Bu görseller Türkçe. Mağaza listesini başka bir dile açarsan o dil için ayrı
ekran görüntüleri gerekir — uygulamayı o dile alıp aynı ekranları çekmek ve
`SHOTS` başlıklarını çevirmek yeterli. Uygulama içi 7 dil desteklemek, mağaza
listesinin 7 dilde olduğu anlamına gelmiyor.
