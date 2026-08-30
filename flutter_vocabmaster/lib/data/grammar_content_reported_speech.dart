import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// REPORTED SPEECH (Exam Grammar)
const reportedSpeechTopic = GrammarTopic(
  id: 'reported_speech',
  title: 'Reported Speech',
  titleTr: 'Dolaylı Anlatım',
  level: 'exam',
  icon: Icons.record_voice_over,
  color: Color(0xFFef4444),
  subtopics: [
    // 1. TENSE CHANGES (BACKSHIFT)
    GrammarSubtopic(
      id: 'backshift',
      title: 'Tense Changes (Backshift)',
      titleTr: 'Zaman Kayması',
      explanation: '''
Birinin söylediğini başkasına aktarırken, giriş fiili geçmiş zamandaysa (said, told), aktarılan cümledeki zamanlar bir derece geçmişe kayar.

🎯 ZAMAN KAYMALARI:

┌─────────────────────┬───────────────────────┐
│ DIRECT SPEECH       │ REPORTED SPEECH       │
├─────────────────────┼───────────────────────┤
│ Present Simple      │ → Past Simple         │
│ "I work"            │ → he worked           │
├─────────────────────┼───────────────────────┤
│ Present Continuous  │ → Past Continuous     │
│ "I am working"      │ → he was working      │
├─────────────────────┼───────────────────────┤
│ Past Simple         │ → Past Perfect        │
│ "I worked"          │ → he had worked       │
├─────────────────────┼───────────────────────┤
│ Present Perfect     │ → Past Perfect        │
│ "I have worked"     │ → he had worked       │
├─────────────────────┼───────────────────────┤
│ Will                │ → Would               │
│ "I will work"       │ → he would work       │
├─────────────────────┼───────────────────────┤
│ Can                 │ → Could               │
│ "I can work"        │ → he could work       │
├─────────────────────┼───────────────────────┤
│ Must                │ → Had to              │
│ "I must work"       │ → he had to work      │
└─────────────────────┴───────────────────────┘

⚠️ DEĞİŞMEYEN DURUMLAR:
• Giriş fiili Present ise (He says...) → zaman değişmez
• Bilimsel gerçekler → zaman değişmez
• Past Perfect zaten en geçmiş → değişmez
• Would, could, should, might, ought to → değişmez
''',
      explanationEn: '''
When you report what someone said and the reporting verb is in the past (said, told), the tenses inside the reported sentence shift one step further back.

🎯 THE SHIFTS:

Present Simple → Past Simple
"I work" → he worked

Present Continuous → Past Continuous
"I am working" → he was working

Past Simple → Past Perfect
"I worked" → he had worked

Present Perfect → Past Perfect
"I have worked" → he had worked

Will → Would
"I will work" → he would work

Can → Could
"I can work" → he could work

Must → Had to
"I must work" → he had to work

⚠️ WHEN NOTHING SHIFTS:
• The reporting verb is present (He says...)
• The statement is a scientific fact
• The tense is already Past Perfect, which cannot go back further
• Would, could, should, might and ought to have no further-back form
''',
      formula: '''
Said + that + [backshifted tense]

"I am tired." → He said (that) he was tired.
"I will come." → She said (that) she would come.
''',
      examples: [
        GrammarExample(
          english: '"I love you," he said.',
          turkish: '"Seni seviyorum" dedi.',
          note: 'Direct Speech',
        ),
        GrammarExample(
          english: 'He said (that) he loved her.',
          turkish: 'Onu sevdiğini söyledi.',
          note: 'Present Simple → Past Simple',
        ),
        GrammarExample(
          english: '"I have finished," she told me.',
          turkish: '"Bitirdim" bana söyledi.',
          note: 'Direct Speech',
        ),
        GrammarExample(
          english: 'She told me (that) she had finished.',
          turkish: 'Bitirdiğini söyledi.',
          note: 'Present Perfect → Past Perfect',
        ),
        GrammarExample(
          english: 'He said that water boils at 100°C.',
          turkish: 'Suyun 100 derecede kaynadığını söyledi.',
          note: 'Bilimsel gerçek - zaman değişmez',
        ),
      ],
      commonMistakes: [
        '❌ He said me that... → ✅ He TOLD me that... / He SAID that...',
        '❌ She said that she will come. → ✅ She said that she WOULD come.',
        '❌ He told that he was tired. → ✅ He SAID that... / He TOLD ME that...',
      ],
      keyPoints: [
        '🔑 SAY + (that) + clause (nesne almaz)',
        '🔑 TELL + person + (that) + clause (nesne alır)',
        '🔑 Past Perfect ve modal perfectler değişmez (zaten en geçmiş)',
        '🔑 "Here → there", "this → that", "today → that day" gibi değişimler de olur',
      ],
      keyPointsEn: [
        '🔑 SAY + (that) + clause — it takes no object',
        '🔑 TELL + person + (that) + clause — it does take one',
        '🔑 The Past Perfect and the perfect modals do not shift; they are already as far back as English goes',
        '🔑 Words of place and time shift too: here → there, this → that, today → that day',
      ],
      examTip: '💡 YDS\'de "He said me..." veya "He told that..." görürseniz YANLIŞ! Say nesne almaz, tell alır.',
    ),

    // 2. REPORTING QUESTIONS
    GrammarSubtopic(
      id: 'reporting_questions',
      title: 'Reporting Questions',
      titleTr: 'Soru Cümlelerini Aktarma',
      explanation: '''
Soru cümlelerini dolaylı anlatıma çevirirken yapı değişir. Soru artık soru değil, cümle olur.

🎯 WH- SORULARI:
Direct: "Where do you live?"
Reported: She asked where I lived.
→ Wh-word kalır, DEVRİKLİK KALKAR!

🎯 YES/NO SORULARI:
Direct: "Are you coming?"
Reported: She asked if/whether I was coming.
→ If/Whether eklenir, devriklik kalkar!

⚠️ KRİTİK KURALLAR:
1. Soru devrikliği (do/does/did + S) KALKAR
2. Düz cümle sırası (S + V) olur
3. Soru işareti KALKAR
4. "Asked" veya "wanted to know" kullanılır
''',
      explanationEn: '''
Turning a question into reported speech changes its shape. It stops being a question and becomes a statement.

🎯 WH- QUESTIONS:
Direct: "Where do you live?"
Reported: She asked where I lived.
→ The wh-word stays; the INVERSION GOES.

🎯 YES/NO QUESTIONS:
Direct: "Are you coming?"
Reported: She asked if/whether I was coming.
→ If or whether is added; the inversion goes.

⚠️ THE CRITICAL RULES:
1. The question inversion (do/does/did + subject) DISAPPEARS
2. The ordinary subject + verb order is used
3. The question mark DISAPPEARS
4. "Asked" or "wanted to know" introduces it
''',
      formula: '''
WH- Questions:
Direct: "Wh- + Aux + S + V?"
Reported: asked + wh- + S + V

Yes/No Questions:
Direct: "Aux + S + V?"
Reported: asked + if/whether + S + V
''',
      examples: [
        GrammarExample(
          english: '"Where do you live?" she asked.',
          turkish: '"Nerede yaşıyorsun?" diye sordu.',
          note: 'Direct Question',
        ),
        GrammarExample(
          english: 'She asked where I lived.',
          turkish: 'Nerede yaşadığımı sordu.',
          note: 'Reported - devriklik kalktı',
        ),
        GrammarExample(
          english: '"Did you see the movie?" he asked.',
          turkish: '"Filmi gördün mü?" diye sordu.',
          note: 'Direct Yes/No Question',
        ),
        GrammarExample(
          english: 'He asked if/whether I had seen the movie.',
          turkish: 'Filmi görüp görmediğimi sordu.',
          note: 'Reported - if/whether eklendi',
        ),
        GrammarExample(
          english: 'She asked where did I live.',
          turkish: 'Nerede yaşadığımı sordu.',
          isCorrect: false,
          note: '❌ YANLIŞ! Devriklik kalmalı!',
        ),
      ],
      commonMistakes: [
        '❌ He asked where DID I go. → ✅ He asked where I went.',
        '❌ She asked if WAS I coming. → ✅ She asked if I was coming.',
        '❌ He asked that I was coming. → ✅ He asked IF I was coming.',
        '❌ She asked me where I live? → ✅ She asked me where I lived. (soru işareti yok)',
      ],
      commonMistakesEn: [
        '❌ He asked where DID I go. → ✅ He asked where I went.',
        '❌ She asked if WAS I coming. → ✅ She asked if I was coming.',
        '❌ He asked that I was coming. → ✅ He asked IF I was coming.',
        '❌ She asked me where I live? → ✅ She asked me where I lived. (no question mark)',
      ],
      keyPoints: [
        '🔑 Dolaylı soruda soru yapısı YOKTUR - düz cümle sırasıdır',
        '🔑 Yes/No soruları için IF veya WHETHER eklenir',
        '🔑 "Asked" veya "wanted to know" gibi fiiller kullanılır',
        '🔑 Cümle sonunda SORU İŞARETİ OLMAZ',
      ],
      keyPointsEn: [
        '🔑 An indirect question has NO question structure — it takes statement order',
        '🔑 For yes/no questions, IF or WHETHER is added',
        '🔑 Verbs like "asked" or "wanted to know" introduce it',
        '🔑 There is NO QUESTION MARK at the end',
      ],
      examTip: '💡 YDS\'de "asked what did..." veya "asked if was..." görürseniz YANLIŞ! Devriklik kalkar.',
    ),

    // 3. REPORTING COMMANDS & REQUESTS
    GrammarSubtopic(
      id: 'reporting_commands',
      title: 'Reporting Commands & Requests',
      titleTr: 'Emir ve Rica Cümlelerini Aktarma',
      explanation: '''
Emir ve rica cümleleri "to-infinitive" yapısı ile aktarılır.

🎯 EMİR CÜMLELERİ:
Direct: "Open the door!"
Reported: He told me to open the door.

🎯 OLUMSUZ EMİR:
Direct: "Don't be late!"
Reported: She told me not to be late.

🎯 RİCA CÜMLELERİ:
Direct: "Could you help me, please?"
Reported: He asked me to help him.

🎯 KULLANILAN FİİLLER:
• tell, order, command → emir
• ask, request → rica
• advise, warn → tavsiye/uyarı
• beg, urge → yalvarma
• encourage → teşvik
• remind → hatırlatma
• forbid → yasaklama
''',
      explanationEn: '''
Orders and requests are reported with a to-infinitive.

🎯 ORDERS:
Direct: "Open the door!"
Reported: He told me to open the door.

🎯 NEGATIVE ORDERS:
Direct: "Don't be late!"
Reported: She told me not to be late.

🎯 REQUESTS:
Direct: "Could you help me, please?"
Reported: He asked me to help him.

🎯 THE VERBS USED:
• tell, order, command → an order
• ask, request → a request
• advise, warn → advice or a warning
• beg, urge → pleading
• encourage → encouragement
• remind → a reminder
• forbid → a prohibition
''',
      formula: '''
Olumlu: told/asked + object + to + V1
Olumsuz: told/asked + object + NOT to + V1

"Study hard!" → She told me to study hard.
"Don't go!" → He told me not to go.
''',
      formulaEn: '''
Affirmative: told/asked + object + to + V1
Negative: told/asked + object + NOT to + V1

"Study hard!" → She told me to study hard.
"Don't go!" → He told me not to go.
''',
      examples: [
        GrammarExample(
          english: '"Sit down!" the teacher said.',
          turkish: '"Oturun!" dedi öğretmen.',
          note: 'Direct Command',
        ),
        GrammarExample(
          english: 'The teacher told us to sit down.',
          turkish: 'Öğretmen oturmamızı söyledi.',
          note: 'Reported Command',
        ),
        GrammarExample(
          english: '"Don\'t touch that!" she warned.',
          turkish: '"Ona dokunma!" diye uyardı.',
          note: 'Direct Negative Command',
        ),
        GrammarExample(
          english: 'She warned me not to touch that.',
          turkish: 'Ona dokunmamamı söyledi.',
          note: 'Reported - not to V1',
        ),
        GrammarExample(
          english: '"Could you lend me some money?" he asked.',
          turkish: '"Bana biraz borç verir misin?" diye sordu.',
          note: 'Direct Request',
        ),
        GrammarExample(
          english: 'He asked me to lend him some money.',
          turkish: 'Ona borç vermemi istedi.',
          note: 'Reported Request',
        ),
      ],
      commonMistakes: [
        '❌ He told me to don\'t go. → ✅ He told me NOT TO go.',
        '❌ She said me to come. → ✅ She TOLD me to come.',
        '❌ He ordered that I leave. → ✅ He ordered me TO leave.',
      ],
      keyPoints: [
        '🔑 Emir/rica cümleleri TO + V1 ile aktarılır',
        '🔑 Olumsuzda NOT TO + V1 kullanılır ("to not" değil!)',
        '🔑 "Say" emir/rica aktarmada kullanılmaz - TELL, ASK, ORDER vs. kullanılır',
        '🔑 Nesne (me, him, her) mutlaka belirtilir',
      ],
      keyPointsEn: [
        '🔑 Orders and requests are reported with TO + V1',
        '🔑 The negative is NOT TO + V1, never "to not"',
        '🔑 "Say" is not used for orders or requests — tell, ask, order and so on are',
        '🔑 The object (me, him, her) must be stated',
      ],
      examTip: '💡 "to don\'t" ASLA doğru değildir. Her zaman "not to" kullanılır.',
    ),

    // 4. REPORTING VERBS
    GrammarSubtopic(
      id: 'reporting_verbs',
      title: 'Reporting Verbs',
      titleTr: 'Aktarım Fiilleri',
      explanation: '''
Farklı aktarım fiilleri farklı yapılar alır. Öne sürme, itiraf etme, inkar etme gibi anlamlar için özel fiiller kullanılır.

🎯 VERB + THAT-CLAUSE:
• say, claim, state, mention, explain, point out, admit, deny, promise, suggest, insist...
"He admitted that he had lied."

🎯 VERB + TO-INFINITIVE:
• agree, decide, offer, promise, refuse, threaten...
"She agreed to help."

🎯 VERB + OBJECT + TO-INFINITIVE:
• advise, ask, beg, encourage, invite, order, permit, persuade, remind, tell, urge, warn...
"He advised me to study."

🎯 VERB + V-ing:
• admit, deny, suggest, recommend...
"He denied stealing the money."

🎯 VERB + PREPOSITION + V-ing:
• apologize for, insist on, object to, accuse of...
"She apologized for being late."
''',
      explanationEn: '''
Different reporting verbs take different structures. There are specific verbs for claiming, admitting, denying and so on.

🎯 VERB + THAT-CLAUSE:
• say, claim, state, mention, explain, point out, admit, deny, promise, suggest, insist...
"He admitted that he had lied."

🎯 VERB + TO-INFINITIVE:
• agree, decide, offer, promise, refuse, threaten...
"She agreed to help."

🎯 VERB + OBJECT + TO-INFINITIVE:
• advise, ask, beg, encourage, invite, order, permit, persuade, remind, tell, urge, warn...
"He advised me to study."

🎯 VERB + V-ing:
• admit, deny, suggest, recommend...
"He denied stealing the money."

🎯 VERB + PREPOSITION + V-ing:
• apologize for, insist on, object to, accuse of...
"She apologized for being late."
''',
      formula: '''
admit + V-ing / that-clause
deny + V-ing / that-clause
suggest + V-ing / that-clause
agree + to V1
refuse + to V1
promise + to V1 / that-clause
''',
      examples: [
        GrammarExample(
          english: 'He denied stealing the car.',
          turkish: 'Arabayı çaldığını inkar etti.',
          note: 'deny + V-ing',
        ),
        GrammarExample(
          english: 'She admitted that she had made a mistake.',
          turkish: 'Hata yaptığını itiraf etti.',
          note: 'admit + that-clause',
        ),
        GrammarExample(
          english: 'He agreed to pay for the damage.',
          turkish: 'Hasarı ödemeyi kabul etti.',
          note: 'agree + to V1',
        ),
        GrammarExample(
          english: 'She threatened to call the police.',
          turkish: 'Polisi aramakla tehdit etti.',
          note: 'threaten + to V1',
        ),
        GrammarExample(
          english: 'He accused me of lying.',
          turkish: 'Beni yalan söylemekle suçladı.',
          note: 'accuse + of + V-ing',
        ),
        GrammarExample(
          english: 'He suggested to go home.',
          turkish: 'Eve gitmeyi önerdi.',
          isCorrect: false,
          note: '❌ YANLIŞ! suggest + V-ing olmalı',
        ),
      ],
      commonMistakes: [
        '❌ He suggested to go. → ✅ He suggested GOING. / He suggested THAT we go.',
        '❌ She denied to steal. → ✅ She denied STEALING.',
        '❌ He accused me to lie. → ✅ He accused me OF LYING.',
        '❌ She insisted to pay. → ✅ She insisted ON PAYING.',
      ],
      keyPoints: [
        '🔑 SUGGEST → V-ing veya that + subjunctive (suggest that he go)',
        '🔑 DENY / ADMIT → V-ing veya that-clause',
        '🔑 ACCUSE / BLAME → of + V-ing',
        '🔑 INSIST / APOLOGIZE → on/for + V-ing',
      ],
      keyPointsEn: [
        '🔑 SUGGEST → V-ing, or that + subjunctive (suggest that he go)',
        '🔑 DENY / ADMIT → V-ing or a that-clause',
        '🔑 ACCUSE / BLAME → of + V-ing',
        '🔑 INSIST / APOLOGISE → on/for + V-ing',
      ],
      examTip: '💡 YDS\'de "suggest to V1" veya "deny to V1" çok sık hata olarak çıkar. YANLIŞ!',
    ),
  ],
);
