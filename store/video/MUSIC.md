# Müzik ve sürelerin nereden geldiği

Parça: **Sunset 52 — Jeremy Black**, `Sunset 52 - Jeremy Black.mp3`
(159 sn, 320 kbps). YouTube Ses Arşivi'nden seçildi.

Lisans, Ses Arşivi'nin en geniş kademesi ve indirme sayfasında şöyle
yazıyor:

> "Bu ses parçasını, para kazandığınız videolar dahil tüm videolarınızda
> kullanabilirsiniz. Atıf gerekmez."

Yani ticari kullanım serbest ve açıklamaya hiçbir şey yazmak gerekmiyor —
Play mağaza videosu, ücretli reklam, sosyal medya, hepsi kapsam içinde.

## Sürelerin tamamı bu parçadan türetildi

Parça ölçüldü, tahmin edilmedi:

| Ölçüm | Değer |
|---|---|
| Tempo | 126 BPM |
| Vuruş | 0.476 sn |
| Ölçü (4/4) | **1.904 sn** |
| İlk vuruş | 0.000 sn — parça sessizlikle değil, vuruşla başlıyor |

Enerji eğrisi (yarım saniyelik pencerelerde RMS) parçanın 19.5–22.5 saniye
arasında belirgin bir düşüş yaptığını gösterdi: −17.6 dB'ye inip 23. saniyede
tekrar tam seviyeye çıkıyor. Bu bir bölüm sonu, yani kesilecek yer orası.

Buradan:

```
SCENE_SECONDS = 2 * BAR + 0.45   = 4.258 sn   (iki ölçü + devrettiği geçiş)
END_SECONDS   = 3 * BAR          = 5.712 sn
toplam                           = 20.944 sn
```

Sonuç, her geçişin bir vuruşun üstüne düşmesi:

| Geçiş | Saniye | Ölçü |
|---|---|---|
| 1 → 2 | 3.808 | 2 |
| 2 → 3 | 7.616 | 4 |
| 3 → 4 | 11.424 | 6 |
| 4 → kapanış | 15.232 | 8 |
| bitiş | 20.944 | 11 |

Filmin bittiği 20.944, parçanın nefes aldığı aralığın içinde bir ölçü başı.
Kapanış kartı üç ölçü tuttuğu için logo, parçanın 12–16. saniyedeki
yükselişinin üstüne oturuyor ve film çözülerek bitiyor, kesilerek değil.

Bu hizalama bir şans eseriyle başladı: kurgu müzikten önce yapılmıştı ve
18.90 saniye sürüyordu, yani 19.04'teki ölçü başına 140 milisaniye uzaktaydı.
Sahneleri 4.3'ten 4.258'e çekmek tamamını yerine oturttu.

## Miks

`make_video.py` içinde: 0.06 sn giriş yumuşatması (örneğin ortasından
başlamanın çıkardığı tık için), 0.5 sn çıkış, kazanç 0.9. Çıkışın tepe değeri
0.908 — kırpma yok. AAC 160 kbps.

## Parçayı değiştirmek

Yeni parçanın tempo ve bölüm yapısını aynı yöntemle ölç, `BAR` değerini
güncelle, `MUSIC` sabitini yeni dosya adına çevir. Süreler `BAR`'dan
türediği için gerisi kendiliğinden oturur.

Dosya yoksa betik sessiz ama sesli-akışlı bir video üretir — Play ve akış
platformları ses akışı olmayan dosyayı reddedebiliyor.
