import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// MODALS (Core Grammar)
const modalsTopic = GrammarTopic(
  id: 'modals',
  title: 'Modals',
  titleTr: 'Kip Ekleri',
  level: 'core',
  icon: Icons.settings_accessibility,
  color: Color(0xFF22c55e),
  subtopics: [
    // 1. ABILITY
    GrammarSubtopic(
      id: 'modals_ability',
      title: 'Ability',
      titleTr: 'Yetenek (Can / Could)',
      explanation: '''
Yetenek ve becerileri ifade etmek için "Can", "Could" ve "Be able to" kullanılır.

🎯 Kullanım Alanları:
• Can: Genel şimdiki zaman/geniş zaman yetenekleri
• Could: Genel geçmiş zaman yetenekleri
• Be able to: Herhangi bir zamanda (gelecek, perfect tense vb.) kullanılabilen yetenek kalıbı
''',
      explanationEn: '''
"Can", "could" and "be able to" express ability and skill.

🎯 Where each is used:
• Can: ability in the present
• Could: ability in the past, in general
• Be able to: ability in any tense, including the future and the perfect forms, where "can" has no form of its own
''',
      formula: '''
Subject + can/could + V1
Subject + be able to + V1
''',
      examples: [
        GrammarExample(
          english: 'I can swim very well.',
          turkish: 'Çok iyi yüzebilirim.',
          note: 'Genel yetenek (Şu an)',
        ),
        GrammarExample(
          english: 'She could read when she was 4.',
          turkish: '4 yaşındayken okuyabiliyordu.',
          note: 'Geçmiş genel yetenek',
        ),
        GrammarExample(
          english: 'I will be able to speak English fluently.',
          turkish: 'Akıcı İngilizce konuşabileceğim.',
          note: 'Gelecek yetenek (will can diyemeyiz!)',
        ),
        GrammarExample(
          english: 'I haven\'t been able to sleep lately.',
          turkish: 'Son zamanlarda uyuyamıyorum.',
          note: 'Perfect tense (have can diyemeyiz!)',
        ),
      ],
      commonMistakes: [
        '❌ I will can go. → ✅ I will be able to go.',
        '❌ He cans swim. → ✅ He can swim. (modallara -s gelmez)',
        '❌ She could saved him. → ✅ She was able to save him. (tek seferlik başarı)',
      ],
      keyPoints: [
        '🔑 Modallardan sonra fiil her zaman yalın (V1) gelir',
        '🔑 Modallar şahsa göre çekimlenmez (-s almaz)',
        '🔑 "Could" geçmiş genel yetenek içindir. Geçmişte tek seferlik zorlu bir başarı için "was/were able to" tercih edilir (managed to).',
      ],
      examTip: '💡 "Managed to" = "Was/were able to" (Zorlukla başardı anlamı katar).',
    ),

    // 2. OBLIGATION & NECESSITY
    GrammarSubtopic(
      id: 'modals_obligation',
      title: 'Obligation & Necessity',
      titleTr: 'Zorunluluk (Must / Have to)',
      explanation: '''
Zorunluluk ve gereklilik bildirmek için "Must" ve "Have to" kullanılır. Geçmiş zaman için "Had to" kullanılır.

🎯 Farklar:
• Must: İçten gelen zorunluluk (konuşmacının kararı), kurallar, güçlü tavsiyeler
• Have to: Dıştan gelen zorunluluk (yasa, okul kuralı, otorite), "zorundayım" anlamı
• Need to: Gereklilik (yapmam lazım)
''',
      explanationEn: '''
"Must" and "have to" express obligation and necessity. For the past, "had to" is used.

🎯 The difference:
• Must: obligation felt from within — the speaker's own decision, rules, strong advice
• Have to: obligation imposed from outside — a law, a school rule, an authority
• Need to: necessity, something that has to be done
''',
      formula: '''
Must + V1
Have to / Has to + V1
Don't have to / Doesn't have to + V1 (Zorunda değil)
Mustn't + V1 (Yasak!)
''',
      formulaEn: '''
Must + V1
Have to / Has to + V1
Don't have to / Doesn't have to + V1 (not required)
Mustn't + V1 (forbidden)
''',
      examples: [
        GrammarExample(
          english: 'I must call my mother.',
          turkish: 'Annemi aramalıyım.',
          note: 'Kendi kararım (İçten)',
        ),
        GrammarExample(
          english: 'Students have to wear uniforms.',
          turkish: 'Öğrenciler üniforma giymek zorunda.',
          note: 'Kural (Dıştan)',
        ),
        GrammarExample(
          english: 'You don\'t have to come if you act tired.',
          turkish: 'Yorgunsan gelmek zorunda değilsin.',
          note: 'Zorunluluk yok (Yapmasan da olur)',
        ),
        GrammarExample(
          english: 'You must NOT smoke here.',
          turkish: 'Burada sigara içemezsin/içmemelisin.',
          note: 'YASAK (Yapma!)',
        ),
      ],
      commonMistakes: [
        '❌ You don\'t must go. → ✅ You don\'t have to go. / You mustn\'t go.',
        '❌ I must went. → ✅ I had to go. ("Must"ın geçmişi "Had to"dur)',
        '❌ Must you go? → ✅ Do you have to go? (Sorularda genelde have to tercih edilir)',
      ],
      keyPoints: [
        '🔑 "Mustn\'t" = Yasak! (Yapma)',
        '🔑 "Don\'t have to" = Zorunda değilsin (İstersen yap)',
        '🔑 "Must" sadece şimdiki/gelecek zamanda kullanılır. Geçmiş için "Had to" kullanılır.',
      ],
      comparison: '''
🆚 Mustn't vs Don't Have to:
• "You mustn't touch that." → Dokunman yasak! (Dokunma)
• "You don't have to touch that." → Dokunmak zorunda değilsin. (Ama istersen dokun)
''',
      examTip: '💡 YDS\'de anlam farkı sorulur: "Mustn\'t" (Prohibition) vs "Don\'t have to" (Lack of necessity).',
    ),

    // 3. ADVICE & SUGGESTION
    GrammarSubtopic(
      id: 'modals_advice',
      title: 'Advice & Suggestion',
      titleTr: 'Tavsiye (Should / Ought to)',
      explanation: '''
Tavsiye vermek, fikir beyan etmek veya "yapman iyi olur" demek için kullanılır.

🎯 Yapılar:
• Should: En yaygın tavsiye kipi (-meli/-malı)
• Ought to: Should ile aynı anlamdadır, daha resmidir
• Had better: Güçlü tavsiye/uyarı (Yapmazsan kötü olur!)
''',
      explanationEn: '''
Used to give advice, offer an opinion, or say that something would be a good idea.

🎯 The forms:
• Should: the ordinary way to give advice
• Ought to: the same meaning as should, a little more formal
• Had better: strong advice or a warning — there will be a bad result otherwise
''',
      formula: '''
Should + V1
Ought to + V1
Had better + V1
''',
      examples: [
        GrammarExample(
          english: 'You should see a doctor.',
          turkish: 'Doktora görünmelisin.',
          note: 'Tavsiye',
        ),
        GrammarExample(
          english: 'We ought to help them.',
          turkish: 'Onlara yardım etmeliyiz.',
          note: 'Resmi/Ahlaki tavsiye',
        ),
        GrammarExample(
          english: 'You had better hurry or you will miss the bus.',
          turkish: 'Acele etsen iyi olur yoksa otobüsü kaçıracaksın.',
          note: 'Uyarı (Tehditvari)',
        ),
      ],
      commonMistakes: [
        '❌ You should to go. → ✅ You should go.',
        '❌ You better go. → ✅ You HAD better go.',
        '❌ Had better to go. → ✅ Had better go.',
      ],
      keyPoints: [
        '🔑 "Had better" geçmiş zaman DEĞİLDİR! Şimdiki veya gelecek zaman için uyarıdır.',
        '🔑 "Should" ve "Ought to" %99 birbirinin yerine kullanılabilir.',
      ],
      examTip: '💡 "It is advisable/recommended that..." kalıbı "Should" anlamı taşır.',
    ),

    // 4. POSSIBILITY
    GrammarSubtopic(
      id: 'modals_possibility',
      title: 'Possibility',
      titleTr: 'İhtimal (May / Might / Could)',
      explanation: '''
Olasılık ve ihtimal bildirmek için kullanılır. "Belki olur", "olabilir" anlamı katar.

🎯 Dereceler:
• May / Might / Could: %50 ihtimal (Belki)
• Must (Deduction): %90 ihtimal (Kesin öyledir - Çıkarım)
• Can't (Deduction): %90 ihtimal (Kesin öyle değildir - İmkansız)
''',
      explanationEn: '''
Used to express possibility and likelihood: that something may be so, or could happen.

🎯 Degrees of certainty:
• May / Might / Could: about even odds — perhaps
• Must (deduction): near certainty that something IS so
• Can't (deduction): near certainty that something is NOT so
''',
      formula: '''
Subject + may/might/could + V1
Subject + must + be (Öyle olmalı)
Subject + can't + be (Öyle olamaz)
''',
      formulaEn: '''
Subject + may/might/could + V1
Subject + must + be (it must be so)
Subject + can't + be (it cannot be so)
''',
      examples: [
        GrammarExample(
          english: 'It may rain tomorrow.',
          turkish: 'Yarın yağmur yağabilir.',
          note: 'İhtimal',
        ),
        GrammarExample(
          english: 'She might be at home.',
          turkish: 'Evde olabilir',
          note: 'Zayıf ihtimal',
        ),
        GrammarExample(
          english: 'He is driving a Ferrari. He must be rich.',
          turkish: 'Ferrari sürüyor. Zengin olmalı.',
          note: 'Güçlü çıkarım',
        ),
        GrammarExample(
          english: 'You just ate. You can\'t be hungry.',
          turkish: 'Az önce yedin. Aç olamazsın.',
          note: 'İmkansızlık çıkarımı',
        ),
      ],
      commonMistakes: [
        '❌ It can rain tomorrow. → ✅ It may/might rain tomorrow. ("Can" genelde teorik ihtimal veya yetenek için kullanılır, spesifik gelecek tahmini için may/might kullanılır)',
        '❌ He mustn\'t be rich. → ✅ He can\'t be rich. (Çıkarımın olumsuzu can\'t dir)',
      ],
      keyPoints: [
        '🔑 Olumlu çıkarım: MUST BE',
        '🔑 Olumsuz çıkarım: CAN\'T BE (Mustn\'t be kullanılmaz, o yasaktır!)',
        '🔑 Gelecek tahmini: May/Might/Could',
      ],
      comparison: '''
🆚 Must (Zorunluluk) vs Must (Çıkarım):
• "You must study." (Çalışmalısın - Zorunluluk)
• "You are sweating. You must be hot." (Terliyorsun. Sıcaklamış olmalısın - Çıkarım)
''',
      examTip: '💡 YDS\'de "I\'m sure that..." → must, "It is impossible that..." → can\'t/couldn\'t işaret eder.',
    ),

    // 5. PAST MODALS
    GrammarSubtopic(
      id: 'modals_past',
      title: 'Past Modals',
      titleTr: 'Geçmiş Kipler (Modal + Have + V3)',
      explanation: '''
Geçmişle ilgili çıkarımlar, pişmanlıklar veya eleştiriler için kullanılır.

🎯 Yapılar:
• Should have V3: Yapmalıydın (ama yapmadın) - Pişmanlık/Eleştiri
• Must have V3: Yapmış olmalı (Kesin öyle oldu) - Güçlü Çıkarım
• Can't/Couldn't have V3: Yapmış olamaz (İmkansız) - Güçlü Çıkarım
• May/Might/Could have V3: Yapmış olabilir (Belki yaptı) - İhtimal
• Needn't have V3: Yapmana gerek yoktu (ama yaptın) - Boşuna eylem
''',
      explanationEn: '''
Used for conclusions about the past, for regret, and for criticism.

🎯 The forms:
• Should have V3: you ought to have done it, and did not — regret or criticism
• Must have V3: it is almost certain that it happened — strong deduction
• Can't/Couldn't have V3: it is almost certain that it did not — strong deduction
• May/Might/Could have V3: it possibly happened
• Needn't have V3: it was not necessary, and it was done anyway — wasted effort
''',
      formula: '''
Modal + have + V3
''',
      examples: [
        GrammarExample(
          english: 'You should have studied harder.',
          turkish: 'Daha sıkı çalışmalıydın. (Ama çalışmadın)',
          note: 'Eleştiri/Pişmanlık',
        ),
        GrammarExample(
          english: 'The streets are wet. It must have rained.',
          turkish: 'Yerler ıslak. Yağmur yağmış olmalı.',
          note: 'Geçmiş çıkarım',
        ),
        GrammarExample(
          english: 'He can\'t have stolen the money. He was with me.',
          turkish: 'Parayı o çalmış olamaz. Benimleydi.',
          note: 'İmkansızlık',
        ),
        GrammarExample(
          english: 'I needn\'t have brought my umbrella.',
          turkish: 'Şemsiyemi getirmeme gerek yoktu. (Ama getirdim)',
          note: 'Gereksiz eylem',
        ),
      ],
      commonMistakes: [
        '❌ You should studied. → ✅ You should have studied.',
        '❌ Must had rained. → ✅ Must have rained. (Modal sonrası always HAVE gelir, had gelmez)',
      ],
      keyPoints: [
        '🔑 "Should have V3" her zaman gerçekleşmemiş bir eylemi anlatır (Past Unreal).',
        '🔑 "Must have V3" fiziksel kanıt olduğunda kullanılır.',
        '🔑 Modal\'dan sonra asla "had" veya "has" gelmez, hep "have" gelir.',
      ],
      comparison: '''
🆚 Didn't need to vs Needn't have V3:
• "I didn't need to go to work." → İşe gitmeme gerek yoktu (ve gitmedim).
• "I needn't have gone to work." → İşe gitmeme gerek yoktu (ama gittim, boşuna oldu).
''',
      examTip: '💡 YDS\'nin EN ÇOK SEVDİĞİ konulardan biridir. "But he didn\'t" gibi bir ifade görürseniz "should/could have V3" arayın.',
    ),
  ],
);
