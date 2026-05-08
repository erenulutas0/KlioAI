# KlioAI Premortem Roadmap

Bu dokuman, premortem analizindeki riskleri uygulanabilir bir sira planina cevirir. Hedef yeni feature eklemek degil; olcumleme, aktivasyon, retention ve birim ekonomi tarafini guclendirerek uygulamanin basari ihtimalini artirmaktir.

## Mevcut Durum Notu

- Firebase Android config var: `android/app/google-services.json`.
- Google Services Gradle plugin var: `com.google.gms.google-services`.
- Firebase Analytics, Crashlytics ve FCM Flutter SDK'lari eklendi.
- Uygulamada temel funnel/event tracking baslatildi.
- Google Play tarafindaki install sayisi repo'dan okunamaz; bunu Play Console Statistics/User acquisition ekranindan dogrulamak gerekir.

## North Star

Kullanici ilk 24 saatte net bir ogrenme kazanci hissetmeli:

1. Ilk oturumda 3 kelime ekler.
2. En az 1 AI destekli cumle olusturur.
3. En az 1 tekrar/pratik tamamlar.
4. XP kazanir ve ertesi gun geri donmesi icin tetiklenir.

## Phase 0 - Release Hygiene

Amac: Uygulamanin yayina alinabilir, olculebilir ve maliyet kontrollu oldugundan emin olmak.

- [ ] Google Play Console fiyatini kod/backend ile hizala.
- [x] `20 TRY` fiyat kararini kaldir veya bilincli test fiyati olarak dokumante et.
- [x] Aylik fiyat icin ilk oneriyi uygula: `149.99 TRY`.
- [x] Yillik plani hazirla: `999.99 TRY`.
- [x] Trial/Premium token kotalarini maliyet hesabina gore dusur:
  - Trial: `3000-5000 token/gun`
  - Premium: `25000-30000 token/gun`
  - Premium Plus: `60000 token/gun`
- [x] Default AI modelini ucuz modele cek:
  - default/utility: `openai/gpt-oss-20b`
  - speech/evaluation: `llama-3.3-70b-versatile`
- [ ] Play Store yuklemesi sonrasi 16 KB page size, logo, abonelik satin alma ve Google Sign-In smoke testlerini yap.

Definition of done:

- Yeni AAB Play Console'a yuklenebilir.
- Uygulama ikonunda `K` kesilmiyor.
- Satin alma akisi gercek tester ile backend'de aktif abonelige donusuyor.
- Token kotasi prod config'te maliyet hesabiyla uyumlu.

## Phase 1 - Instrumentation

Amac: Kullanici ne yapiyor, nerede dusuyor ve neden odemiyor sorularini cevaplayabilmek.

- [x] `firebase_core` ekle.
- [x] `firebase_analytics` ekle.
- [x] `firebase_crashlytics` ekle.
- [x] Android Firebase config'i yeniden dogrula.
- [x] Crashlytics global error handler bagla.
- [x] Analytics icin merkezi servis olustur: `AnalyticsService`.
- [x] Minimum eventleri ekle:
  - `app_open`
  - `signup_completed`
  - `login_completed`
  - `onboarding_started`
  - `onboarding_completed`
  - `first_word_added`
  - `first_sentence_added`
  - `first_ai_use`
  - `practice_started`
  - `practice_completed`
  - `paywall_shown`
  - `purchase_started`
  - `purchase_completed`
  - `purchase_failed`
  - `trial_started`
  - `trial_expired`
  - `support_ticket_created`

Definition of done:

- Firebase dashboard'da test cihazindan event gorunur.
- Crashlytics test crash'i panelde gorunur.
- D1/D7 retention ve funnel icin gerekli eventler toplanir.

## Phase 2 - First Session Activation

Amac: Yeni kullaniciya her seyi gostermek yerine ilk kazanci yasatmak.

- [x] Ilk oturum akisina sade hedef koy:
  - Seviye sec.
  - 3 kelime ekle.
  - 1 AI cumle olustur.
  - 1 tekrar tamamla.
- [x] Yeni kullanici icin Practice ekraninda ilk etapta sadece 3 mod goster:
  - Kelime ekle/cumle uret
  - Klasik tekrar
  - AI chat veya Writing
- [ ] Word Galaxy, Neural Game, Exams ve ileri modlari progressive unlock yap.
- [x] Home ekraninda "bugunku tek hedef" karti ekle.
- [x] Aktivasyon eventlerini analytics'e bagla.

Definition of done:

- Yeni kullanici 2 dakika icinde ilk XP'yi kazanabilir.
- Ilk oturumda kullaniciya 8-10 secenek birden gosterilmez.
- Aktivasyon hunisi Firebase'de izlenebilir.

## Phase 3 - Retention

Amac: Kullaniciya geri donmesi icin neden ve tetikleyici vermek.

- [x] `flutter_local_notifications` ile lokal bildirim ekle.
- [x] Gunluk calisma hatirlaticisi kur.
- [x] Streak bozulmadan once hatirlatici kur.
- [x] Trial bitmeden 2 gun once lokal bildirim kur.
- [x] FCM icin `firebase_messaging` ekle.
- [x] FCM token'i backend'e kaydet.
- [x] Backend tarafinda bildirim hedefleme endpoint'i/servisi olustur.
- [x] Bildirim opt-in metnini sade ve acik yap.

Definition of done:

- Kullanici izin verirse gunluk reminder alir.
- Bildirim tiklama event'i analytics'e duser.
- D1/D7 retention olculebilir hale gelir.

## Phase 4 - Monetization

