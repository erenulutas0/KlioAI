# Outreach — öğretmenler ve sınav toplulukları

TikTok reklamı denendi: 75 TL, sıfır kurulum. Bu doküman onun yerine geçen iki
ücretsiz kanal: **kendi kitlesi olan İngilizce öğretmenleri** ve **sınav
hazırlık toplulukları** (YDS, YÖKDİL, IELTS, TOEFL). Reddit ve TikTok için
zaten `store/REDDIT.md` ve `store/TIKTOK.md` var — burada onları tekrar
yazmıyorum, sadece referans veriyorum ve genişletiyorum.

Beş dakikada okunacak kadar kısa tutuldu. Tahmin olan her yerde "tahmin" ya da
"doğrulanamadı" yazıyor — kafamdan uydurup kesin gibi sunmuyorum.

---

## Önce: ücretsiz premium nasıl verilir (gerçek mekanizma)

Backend'de zaten bir mekanizma var: `ComplimentaryAccessProperties`
(`backend/src/main/java/com/ingilizce/calismaapp/config/ComplimentaryAccessProperties.java`).
Bir e-posta listesi bu listedeyse `AiEntitlementService` o hesaba abonelik
kaydına hiç bakmadan doğrudan **PREMIUM_PLUS** veriyor — kartsız, süresiz,
Google Play faturalandırmasına hiç girmeden. Şu an listede geliştiricinin
kendi hesabı var (`eerenulutass@gmail.com`).

**Bunu bir öğretmene vermek için geliştiricinin yapması gereken:**

1. Öğretmenden uygulamaya **hangi e-posta ile kayıt olacağını** (normal
   e-posta ya da Google ile giriş — ikisi de aynı `email` alanına yazılıyor)
   iste. Küçük harfe çevrilerek karşılaştırılıyor, yani büyük/küçük harf
   önemli değil.
2. Sunucuda `/opt/vocabmaster/deploy/docker-compose.app.yml` dosyasını aç —
   **repodaki `docker-compose.prod.yml` değil**, o sunucuda kullanılmıyor
   (bkz. proje hafızası: *VPS compose repo dosyası değil*). Backend
   servisinin `environment:` bölümünde `APP_SUBSCRIPTION_COMPLIMENTARY_EMAILS`
   satırını bul (yoksa ekle) ve virgülle yeni e-postayı ilave et:
   ```
   APP_SUBSCRIPTION_COMPLIMENTARY_EMAILS=eerenulutass@gmail.com,ogretmen@ornek.com
   ```
   `APP_SUBSCRIPTION_COMPLIMENTARY_PLAN` satırına dokunma — varsayılan
   `PREMIUM_PLUS`, istenen de bu.
3. `docker compose -f docker-compose.app.yml config >/dev/null` ile dosyayı
   doğrula, sonra backend'i yeniden başlat. **`--remove-orphans` kullanma** —
   o bayrak `vocabmaster-caddy` ve `vocabmaster-postgres` konteynerlerini
   siler.
4. Bu komutları geliştirici kendisi çalıştırır (sunucu komutlarını ben
   çalıştırmıyorum, sadece komutu veriyorum).

Değer önerisi tam olarak şu: **kalıcı, ücretsiz, kart bilgisi girmeden
PREMIUM_PLUS.** Öğretmene mesajda bunu böyle söyle — "süresiz" ve "kart
istemiyorum" ikisi de doğru, yazması abartı değil.

### Play Console promosyon kodları — neden bunun yerine değil

Play Console'da abonelikler için promosyon kodu üretmek de mümkün, ama iki
noktada bu iş için daha zayıf (Google'ın kendi dokümantasyonuna göre):

- Kod ile verilen şey **en fazla 90 günlük bir deneme** — kalıcı değil.
  "Sana süresiz premium veriyorum" demek istiyorsan bu, istediğin şeyi
  vermiyor.
- Özel (vanity) kodlarda minimum kullanım limiti 2.000; tek kullanımlık
  kodlarda çeyrek başına 10.000 koda kadar üretilebiliyor ama yine de her biri
  geçici deneme. Tek bir öğretmene tek kod vermek teknik olarak mümkün ama tüm
  bu makine tek kişi için gereğinden karmaşık.

Sonuç: e-posta listesi zaten kurulu, tek dosya değişikliği, kalıcı ve
ücretsiz. Promosyon kodları büyük/kısa süreli bir kampanya lazım olursa
saklanacak ayrı bir araç — bu outreach için değil.

---

## 1. Öğretmenler

### Nerede aranır

**YouTube** — arama terimleri: `İngilizce konuşma pratiği`, `İngilizce
speaking dersi`, `IELTS speaking Türkçe anlatım`, `YDS İngilizce kanalı`.
Aranan hesap tipi: kendi yüzüyle/sesiyle konuşan, düzenli (son 1-2 ayda
video atmış), yorumlara kendisi cevap veren biri — ajans yönetimindeki büyük
kanallar mesajı okumaz.

**Instagram** — hashtag: `#ingilizceogretmeni`, `#speakingenglish`,
`#ieltsturkiye`, `#yökdil`, `#ingilizcekonuşma`. Reels'te kendi sesiyle
konuşan, DM'e görünür şekilde cevap veren (yorumlarda "DM attım" gibi
etkileşim olan) hesaplar iyi işaret.

