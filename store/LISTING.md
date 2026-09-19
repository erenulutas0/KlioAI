# KlioAI — mağaza girişi: tek bir şey satmak

Bu dosya kodu okuyarak yazıldı: `nf_tutor_page.dart`, `GroqSpeechToTextService.java`,
`ChatbotService.java`, `TIKTOK.md`, `REDDIT.md`. Aşağıda iddia edilen her şey
bu dosyalarda karşılığı olan bir davranış. Doğrulayamadığım hiçbir şeyi
"kesin çalışıyor" diye yazmadım — böyle bir yer çıkmadı, ama kural bu: emin
olunmayan yerde pazarlama cümlesi değil, "bundan emin değilim" yazılır.

**Gerçekte ne oluyor (kod bunu söylüyor):** Sesli tutor ekranında bir
karakterle (garson, resepsiyonist, doktor) İngilizce konuşuyorsun. Cümlenin
ortasında kelime kaybolunca Türkçe söylüyorsun — mesela "I'd like the pasta,
and also biraz su alabilir miyiz?" (`TIKTOK.md`'nin cihazda test ettiği
örnek). `GroqSpeechToTextService` sesi hem İngilizceye kilitli hem serbest
olmak üzere iki kere okur; ikisi anlaşmıyorsa ("bu İngilizce değildi") sana
kulağına uydurduğu sahte bir İngilizce cümle göstermek yerine, gerçekten
duyduğunu **Türkçe olarak** yazıp önüne koyuyor (`respellInNativeLanguage`).
Bu an otomatik geçmiyor — `NfCaptureResult.needsChecking` bunu "önce onaya
sor" olarak işaretliyor, `nf_tutor_page.dart` da alt kısımda cümleni gösterip
tek dokunuşluk bir **Gönder** düğmesi çıkarıyor ("Bunu başka bir dilde
duyduk." / `tutor.confirm.hint.language`). Gönder'e bastığında konuşma
kesilmiyor, kaldığı yerden sürüyor — model karışık cümleyi anlıyor ve
öyle davranıyor (`ChatbotService.fixInstructions`: "even when your reply
understood them and carried on"). Cevabın altında beliren düzeltme kartında
Türkçe söylediğin kısmın üstü çizili, yanında İngilizcesi duruyor — aynı
`ChatbotService` kuralı: "Anything they said in another language is a
correction too: those words exactly as they said them, then the English
for them."

Yani doğru cümle şu: **tek dokunuşla onaylıyorsun, otomatik değil** — ama
akış kesilmiyor ve rakiplerin çoğunda olmayan bir şey bu (bunu ben
doğrulamadım, senin öncülün; mağaza metnine rakip kıyası olarak koymadım,
çünkü Play bunu onaylamaz ve doğrulanamaz bir iddia olur).

---

## 1. Konumlandırma cümlesi

**TR:** Konuşurken kelimeyi bilmiyorsan Türkçe söyle: KlioAI konuşmayı
sürdürür ve İngilizcesini bir kartla gösterir.

**EN:** Get stuck for a word mid-sentence — say it in Turkish, and KlioAI
keeps the conversation going and shows you the English on a card.

Aşağıdaki her şey bu cümleden çıkıyor: başlık, kısa açıklama, ilk üç ekran
görüntüsü, deney ve uygulamanın ilk ekranı. Biri çelişirse konumlandırma
değil, o diğer şey yanlış.

---

## 2. Play Store metni — kopyalamaya hazır

### Uygulama adı (30 karakter sınırı)

**TR — 30 karakter:**
```
KlioAI: Takılınca Türkçe Söyle
```

**EN — 25 karakter:**
```
KlioAI: Say It in Turkish
```

### Kısa açıklama (80 karakter sınırı)

**TR — 74 karakter:**
```
Takılınca Türkçe söyle: KlioAI konuşmayı sürdürür, İngilizcesini gösterir.
```

**EN — 79 karakter:**
```
Get stuck? Say it in Turkish - the tutor keeps going and shows you the English.
```

### Tam açıklama (4000 karakter sınırı — kısa olan dolgulu olandan iyidir)

**TR — 1763 karakter:**
```
KlioAI, İngilizce öğrenirken herkesin yaşadığı şu ana göre kuruldu: konuşurken cümlenin ortasında kelime kayboluyor.

TAKILINCA TÜRKÇE SÖYLE
Sesli konuşma ekranında bir karakterle İngilizce konuşursun — garson, otel resepsiyonisti, doktor. Cümlenin ortasında bilmediğin kelimeye gelince Türkçesini söyle: "I'd like the pasta, and also biraz su alabilir miyiz?" gibi. KlioAI bunun İngilizce olmadığını fark eder; kulağına uydurma bir İngilizce cümle söylemek yerine, tam olarak ne duyduğunu Türkçe yazıp önüne koyar, sen "Gönder"e basarsın. Konuşma kesilmez, kaldığı yerden sürer — garson suyu getirir. Cevabın altında beliren küçük bir kartta Türkçe söylediğin kısmın üstü çizili, yanında söylemen gereken İngilizcesi duruyor. Kelimeyi unuttuğun an konuşmanın sonu değil, öğrendiğin an oluyor.

Bunun dışında kalan her şey aynı uygulamada: baştan sona okuyabileceğin gerçek kitaplar (Sherlock Holmes, Ezop Masalları, Dr. Jekyll ve Bay Hyde), bilmediğin kelimeye dokunup o cümledeki anlamını görme, kaydettiğin kelimenin tam kaybetmek üzereyken önüne gelen tekrarı, kısa ve biten bir günlük plan, kendi kelimelerinden kurulan çeviri alıştırmaları, örnekli gramer anlatımları ve yazdığın metne AI geri bildirimi.

Arayüz Türkçe dahil yedi dilde; bir düzeltmenin altındaki "neden yanlıştı" satırı da kendi dilinde gelebiliyor. Karşındaki her zaman İngilizce konuşuyor ve İngilizce cevap veriyor — pratiğin sebebi zaten o.

Kelime listesi, tekrarlar, kitaplar ve gramer anlatımları ücretsiz. Konuşma ekranı dahil yapay zekâ özellikleri günlük bir kotayla çalışıyor; yeni hesaplar 7 günlük deneme kotasıyla başlıyor, sonrasında her gün yenilenen ücretsiz bir hak kalıyor, PRO ise kotayı yükseltiyor. Reklam yok, seni suçlayan bir seri sayacı yok, sıralama tablosu yok.
```

**EN — 1756 characters:**
```
KlioAI is built around the moment every English learner knows: you're mid-sentence and the word isn't there.

STUCK? SAY IT IN TURKISH
In the spoken tutor, you talk out loud to a character — a waiter, a hotel receptionist, a doctor. When you hit a word you don't have, say it in Turkish: "I'd like the pasta, and also biraz su alabilir miyiz?" KlioAI notices it wasn't English, and instead of guessing a fake English sentence from the audio, it shows you exactly what it heard, in Turkish, so nothing is put in your mouth. You tap Send, and the conversation carries straight on — the waiter brings the water. Under your line, a small card appears: the Turkish part struck through, the English you should have said next to it. The moment you forget a word stops being where the conversation ends, and becomes where you learn it.

Everything else lives in the same app: whole public-domain books to read end to end (Sherlock Holmes, Aesop's Fables, Dr Jekyll and Mr Hyde), tapping any word for its meaning inside that exact sentence, saved words that come back right before you'd forget them, a short daily plan that actually ends, translation practice built from your own words, grammar guides with worked examples, and AI feedback on your writing.

The interface speaks seven languages, Turkish included, and the line under a correction that explains why can arrive in yours too. The tutor itself always speaks and answers in English — that's the part you're here to practise.

The word list, reviews, books and grammar guides are free. AI features, including the speaking tutor, run on a daily quota; new accounts get a 7-day trial quota, then a free daily allowance continues, and PRO lifts the ceiling. No ads, no streak that shames you, no leaderboard.
```

Not: "Konuşma durmaz, garson suyu getirir" cümlesini kart örneğiyle birlikte
kullandım çünkü `TIKTOK.md`'de gerçekten cihazda üretilmiş bir örnek — uydurma
değil. Ekran görüntüsü çekerken bu örneği kullanmak metinle görüntüyü
tutarlı yapar (bkz. bölüm 3).

---

## 3. İlk üç ekran görüntüsü

Play arama sonuçlarında ilk 2–3 kareyi gösteriyor (`store/README.md` bunu
zaten biliyor ve buna göre sıralamış) — ama şu anki 7 karenin hiçbiri bu
özelliği göstermiyor. Sırayla: 1) günlük plan, 2) kafede sipariş (düz
İngilizce, hata yok), 3) kelime güç çubuğu, 4) aralıklı tekrar, 5) kitaplık,
6) okuyucuda kelime dokunma, 7) pratik modları. Tek bir şeyi satmaya
karar verdiysen bu yedi karenin hiçbiri o şey değil.

