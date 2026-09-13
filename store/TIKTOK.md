# TikTok — sesli klipler (13 Eylül 2026)

Eylül başındaki altı klip (`tiktok/clips/`: bored, light, agree, verylike, home,
explain) **sessizdi** ve bilinçliydi: o zaman ses Piper'dı ve cevap 3–6 saniye
sürüyordu, gösterilecek şey karttı. Bugün en güçlü şey ses: Kokoro ve yaklaşık
bir saniyelik cevap. Yeni klipler bu yüzden **sesli**.

Eski altı klip hâlâ geçerli ve atılmadıysa atılabilir — ama sesli bir klipten
sonra, onun devamı olarak ("aynı uygulama, hatanı böyle düzeltiyor").

---

## Önce: yayın öncesi kontrol

- [ ] **Play Console → Politika → Uygulama içeriği → Reklamlar → "Hayır".**
      Mağaza sayfası şu an "Reklam içerir" diyor; uygulamada tek bir reklam
      SDK'sı yok. Videodan gelip sayfaya bakan biri bunu görüyor.
- [ ] Play Console → İstatistikler'den **bugünkü toplam yükleme sayısını not al**
      (sayfa "10+" diyor). Ölçüm karşılaştırma ister.
- [ ] Telefonda **Rahatsız Etmeyin** açık, kulaklık takılı değil.

---

## Kayıt nasıl yapılır

Samsung hızlı panel → **Ekran kaydedici** → Ses: **"Medya sesleri ve mikrofon"**.

- **Kulaklık yok.** Bluetooth kulaklıkta medya sesi kayda girmeyebilir; Luca'nın
  sesi klibin yarısı.
- Sessiz oda. Mikrofon senin sesini de alıyor, ve klipte senin İngilizcen de
  duyulmalı — kusurlu olması iyi, izleyici kendini görüyor.
- **Her klip için 3–4 deneme.** Model her seferinde biraz farklı cevap veriyor;
  sürprizi (lazanya bitti), kartı ve süreyi en iyi tutturanı seçeriz.
- Kayıtları `store/tiktok/raw/` içine koy ve haber ver. Ben keserim: ilk karede
  kanca yazısı, ortada gerçek konuşma **sesiyle birlikte**, sonda uygulama adı.
  (`make_clip.py` şu an sesi atıyor; sesli kayıtlar gelince onu uyarlayacağım.)

---

## Klip 1 — "Garsonla İngilizce konuştum"

**Neyi satıyor:** konuşmanın gerçek bir konuşma gibi akması ve hızı.

**Kanca (ilk kare):** `Yapay zekâ garsonla İngilizce sipariş verdim 🍝`

**Söyleyeceklerin (Restoranda sahnesi, yeni konuşma):**
1. "Good evening, a table for two, please."
2. "What do you recommend tonight?"
3. "I'll have the lasagne, please."  ← Luca "bitti" diyebilir, bu klibin en iyi anı
4. "Okay, then I'll try that instead."

**Süre:** 20–25 sn. Kesimde bekleme anları kısalır ama **Luca'nın cevaba başlama
süresi kesilmez** — o bir saniye, klibin kanıtı.

**Açıklama:** `Restoranda İngilizce konuşmayı gerçek garson gibi cevap veren
yapay zekâyla deniyorum. Play Store'da: KlioAI 🇬🇧`

---

## Klip 2 — "Kelimeyi unuttum, Türkçe söyledim"

**Neyi satıyor:** rakiplerde görmediğim şey — takıldığın yeri Türkçe söyle,
İngilizcesini öğretsin.

**Kanca:** `İngilizce konuşurken kelimeyi unuttum 😅` / ikinci satır:
`Türkçe söyledim…`

**Söyleyeceklerin (Restoranda):**
1. "I'd like the pasta, and also biraz su alabilir miyiz?"
2. Uygulama "Bunu başka bir dilde duyduk" diyecek ve cümleni gösterecek →
   **Gönder'e bas.**
3. Luca suyu getirir, kart "biraz su alabilir miyiz → could we have some water"
   gösterir. **Klip kartın ekranda kaldığı iki saniyeyle biter.**

**Süre:** 15–20 sn.

**Dikkat:** kart her denemede aynı çıkmayabilir. Kartın "doğrusu" tarafı Türkçe
çıkarsa o denemeyi kullanma — bunu engelleyen bir kontrol var ama kayıtta
görmek istemeyiz.

---

## Klip 3 — "Bu hatayı sen de yapıyor musun?"

Eylül kliplerinin formatı, bu sefer sesli. Tek bir yaygın hata, kart, not.

**Kanca:** `Bunu sen de diyorsun:` / `I prefer a eggplant`

**Söyleyeceğin (Restoranda, Luca patlıcan önerdiğinde ya da doğrudan):**
- "I prefer a eggplant parmigiana."

Kart: "a eggplant → an eggplant", not: *"a" sesli harfle başlayan kelimelerden
önce kullanılmaz.*

**Alternatif hatalar** (aynı klibi farklı cümleyle çekmek için — hepsi cihazda
kart üretti): "I am agree with you", "Can you explain me the menu?", "What do you
recommend dessert?"

---

## Paylaşım sırası

| Gün | Ne | Neden |
|---|---|---|
| 1 | Klip 1 | En geniş kanca, uygulamayı tanıtıyor |
| 2 | Klip 2 | En ayırt edici özellik; 1'i izleyen ikinciyi merak eder |
| 3 | Klip 3 | Format tanıdık, tekrar izlenir |
| 4–9 | Eski sessiz klipler, günde bir | Atılmadıysa |

- Saat: **19:00–22:00** arası, her gün aynı saat.
- Link açıklamada tıklanmıyor; **"Play Store'da KlioAI"** yaz, profil biyografisine
  Play linkini koy.
- İlk saat yorumlara cevap ver. "Hangi uygulama?" sorusu gelecek; cevap kısa:
  "KlioAI, Play Store'da."

## Ölçüm

TikTok kendi izlenmesini gösterir ama asıl soru **yükleme**. Her paylaşımdan
sonraki gün Play Console → İstatistikler → Yeni kullanıcı edinme. Aynı gün hem
TikTok hem Reddit atma — hangisinin getirdiğini ayıramazsın.