**TikTok** — aynı hashtag mantığı: `#ingilizceöğreniyorum`,
`#speakingpractice`, arama: "İngilizce öğretmeni". TikTok'ta çok küçük
hesaplar bile (birkaç bin takipçi) günlük konuşma pratiği videoları atıyor;
bunlar tam hedef.

**Özel ders platformları** — Preply ve Cambly gibi uluslararası platformlarda
Türk öğretmenlerin profil sayfası herkese açık ve profilde genelde bir sosyal
medya/site linki var; oradan ulaşılabilir. **Doğrulanamadı:** Türkiye'ye özgü
platformların (yerel özel ders siteleri) hangilerinin hâlâ aktif olduğunu ve
öğretmenlere doğrudan mesaj izni verip vermediğini kontrol etmedim — platforma
girip "mesaj gönder" seçeneği var mı diye bakmak gerekiyor.

### Hangi büyüklükteki hesaptan cevap gelir

**Gerçekçi aralık: 2.000–30.000 takipçi**, özellikle DM'lerine/yorumlarına
kendisi cevap veren hesaplar. Altında (birkaç yüz) hesap sahibinin gerçek bir
kitlesi/otoritesi olmayabilir; üstünde (100 bin+) mesaj kutusu pazarlama
teklifleriyle dolu olur ve bir solo geliştiricinin mesajı kaybolur. Orta
büyüklük hem ulaşılabilir hem de öğrencilerine gerçekten tavsiye edebilecek
bir kitleye sahip.

### İlk mesaj — ne olmalı, ne olmamalı

**Olmalı:** kısa, kim olduğunu ilk cümlede söyleyen, pazarlama dili
kullanmayan, "dene ve ne bozuk söyle" diyen bir mesaj. Şablon aşağıda,
bölüm 3'te.

**Olmamalı:**

- **Toplu DM.** Aynı metni onlarca hesaba art arda kopyala-yapıştır atmak —
  hem etik değil hem de çoğu platform bunu spam olarak işaretleyip hesabını
  kısıtlayabilir. Her mesaj o hesabın içeriğine bakıldığını gösteren tek bir
  cümle taşımalı (izlediğin bir videosuna, bir yorumuna atıf).
- **Affiliate/komisyon teklifi.** "Öğrencilerine satarsan sana pay veririm"
  gibi bir teklif yok — bu bir güven karşılığı değişimi, para karşılığı
  reklam değil.
- **İlk mesajda shoutout istemek.** "Videonda bahsedebilir misin" ilk
  cümlede gelirse bu bir reklam teklifidir, geri bildirim isteği değil.
  Öğretmen kendi isteğiyle bahsederse bu ayrı ve iyi bir şey.

---

## 2. Sınav hazırlık ve öğrenci toplulukları

Reddit için `store/REDDIT.md` zaten var (r/SideProject, r/androidapps,
r/droidappshowcase, r/languagelearning, r/EnglishLearning — kurallar,
sıralama ve metinler orada). Burada onu tekrar etmiyorum; sınav odaklı
eklenecek yerler aşağıda.

