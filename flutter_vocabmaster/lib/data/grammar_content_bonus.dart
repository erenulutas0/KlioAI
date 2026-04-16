import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// ERROR CORRECTION (Bonus Grammar)
const errorCorrectionTopic = GrammarTopic(
  id: 'error_correction',
  title: 'Error Correction',
  titleTr: 'Hata Düzeltme',
  level: 'bonus',
  icon: Icons.bug_report,
  color: Color(0xFF8b5cf6),
  subtopics: [
    // 1. COMMON VERB ERRORS
    GrammarSubtopic(
      id: 'common_verb_errors',
      title: 'Common Verb Errors',
      titleTr: 'Yaygın Fiil Hataları',
      explanation: '''
Türkçe düşünmekten kaynaklanan en yaygın fiil hataları.

🎯 SUBJECT-VERB AGREEMENT:
• Her 3. tekil şahıs (he/she/it) Present Simple'da -s alır
❌ He work hard.
✅ He works hard.

• "Everyone, everybody, someone, nobody" tekildir
❌ Everyone are here.
✅ Everyone is here.

🎯 AUXILIARY VERB ERRORS:
❌ Does she likes?
✅ Does she like? (does varken -s olmaz)

❌ She didn't went.
✅ She didn't go. (did varken V2 olmaz)

🎯 MODAL ERRORS:
❌ I can to swim.
✅ I can swim. (modal sonrası to yok)

❌ He musts study.
✅ He must study. (modal'a -s eklenmez)

🎯 STATIVE VERB ERRORS:
❌ I am knowing the answer.
✅ I know the answer. (know stative - continuous olmaz)

❌ I am believing you.
✅ I believe you.
''',
      formula: '''
✓ S/he + V-s (Present Simple)
✓ Does/Did + V1 (yardımcı varken yalın fiil)
✓ Modal + V1 (to yok, -s yok)
''',
      examples: [
        GrammarExample(
          english: 'She don\'t like coffee.',
          turkish: 'Kahve sevmiyor.',
          isCorrect: false,
          note: '❌ She DOESN\'T like...',
        ),
        GrammarExample(
          english: 'Nobody know the answer.',
          turkish: 'Kimse cevabı bilmiyor.',
          isCorrect: false,
          note: '❌ Nobody KNOWS... (tekil)',
        ),
        GrammarExample(
          english: 'I am understanding now.',
          turkish: 'Şu an anlıyorum.',
          isCorrect: false,
          note: '❌ I UNDERSTAND now. (stative)',
        ),
        GrammarExample(
          english: 'She can speaks English.',
          turkish: 'İngilizce konuşabiliyor.',
          isCorrect: false,
          note: '❌ She can SPEAK... (modal + V1)',
        ),
      ],
      keyPoints: [
        '🔑 3. tekil şahıs → -s (works, studies, goes)',
        '🔑 Does/Did varken ana fiil YALIN kalır',
        '🔑 Modal sonrası TO ve -S olmaz',
        '🔑 Stative verbs (know, believe, love) continuous yapılmaz',
      ],
      examTip: '💡 YDS\'de "Everyone are" veya "Does she likes" çok sık çıkar. Bunlar her zaman YANLIŞ!',
    ),

    // 2. COMMON PREPOSITION ERRORS
    GrammarSubtopic(
      id: 'common_preposition_errors',
      title: 'Common Preposition Errors',
      titleTr: 'Yaygın Edat Hataları',
      explanation: '''
Türkçe'den birebir çeviri yaparken yapılan edat hataları.

🎯 YAYGIIN YANLIŞ / DOĞRU ÇİFTLERİ:

❌ married WITH → ✅ married TO
❌ listen him → ✅ listen TO him
❌ wait you → ✅ wait FOR you
❌ interested AT → ✅ interested IN
❌ different THAN → ✅ different FROM
❌ afraid FROM → ✅ afraid OF
❌ arrive TO → ✅ arrive IN/AT
❌ enter TO → ✅ enter (edat almaz!)
❌ discuss ABOUT → ✅ discuss (edat almaz!)
❌ reach TO → ✅ reach (edat almaz!)
❌ attend TO → ✅ attend (edat almaz!)
❌ answer TO → ✅ answer (edat almaz!)

🎯 EDAT ALMAYAN FİİLLER:
enter, discuss, reach, attend, answer, approach, marry
Bu fiiller doğrudan nesne alır, edat gerekmez!
''',
      formula: '''
❌ Gereksiz edat: discuss ABOUT, reach TO
❌ Yanlış edat: married WITH, afraid FROM
❌ Eksik edat: listen him, wait you
''',
      examples: [
        GrammarExample(
          english: 'She is married with a doctor.',
          turkish: 'Bir doktorla evli.',
          isCorrect: false,
          note: '❌ married TO',
        ),
        GrammarExample(
          english: 'Let\'s discuss about the problem.',
          turkish: 'Sorunu tartışalım.',
          isCorrect: false,
          note: '❌ discuss (edat yok!)',
        ),
        GrammarExample(
          english: 'The train arrived to the station.',
          turkish: 'Tren istasyona vardı.',
          isCorrect: false,
          note: '❌ arrived AT the station',
        ),
        GrammarExample(
          english: 'I couldn\'t reach to him.',
          turkish: 'Ona ulaşamadım.',
          isCorrect: false,
          note: '❌ reach (edat yok!)',
        ),
      ],
      keyPoints: [
        '🔑 MARRIED TO, not with',
        '🔑 DISCUSS/ENTER/REACH/ATTEND → edat almaz',
        '🔑 LISTEN TO, WAIT FOR, LOOK AT → edat şart',
        '🔑 ARRIVE IN (city), ARRIVE AT (place)',
      ],
      examTip: '💡 "Discuss about" ve "married with" YDS\'nin en sevdiği tuzaklardır!',
    ),

    // 3. COMMON WORD ORDER ERRORS
    GrammarSubtopic(
      id: 'common_word_order_errors',
      title: 'Common Word Order Errors',
      titleTr: 'Yaygın Söz Dizimi Hataları',
      explanation: '''
İngilizce'de kelime sırası katıdır. Türkçe'nin esnek yapısından kaynaklanan hatalar.

🎯 SIFAT SIRASI:
İngilizce'de sıfatlar isimden ÖNCE gelir ve sıralama önemlidir.
❌ A car red big → ✅ A big red car
OSASCOMP: Opinion-Size-Age-Shape-Color-Origin-Material-Purpose

🎯 ZARF POZİSYONU:
• Sıklık zarfları (always, never) → yardımcı fiilden SONRA, ana fiilden ÖNCE
❌ I always am tired. → ✅ I am always tired.
❌ She goes always there. → ✅ She always goes there.

• "Enough" → sıfattan SONRA
❌ enough tall → ✅ tall enough

🎯 NESNE POZİSYONU:
Nesne fiilden hemen sonra gelir, araya giremez.
❌ I play every day football. → ✅ I play football every day.

🎯 INDIRECT QUESTION:
❌ I wonder where is he. → ✅ I wonder where he is.
''',
      formula: '''
S + V + O (Özne-Yüklem-Nesne sabit!)
Freq. Adverb: Subject + BE + always / Subject + always + V
Adjective + enough (not: enough + adj)
''',
      examples: [
        GrammarExample(
          english: 'I eat every morning breakfast.',
          turkish: 'Her sabah kahvaltı yaparım.',
          isCorrect: false,
          note: '❌ I eat breakfast every morning.',
        ),
        GrammarExample(
          english: 'She is enough old to drive.',
          turkish: 'Araba kullanacak kadar büyük.',
          isCorrect: false,
          note: '❌ old ENOUGH',
        ),
        GrammarExample(
          english: 'He never is late.',
          turkish: 'Asla geç kalmaz.',
          isCorrect: false,
          note: '❌ He IS never late.',
        ),
        GrammarExample(
          english: 'Tell me where does she live.',
          turkish: 'Bana nerede yaşadığını söyle.',
          isCorrect: false,
          note: '❌ Tell me where she LIVES.',
        ),
      ],
      keyPoints: [
        '🔑 Nesne fiilden ayrılmaz: "I play football every day"',
        '🔑 Enough → sıfattan SONRA: "tall enough"',
        '🔑 Sıklık zarfı: BE\'den sonra, diğer fiillerden önce',
        '🔑 Indirect question: düz cümle sırası',
      ],
      examTip: '💡 "Enough" pozisyonu çok sık sorulur. Sıfattan SONRA gelir!',
    ),

    // 4. COMMON ARTICLE ERRORS
    GrammarSubtopic(
      id: 'common_article_errors',
      title: 'Common Article Errors',
      titleTr: 'Yaygın Tanımlık Hataları',
      explanation: '''
Türkçe'de tanımlık olmadığı için bu konuda hatalar sık yapılır.

🎯 GEREKSIZ "THE":
❌ The life is beautiful. → ✅ Life is beautiful. (genel kavram)
❌ I speak the English. → ✅ I speak English. (dil)
❌ I had the breakfast. → ✅ I had breakfast. (öğün)
❌ The Mount Everest → ✅ Mount Everest (dağ ismi)

🎯 EKSİK "THE":
❌ Sun rises in east. → ✅ THE sun rises in THE east. (tek olan)
❌ He is best student. → ✅ He is THE best student. (superlative)
❌ Nile is longest river. → ✅ THE Nile is THE longest river.

🎯 A vs AN:
❌ An university → ✅ A university (yuu sesi)
❌ A hour → ✅ AN hour (h okunmaz)
❌ A honest man → ✅ AN honest man

🎯 SAYILAMAZ İSİMLER:
❌ I need an information. → ✅ I need information/some information.
❌ She gave me an advice. → ✅ She gave me advice/a piece of advice.
''',
      formula: '''
❌ The + genel kavram (life, love, money)
❌ The + dil (English, Turkish)
❌ A/An + sayılamaz (information, advice)
✓ The + tek olan (the sun, the moon)
✓ The + superlative (the best, the first)
''',
      examples: [
        GrammarExample(
          english: 'The happiness is important.',
          turkish: 'Mutluluk önemlidir.',
          isCorrect: false,
          note: '❌ Happiness is... (genel)',
        ),
        GrammarExample(
          english: 'I need an advice.',
          turkish: 'Bir tavsiyeye ihtiyacım var.',
          isCorrect: false,
          note: '❌ I need advice. (sayılamaz)',
        ),
        GrammarExample(
          english: 'She is best singer I know.',
          turkish: 'Tanıdığım en iyi şarkıcı.',
          isCorrect: false,
          note: '❌ THE best singer',
        ),
        GrammarExample(
          english: 'He has an European passport.',
          turkish: 'Avrupa pasaportu var.',
          isCorrect: false,
          note: '❌ A European (yuu sesi)',
        ),
      ],
      keyPoints: [
        '🔑 Genel kavramlar, diller, öğünler → THE yok',
        '🔑 Superlative (the best) → THE şart',
        '🔑 A/An = SES\'e göre (harf değil!)',
        '🔑 Information, advice, news → sayılamaz (a/an yok)',
      ],
      examTip: '💡 "An European" veya "a hour" her zaman YANLIŞ! Sesi dinle, harfe bakma.',
    ),
  ],
);