`store/promo/` klasörüne de baktım (`make_promo.py`, TikTok/Reddit/Facebook
için 1080×1440, telefon çerçeveli-gradyanlı stil): dört görsel var —
`promo_card.png` bir **dilbilgisi** düzeltmesi gösteriyor ("I prefer glass
of wine" → "I prefer a glass of wine"), dil değişimi değil; `promo_talk.png`
düz bir İngilizce karşılama; `promo_reader.png` ve `promo_library.png`
okuyucuyla ilgili. Dördünü de açıp baktım — **hiçbirinde Türkçe söyleme anı
yok.** Yani ne Play'deki 7 kare ne de promo'daki 4 görsel yeniden
kullanılabilir; bu özelliğin ekran görüntüsü hiç çekilmemiş.

İyi haber: `TIKTOK.md`'nin Klip 2 talimatı tam olarak bu anı cihazda
üretmeyi tarif ediyor ve "hepsi cihazda kart üretti" diyor — yani sahne
zaten prova edilmiş, sadece Play için kare olarak çekilmemiş.

**Çekilecek sıra:**

1. **[Yeni çekim] Onay ekranı, tam Türkçe söylediğin an.** Restoran
   sahnesinde "I'd like the pasta, and also biraz su alabilir miyiz?" de.
   Ekranda: "Bunu başka bir dilde duyduk." satırı, alanda **senin Türkçe
   cümlen** (uydurma İngilizce değil), altında Gönder düğmesi. Başlık:
   "Kelimeyi bilmiyorsan Türkçe söyle" / "Don't know the word? Say it in
   Turkish." **Neden ilk:** bu, konumlandırma cümlesinin kendisi. Arama
   sonucuna bakan biri mekanizmayı ilk karede görmeli, sonucu değil.
2. **[Yeni çekim, aynı akışın devamı] Düzeltme kartı.** Gönder'e bastıktan
   sonraki ekran: Luca'nın suyu getirdiği cevabı, altında "biraz su
   alabilir miyiz → could we have some water" kartı, üstü çizili Türkçe,
   yanında İngilizcesi. Başlık: "Konuşma durmaz, İngilizcesini görürsün" /
   "The conversation doesn't stop — you see the English." **Neden ikinci:**
   birincinin ispatı. Sadece mekanizmayı değil, sonucu da gösteriyor —
   biri "peki sonra ne oluyor" diye sorar, bu kare cevaplıyor.
3. **[Mevcut, yeniden kullanılabilir] Okuyucuda kelime dokunma** —
   `store/raw/06_reader_word.png` / `store/raw_en/06_reader_word.png`,
   şu an zaten `store/play/screenshot_en_02.png` olarak kullanılıyor
   ("Tap a word you don't know"). **Neden üçüncü:** ilk iki kare tek bir
   özelliği kanıtlıyor; üçüncü kare uygulamanın tek numaralı bir hile
   olmadığını, gerçek içerik (kitaplar) üzerine kurulu olduğunu gösteriyor.
   Başlığı ve rengi değiştirmeye gerek yok, sırasını öne almak yeterli.

**Nasıl çekilir:** `TIKTOK.md`'deki kayıt talimatı geçerli (sessiz oda,
kulaklık yok, 3–4 deneme — kart her seferinde birebir aynı çıkmıyor).
Ham kareyi `store/raw/` ve `store/raw_en/` içine koy, `store/make_store.py`
içindeki `SHOTS` / `SHOTS_EN` listelerine dosya adı + başlık + alt başlıkla
ekle, yeni ikisini listenin **başına** taşı. `store/promo/` için ayrıca
`make_promo.py`'nin `IMAGES` listesine aynı iki kareyi eklemek TikTok/Reddit
tarafını da güncel tutar — aynı kanıt, iki farklı kanalda.