| Yer | Kendi tanıtım kuralı | Gönderi biçimi |
|---|---|---|
| **r/IELTS**, **r/EnglishLearning** (sınav soruları da geliyor) | **Doğrulanamadı** — kuralları çekemedim. `store/REDDIT.md`'deki 90/10 kuralı ve "ilk cümlede geliştirici ol" ilkesi burada da geçerli varsayım. **Göndermeden kenar çubuğunu oku.** | Ürün tanıtımı değil, "şunu şöyle çözmeye çalıştım, IELTS speaking pratiği için işe yarar mı" tarzı soru. |
| **YDS/YÖKDİL Telegram grupları** (arama: Telegram içinde "YDS grubu", "YÖKDİL soru bankası", "YDS-YÖKDİL 2026") | **Doğrulanamadı** — hangi grupların hâlâ aktif olduğunu ve tanıtım kuralı olup olmadığını kontrol etmedim; her Telegram grubunun sabitlenmiş mesajında ("pinned") kuralları oluyor, önce onu oku. | Reklam gibi durmayan tek mesaj: "konuşma pratiği için bunu kullanıyorum, YDS'ye faydası olur mu bilmiyorum, deneyip söyleyin" — soru cümlesiyle bitmeli, link ısrarcı olmamalı. |
| **YDS/YÖKDİL/IELTS Discord sunucuları** (arama: Discord sunucu keşfi içinde "İngilizce", "YDS", "IELTS") | **Doğrulanamadı** — çoğu Discord sunucusunun `#kurallar` kanalında link/reklam kuralı oluyor; bota veya moderatöre sormadan atma. | Genelde `#uygulama-önerileri` veya `#kaynaklar` gibi ayrı bir kanal vardır — reklam kanalı yoksa genel sohbete atmak yerine moderatöre sor. |
| **Ekşi Sözlük** — `yds`, `yökdil`, `ielts`, `toefl`, `ingilizce öğrenme`, `dil öğrenme uygulamaları` başlıkları | **Doğrulanamadı platform kuralı olarak**, ama Ekşi Sözlük'ün genel kültürü biliniyor: gizlenmiş reklam ("astroturf") hızla fark edilip aşağı çekiliyor; geliştirici olduğunu açıkça yazan, ilk şahıs "denedim/yaptım" tonunda, öven değil eleştiriye açık bir entry kabul görüyor. | Başlığa uzun bir entry: neden yaptığını, neyin eksik olduğunu da yazan, sonda link. Övgü dolu tek satırlık tanıtım entry'si silinir/aşağı çekilir. |
| **Üniversite/dershane hazırlık forumları** | **Doğrulanamadı, muhtemelen büyük ölçüde ölü** — geleneksel forum formatı (dershane.net tarzı siteler) son yıllarda öğrenci trafiğini Instagram/Telegram gruplarına kaptırdı; hangi forumların hâlâ canlı olduğunu doğrulayamadım. Önce forumu aç, son bir haftada gönderi var mı diye bak — yoksa zaman kaybı. | Eğer canlı bir forum bulunursa: "kaynak önerileri" başlığı altına, reklam başlığı açmadan, mevcut bir soruya cevap olarak. |

**Ortak kural, her yer için:** kuralı doğrulayamadığın her yerde önce bir
hafta gerçek katılım yap (soru cevapla, yorum at), sonra kendi gönderini
paylaş. `store/REDDIT.md`'deki 90/10 ilkesi buraya da uygulanır.

---

## 3. Mesaj şablonları (Türkçe, olduğu gibi gönderilebilir)

### Öğretmene ilk mesaj

```
Merhaba [isim], ben [ad soyad] — İngilizce öğrenme uygulaması KlioAI'ı tek
başıma geliştiriyorum. [Videonuzu/postunuzu] izledim, konuşma pratiğine
verdiğiniz önem dikkatimi çekti.

Uygulamada sesli bir yapay zekâ öğretmen var; sahne kuruyor (restoran, otel,
mülakat), yaklaşık bir saniyede cevap veriyor, ve öğrenci takıldığı kelimeyi
Türkçe söyleyince konuşmayı bozmadan İngilizcesini öğretiyor.

Satmak için yazmıyorum — profesyonel bir gözle deneyip ne bozuk, ne eksik,
nerede yanlış olduğunu söylerseniz çok değerli olur. İsterseniz size kalıcı
ve ücretsiz premium tanımlayabilirim, karşılığında hiçbir şey istemiyorum.
Uygun olursa hangi e-posta ile kayıt olacağınızı yazmanız yeterli.
```

### Topluluk gönderisi (Telegram/Discord/forum için genel)

```
Selam, ben bu uygulamayı yapan geliştiriciyim, saklamak istemem.

Konuşma pratiği için sesli bir yapay zekâ öğretmen içeren bir İngilizce
uygulaması yapıyorum (KlioAI). Takıldığınız kelimeyi Türkçe söyleyip devam
edebiliyorsunuz, o an İngilizcesini öğretiyor.

[YDS/YÖKDİL/IELTS] hazırlığına gerçekten faydası olur mu, yoksa eksik bir
yanı mı var bilmiyorum — deneyip söylerseniz sevinirim: [link]
```