/// WORD ORDER (Bonus Grammar)
const wordOrderTopic = GrammarTopic(
  id: 'word_order',
  title: 'Word Order',
  titleTr: 'Kelime Sırası',
  level: 'bonus',
  icon: Icons.sort,
  color: Color(0xFF8b5cf6),
  subtopics: [
    // 1. BASIC SENTENCE ORDER
    GrammarSubtopic(
      id: 'basic_sentence_order',
      title: 'Basic Sentence Order (SVO)',
      titleTr: 'Temel Cümle Sırası',
      explanation: '''
İngilizce'de cümle sırası katıdır: Subject + Verb + Object (SVO)

🎯 TEMEL SIRA:
Özne + Yüklem + Nesne + Yer + Zaman
(S + V + O + Place + Time)

"I play football in the park every Sunday."
    S     V      O      Place       Time

🎯 TÜRLİ FARKLAR:
Türkçe: Özne + Zaman + Yer + Nesne + Yüklem
"Ben her Pazar parkta futbol oynarım."

İngilizce: Özne + Yüklem + Nesne + Yer + Zaman
"I play football in the park every Sunday."

⚠️ ÖNEMLİ:
• Nesne fiilden hemen sonra gelir, ayrılmaz!
❌ "I play every day football."
✅ "I play football every day."
''',
      formula: '''
S + V + O + Place + Time

"She reads books at home every evening."
   S     V     O    Place     Time
''',
      examples: [
        GrammarExample(
          english: 'I study English at home every day.',
          turkish: 'Her gün evde İngilizce çalışırım.',
          note: 'S-V-O-Place-Time',
        ),
        GrammarExample(
          english: 'We watched a movie at the cinema last night.',
          turkish: 'Dün gece sinemada film izledik.',
          note: 'S-V-O-Place-Time',
        ),
        GrammarExample(
          english: 'She always drinks coffee in the morning.',
          turkish: 'Sabahları her zaman kahve içer.',
          note: 'always fiilden önce',
        ),
      ],
      keyPoints: [
        '🔑 S + V + O sırası sabittir',
        '🔑 Nesne fiilden ayrılmaz',
        '🔑 Place genellikle Time\'dan önce gelir',
        '🔑 Zaman başa da sonra da alınabilir (vurgu)',
      ],
    ),

    // 2. ADVERB POSITION
    GrammarSubtopic(
      id: 'adverb_position',
      title: 'Adverb Position',
      titleTr: 'Zarf Pozisyonu',
      explanation: '''
Zarfların cümledeki pozisyonu türlerine göre değişir.

🎯 SIKLIK ZARFLARI (always, never, often, usually):
• BE fiilinden SONRA
  "She IS always late."
• Ana fiilden ÖNCE
  "She always GOES to work by bus."
• Modal + zarf + V
  "I can never forget you."

🎯 DERECE ZARFLARI (very, quite, rather):
• Sıfat/zarftan ÖNCE
  "She is VERY beautiful."
  "He speaks QUITE fluently."

🎯 TARZ ZARFLARI (quickly, carefully):
• Genellikle fiilden SONRA veya cümle sonunda
  "She spoke quickly."
  "He carefully opened the door."

🎯 ZAMAN ZARFLARI (yesterday, today):
• Genellikle cümle başında veya sonunda
  "Yesterday, I met him."
  "I met him yesterday."
''',
      formula: '''
Frequency: S + BE + adverb / S + adverb + V
Degree: adverb + adjective/adverb
Manner: V + adverb / adverb + V
Time: Beginning or End
''',
      examples: [
        GrammarExample(
          english: 'She is always happy.',
          turkish: 'O her zaman mutlu.',
          note: 'BE + always',
        ),
        GrammarExample(
          english: 'I never eat meat.',
          turkish: 'Asla et yemem.',
          note: 'never + V',
        ),
        GrammarExample(
          english: 'He speaks English very well.',
          turkish: 'İngilizce\'yi çok iyi konuşur.',
          note: 'V + adverb',
        ),
      ],
      keyPoints: [
        '🔑 BE + frequency adverb',
        '🔑 Frequency adverb + main verb',
        '🔑 Degree adverb + adjective',
        '🔑 Time adverbs: flexible (beginning/end)',
      ],
    ),

    // 3. ADJECTIVE ORDER
    GrammarSubtopic(
      id: 'adjective_order',
      title: 'Adjective Order',
      titleTr: 'Sıfat Sıralaması',
      explanation: '''
Birden fazla sıfat kullanıldığında belirli bir sıra izlenir: OSASCOMP

🎯 OSASCOMP KURALI:
1. Opinion (Görüş): beautiful, ugly, nice, horrible
2. Size (Boyut): big, small, tall, short
3. Age (Yaş): old, young, new, ancient
4. Shape (Şekil): round, square, flat
5. Color (Renk): red, blue, green
6. Origin (Köken): Turkish, American, Chinese
7. Material (Malzeme): wooden, plastic, golden
8. Purpose (Amaç): sleeping (bag), wedding (dress)

"A beautiful small old round blue Turkish wooden dining table"
   Opinion  Size Age Shape Color Origin Material Purpose  NOUN
''',
      formula: '''
Opinion + Size + Age + Shape + Color + Origin + Material + Purpose + NOUN

"A lovely little old rectangular green French silver whittling knife"
''',
      examples: [
        GrammarExample(
          english: 'A beautiful old Italian car.',
          turkish: 'Güzel eski bir İtalyan arabası.',
          note: 'Opinion-Age-Origin',
        ),
        GrammarExample(
          english: 'A big round wooden table.',
          turkish: 'Büyük yuvarlak ahşap bir masa.',
          note: 'Size-Shape-Material',
        ),
        GrammarExample(
          english: 'An ugly old red dress.',
          turkish: 'Çirkin eski kırmızı bir elbise.',
          note: 'Opinion-Age-Color',
        ),
      ],
      keyPoints: [
        '🔑 Opinion her zaman ilk sırada',
        '🔑 Size, Age, Shape → Color\'dan önce',
        '🔑 Origin, Material → Purpose\'dan önce',
        '🔑 Genellikle 3\'ten fazla sıfat kullanılmaz',
      ],
    ),
  ],
);

