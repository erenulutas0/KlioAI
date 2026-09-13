# Reddit — nereye, ne zaman, ne yazarak

İki metin ve bir sıra. Metinler İngilizce, çünkü hedef kitlenin dili o; bu
dosyanın kendisi Türkçe, çünkü onu sen okuyacaksın.

---

## 13 Eylül — yeni gönderi: Metin C

Aşağıdaki Metin A ve B 6 Eylül'de yazıldı. O günden beri uygulamanın en
anlatılacak tarafı değişti: sesli tutor artık yaklaşık bir buçuk saniyede
cevap veriyor, ve oraya nasıl gelindiği ölçülmüş, somut bir yapımcı hikâyesi.
**r/SideProject için ilk gönderi bu olsun.** Metin A atılmadıysa sonraya kalır;
atıldıysa bu, iki hafta sonra atılacak devamıdır.

Göndermeden önce:

- [ ] **Play Console'da reklam beyanını "Hayır" yap.** Mağaza sayfası "Reklam
      içerir" diyor, uygulamada reklam yok. Metin B "No ads" diyor; biri linke
      tıklayıp tersini görürse ilk yorum o olur.
- [ ] Rakamlar bu oturumun sunucu loglarından. Kendi logunda yeniden görmek
      istersen: `docker logs --since 1h vocabmaster-backend 2>&1 | grep TIMING`

**Başlık:**

```
My voice tutor took 7 seconds to reply. The LLM was the fast part.
```

**Gövde:**

```
Solo dev. I build an app where you practise English by talking out loud to a
character -- a waiter, a hotel receptionist -- and it answers in a voice.

A week ago one turn took about 7 seconds on the server. I blamed the model.
The logs said:

- speech-to-text: 0.27 s
- the LLM writing the reply: 0.85 s
- text-to-speech: 6.0 s

I'd just moved the voice to Kokoro-82M -- far better than what I had, and
Apache 2.0 -- on an 8-core CPU box already at 700% CPU. Nothing left to tune.

What fixed it:

1. Synthesise only the first sentence before replying; the app fetches the
   rest while it plays. Speech plays about 4x slower than Kokoro makes it,
   so the opening covers the remainder.
2. The first part is a proportion of the reply (about a fifth), not a fixed
   length -- fixed lengths either wait too long or run out mid-reply.
3. A very long first sentence gets cut at a comma instead.
4. Shorter sentences from the model. One 289-character reply was 17 seconds
   of speech. That's a monologue, not a conversation.
5. Kokoro loads on its first request (8.4 s after a restart), so the backend
   now makes that request itself at startup.

The whole turn is now about 1.5 s on the server.

https://play.google.com/store/apps/details?id=com.VocabMaster

Genuine question: where does a voice reply stop feeling like a conversation
for you -- one second, two?
```

Yaklaşık 210 kelime. Metin A ile aynı iskelet: ilk cümlede geliştirici, bir şey
öğretiyor, rakamlar gerçek, link sonda ve düz, sonda gerçek bir soru.

**Yorumlarda gelecek sorular ve hazır cevaplar:**

- *"Why not stream audio?"* — Çünkü uygulama tek bir WAV çalıyor; iki parçaya
  bölmek, akış protokolü kurmadan kazancın çoğunu verdi. Sıradaki adım gerçek
  akış olabilir.
- *"Why not a GPU?"* — Maliyet. CPU'da ilk cümle ~1 sn; kullanıcı bekleyişinin
  çoğu gitti, GPU'nun kalan farkı parasına değmiyor (şimdilik).
- *"Seams between the two clips?"* — Kesim nokta ya da virgülde, konuşan zaten
  orada duruyor. Ölçülen: ikinci parça birinci bitmeden hazır.
- *"What about the 1.5 s?"* — Kabaca 0.25 sn tanıma, 0.4 sn model, ~0.9 sn ilk
  cümlenin sesi. Artık en büyük kalem yine ses, ama bölünmüş hali.