---

## 4. Play Console mağaza deneyi

**Neyi test et (tek değişken):** kısa açıklama. Ekran görüntüsü seti
tasarım işi gerektiriyor (bölüm 3), kısa açıklama tek satır — bugün
başlatılabilir ve mağaza sayfasına gelen birinin en çok okuduğu satır bu.

- **Kontrol:** şu an yayında olan kısa açıklama (`LISTING_EN.md`'deki
  "Read real books, speak with an AI tutor, and keep every word you learn.")
- **Varyant:** bölüm 2'deki yeni kısa açıklama
- **Karar sayısı:** Play Console'un kendi gösterdiği **mağaza sayfası
  ziyaretçisi → yükleyen** dönüşüm oranı. Play bunu her varyant için ayrı
  ayrı hesaplayıp bir "anlamlılık" (significance) işareti veriyor —
  o işareti bekle, kendi gözünle yüzdeye bakıp erken karar verme.
- **Süre:** Play'in izin verdiği en uzun pencereyi seç (deney başına ~90
  gün). Kısa tutmanın bir faydası yok, çünkü asıl sorun süre değil trafik.

**Dürüst kısım — bu sayıda ziyaretle "anlamlı" sonuç muhtemelen hiç
gelmeyecek.** Google'ın kendi aracı, her varyantın makul bir güvenle
karşılaştırılabilmesi için kabaca binlerce ziyaretçi istiyor. 105 kayıtlı
kullanıcının tamamı, aylar süren organik trafiğin toplamı — günlük mağaza
sayfası ziyareti muhtemelen tek haneli. Bu hızda "anlamlı" işaretine
ulaşmak ay değil yıl alır. Deneyi kurup unutmak, hiç kurmamakla aynı kapıya
çıkar.

