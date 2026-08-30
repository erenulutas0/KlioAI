import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// RELATIVE CLAUSES (Advanced Grammar)
const relativeClausesTopic = GrammarTopic(
  id: 'relative_clauses',
  title: 'Relative Clauses',
  titleTr: 'Sıfat Cümlecikleri',
  level: 'advanced',
  icon: Icons.link,
  color: Color(0xFFf59e0b),
  subtopics: [
    // 1. DEFINING VS NON-DEFINING
    GrammarSubtopic(
      id: 'defining_vs_nondefining',
      title: 'Defining vs Non-Defining',
      titleTr: 'Belirleyici ve Belirleyici Olmayan',
      explanation: '''
Sıfat cümlecikleri (Relative Clauses), bir ismi niteleyen, onun hakkında ek bilgi veren cümlelerdir. İki ana türü vardır:

🎯 1. DEFINING (Identifying - Belirleyici):
• Cümlenin anlamı için ŞART olan bilgiyi verir
• Virgül KULLANILMAZ
• "That" kullanılabilir
• "Which/Who" atılabilir (nesne pozisyonunda ise)

🎯 2. NON-DEFINING (Additional Info - Ek Bilgi):
• Ekstra, çıkarılabilir bilgi verir
• VİRGÜL KULLANILIR (cümlenin ortasında veya sonunda)
• "That" KULLANILMAZ
• Relative pronoun atılamaz

💡 Kritik Fark:
"My brother who lives in London came." (Londra'da yaşayan kardeşim geldi - birden fazla kardeşim var, o özellikle geldi)
"My brother, who lives in London, came." (Kardeşim geldi, o Londra'da yaşar - tek kardeşim var, ek bilgi)
''',
      explanationEn: '''
A relative clause describes a noun and tells you more about it. There are two kinds, and the difference changes the meaning of the sentence.

🎯 1. DEFINING — it identifies which one:
• The information is essential to the meaning
• NO commas
• "That" is allowed
• "Which/who" can be dropped when it is the object

🎯 2. NON-DEFINING — it adds an aside:
• The information could be removed and the sentence would still stand
• COMMAS are required, in the middle or at the end
• "That" is NOT allowed
• The relative pronoun cannot be dropped

💡 The critical difference:
"My brother who lives in London came." — I have more than one brother; this is the one who came.
"My brother, who lives in London, came." — I have one brother; where he lives is an aside.
''',
      formula: '''
Defining: The man WHO/THAT lives here is my uncle.
Non-Defining: My father, WHO is 60, retired.

⚠️ VİRGÜL = NON-DEFINING = NO "THAT"
''',
      formulaEn: '''
Defining: The man WHO/THAT lives here is my uncle.
Non-Defining: My father, WHO is 60, retired.

⚠️ COMMA = NON-DEFINING = NO "THAT"
''',
      examples: [
        GrammarExample(
          english: 'The students who studied passed the exam.',
          turkish: 'Çalışan öğrenciler sınavı geçti.',
          note: 'Defining (virgülsüz) - Sadece çalışanlar geçti',
        ),
        GrammarExample(
          english: 'My mother, who is a doctor, works at a hospital.',
          turkish: 'Annem, doktor olan, hastanede çalışıyor.',
          note: 'Non-Defining (virgüllü) - Ek bilgi',
        ),
        GrammarExample(
          english: 'The book that I bought yesterday was interesting.',
          turkish: 'Dün aldığım kitap ilginçti.',
          note: 'Defining - "that" kullanılabilir',
        ),
        GrammarExample(
          english: 'Paris, which is the capital of France, is beautiful.',
          turkish: 'Fransa\'nın başkenti Paris güzel.',
          note: 'Non-Defining - "that" KULLANILAMAZ',
          isCorrect: true,
        ),
      ],
      commonMistakes: [
        '❌ My mother, THAT is a doctor... → ✅ My mother, WHO is a doctor... (Virgül varsa that olmaz!)',
        '❌ Paris, that is beautiful... → ✅ Paris, which is beautiful... (Özel isimler non-defining olmalı)',
        '❌ The Eiffel Tower which is in Paris → ✅ The Eiffel Tower, which is in Paris, (Tek olan şeyler virgüllü olmalı)',
      ],
      commonMistakesEn: [
        '❌ My mother, THAT is a doctor... → ✅ My mother, WHO is a doctor... (no "that" after a comma)',
        '❌ Paris, that is beautiful... → ✅ Paris, which is beautiful... (a proper noun takes a non-defining clause)',
        '❌ The Eiffel Tower which is in Paris → ✅ The Eiffel Tower, which is in Paris, (something one of a kind takes commas)',
      ],
      keyPoints: [
        '🔑 Virgül görürsen → Non-Defining → "That" ASLA kullanılmaz',
        '🔑 Özel isimler (Paris, John) → HER ZAMAN Non-Defining (virgüllü)',
        '🔑 Tek olan şeyler (The sun, My father) → Non-Defining',
        '🔑 "That" sadece Defining Clause\'da kullanılır',
      ],
      keyPointsEn: [
        '🔑 If you see a comma → non-defining → "that" is NEVER used',
        '🔑 Proper nouns (Paris, John) → ALWAYS non-defining, with commas',
        '🔑 Things there is only one of (the sun, my father) → non-defining',
        '🔑 "That" belongs to defining clauses only',
      ],
      examTip: '💡 YDS\'de boşluktan önce virgül varsa, şıklarda "that"i hemen eleyin! Geriye "who" veya "which" kalır.',
    ),

    // 2. RELATIVE PRONOUNS
    GrammarSubtopic(
      id: 'relative_pronouns',
      title: 'Relative Pronouns',
      titleTr: 'Bağıl Zamirler',
      explanation: '''
Sıfat cümlelerini bağlamak için kullanılan zamirlerdir.

🎯 TEMEL ZAMİRLER:

👤 WHO: İnsanlar için (Subject/Object)
• The man WHO called you is my friend.

👤 WHOM: İnsanlar için, SADECE Object pozisyonunda (Resmi)
• The man WHOM I saw is my friend.
• ⚠️ Preposition'dan sonra WHOM kullanılır: "The man TO WHOM I spoke..."

🔵 WHICH: Nesneler ve hayvanlar için
• The book WHICH I read was good.

🔵 THAT: İnsanlar, nesneler için (Defining'de)
• The man THAT lives here...
• The book THAT I read...

💼 WHOSE: Sahiplik (Onun... -i)
• The girl WHOSE car was stolen...
• ⚠️ İnsan/hayvan/nesne hepsi için kullanılır!

📍 WHERE: Yer için
• The city WHERE I was born...
• = ...in which I was born

⏰ WHEN: Zaman için
• The day WHEN I got married...
• = ...on which I got married

❓ WHY: Sebep için (only with "reason")
• The reason WHY I came...
• = ...for which I came
''',
      explanationEn: '''
These are the pronouns that join a relative clause to the noun it describes.

🎯 THE MAIN ONES:

👤 WHO: for people, as subject or object
• The man WHO called you is my friend.

👤 WHOM: for people, as object only, and formal
• The man WHOM I saw is my friend.
• ⚠️ After a preposition it must be whom: "The man TO WHOM I spoke..."

🔵 WHICH: for things and animals
• The book WHICH I read was good.

🔵 THAT: for people and things, in defining clauses only
• The man THAT lives here...
• The book THAT I read...

💼 WHOSE: possession
• The girl WHOSE car was stolen...
• ⚠️ It works for people, animals and things alike.

📍 WHERE: for places
• The city WHERE I was born...
• = ...in which I was born

⏰ WHEN: for times
• The day WHEN I got married...
• = ...on which I got married

❓ WHY: for reasons, and only after "reason"
• The reason WHY I came...
• = ...for which I came
''',
      formula: '''
Subject: The man WHO lives here...
Object: The man (WHO/WHOM/THAT) I saw...
Possessive: The man WHOSE car...
Place: The city WHERE/IN WHICH I live...
Time: The day WHEN/ON WHICH I arrived...
''',
      examples: [
        GrammarExample(
          english: 'The woman WHO called you is my sister.',
          turkish: 'Seni arayan kadın benim kardeşim.',
          note: 'WHO = Özne pozisyonu (called\'ın öznesi)',
        ),
        GrammarExample(
          english: 'The woman (whom/who/that) I called is my sister.',
          turkish: 'Aradığım kadın kardeşim.',
          note: 'Object pozisyonu - Atılabilir!',
        ),
        GrammarExample(
          english: 'The house whose roof was damaged is being repaired.',
          turkish: 'Çatısı hasar gören ev tamir ediliyor.',
          note: 'WHOSE - Sahiplik (evin çatısı)',
        ),
        GrammarExample(
          english: 'This is the restaurant where we first met.',
          turkish: 'Burası ilk tanıştığımız restoran.',
          note: 'WHERE = Yer',
        ),
        GrammarExample(
          english: 'The person to who I spoke was very helpful.',
          turkish: 'Konuştuğum kişi çok yardımcı oldu.',
          isCorrect: false,
          note: '❌ YANLIŞ! Preposition sonrası WHOM olmalı.',
        ),
      ],
      commonMistakes: [
        '❌ The man WHICH I saw → ✅ The man WHO/WHOM/THAT I saw (İnsan için which olmaz)',
        '❌ The book WHO I read → ✅ The book WHICH/THAT I read (Nesne için who olmaz)',
        '❌ The man WHOSE he is rich → ✅ The man WHO is rich (Whose arkasından isim gelir!)',
        '❌ The place WHICH I work → ✅ The place WHERE I work / The place WHICH I work AT',
      ],
      commonMistakesEn: [
        '❌ The man WHICH I saw → ✅ The man WHO/WHOM/THAT I saw ("which" is not used for people)',
        '❌ The book WHO I read → ✅ The book WHICH/THAT I read ("who" is not used for things)',
        '❌ The man WHOSE he is rich → ✅ The man WHO is rich ("whose" must be followed by a noun)',
        '❌ The place WHICH I work → ✅ The place WHERE I work / The place WHICH I work AT',
      ],
      keyPoints: [
        '🔑 WHOSE arkasından her zaman bir İSİM gelir (whose car, whose idea)',
        '🔑 WHERE = in/at which, WHEN = on/at which, WHY = for which',
        '🔑 Object pozisyonundaki who/which/that atılabilir',
        '🔑 Preposition + WHOM (resmi) / Who + preposition (günlük)',
      ],
      keyPointsEn: [
        '🔑 WHOSE is always followed by a NOUN (whose car, whose idea)',
        '🔑 WHERE = in/at which, WHEN = on/at which, WHY = for which',
        '🔑 Who/which/that can be dropped when it is the object',
        '🔑 Preposition + WHOM is formal; who... + preposition at the end is everyday',
      ],
      comparison: '''
🆚 WHO vs WHOM:
• WHO: Subject → "The man WHO called..." (Adam aradı)
• WHOM: Object → "The man WHOM I called..." (Adamı aradım)

💡 İpucu: "HIM" koyabiliyorsan WHOM, "HE" koyabiliyorsan WHO.
• I called HIM → whom
• HE called → who
''',
      comparisonEn: '''
🆚 WHO vs WHOM:
• WHO: the subject → "The man WHO called..." — he called
• WHOM: the object → "The man WHOM I called..." — I called him

💡 The test: if "him" fits, use whom; if "he" fits, use who.
• I called HIM → whom
• HE called → who
''',
      examTip: '💡 YDS\'de boşluktan sonra bir FİİL geliyorsa → WHO/WHICH (özne gerekiyor). Boşluktan sonra ÖZNE+FİİL geliyorsa → atılabilir veya whom.',
    ),

    // 3. REDUCED RELATIVE CLAUSES
    GrammarSubtopic(
      id: 'reduced_relative_clauses',
      title: 'Reduced Relative Clauses',
      titleTr: 'Kısaltılmış Sıfat Cümleleri',
      explanation: '''
Relative clause'ları daha kısa ve akıcı hale getirmek için "who/which/that + be" kısmını atarak kısaltabiliriz.

🎯 KURALLAR:

1. AKTİF FİİL → V-ing (Present Participle)
"The man WHO IS sitting there" → "The man sitting there"

2. PASİF FİİL → V3 (Past Participle)
"The book WHICH WAS written by Orwell" → "The book written by Orwell"

3. SIFAT (TO BE + ADJECTIVE)
"The students WHO ARE unable to come" → "The students unable to come"

4. TO-INFINITIVE (İlk, Son, Tek...)
"She was the first woman WHO won the prize" → "She was the first woman to win the prize"
''',
      explanationEn: '''
A relative clause can be shortened by dropping "who/which/that + be", which makes the sentence tighter and more natural.

🎯 THE RULES:

1. ACTIVE VERB → V-ing (present participle)
"The man WHO IS sitting there" → "The man sitting there"

2. PASSIVE VERB → V3 (past participle)
"The book WHICH WAS written by Orwell" → "The book written by Orwell"

3. ADJECTIVE (be + adjective)
"The students WHO ARE unable to come" → "The students unable to come"

4. TO-INFINITIVE (after first, last, only, or a superlative)
"She was the first woman WHO won the prize" → "She was the first woman to win the prize"
''',
      formula: '''
Active: who/which + V → V-ing
  "The man WHO lives here" → "The man living here"

Passive: who/which + be + V3 → V3
  "The car WHICH WAS stolen" → "The car stolen"

Adjective: who/which + be + adj → adj
  "Anyone WHO IS interested" → "Anyone interested"

First/Last/Only/Superlative + to-infinitive
''',
      examples: [
        GrammarExample(
          english: 'The man sitting in the corner is my uncle.',
          turkish: 'Köşede oturan adam amcam.',
          note: 'who is sitting → sitting (Active)',
        ),
        GrammarExample(
          english: 'The products made in China are cheap.',
          turkish: 'Çin\'de üretilen ürünler ucuz.',
          note: 'which are made → made (Passive)',
        ),
        GrammarExample(
          english: 'Do you know anyone interested in the job?',
          turkish: 'İşle ilgilenen birini tanıyor musun?',
          note: 'who is interested → interested (Adjective)',
        ),
        GrammarExample(
          english: 'She was the first woman to run a company.',
          turkish: 'Şirket yöneten ilk kadındı.',
          note: 'who ran → to run (First... to V1)',
        ),
        GrammarExample(
          english: 'There is nothing to eat.',
          turkish: 'Yiyecek bir şey yok.',
          note: 'which we can eat → to eat',
        ),
      ],
      commonMistakes: [
        '❌ The man lived next door → ✅ The man LIVING next door (Active = V-ing)',
        '❌ The letter writing by him → ✅ The letter WRITTEN by him (Passive = V3)',
        '❌ Anyone interest → ✅ Anyone INTERESTED (Sıfat)',
      ],
      commonMistakesEn: [
        '❌ The man lived next door → ✅ The man LIVING next door (active = V-ing)',
        '❌ The letter writing by him → ✅ The letter WRITTEN by him (passive = V3)',
        '❌ Anyone interest → ✅ Anyone INTERESTED (an adjective is needed)',
      ],
      keyPoints: [
        '🔑 Active (yapan) → V-ing: "The dog barking loudly"',
        '🔑 Passive (yapılan) → V3: "The cake baked by mom"',
        '🔑 Sadece DEFINING clause\'lar kısaltılabilir',
        '🔑 first/last/only/next/superlative → to-infinitive',
      ],
      keyPointsEn: [
        '🔑 Active → V-ing: "The dog barking loudly"',
        '🔑 Passive → V3: "The cake baked by mum"',
        '🔑 Only DEFINING clauses can be reduced',
        '🔑 first/last/only/next and superlatives → to-infinitive',
      ],
      examTip: '💡 YDS\'de boşluktan sonra isim geliyorsa V3 (passive), fiil geliyorsa V-ing (active) büyük ihtimalle doğrudur.',
    ),

    // 4. PREPOSITIONS IN RELATIVE CLAUSES
    GrammarSubtopic(
      id: 'prepositions_relative',
      title: 'Prepositions in Relative Clauses',
      titleTr: 'Edatlar ve Sıfat Cümleleri',
      explanation: '''
Preposition (edat) içeren sıfat cümlelerinde edatın yeri değişebilir.

🎯 İKİ YÖNTEM:

1. FORMAL (Resmi/Akademik):
Preposition + whom/which
• "The person TO WHOM I spoke was helpful."
• "The topic ABOUT WHICH we discussed was important."

2. INFORMAL (Günlük/Konuşma):
Who/Which/That... Preposition (sonda)
• "The person (who) I spoke TO was helpful."
• "The topic (which) we discussed ABOUT..."
• ⚠️ Bu yapıda "that" veya hiçbir şey kullanılabilir

💡 KRİTİK FARKLAR:
• Preposition başta ise → whom/which ZORUNLU
• Preposition sonda ise → who/which/that/nothing hepsi olur
• WHY = for which
• WHERE = in/at which
• WHEN = on/at which
''',
      explanationEn: '''
When a relative clause contains a preposition, the preposition can sit in either of two places.

🎯 THE TWO PATTERNS:

1. FORMAL, as in academic writing:
Preposition + whom/which
• "The person TO WHOM I spoke was helpful."
• "The topic ABOUT WHICH we spoke was important."

2. INFORMAL, as in speech:
Who/which/that... with the preposition at the end
• "The person (who) I spoke TO was helpful."
• "The topic (which) we spoke ABOUT..."
• ⚠️ Here "that" or nothing at all can be used

💡 THE CRITICAL DIFFERENCES:
• Preposition in front → whom/which is REQUIRED
• Preposition at the end → who/which/that/nothing all work
• WHY = for which
• WHERE = in/at which
• WHEN = on/at which
''',
      formula: '''
Formal: Prep + whom/which + S + V
  "The man TO WHOM I gave the book..."

Informal: (who/which/that/Ø) + S + V + Prep
  "The man (who) I gave the book TO..."
''',
      examples: [
        GrammarExample(
          english: 'The company for which I work is international.',
          turkish: 'Çalıştığım şirket uluslararası.',
          note: 'Formal: for which',
        ),
        GrammarExample(
          english: 'The company (that) I work for is international.',
          turkish: 'Çalıştığım şirket uluslararası.',
          note: 'Informal: sonda for',
        ),
        GrammarExample(
          english: 'The woman with whom I traveled was very kind.',
          turkish: 'Birlikte seyahat ettiğim kadın çok kibardı.',
          note: 'Formal: with whom',
        ),
        GrammarExample(
          english: 'Is this the issue you are worried about?',
          turkish: 'Endişelendiğin mesele bu mu?',
          note: 'Informal: sonda about, pronoun atılmış',
        ),
      ],
      commonMistakes: [
        '❌ The man to WHO I spoke → ✅ The man to WHOM I spoke (Prep + whom)',
        '❌ The topic about that we discussed → ✅ The topic ABOUT WHICH / that...about',
        '❌ For that I work → ✅ FOR WHICH I work (Prep başta ise that olmaz!)',
      ],
      commonMistakesEn: [
        '❌ The man to WHO I spoke → ✅ The man to WHOM I spoke (preposition + whom)',
        '❌ The topic about that we discussed → ✅ The topic ABOUT WHICH / that...about',
        '❌ For that I work → ✅ FOR WHICH I work ("that" cannot follow a preposition)',
      ],
      keyPoints: [
        '🔑 Preposition başta ise: %100 whom/which kullanılır, that ASLA!',
        '🔑 Preposition sonda ise: that, who, which hatta hiçbiri olabilir',
        '🔑 YDS/YÖKDİL\'de genellikle formal yapı (Prep + whom/which) sorulur',
      ],
      keyPointsEn: [
        '🔑 With the preposition in front: whom/which every time, and NEVER that',
        '🔑 With the preposition at the end: that, who, which or nothing at all',
        '🔑 Exams tend to ask for the formal pattern (preposition + whom/which)',
      ],
      examTip: '💡 Boşluktan önce preposition görürseniz → whom (insan) veya which (nesne). "That" şıkkını hemen eleyin!',
    ),
  ],
);