---

## Önce: neyi doğrulayabildim, neyi doğrulayamadım

Reddit'in kural sayfaları buradan çekilemiyor, o yüzden ayrımı açık tutuyorum.

| Subreddit | Kural durumu | Kaynak |
|---|---|---|
| **r/SideProject** | **Doğrulandı** — kendi tanıtımın açıkça hoş karşılanıyor. Kapı karma değil, "bunu gerçekten sen mi yaptın ve gerçek bir yapımcı gibi mi anlatıyorsun". Yeni hesapsan önce bir hafta yorum yap. | [GrowReddit](https://www.growreddit.com/blog/reddit-self-promotion-rules-sideproject), [OneUp](https://oneup.today/tools/reddit-self-promotion-checker/sideproject) |
| **r/androidapps** | **YASAK** — Kural 2, birebir: "Any self-promotion, tester requests, new app ideas or app feedback are not allowed." Kendi yönlendirdiği kardeş subreddit **r/droidappshowcase**. Buraya gönderme. | Reddit'in gönderi ekranındaki kural uyarısı, 6 Eylül 2026 |
| **r/droidappshowcase** | **Doğru adres** — r/androidapps'in resmi kardeşi, tam olarak yeni uygulama göstermek için. Daha küçük, ama kitlesi bunu görmek isteyen insanlar. Showcase olduğu için görsel büyük ihtimalle serbest; kenar çubuğunu oku. | r/androidapps Kural 2 |
| **r/languagelearning** | **Kısmen** — "şartlarla izinli". "Kendi içeriğini çok sık gönderme" kuralı var; genelde bu ayrı bir haftalık başlık, zorunlu flair veya mod onayı demek. **Göndermeden önce kenar çubuğunu oku.** | [LeadsRover](https://leadsrover.io/subreddits/r/languagelearning) |
| **r/EnglishLearning** | **Doğrulanamadı** — 707 bin üye, topluluk uygulama önerilerini ve incelemelerini sık konuşuyor, ama kendi tanıtım kuralını teyit edemedim. **Kenar çubuğunu okumadan gönderme.** | [GummySearch](https://gummysearch.com/r/EnglishLearning/) |

Her yer için geçerli olan üçü, ve bunlar doğrulandı:

1. **90/10.** Etkinliğinin en az %90'ı gerçek katılım olmalı. Sadece kendi
   gönderin için ortaya çıkan hesap görmezden gelinir.
2. **İlk cümlede geliştirici olduğunu söyle.** Saklamaya çalışmak, yakalanınca
   gönderiyi de hesabı da bitiriyor.
3. **Kısaltılmış veya takipli link kullanma.** `bit.ly`, UTM parametresi,
   yönlendirme kodu — otomatik spam filtreleri bunları eliyor. Düz Play linki.

---

## Sıra

Aynı gün hepsine atma. `signup_completed` artık çalışıyor, yani ilk kez hangi
gönderinin kullanıcı getirdiğini **ölçebilirsin** — ama sadece aralarında
boşluk bırakırsan.

1. **Gün 1 — r/SideProject.** En güvenli ve kuralları en net olan. Metin A.
2. **Gün 3 — Play Console → Yüklemeler'e bak.** Ne geldi?
3. **Gün 4 — r/droidappshowcase.** Metin A'nın kısaltılmışı, ekran görüntüsüyle. (r/androidapps değil — orada yasak.)
4. **Gün 6 — tekrar bak.**
5. **Sonra r/languagelearning**, kenar çubuğunu okuduktan sonra. Metin B.
6. **En son r/EnglishLearning**, kuralları teyit edersen. Metin B.

Sondaki ikisi en değerli kitle *ve* en sıkı kurallar — o yüzden en sona
bırakıyoruz, sen o zamana kadar Reddit'te birkaç gerçek yorum yapmış olursun.

---

## Uzunluk hakkında

Kısa gönderi kazanır. Reddit'in doğru yapısı **kısa gövde + derinlik
yorumlarda**: ilk saatte gelen sorulara verdiğin cevaplar gönderiyi taşır,
gövdeye tıkıştırdığın paragraflar değil.

İki şeyi de yapma:

- **Özellik listesi yazma.** "İşte uygulamam, işte özellikleri" Reddit'te
  görmezden gelinen formattır — okuyucuya hiçbir şey vermez, sadece ister.
- **Tanıtım videosunu gövdeye koyma.** Müzikli, kurgulu 20 saniye orada
  reklam gibi okunur. Videonun yeri Twitter, TikTok ve YouTube. Reddit'te
  görsel gerekiyorsa **ham ekran görüntüsü** koy; "yapımcı işini gösteriyor"
  diye okunur.

Aşağıdaki kısa metinler varsayılan. Uzun versiyonlar en altta duruyor — bir
gönderi tutarsa ve "nasıl yaptın" diye sorarlarsa, oradaki malzemeyi
**yorumda** kullan.

---

## Metin A (kısa) — yapımcı kitlesi

**Başlık:**

```
I was about to ship pronunciation scoring. Reading my own code stopped me.
```

**Gövde:**

```
Solo dev. I've been building an English learning app for six months.

Every competitor sells a pronunciation score, so I went to build one from
Whisper's `avg_logprob` — how confident the model was in its own
transcription. Three things stopped me:

- Whisper gives no per-word confidence. A word object has `word`, `start`,
  `end`. That's all. `avg_logprob` is per segment.
- I found a comment I'd written months earlier in my own speech code: low
  log-probability "fires on unusual accents." Every user of my app has one by
  that model's standards. That's the whole point of the app.
- Testing that afternoon I said "Hi Amy" to the tutor. It transcribed "Hi
  Emi." A score would have reported that to the learner as their mistake.

So I shipped pace and hesitation instead — computed from word timestamps that
were already in the API response and being thrown away by my own client.

https://play.google.com/store/apps/details?id=com.VocabMaster

Genuine question: is showing someone "62 words/min" motivating or
discouraging? I went back and forth for a day and still don't know.
```

Yaklaşık 170 kelime. Ne yaptığını anlatmıyor, **ne öğrendiğini** anlatıyor —
ve okuyan biri uygulamayı hiç indirmese bile bir şey öğrenmiş oluyor. Reddit'te
işe yarayan şey bu.

---

## Metin B (kısa) — öğrenen kitlesi

**Başlık:**

```
Dictionary definitions never matched the sentence I was reading, so I built a reader that explains words in context
```

**Gövde:**

```
I'm the developer — saying that first so nobody has to wonder.

The problem I started from: you hit a word you don't know, look it up, and get
nine definitions of which one fits the sentence in front of you. Picking the
right one takes the vocabulary you don't have yet. So the lookup teaches you
least at exactly the moment you understand least.

What I built: public-domain books — Sherlock Holmes, Aesop, Wilde — sorted by
CEFR level. Tap a word and it's explained inside *that* sentence, one meaning,
the one on the page. Tap again and it's saved with the sentence, and comes
back for review on the day you're about to forget it.

Free: reading, the word list, reviews, grammar, and a daily quota of the AI
parts. Paid plans lift the quota. No ads, no leaderboard, no streak that
shames you.

https://play.google.com/store/apps/details?id=com.VocabMaster

Two things I'd like criticised:

- Is an in-context definition actually better, or does it hide something you'd
  want from a full entry?
- Does reading 19th-century books help modern English, or am I teaching people
  to speak like Conan Doyle?
```

Yaklaşık 180 kelime. İkinci soru gerçek bir eleştiriyi davet ediyor ve
alacaksın — kütüphane kamu malı olduğu için hepsi eski metin. **Kendin sormak,
birinin yorumlarda vurmasından iyidir**, ve cevabın hazır olmalı: seviyeye göre
sıralı, ve kaydettiğin kelimeler modern konuşma pratiğinde geri geliyor.

---

## r/droidappshowcase için

Metin A'nın kısasını al, ilk üç maddeyi çıkar, yerine iki cümle koy:

```
I built an English app where you read whole public-domain books and tap any
word to get its meaning inside that sentence — plus a tutor you talk to out
loud, who answers in English. Get something clearly wrong and a card shows
your own sentence struck through, the better version, and one line in your
own language on what went wrong.
```

Ve **iki ham ekran görüntüsü** ekle: `store/play/screenshot_en_03.png`
(kapaklı kitaplık) ve `store/play/screenshot_en_01.png` (kafede sipariş).
Mağaza rozeti değil, gerçek ekran.

---

## Uzun versiyonlar (yedek — yorumlarda kullan)

## Metin A — yapımcı kitlesi (r/SideProject, r/androidapps)

Bu gönderi ürünü satmıyor, bir kararı anlatıyor. r/SideProject'te tutan şey
bu: dürüst bir ders, reklam değil. Hikâye gerçek — bu haftaki bir günün
tamamı buydu.

**Başlık:**

```
I was about to ship pronunciation scoring in my English app. Reading my own code stopped me.
```

**Gövde:**

```
I'm a solo developer. For the last six months I've been building an English
learning app, and this week I nearly shipped the feature every competitor
sells: a pronunciation score.

The plan was reasonable. I use Whisper for speech-to-text, and Whisper's
verbose response includes `avg_logprob` — how confident the model was in what
it transcribed. Low confidence, bad pronunciation, show the learner a score.
Every speaking app on the store has one. Mine didn't.

Three things stopped me, in order:

**1. There is no per-word confidence.** A word object from Whisper carries
`word`, `start` and `end`. That's it. `avg_logprob` exists per *segment* —
roughly per sentence. There is nothing to score a word against.

**2. My own repository had already written the reason down.** I went looking
in my speech service and found a comment I'd left months ago while building a
silence detector: low log-probability alone "fires on unusual accents." Every
single user of my app has an unusual accent by that model's standards. That is
the entire point of the app. A score built on it would have marked a Turkish
speaker down for sounding Turkish.

**3. I watched it happen.** Testing on my phone the same day, I said "Hi Amy"
to the tutor. Whisper transcribed "Hi Emi." That is the model missing a name,
and a pronunciation score would have reported it to the learner as their
mistake.

So I didn't build it. What I built instead was sitting in the response the
whole time: Whisper returns word-level *timestamps*, and my backend had been
fetching them, parsing them into a struct, and sending them to the app, where
the client read the transcript and threw the array away. Timings carry no
judgement — pace and hesitation are arithmetic on when words started and
stopped, true whatever your accent.

Now a turn shows "62 words/min · 2 pauses" under your own sentence. No colour,
no threshold, no "too slow." 62 is only slow next to a native speaker and
nobody opens a language app already being one. What makes it worth showing is
watching it climb.

The rest of the app, briefly: you hold a button and talk to a tutor who
answers out loud in English, in character (ordering coffee, hotel check-in, a
doctor's appointment), and when you get something clearly wrong, a card under
your own reply shows what you said struck through, the better version, and one
line in your own language on why. You read whole public-domain books —
Sherlock Holmes, Aesop, Wilde — and tap any word to get its meaning *inside the
sentence it came from*, not a dictionary entry with nine definitions. Saved
words come back for review on the day you're about to forget them.

Free: word list, reviews, books, grammar, and a daily quota of the AI
features. Paid plans lift the quota. No ads, no leaderboard, no streak that
guilt-trips you.

https://play.google.com/store/apps/details?id=com.VocabMaster

I'd genuinely like to be told what's wrong with it. Especially: is showing a
words-per-minute number motivating or discouraging? I went back and forth on
it for a day and I still don't know.
```

**Neden bu metin çalışır:** ilk cümlede kim olduğunu söylüyor · bir şey
*öğretiyor* (Whisper'ın gerçek sınırları, teknik ve doğrulanabilir) · kendi
aleyhine bir karar anlatıyor · link sonda ve düz · gerçek bir soru soruyor.

**r/androidapps için:** ilk üç bölümü at, "The rest of the app, briefly"den
başla, başlığı `I built an English app where you read real books and tap words
for in-context meanings — feedback wanted` yap ve **iki ekran görüntüsü** ekle
(kitaplık ve eğitmen; `store/play/screenshot_en_03.png` ve
`screenshot_en_01.png` iş görür).

---

## Metin B — öğrenen kitlesi (r/languagelearning, sonra r/EnglishLearning)

Burada ürün değil, **çözdüğü sorun** öne çıkıyor. Bu topluluklar reklamdan
hızla sıkılıyor ama "şunu şöyle çözmeye çalıştım, sizce doğru mu" sorusuna
açıklar.

**Başlık:**

```
Dictionary definitions never matched the sentence I was reading, so I built a reader that explains the word in context. Would like your criticism.
```

**Gövde:**

```
I'm the developer — saying that first so nobody has to wonder.

The thing that made me start: I'd be reading something in English, hit a word
I didn't know, look it up, and get nine definitions of which exactly one was
relevant to the sentence in front of me. Picking the right one is a skill you
need the vocabulary to have. So the lookup taught me the least at exactly the
moment I understood the least.

What I ended up building is a reader over public-domain books — Sherlock
Holmes, Aesop's Fables, The Happy Prince, Jekyll and Hyde, sorted by CEFR
level — where tapping a word explains *that* word in *that* sentence. One
meaning, the one on the page. A second tap saves it, with the sentence
attached, and it comes back for review on the day you're about to lose it.

Two other things are in there: a tutor you can talk to out loud in a specific
situation (ordering coffee, checking into a hotel, explaining a symptom at the
doctor), who answers in English and corrects you by showing a better version of
your own sentence rather than marking it wrong — with one line under it, in
your own language, saying what was actually wrong; and translation practice
built from the words *you* saved rather than a fixed list.

Things I deliberately did not do, in case they matter to you: no ads, no
leaderboard, no streak that shames you when you miss a day, and today's plan is
finite — you can finish it and be done.

The reading, the word list, the reviews and the grammar guides are free. The AI
parts run on a quota with a paid tier. I'm not going to pretend that isn't a
business; I'd rather say it plainly than bury it.

https://play.google.com/store/apps/details?id=com.VocabMaster

What I actually want from this post is criticism. Specifically:

- Is in-context definition genuinely better than a dictionary entry, or does it
  hide useful information you'd want?
- Does reading a whole 19th-century book help modern English, or am I teaching
  people to speak like Conan Doyle?

I'll answer everything in the comments.
```

**Uyarı:** İkinci soru gerçek bir eleştiriyi davet ediyor ve alacaksın —
kütüphane kamu malı olduğu için hepsi eski metin. Bu bilinçli: kendin sormak,
başkasının vurmasından iyidir, ve cevabın hazır olmalı (seviyeye göre sıralı,
ve kaydettiğin kelimeler modern konuşma pratiğinde geri geliyor).

---

## Göndermeden önceki kontrol listesi

- [ ] Hesabın birkaç günlük gerçek yorum geçmişi var mı? Yoksa önce onu yap.
- [ ] O subreddit'in kenar çubuğunu **bugün** okudun mu? Kurallar değişiyor.
- [ ] Link düz Play linki mi? (UTM yok, kısaltma yok)
- [ ] İlk cümlede geliştirici olduğunu söylüyor musun?
- [ ] Gönderiden sonraki 2 saat müsait misin? İlk saatteki cevaplar
      gönderinin görünürlüğünü belirliyor; sorulara cevap vermezsen ölür.
- [ ] Play Console → Yüklemeler'in bugünkü sayısını not aldın mı? Ölçüm
      karşılaştırma gerektirir.
