import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// CAUSATIVE FORMS (Exam Grammar)
const causativeTopic = GrammarTopic(
  id: 'causative',
  title: 'Causative Forms',
  titleTr: 'Ettirgen Çatı',
  level: 'exam',
  icon: Icons.engineering,
  color: Color(0xFFef4444),
  subtopics: [
    // 1. HAVE SOMETHING DONE
    GrammarSubtopic(
      id: 'have_something_done',
      title: 'Have Something Done',
      titleTr: 'Bir Şeyi Yaptırmak',
      explanation: '''
Bir işi başkasına yaptırmak için kullanılır. İşi yapan kişi önemli değildir veya bilinmiyordur; asıl önemli olan işin yapılmış olmasıdır.

🎯 KULLANIM ALANLARI:
• Profesyonel hizmetler (saç kestirmek, araba tamir ettirmek)
• Başkasının yararına yapılan işler
• Olumsuz olaylar (çalınmak, kırılmak - "get" ile)

🎯 ZAMAN DEĞİŞİMLERİ:
• Present: I have my car washed.
• Past: I had my car washed.
• Future: I will have my car washed.
• Perfect: I have had my car washed.
• Continuous: I am having my car washed.

💡 NOT:
"Something" (bir şey) cansız nesne olmalıdır!
"My car = araba" → have my car washed ✓
"John = insan" → have John wash... (farklı yapı!)
''',
      explanationEn: '''
Used when you arrange for someone else to do something. Who actually does it is unknown or beside the point; what matters is that it gets done.

🎯 WHERE IT IS USED:
• Professional services (getting a haircut, getting a car repaired)
• Work done on your behalf
• Unwelcome events (being robbed, having something broken) — usually with "get"

🎯 ACROSS THE TENSES:
• Present: I have my car washed.
• Past: I had my car washed.
• Future: I will have my car washed.
• Perfect: I have had my car washed.
• Continuous: I am having my car washed.

💡 NOTE:
The "something" must be a thing, not a person.
"my car" → have my car washed ✓
"John" → have John wash... — a different structure
''',
      formula: '''
HAVE + NESNE (thing) + V3 (Past Participle)

Present: I have my hair cut.
Past: I had my hair cut.
Future: I will have my hair cut.
''',
      formulaEn: '''
HAVE + THING + V3 (Past Participle)

Present: I have my hair cut.
Past: I had my hair cut.
Future: I will have my hair cut.
''',
      examples: [
        GrammarExample(
          english: 'I had my car repaired yesterday.',
          turkish: 'Dün arabamı tamir ettirdim.',
          note: 'Past tense',
        ),
        GrammarExample(
          english: 'She is having her house painted.',
          turkish: 'Evini boyatıyor.',
          note: 'Continuous',
        ),
        GrammarExample(
          english: 'I need to have my eyes tested.',
          turkish: 'Gözlerimi kontrol ettirmem lazım.',
          note: 'Need + causative',
        ),
        GrammarExample(
          english: 'We will have the documents sent tomorrow.',
          turkish: 'Yarın belgeleri göndertirdeceğiz.',
          note: 'Future',
        ),
        GrammarExample(
          english: 'I had repaired my car.',
          turkish: 'Arabamı tamir ettirdim.',
          isCorrect: false,
          note: '❌ YANLIŞ! Bu Past Perfect olur. Causative: I had my car repaired.',
        ),
      ],
      commonMistakes: [
        '❌ I had repaired my car. → ✅ I had my car repaired. (Sıralama önemli!)',
        '❌ I have my car to repair. → ✅ I have my car repaired. (V3 kullanılır, to V1 değil)',
        '❌ I had cut my hair. → ✅ I had my hair cut. (Nesne + V3)',
      ],
      commonMistakesEn: [
        '❌ I had repaired my car. → ✅ I had my car repaired. (the order carries the meaning)',
        '❌ I have my car to repair. → ✅ I have my car repaired. (V3, not to + V1)',
        '❌ I had cut my hair. → ✅ I had my hair cut. (object + V3)',
      ],
      keyPoints: [
        '🔑 Yapı: HAVE + Nesne + V3 (Past Participle)',
        '🔑 Nesne her zaman HAVE ile V3 arasında gelir',
        '🔑 "Have" fiili zamana göre çekimlenir (have/has/had/will have/having)',
        '🔑 İşi yapan kişi "by..." ile eklenebilir ama genellikle söylenmez',
      ],
      keyPointsEn: [
        '🔑 The structure: HAVE + object + V3 (past participle)',
        '🔑 The object always sits between HAVE and the V3',
        '🔑 "Have" is what changes for tense (have/has/had/will have/having)',
        '🔑 The doer can be added with "by...", though it usually is not',
      ],
      examTip: '💡 YDS\'de "I had repaired" (Ben tamir ettim) ile "I had it repaired" (Tamir ettirdim) farkına dikkat! Birincisi kendim yaptım, ikincisi yaptırdım.',
    ),

    // 2. HAVE SOMEONE DO SOMETHING
    GrammarSubtopic(
      id: 'have_someone_do',
      title: 'Have Someone Do Something',
      titleTr: 'Birine Bir Şey Yaptırmak',
      explanation: '''
Bir kişiye bir iş yaptırmak anlamında kullanılır. İşi yapan kişi (someone) belirtilir. Bu yapıda otorite veya düzenleme anlamı vardır.

🎯 HAVE vs GET FARKI:
• HAVE someone DO: Otorite ile, profesyonel düzenleme
  "I had the mechanic fix my car."

• GET someone TO DO: İkna etme, rica etme
  "I got my friend to help me."

⚠️ KRİTİK FARK:
• HAVE someone DO → "to" YOK (Bare infinitive)
• GET someone TO DO → "to" VAR (To-infinitive)
''',
      explanationEn: '''
Used when you get a particular person to do something. The person is named, and the structure carries a sense of authority or arrangement.

🎯 HAVE vs GET:
• HAVE someone DO: by authority, or a professional arrangement
  "I had the mechanic fix my car."

• GET someone TO DO: by persuading or asking
  "I got my friend to help me."

⚠️ THE CRITICAL DIFFERENCE:
• HAVE someone DO → NO "to" (bare infinitive)
• GET someone TO DO → "to" is required
''',
      formula: '''
HAVE + KİŞİ + V1 (Yalın fiil)
  "I had the doctor examine me."

GET + KİŞİ + TO + V1
  "I got Mary to help me."
''',
      formulaEn: '''
HAVE + PERSON + V1 (bare infinitive)
  "I had the doctor examine me."

GET + PERSON + TO + V1
  "I got Mary to help me."
''',
      examples: [
        GrammarExample(
          english: 'I\'ll have my assistant book the tickets.',
          turkish: 'Asistanıma biletleri aldıracağım.',
          note: 'Have + person + V1',
        ),
        GrammarExample(
          english: 'The manager had his secretary prepare the report.',
          turkish: 'Müdür sekreterine raporu hazırlattı.',
          note: 'Otorite ile',
        ),
        GrammarExample(
          english: 'I got my brother to fix my bike.',
          turkish: 'Kardeşime bisikletimi tamir ettirdim.',
          note: 'Get + to V1 (ikna)',
        ),
        GrammarExample(
          english: 'I had the mechanic to fix my car.',
          turkish: 'Tamirciye arabamı tamir ettirdim.',
          isCorrect: false,
          note: '❌ YANLIŞ! Have someone DO (to yok)',
        ),
      ],
      commonMistakes: [
        '❌ I had him to go. → ✅ I had him GO.',
        '❌ I got him help me. → ✅ I got him TO help me.',
        '❌ I had to fix my car the mechanic. → ✅ I had the mechanic fix my car.',
      ],
      keyPoints: [
        '🔑 HAVE someone DO → "to" YOK',
        '🔑 GET someone TO DO → "to" VAR',
        '🔑 HAVE = otorite/düzenleme, GET = ikna/rica',
        '🔑 Kişi (someone) her zaman have/get ile fiil arasında gelir',
      ],
      keyPointsEn: [
        '🔑 HAVE someone DO → NO "to"',
        '🔑 GET someone TO DO → "to" is required',
        '🔑 HAVE suggests authority or arrangement; GET suggests persuading or asking',
        '🔑 The person always sits between have/get and the verb',
      ],
      comparison: '''
🆚 Have vs Get:
• "I had my secretary type the letter." (Sekreterime yazdırdım - iş ilişkisi)
• "I got my friend to type the letter." (Arkadaşımı ikna ettim yazsın diye)

🆚 Have someone DO vs Have something DONE:
• "I had the mechanic repair my car." (Tamirciye tamir ettirdim - kişi belli)
• "I had my car repaired." (Arabamı tamir ettirdim - kişi belli değil)
''',
      comparisonEn: '''
🆚 Have vs Get:
• "I had my secretary type the letter." — a working relationship, arranged
• "I got my friend to type the letter." — I persuaded them

🆚 Have someone DO vs Have something DONE:
• "I had the mechanic repair my car." — the person is named
• "I had my car repaired." — who did it is not stated
''',
      examTip: '💡 YDS\'de "have someone TO do" veya "get someone do" görürseniz YANLIŞ!',
    ),

    // 3. LET / MAKE / HELP
    GrammarSubtopic(
      id: 'let_make_help',
      title: 'Let / Make / Help',
      titleTr: 'İzin Vermek / Zorlamak / Yardım Etmek',
      explanation: '''
Bu fiiller de causative yapıda kullanılır ve farklı anlamlar taşır.

🎯 LET + someone + V1 (İzin vermek)
"Let me go." (Gitmeme izin ver.)
"My parents let me stay out late."

🎯 MAKE + someone + V1 (Zorlamak, yaptırmak)
"The teacher made us write an essay."
"Don't make me laugh."

🎯 HELP + someone + (to) V1 (Yardım etmek)
"He helped me (to) carry the boxes."
→ "to" opsiyoneldir!

⚠️ PASİF YAPILAR:
• LET → Pasif yapılmaz. "Be allowed to" kullanılır.
  ❌ "I was let to go."
  ✅ "I was allowed to go."

• MAKE → Pasif yapılırsa "to" eklenir!
  Active: "They made him confess."
  Passive: "He was made TO confess."
''',
      explanationEn: '''
These verbs also form causatives, and each carries a different meaning.

🎯 LET + someone + V1 — giving permission
"My parents let me stay out late."

🎯 MAKE + someone + V1 — forcing or compelling
"The teacher made us rewrite the essay."

🎯 HELP + someone + (to) V1 — assisting; both forms are correct
"She helped me (to) carry the bags."

⚠️ THE CRITICAL POINT:
Let and make take the bare infinitive — no "to". But in the passive, make gains one:
"We were made TO rewrite the essay."
Let has no passive of its own; "be allowed to" is used instead.
''',
      formula: '''
LET + object + V1 (to yok)
MAKE + object + V1 (to yok)
HELP + object + (to) V1 (opsiyonel)

Passive MAKE:
  was/were made + TO + V1
''',
      formulaEn: '''
LET + object + V1 (no "to")
MAKE + object + V1 (no "to")
HELP + object + (to) V1 (optional)

Passive MAKE:
  was/were made + TO + V1
''',
      examples: [
        GrammarExample(
          english: 'The boss let us leave early.',
          turkish: 'Patron erken çıkmamıza izin verdi.',
          note: 'Let + V1 (izin)',
        ),
        GrammarExample(
          english: 'The movie made me cry.',
          turkish: 'Film beni ağlattı.',
          note: 'Make + V1 (zorlamak)',
        ),
        GrammarExample(
          english: 'She helped me (to) find the address.',
          turkish: 'Adresi bulmama yardım etti.',
          note: 'Help + (to) V1',
        ),
        GrammarExample(
          english: 'He was made to apologize.',
          turkish: 'Özür dilemeye zorlandı.',
          note: 'Passive: was made TO V1',
        ),
        GrammarExample(
          english: 'She made me to go.',
          turkish: 'Beni gitmem için zorladı.',
          isCorrect: false,
          note: '❌ YANLIŞ! Make + V1 (to yok)',
        ),
      ],
      commonMistakes: [
        '❌ He let me to go. → ✅ He let me GO.',
        '❌ She made me to cry. → ✅ She made me CRY.',
        '❌ I was made go. → ✅ I was made TO go. (Pasif\'te to var!)',
        '❌ He was let to go. → ✅ He was ALLOWED to go.',
      ],
      keyPoints: [
        '🔑 LET, MAKE → Active\'de "to" YOK',
        '🔑 MAKE → Passive\'de "to" VAR (was made TO do)',
        '🔑 LET → Pasif yapılamaz, "be allowed to" kullanılır',
        '🔑 HELP → "to" opsiyoneldir',
      ],
      keyPointsEn: [
        '🔑 LET and MAKE take no "to" in the active',
        '🔑 MAKE gains a "to" in the passive (was made TO do)',
        '🔑 LET has no passive; "be allowed to" is used instead',
        '🔑 With HELP the "to" is optional',
      ],
      examTip: '💡 YDS\'de "was made" görürseniz arkasında TO + V1 olmalı. "Was made do" YANLIŞTIR!',
    ),

    // 4. GET SOMETHING DONE
    GrammarSubtopic(
      id: 'get_something_done',
      title: 'Get Something Done',
      titleTr: 'Get ile Yaptırmak',
      explanation: '''
"Have something done" yapısının alternatifidir. Daha informal (günlük) ve bazen olumsuz durumlar (kazalar, hırsızlık) için tercih edilir.

🎯 KULLANIM ALANLARI:
• Günlük konuşma (informal)
• Olumsuz olaylar (çalınmak, kırılmak)
• "Başarmak" anlamı (bir işi tamamlamak)

🎯 GET vs HAVE:
• GET: Daha informal, olumsuz olaylar için
• HAVE: Daha formal/nötr

💡 GET + Nesne (thing) + V3:
"I got my car fixed." = "I had my car fixed."

💡 GET + Nesne (thing) + V3 (olumsuz):
"I got my wallet stolen." (Cüzdanım çalındı.)
"She got her leg broken." (Bacağı kırıldı.)
''',
      explanationEn: '''
The same idea as "have something done", but more informal and more common in speech.

🎯 THE STRUCTURE:
GET + thing + V3 (past participle)
"I got my hair cut."
"We need to get this problem solved."

🎯 HAVE vs GET:
The meaning is the same. "Get" sounds more casual and often suggests effort or difficulty in arranging it; "have" is neutral and slightly more formal.

💡 NOTE:
Get is also used for things that happen to you without any arrangement at all:
"I got my phone stolen." — nobody arranged that.
''',
      formula: '''
GET + NESNE + V3

"I got my hair cut."
"We need to get this problem solved."
''',
      formulaEn: '''
GET + THING + V3

"I got my hair cut."
"We need to get this problem solved."
''',
      examples: [
        GrammarExample(
          english: 'I need to get my car fixed.',
          turkish: 'Arabamı tamir ettirmem lazım.',
          note: 'Get + sth + V3',
        ),
        GrammarExample(
          english: 'She got her phone stolen on the bus.',
          turkish: 'Otobüste telefonu çalındı.',
          note: 'Olumsuz olay',
        ),
        GrammarExample(
          english: 'I finally got all my work done.',
          turkish: 'Sonunda bütün işlerimi bitirdim.',
          note: '"Başarmak" anlamı',
        ),
        GrammarExample(
          english: 'He got the project finished on time.',
          turkish: 'Projeyi zamanında bitirdi.',
          note: 'Tamamlamak',
        ),
        GrammarExample(
          english: 'I got my house to paint.',
          turkish: 'Evimi boyattım.',
          isCorrect: false,
          note: '❌ YANLIŞ! Get + sth + V3 olmalı',
        ),
      ],
      commonMistakes: [
        '❌ I got repaired my car. → ✅ I got my car repaired.',
        '❌ I got my car to repair. → ✅ I got my car repaired.',
        '❌ I got done my homework. → ✅ I got my homework done.',
      ],
      keyPoints: [
        '🔑 GET + Nesne + V3 = HAVE + Nesne + V3',
        '🔑 GET daha informal ve günlük',
        '🔑 Olumsuz olaylar için GET tercih edilir (got stolen, got broken)',
        '🔑 "Get something done" = bir işi tamamlamak anlamı da taşır',
      ],
      keyPointsEn: [
        '🔑 GET + object + V3 means the same as HAVE + object + V3',
        '🔑 GET is the more informal, everyday one',
        '🔑 GET is preferred for unwelcome events (got stolen, got broken)',
        '🔑 "Get something done" also carries the sense of finally finishing a task',
      ],
      comparison: '''
🆚 Get something done vs Get someone to do:
• "I got my car repaired." (Arabamı tamir ettirdim - kim yaptı önemsiz)
• "I got Tom to repair my car." (Tom'a tamir ettirdim - kişi belli)

🆚 Have vs Get (topluca):
• Have sth done = Get sth done (Yaptırmak)
• Have sb do = Get sb to do (Birine yaptırmak)
''',
      comparisonEn: '''
🆚 Get something done vs Get someone to do:
• "I got my car repaired." — who did it does not matter
• "I got Tom to repair my car." — the person is named

🆚 Have vs Get, side by side:
• Have sth done = Get sth done
• Have sb do = Get sb to do
''',
      examTip: '💡 YDS\'de "get something + to V1" görürseniz YANLIŞ! Doğrusu "get something + V3".',
    ),
  ],
);