/// PARALLEL STRUCTURES (Bonus Grammar)
const parallelStructuresTopic = GrammarTopic(
  id: 'parallel_structures',
  title: 'Parallel Structures',
  titleTr: 'Paralel Yapılar',
  level: 'bonus',
  icon: Icons.view_column,
  color: Color(0xFF8b5cf6),
  subtopics: [
    // 1. PARALLELISM BASICS
    GrammarSubtopic(
      id: 'parallelism_basics',
      title: 'Parallelism Basics',
      titleTr: 'Paralellik Temelleri',
      explanation: '''
Bir cümledeki eşit öğeler (and, or, but ile bağlananlar) aynı dilbilgisel yapıda olmalıdır.

🎯 PARALEL YAPI KURALI:
Verb + Verb (aynı form)
Noun + Noun
Adjective + Adjective
Gerund + Gerund
Infinitive + Infinitive

❌ "I like swimming, to run, and basketball."
   (gerund, infinitive, noun - PARALEL DEĞİL!)
✅ "I like swimming, running, and playing basketball."
   (gerund, gerund, gerund - PARALEL!)

⚠️ İKİLİ BAĞLAÇLARDA:
• both...and
• either...or
• neither...nor
• not only...but also

Bu bağlaçlardan sonra gelen yapılar da paralel olmalı!
''',
      formula: '''
X and/or Y → X ve Y aynı yapıda

Noun + and + Noun
V-ing + and + V-ing
To V + and + To V
Adj + and + Adj
''',
      examples: [
        GrammarExample(
          english: 'She enjoys reading, writing, and painting.',
          turkish: 'Okumayı, yazmayı ve resim yapmayı sever.',
          note: 'V-ing + V-ing + V-ing ✓',
        ),
        GrammarExample(
          english: 'He is smart, hardworking, and reliable.',
          turkish: 'Zeki, çalışkan ve güvenilir.',
          note: 'Adj + Adj + Adj ✓',
        ),
        GrammarExample(
          english: 'The report was accurate and detailed.',
          turkish: 'Rapor doğru ve ayrıntılıydı.',
          note: 'Adj + Adj ✓',
        ),
        GrammarExample(
          english: 'She likes to swim, running, and plays tennis.',
          turkish: 'Yüzmeyi, koşmayı ve tenis oynamayı sever.',
          isCorrect: false,
          note: '❌ to V / V-ing / V-s (paralel değil!)',
        ),
      ],
      keyPoints: [
        '🔑 And/Or ile bağlanan öğeler aynı yapıda olmalı',
        '🔑 Gerund + Gerund veya To V + To V',
        '🔑 Noun + Noun veya Adj + Adj',
        '🔑 İkili bağlaçlarda da paralellik şart',
      ],
      examTip: '💡 YDS\'de liste içeren cümlelerde paralellik bozulmuşsa YANLIŞ!',
    ),

    // 2. CORRELATIVE PARALLELISM
    GrammarSubtopic(
      id: 'correlative_parallelism',
      title: 'Correlative Conjunctions',
      titleTr: 'İkili Bağlaçlarda Paralellik',
      explanation: '''
İkili bağlaçlardan (correlative conjunctions) sonra gelen yapılar paralel olmalıdır.

🎯 İKİLİ BAĞLAÇLAR:
• both...AND
• either...OR
• neither...NOR
• not only...BUT ALSO
• whether...OR

❌ "She is both smart and has beauty."
   (adj + clause - paralel değil!)
✅ "She is both smart and beautiful."
   (adj + adj - paralel!)

❌ "He not only plays guitar but also singing."
   (V + V-ing - paralel değil!)
✅ "He not only plays guitar but also sings."
   (V + V - paralel!)
''',
      formula: '''
Both X and Y → X = Y (aynı yapı)
Either X or Y → X = Y
Neither X nor Y → X = Y
Not only X but also Y → X = Y
''',
      examples: [
        GrammarExample(
          english: 'She is both intelligent and creative.',
          turkish: 'Hem zeki hem yaratıcı.',
          note: 'Adj + Adj ✓',
        ),
        GrammarExample(
          english: 'You can either stay or leave.',
          turkish: 'Ya kalabilirsin ya gidebilirsin.',
          note: 'V + V ✓',
        ),
        GrammarExample(
          english: 'He neither called nor texted.',
          turkish: 'Ne aradı ne mesaj attı.',
          note: 'V + V ✓',
        ),
        GrammarExample(
          english: 'She is neither honest nor is trustworthy.',
          turkish: 'Ne dürüst ne güvenilir.',
          isCorrect: false,
          note: '❌ adj + is adj (paralel değil!)',
        ),
      ],
      keyPoints: [
        '🔑 Both...and: her iki taraf aynı yapı',
        '🔑 Either...or: her iki taraf aynı yapı',
        '🔑 Neither...nor: her iki taraf aynı yapı',
        '🔑 Not only...but also: her iki taraf aynı yapı',
      ],
      examTip: '💡 "Both smart and has talent" YANLIŞ! "Both smart and talented" doğru.',
    ),

    // 3. COMPARISON PARALLELISM
    GrammarSubtopic(
      id: 'comparison_parallelism',
      title: 'Comparison Parallelism',
      titleTr: 'Karşılaştırmada Paralellik',
      explanation: '''
Karşılaştırma yaparken karşılaştırılan öğeler paralel olmalıdır.

🎯 TEMEL KURAL:
Elmaları elmalarla, portakalları portakallarla karşılaştır!

❌ "The weather in Turkey is hotter than England."
   (weather vs England - elma vs portakal!)
✅ "The weather in Turkey is hotter than the weather in England."
✅ "The weather in Turkey is hotter than that in England."
   (weather vs weather)

🎯 KARŞILAŞTIRMA ZAMİRLERİ:
• that of: tekil isimler için
• those of: çoğul isimler için

"The population of China is larger than THAT OF Japan."
(population vs population)

"The students in my class are smarter than THOSE IN hers."
(students vs students)
''',
      formula: '''
X...than X (aynı kategori)
X...than that of Y (tekil)
X...than those of Y (çoğul)
''',
      examples: [
        GrammarExample(
          english: 'Her salary is higher than that of her colleague.',
          turkish: 'Maaşı iş arkadaşınınkinden yüksek.',
          note: 'salary vs that (salary) ✓',
        ),
        GrammarExample(
          english: 'The cars in Germany are better than those in Italy.',
          turkish: 'Almanya\'daki arabalar İtalya\'dakilerden iyi.',
          note: 'cars vs those (cars) ✓',
        ),
        GrammarExample(
          english: 'Her hair is longer than me.',
          turkish: 'Saçları benimkinden uzun.',
          isCorrect: false,
          note: '❌ hair vs me (paralel değil!)',
        ),
      ],
      keyPoints: [
        '🔑 Aynı kategorileri karşılaştır',
        '🔑 "That of" tekil isimler için',
        '🔑 "Those of" çoğul isimler için',
        '🔑 "...than mine/yours/his/hers" possessive parallelism',
      ],
      examTip: '💡 "The price of apples is higher than oranges" YANLIŞ! "...than that of oranges" doğru.',
    ),
  ],
);
