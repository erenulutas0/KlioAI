import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// ARTICLES & DETERMINERS (Exam Grammar)
const articlesTopic = GrammarTopic(
  id: 'articles',
  title: 'Articles & Determiners',
  titleTr: 'Tanımlıklar/Miktar',
  level: 'exam',
  icon: Icons.category,
  color: Color(0xFFef4444),
  subtopics: [
    // 1. INDEFINITE ARTICLES (A/AN)
    GrammarSubtopic(
      id: 'indefinite_articles',
      title: 'Indefinite Articles (A/An)',
      titleTr: 'Belirsiz Tanımlıklar',
      explanation: '''
"A" ve "An" belirsiz tanımlıklardır. SAYILABİLİR, TEKİL ve BELİRSİZ isimlerden önce kullanılır.

🎯 A vs AN KURALI:
• A: ÜNSÜZ SES ile başlayan kelimelerden önce
  a book, a car, a university (yuu sesi), a European, a one-way ticket

• AN: ÜNLÜ SES ile başlayan kelimelerden önce
  an apple, an hour (h okunmaz), an honest man, an MBA

⚠️ ÖNEMLİ:
Harf değil, SES önemlidir!
• "University" U harfi ama "yuu" sesi → a university
• "Hour" H harfi ama ünlü ses → an hour

🎯 KULLANIM ALANLARI:
• İlk kez bahsetme: "I saw a cat."
• Meslek: "She is a doctor."
• Sayı anlamı: "a hundred, a thousand"
• "Per" anlamı: "twice a week, 60 km an hour"
''',
      formula: '''
A/AN + Sayılabilir Tekil İsim

a + ünsüz SES: a book, a university
an + ünlü SES: an apple, an hour
''',
      formulaEn: '''
A/AN + Singular Countable Noun

a + consonant SOUND: a book, a university
an + vowel SOUND: an apple, an hour
''',
      examples: [
        GrammarExample(
          english: 'She is a university student.',
          turkish: 'O bir üniversite öğrencisi.',
          note: 'a + university (yuu sesi)',
        ),
        GrammarExample(
          english: 'I waited for an hour.',
          turkish: 'Bir saat bekledim.',
          note: 'an + hour (h okunmaz)',
        ),
        GrammarExample(
          english: 'It was an honor to meet you.',
          turkish: 'Sizinle tanışmak bir onurdu.',
          note: 'an + honor (h okunmaz)',
        ),
        GrammarExample(
          english: 'He earns \$50 an hour.',
          turkish: 'Saatte 50 dolar kazanıyor.',
          note: 'an = per (başına)',
        ),
        GrammarExample(
          english: 'I need an university degree.',
          turkish: 'Üniversite diplomasına ihtiyacım var.',
          isCorrect: false,
          note: '❌ YANLIŞ! A university (yuu sesi)',
        ),
      ],
      commonMistakes: [
        '❌ an university → ✅ a university (yuu sesi ünsüz)',
        '❌ a hour → ✅ an hour (h okunmaz, ünlü ses)',
        '❌ a honest man → ✅ an honest man',
        '❌ an European → ✅ a European (yuu sesi)',
      ],
      keyPoints: [
        '🔑 HARF değil SES önemlidir!',
        '🔑 A/An sadece SAYILABİLİR TEKİL isimlerle kullanılır',
        '🔑 "Information, advice, money" gibi sayılamaz isimlerle A/An KULLANILMAZ',
        '🔑 Çoğul isimlerle A/An KULLANILMAZ (a books ❌)',
      ],
      examTip: '💡 YDS\'de "an university" veya "a hour" görürseniz YANLIŞ!',
    ),

    // 2. DEFINITE ARTICLE (THE)
    GrammarSubtopic(
      id: 'definite_article',
      title: 'The Definite Article (The)',
      titleTr: 'Belirli Tanımlık (The)',
      explanation: '''
"The" belirli tanımlıktır. Bahsettiğimiz şey belirli veya daha önce bahsedilmişse kullanılır.

🎯 "THE" KULLANIM ALANLARI:

1. DAHA ÖNCE BAHSEDİLEN:
"I saw a cat. THE cat was black."

2. TEK OLAN ŞEYLER:
the sun, the moon, the sky, the world, the Internet

3. SUPERLATIVE VE ORDINAL:
the best, the first, the only, the same

4. ÜLKE/BÖLGE GRUPLARI:
the USA, the UK, the Netherlands, the Alps

5. DENİZ/OKYANUS/NEHİR:
the Pacific, the Nile, the Mediterranean

6. SPEC. İSİM + of + İSİM:
the University of Oxford, the Bank of England

🎯 "THE" KULLANILMAYAN DURUMLAR:
• Genel konularda (çoğul): "Cats are cute." (değil: The cats)
• Ülke isimleri (çoğu): Turkey, Japan, France
• Dağ isimleri: Mount Everest
• Diller: English, Turkish
• Öğünler: breakfast, lunch, dinner
• Sporlar: football, tennis
''',
      formula: '''
THE + Belirli/Bilinen İsim

"I bought a book. THE book was expensive."
"THE sun rises in the east."
''',
      formulaEn: '''
THE + a specific or already-known noun

"I bought a book. THE book was expensive."
"THE sun rises in the east."
''',
      examples: [
        GrammarExample(
          english: 'The Earth revolves around the Sun.',
          turkish: 'Dünya güneşin etrafında döner.',
          note: 'Tek olan (the Sun, the Earth)',
        ),
        GrammarExample(
          english: 'This is the best movie I have ever seen.',
          turkish: 'Bu gördüğüm en iyi film.',
          note: 'Superlative + the',
        ),
        GrammarExample(
          english: 'They traveled across the United States.',
          turkish: 'Amerika Birleşik Devletleri\'ni gezdiler.',
          note: 'The + "United" ülkeler',
        ),
        GrammarExample(
          english: 'Please close the door.',
          turkish: 'Lütfen kapıyı kapa.',
          note: 'Bilinen (odadaki kapı)',
        ),
        GrammarExample(
          english: 'The life is beautiful.',
          turkish: 'Hayat güzeldir.',
          isCorrect: false,
          note: '❌ YANLIŞ! Genel kavram: Life is beautiful.',
        ),
      ],
      commonMistakes: [
        '❌ The life is hard. → ✅ Life is hard. (genel)',
        '❌ I like the coffee. → ✅ I like coffee. (genel)',
        '❌ He speaks the English. → ✅ He speaks English. (dil)',
        '❌ Let\'s have the lunch. → ✅ Let\'s have lunch. (öğün)',
      ],
      keyPoints: [
        '🔑 Genel konularda "THE" kullanılmaz',
        '🔑 Diller, öğünler, sporlar → "THE" yok',
        '🔑 Superlative (the best) ve ordinal (the first) → "THE" var',
        '🔑 Okyanuslar, denizler, nehirler → "THE" var',
      ],
      examTip: '💡 YDS\'de "The money is important" veya "The love is great" görürseniz YANLIŞ! Genel kavramlarda the yok.',
    ),

    // 3. ZERO ARTICLE
    GrammarSubtopic(
      id: 'zero_article',
      title: 'Zero Article',
      titleTr: 'Artikelsiz Kullanım',
      explanation: '''
Bazı durumlarda hiçbir tanımlık (a/an/the) kullanılmaz.

🎯 ZERO ARTICLE DURUMLAR:

1. GENEL KAVRAMLAR (ÇOĞUL/SAYILAMAZ):
"Dogs are loyal." (Köpekler sadıktır - genel)
"Water is essential." (Su gereklidir - genel)

2. DİLLER:
"He speaks French fluently."

3. ÜLKE İSİMLERİ (çoğu):
"Turkey is beautiful." (değil: The Turkey)

4. ÖĞÜNLER:
"Let's have breakfast."

5. SPORLAR:
"I play tennis."

6. OKUL/HAPİSHANE/HASTANe (AMAÇ):
"He is in prison." (Mahkum olarak)
"She is at school." (Öğrenci olarak)
⚠️ FAKAT: "He is in THE prison." (Ziyarete gitti)

7. DAĞ İSİMLERİ (tekil):
"Mount Everest" (değil: The Mount Everest)

8. GÖLLER:
"Lake Baikal" (değil: The Lake Baikal)
''',
      formula: '''
Ø (Zero Article) + Genel isim
Ø + Dil, ülke, öğün, spor

"Life is short."
"I love music."
"She speaks Japanese."
''',
      formulaEn: '''
Ø (Zero Article) + a noun in general
Ø + languages, countries, meals, sports

"Life is short."
"I love music."
"She speaks Japanese."
''',
      examples: [
        GrammarExample(
          english: 'Money doesn\'t buy happiness.',
          turkish: 'Para mutluluk satın almaz.',
          note: 'Genel kavramlar (money, happiness)',
        ),
        GrammarExample(
          english: 'I had breakfast at 8 AM.',
          turkish: 'Saat 8\'de kahvaltı yaptım.',
          note: 'Öğün - the yok',
        ),
        GrammarExample(
          english: 'He is in hospital.',
          turkish: 'Hastanede yatıyor. (Hasta olarak)',
          note: 'Amaç - the yok',
        ),
        GrammarExample(
          english: 'He is in the hospital.',
          turkish: 'Hastanede. (Ziyaret veya bina)',
          note: 'Bina olarak - the var',
        ),
        GrammarExample(
          english: 'She studies the history at university.',
          turkish: 'Üniversitede tarih okuyor.',
          isCorrect: false,
          note: '❌ YANLIŞ! Ders/alan: She studies history.',
        ),
      ],
      commonMistakes: [
        '❌ I like the music. → ✅ I like music. (genel)',
        '❌ The Mount Everest → ✅ Mount Everest',
        '❌ The Lake Michigan → ✅ Lake Michigan',
        '❌ I study the English. → ✅ I study English.',
      ],
      keyPoints: [
        '🔑 Genel kavramlar, diller, öğünler → tanımlık YOK',
        '🔑 Mount + isim → the yok',
        '🔑 Lake + isim → the yok',
        '🔑 School/hospital/prison → amaç ise the yok, bina ise the var',
      ],
      comparison: '''
🆚 Amaç vs Bina:
• "He is in PRISON." (Mahkum - amaç)
• "He is in THE PRISON." (Ziyaretçi - bina)

• "She is at SCHOOL." (Öğrenci - amaç)
• "She is at THE SCHOOL." (Başka bir iş için - bina)
''',
      examTip: '💡 YDS\'de "go to the school" (öğrenci olarak) veya "in the hospital" (hasta olarak) YANLIŞTIR!',
    ),

    // 4. QUANTIFIERS
    GrammarSubtopic(
      id: 'quantifiers',
      title: 'Quantifiers',
      titleTr: 'Miktar Belirteçleri',
      explanation: '''
Miktarı belirten kelimelerdir. Sayılabilir ve sayılamaz isimlere göre farklılık gösterir.

🎯 SAYILABILIR (Countable) İÇİN:
• many, few, a few, several, a number of
"Many students passed." (Birçok öğrenci)
"A few students failed." (Birkaç öğrenci)

🎯 SAYILAMAZ (Uncountable) İÇİN:
• much, little, a little, a great deal of, an amount of
"Much information was given." (Çok bilgi)
"A little milk, please." (Biraz süt)

🎯 HER İKİSİ İÇİN:
• some, any, a lot of, lots of, plenty of, no, all, most
"Some books / Some water"
"A lot of people / A lot of money"

🎯 FEW vs A FEW, LITTLE vs A LITTLE:
• FEW / LITTLE: Olumsuz anlam (çok az, yetersiz)
  "Few people came." (Az geldi - hayal kırıklığı)
  
• A FEW / A LITTLE: Olumlu anlam (biraz, yeterli)
  "A few people came." (Birkaç kişi geldi - yeterli)
''',
      formula: '''
Countable: many, few, a few, several
Uncountable: much, little, a little
Both: some, any, a lot of, no

"Many books" ✓   "Many water" ✗
"Much water" ✓   "Much books" ✗
''',
      examples: [
        GrammarExample(
          english: 'I don\'t have much time.',
          turkish: 'Çok zamanım yok.',
          note: 'much + sayılamaz (time)',
        ),
        GrammarExample(
          english: 'There are many students in the class.',
          turkish: 'Sınıfta birçok öğrenci var.',
          note: 'many + sayılabilir çoğul',
        ),
        GrammarExample(
          english: 'I have a little money left.',
          turkish: 'Biraz param kaldı. (Yeterli)',
          note: 'a little (olumlu)',
        ),
        GrammarExample(
          english: 'He has little patience.',
          turkish: 'Çok az sabrı var. (Yetersiz)',
          note: 'little (olumsuz)',
        ),
        GrammarExample(
          english: 'I don\'t have many money.',
          turkish: 'Çok param yok.',
          isCorrect: false,
          note: '❌ YANLIŞ! much money (sayılamaz)',
        ),
      ],
      commonMistakes: [
        '❌ many money → ✅ much money',
        '❌ much books → ✅ many books',
        '❌ few information → ✅ little information',
        '❌ a little people → ✅ a few people',
      ],
      keyPoints: [
        '🔑 MANY/FEW → Sayılabilir çoğul',
        '🔑 MUCH/LITTLE → Sayılamaz',
        '🔑 A FEW/A LITTLE → Olumlu (biraz, yeterli)',
        '🔑 FEW/LITTLE → Olumsuz (çok az, yetersiz)',
      ],
      examTip: '💡 YDS\'de "many information" veya "much students" görürseniz YANLIŞ!',
    ),
  ],
);