**Bu yüzden minimum uygulanabilir versiyon şu — Play'in kendi deney aracını
hiç beklemeden:**

1. Yeni kısa açıklamayı ve ilk üç ekran görüntüsünü **doğrudan yayınla**,
   deney olarak değil, tek sürüm olarak.
2. `REDDIT.md`'deki `signup_completed` olayı zaten hangi gönderinin
   kullanıcı getirdiğini ayırt edebiliyor — aynı mantığı mağaza değişikliği
   için kullan: değişiklikten önceki ve sonraki 7 günün Play Console →
   İstatistikler → **mağaza sayfası ziyaretçisi → yükleyen** oranını yan
   yana koy. Bu istatistiksel anlamlılık değil, yön bilgisi — ama 105
   kullanıcılık bir uygulamada elde edilebilecek gerçekçi tek şey bu.
3. Sayıyı tek başına yeterli sayma. `nf_tutor_page.dart` zaten
   `AnalyticsService.logFirstSpeakingStarted(source: 'nf_tutor')` olayını
   atıyor — yeni gelen kullanıcıların gerçekten konuşma ekranını
   denediğini (yükleme sayısı değil, **doğru kullanıcının** geldiğini)
   bu olayla çapraz kontrol et. Yükleme artıp bu olay artmıyorsa, yeni
   metin yanlış beklenti yaratıyor demektir.
4. Play'in deney aracını yine de kurabilirsin — kaybedecek bir şey yok —
   ama "significant" işaretini beklemeden, 60–90 gün sonra yön aynı
   kalıyorsa (yüzde kontrolden yüksekse) ve 3. maddedeki olay da aynı
   yönde büyüyorsa, o zaman değiştir. Tek başına yüzdeye güvenme.

---

## 5. Uygulamanın ilk ekranında değişmesi gereken

"Takılınca Türkçe söyle, İngilizcesini öğren" okuyup indiren biri şunu bir
dakika içinde görmeli — ve şu an görmüyor. İki yer, ikisi de küçük
değişiklik:

**a) Onboarding turu bu özelliği hiç anmıyor.**
`flutter_vocabmaster/lib/frontend_newest/screens/nf_onboarding_page.dart`
içindeki dört slayt (satır ~369–410): kelime listesi, okuma, tekrar,
pratik — bu son slayt (`onboarding.tour.practice.title/body`,
`app_localizations.dart` satır ~1186–1187 EN / ~2313–2314 TR) şu an
"Practise and see your mistakes" / "Talk or write with the tutor.
Corrections arrive in the language you chose." diyor. Konuşma mı yazma mı,
Türkçe söyleme hiç yok, ve dört slaytın **sonuncusu** — mağazanın sattığı
tek şey, uygulamanın kendi turunda son sırada ve isimsiz.
→ Bu slaytın metnini özellikle bu anı anlatacak şekilde değiştir ("Kelimeyi
bilmiyorsan Türkçe söyle") ve slaytı sona değil öne al (aynı dosyadaki dört
`_TourSlide` çağrısının sırasını değiştirmek yeterli, yeni widget gerekmez).

**b) Today sekmesinde tutor kartı beşinci sırada ve isimsiz.**
`nf_today_page.dart` satır ~216–260: `ListView` sırası — karşılama, deneme
uyarısı, hafta şeridi, **`_PlanCard`** (kelime tekrarı), **`_DailyWordsCard`**,
sonra **`_TutorCard`** (satır ~1461–1520, metni `home.tutor.title` /
`home.tutor.chat` — "Talk with {name}" / "Chat"). Uygulama her açıldığında
önce kelime tekrarını gösteriyor; konuşma kartı dördüncü bloktan sonra
geliyor ve jenerik.
→ İki ayrı, birbirinden bağımsız değişiklik, istenirse ikisi birden:
  - `_TutorCard`'ı `_PlanCard`'dan önceye al (tek satırlık sıralama
    değişikliği, `ListView`'in `children` listesinde).
  - `home.tutor.title` / `home.tutor.chat` metnini (satır ~641–642 EN,
    ~1777–1778 TR) mekanizmayı adlandıracak şekilde değiştir — örneğin alt
    başlık olarak "Konuşurken takılırsan Türkçesini söyle" ekle, düğmeyi
    "Sohbet" yerine "Dene" yap. Bu, mağaza metnindeki cümleyle birebir aynı
    dili konuşmalı; biri store'dan gelip ilk ekranda farklı bir cümle
    görürse vaat tutulmamış olur.

İkisi de metin ve sıralama değişikliği; yeni ekran, yeni akış, yeni
backend çağrısı gerekmiyor.