### "Bu hangi uygulama?" sorusuna cevap

```
KlioAI, Play Store'da ücretsiz. Ben geliştiricisiyim, sorunuz olursa
buradan yazabilirsiniz.
```

---

## 4. Haftalık ritim

Tek kişi için spam gibi görünmeden sürdürülebilir tempo:

- **Öğretmenlere: haftada 5-8 kişiselleştirilmiş mesaj.** Her biri o hesabın
  içeriğine gerçekten bakılarak yazılmalı — bu sayı bir kişinin günün
  sonunda hâlâ dikkatli yazabileceği üst sınır.
- **Topluluk gönderisi: haftada en fazla 1.** Aynı hafta iki farklı yere
  atmak hem hangisinin getirdiğini ölçmeyi bozar (bkz. `store/TIKTOK.md`'deki
  aynı ilke: aynı gün iki kanala atma) hem de tek kişinin ilk saatteki
  yorumlara cevap verme kapasitesini aşar.
- **Günler:** öğretmen mesajları hafta içi, iş saatlerinde (10:00-18:00) —
  akşam/hafta sonu gelen tanımadık bir DM daha kolay göz ardı ediliyor.
  Topluluk gönderisi salı-perşembe arası, gönderiden sonraki 2 saat
  yorumlara cevap verebilecek şekilde planla (aynı disiplin
  `store/REDDIT.md`'nin son kontrol listesinde de var).
- **Takip:** ayrı bir araç kurmaya değmez — basit bir tablo yeter (Google
  E-Tablolar ya da elle tutulan bir not): isim/hesap, platform, tarih, hangi
  mesaj/link verildi, cevap geldi mi, premium tanımlandı mı. Bu repo'ya yeni
  bir dosya eklemedim; bu tabloyu geliştirici kendi tercih ettiği yerde
  tutsun, her outreach mesajı zaten kendi UTM linkini taşıyacağı için hangi
  kişinin nereden geldiği tablo olmasa da linkten geriye izlenebilir.

---

## 5. Sonucu nasıl anlarsın

Uygulamanın kendisi kimin getirdiğini bilmiyor — bunu ölçmenin yolu her
kanala/kişiye **ayrı bir UTM etiketli Play Store linki** vermek:

```
https://play.google.com/store/apps/details?id=com.VocabMaster&referrer=utm_source%3D<kaynak>%26utm_medium%3D<kanal>%26utm_campaign%3Doutreach
```

`%3D` işareti `=`, `%26` işareti `&` yerine geçiyor — link URL içinde
olduğu için böyle kodlanmaları gerekiyor. Örnekler:

- Bir öğretmene: `utm_source%3Dteacher_ayse%26utm_medium%3Ddm`
- Bir Telegram grubuna: `utm_source%3Dtelegram_yds1%26utm_medium%3Dpost`
- Bir Discord sunucusuna: `utm_source%3Ddiscord_ielts1%26utm_medium%3Dpost`

Her öğretmene ve her topluluğa **farklı** bir `utm_source` ver — aynı
kaynağı iki yerde kullanırsan hangisinin getirdiğini yine ayıramazsın.

**Nereden okunur:** Play Console → Büyüme/İstatistikler → Kullanıcı edinme
raporları, kampanya/trafik kaynağı kırılımı. **Doğrulanamadı:** Play
Console'un menü adları zaman zaman değişiyor; `store/REDDIT.md` ve
`store/TIKTOK.md`'de kullanılan "İstatistikler → Yeni kullanıcı edinme"
yoluyla başla, orada bir kampanya/kaynak kırılımı göremezsen "Kullanıcı
edinme raporları" ya da "Acquisition reports" adıyla ara. Aynı ilke burada
da geçerli: aynı gün birden fazla linki paylaşma, karşılaştırma yapamazsın.

---

## Bugün başlamak için

1. Yukarıdaki backend adımını oku, gerektiğinde sunucuya kendin uygula
   (ben çalıştırmıyorum).
2. İki-üç öğretmen hesabı bul (YouTube veya Instagram), her biri için ayrı
   UTM linki hazırla, bölüm 3'teki şablonu o hesaba özel tek cümleyle
   kişiselleştirip gönder.
3. Bu hafta bir topluluk seç (Reddit için `store/REDDIT.md`'deki sıra zaten
   işliyor; sınav topluluğu istiyorsan yukarıdaki tablodan kuralı en azından
   "okudum" diyebileceğin birini seç) ve tek bir gönderi at.
