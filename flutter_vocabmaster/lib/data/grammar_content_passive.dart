import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// PASSIVE VOICE (Core Grammar)
const passiveVoiceTopic = GrammarTopic(
  id: 'passive_voice',
  title: 'Passive Voice',
  titleTr: 'Edilgen Çatı',
  level: 'core',
  icon: Icons.loop,
  color: Color(0xFF22c55e),
  subtopics: [
    // 1. BASIC PASSIVE
    GrammarSubtopic(
      id: 'basic_passive',
      title: 'Basic Passive Forms',
      titleTr: 'Temel Edilgen Yapı',
      explanation: '''
Passive Voice (Edilgen Çatı), eylemi kimin yaptığından çok, eylemin kendisine veya etkilenen nesneye odaklanmak istediğimizde kullanılır.

🎯 Ne zaman kullanılır?
• Eylemi yapanı bilmiyorsak (Cüzdanım çalındı)
• Eylemi yapanın önemi yoksa (Köprü 1990'da inşa edildi)
• Eylem, yapandan daha önemliyse
''',
      formula: '''
Active: Subject + Verb + Object
Passive: Object + Be + V3 (+ by Subject)

Zamanlara göre "Be" çekimi:
• Present Simple: am/is/are + V3
• Past Simple: was/were + V3
• Future (will): will be + V3
• Continuous: being + V3
• Perfect: been + V3
''',
      formulaEn: '''
Active: Subject + Verb + Object
Passive: Object + Be + V3 (+ by Subject)

"Be" by tense:
• Present Simple: am/is/are + V3
• Past Simple: was/were + V3
• Future (will): will be + V3
• Continuous: being + V3
• Perfect: been + V3
''',
      examples: [
        GrammarExample(
          english: 'English is spoken all over the world.',
          turkish: 'Dünyanın her yerinde İngilizce konuşulur.',
          note: 'Present Simple Passive',
        ),
        GrammarExample(
          english: 'My car was stolen last night.',
          turkish: 'Arabbam dün gece çalındı.',
          note: 'Past Simple Passive',
        ),
        GrammarExample(
          english: 'The house is being painted.',
          turkish: 'Ev boyanıyor.',
          note: 'Present Continuous Passive',
        ),
        GrammarExample(
          english: 'The work will be finished tomorrow.',
          turkish: 'İş yarın bitirilecek.',
          note: 'Future Passive',
        ),
      ],
      commonMistakes: [
        '❌ The book wrote by Shakespeare. → ✅ The book WAS written by Shakespeare.',
        '❌ English speaks here. → ✅ English IS spoken here.',
        '❌ I was borned. → ✅ I was born. (V3 zaten born)',
      ],
      keyPoints: [
        '🔑 Passive yapabilmek için fiilin NESNE alabilmesi gerekir (Transitive Verb). "Go, sleep, arrive" gibi fiiller passive yapılmaz.',
        '🔑 Eylemi yapanı belirtmek istersek cümlenin sonuna "by ..." ekleriz.',
      ],
      examTip: '💡 Cümlede özne cansız ise ve ardından fiil geliyorsa %90 passive\'dir. "The message sent..." olamaz, "The message was sent..." olmalı.',
    ),

    // 2. PASSIVE WITH MODALS
    GrammarSubtopic(
      id: 'passive_modals',
      title: 'Passive with Modals',
      titleTr: 'Modallarla Edilgen',
      explanation: '''
Modal fiillerin (can, should, must...) passive halleridir.

🎯 Yapı:
• Modal + be + V3 (Şimdiki/Gelecek)
• Modal + have been + V3 (Geçmiş)
''',
      formula: '''
Active: You should do it.
Passive: It should be done.

Active: Someone must have taken it.
Passive: It must have been taken.
''',
      examples: [
        GrammarExample(
          english: 'This form must be signed.',
          turkish: 'Bu form imzalanmalı(dır).',
          note: 'Must be V3',
        ),
        GrammarExample(
          english: 'Passports can be renewed online.',
          turkish: 'Pasaportlar online yenilenebilir.',
          note: 'Can be V3',
        ),
        GrammarExample(
          english: 'The mistake could have been prevented.',
          turkish: 'Hata önlenebilirdi.',
          note: 'Could have been V3 (Geçmiş)',
        ),
      ],
      commonMistakes: [
        '❌ It must done. → ✅ It must BE done.',
        '❌ It should been done. → ✅ It should HAVE been done.',
      ],
      keyPoints: [
        '🔑 Modal passive yaparken araya "be" eklemeyi unutmayın.',
        '🔑 Perfect modal passive (geçmiş) için "have been" kullanılır.',
      ],
    ),
    
    // 3. GET PASSIVE
    GrammarSubtopic(
      id: 'get_passive',
      title: 'The Get-Passive',
      titleTr: 'Get ile Yapılan Edilgen',
      explanation: '''
Günlük konuşma dilinde (informal), "be" yerine "get" kullanılarak passive yapılabilir. Genellikle nahoş veya beklenmedik olaylar için kullanılır.

🎯 Örnekler:
• get hurt (yaralanmak)
• get fired (kovulmak)
• get stolen (çalınmak)
• get married (evlenmek - istisna, nahoş değil ama passive yapısıdır)
''',
      formula: '''
Subject + get/got + V3
''',
      examples: [
        GrammarExample(
          english: 'My car got stolen.',
          turkish: 'Arabam çalındı.',
          note: 'Was stolen yerine got stolen',
        ),
        GrammarExample(
          english: 'Be careful, you might get hurt.',
          turkish: 'Dikkat et, yaralanabilirsin.',
          note: 'Might be hurt yerine',
        ),
        GrammarExample(
          english: 'He got fired yesterday.',
          turkish: 'Dün kovuldu.',
          note: 'Was fired yerine',
        ),
      ],
      commonMistakes: [
        '❌ The work got done by me. (Garip) → ✅ The work was done by me.',
      ],
      keyPoints: [
        '🔑 "Get passive" daha çok kazalar, değişimler ve olaylar için kullanılır.',
        '🔑 Resmi yazışmalarda (akademik/sınav) "be + V3" tercih edilmelidir.',
      ],
    ),
  ],
);