Amac: Fiyat, kota ve deger algisini ayni yone cekmek.

- [x] Paywall metnini sadelestir: "AI destekli gunluk pratik, cumle uretme, konusma ve tekrar".
- [x] Aylik plani gorunur yap.
- [x] Yillik plani gorunur yap.
- [x] Premium Plus'i simdilik gizli tut veya net farkla sun.
- [x] Free tier'i sifir AI yerine dusuk ama kullanilabilir yap:
  - Oneri: `1000-3000 token/gun`
- [x] Kullaniciya kalan gunluk AI hakkini UI'da goster.
- [x] Abonelik basarili/iptal/restore eventlerini analytics'e bagla.
- [x] Google Play fiyatini uygulamadaki gorunen fiyatla ayni tut.

Definition of done:

- Paywall fiyatlari Play Console ile tutarli.
- Trial -> purchase conversion izlenir.
- AI cost / revenue oranini hesaplamak icin veri toplanir.

## Phase 5 - Discovery And Store Readiness

Amac: Uygulamanin disaridan guvenilir ve indirilebilir gorunmesi.

- [x] Landing page CTA'larini `/actuator/health` yerine Play Store linkine bagla.
- [ ] Gercek app screenshot'lari ekle.
- [x] Google Play badge ekle.
- [x] Privacy ve Terms linklerini netlestir.
- [x] Play Store aciklamasini ASO odakli yaz.
- [x] Ana keyword setini belirle:
  - AI English learning
  - English vocabulary
  - speaking practice
  - grammar practice
  - kelime ezberleme
  - AI ingilizce
- [x] `in_app_review` ekle.
- [x] 3. basarili pratikten sonra review prompt tetikle.

Definition of done:

- Landing page ziyaretcisi tek tikla Play Store'a gider.
- Store listing screenshot, aciklama, privacy ve support bilgileri tamamdir.
- Review prompt rahatsiz etmeyecek sekilde tetiklenir.

## Phase 6 - AI Reliability And Cost Control

Amac: Tek provider/model riskini azaltmak ve maliyet patlamasini onlemek.

- [x] `AiCompletionProvider` interface tasarla.
- [x] Mevcut Groq cagrilarini provider interface arkasina al.
- [x] Provider bazli token usage ve hata oranini kaydet.
- [x] Gunluk projected AI spend hesabi ekle.
- [x] Admin/log endpoint veya basit dashboard ile su metrikleri gor:
  - token usage by user
  - token usage by scope
  - token usage by model
  - provider error rate
  - quota block count
- [x] Pahali model kullanan scope'lari azalt.
- [x] JSON response isteyen islerde schema/validation ve retry limitlerini netlestir.

Definition of done:

- Bir model/provider sorununda tum AI sistemi durmaz.
- Gunluk maliyet riski gorunur.
- Scope bazli kota ve model karari veriye dayanir.

## Phase 7 - Localization Reality

Amac: "5 dil UI" yerine gercekten calisan pazar secmek.

- [x] Ilk hedef pazari net sec: Turkiye odakli English learning.
- [ ] UI'da global iddia yapma; once TR->EN deneyimi guclendir.
- [x] AI promptlarindaki Turkish varsayimini merkezi hale getir.
- [ ] Daha sonra kaynak dil parametresi ekle:
  - `sourceLanguage`
  - `targetLanguage`
  - `feedbackLanguage`
- [ ] Speaking, grammar, writing ve dictionary promptlarini bu parametrelere gore uret.
- [x] Mevcut uretim odagi dokumante edildi: `docs/localization_reality.md`.

Definition of done:

- Uygulama TR pazarinda tutarli ve kaliteli calisir.
- Diger UI dilleri kullaniciyi yaniltmaz veya kademeli olarak devreye alinir.

## Phase 8 - Scale Readiness

Amac: Ilk buyume dalgasinda tamamen dusmemek.

- [x] PostgreSQL backup + restore test scripti ekle.
- [x] VPS disk doluluk alarmi ekle.
- [x] Backend health check disinda sentetik prod smoke test ekle.
- [x] Hikari pool, Redis memory ve JVM memory metriklerini izle.
- [x] Statik landing assetleri CDN/GitHub Pages tarafinda tut.
- [x] Gerektiginde DB'yi managed Postgres'e tasima planini dokumante et.
- [x] Scale readiness calisma notlarini dokumante et: `docs/scale_readiness.md`.

Definition of done:

- Backup geri yukleme test edildi.
- Disk/memory/db pool riskleri alarm uretir.
- Ani trafik halinde temel servisler izlenebilir olur.

## Ilk 10 Uygulama Sirasi

1. [x] Firebase Analytics + Crashlytics ekle.
2. [x] Funnel eventlerini bagla.
3. [x] Fiyati ve token kotalarini maliyet hesabina gore duzelt.
4. [x] Play Store fiyatlari ile app/backend fiyatlarini hizala.
5. [x] Yeni kullanici first-session flow'unu sadelestir.
6. [x] Local notification ekle.
7. Landing page Play Store linki + screenshot'lari ekle.
8. [x] In-app review prompt ekle.
9. [x] AI usage/cost dashboard veya minimum log raporu ekle.
10. [x] AI provider abstraction icin ilk interface'i cikar.

## Izlenecek KPI'lar

- D1 retention: hedef `%25+`
- D7 retention: hedef `%8-12+`
- First session activation: hedef `%40+`
- Trial -> paid conversion: hedef `%3-7`
- Purchase failure rate: hedef `%5 altinda`
- Crash-free users: hedef `%99+`
- AI cost / subscription revenue: hedef `%25-35 altinda`
