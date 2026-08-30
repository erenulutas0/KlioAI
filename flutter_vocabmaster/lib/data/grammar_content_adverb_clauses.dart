import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// ADVERB CLAUSES (Advanced Grammar)
const adverbClausesTopic = GrammarTopic(
  id: 'adverb_clauses',
  title: 'Adjective & Adverb Clauses',
  titleTr: 'Zarf Cümlecikleri',
  level: 'advanced',
  icon: Icons.sync_alt,
  color: Color(0xFFf59e0b),
  subtopics: [
    // 1. TIME CLAUSES
    GrammarSubtopic(
      id: 'time_clauses',
      title: 'Time Clauses',
      titleTr: 'Zaman Cümlecikleri',
      explanation: '''
Zaman ilişkisi kuran bağlaçlarla oluşturulan yan cümlelerdir. "Ne zaman?" sorusuna cevap verir.

🎯 ZAMAN BAĞLAÇLARI:

• WHEN: ...dığında, ...ince
• WHILE / AS: ...iken (eşzamanlı eylemler)
• BEFORE: ...madan önce
• AFTER: ...dıktan sonra
• UNTIL / TILL: ...e kadar (devam eden süre)
• SINCE: ...den beri
• AS SOON AS: ...ir ...mez (hemen ardından)
• BY THE TIME: ...e kadar, ...dığında (tamamlanmış)
• ONCE: ...dığında, ...dikten sonra (bir kez olunca)
• WHENEVER / EVERY TIME: Ne zaman ...sa

⚠️ KRİTİK KURAL:
Zaman cümlelerinde GELECEK anlam olsa bile "WILL" KULLANILMAZ!
"When I will go" → YANLIŞ!
"When I go" → DOĞRU!
''',
      explanationEn: '''
These are subordinate clauses built with conjunctions of time. They answer the question "when?".

🎯 CONJUNCTIONS OF TIME:

• WHEN: at the point that
• WHILE / AS: during the time that — two things at once
• BEFORE: earlier than
• AFTER: later than
• UNTIL / TILL: up to the point that
• SINCE: from a point in the past onwards
• AS SOON AS: immediately after
• BY THE TIME: not later than, with the action complete
• ONCE: as soon as, after something has happened
• WHENEVER / EVERY TIME: on each occasion that

⚠️ THE CRITICAL RULE:
A time clause does NOT take "will", even when it clearly refers to the future.
"When I will go" → WRONG
"When I go" → RIGHT
''',
      formula: '''
Time Clause + Main Clause
Main Clause + Time Clause

⚠️ Zaman cümlesinde will yok!
"When I finish, I will call you."
"I will call you when I finish."
''',
      formulaEn: '''
Time Clause + Main Clause
Main Clause + Time Clause

⚠️ No "will" inside the time clause!
"When I finish, I will call you."
"I will call you when I finish."
''',
      examples: [
        GrammarExample(
          english: 'When I get home, I will have dinner.',
          turkish: 'Eve vardığımda akşam yemeği yiyeceğim.',
          note: 'When + Present Simple (will yok!)',
        ),
        GrammarExample(
          english: 'I was watching TV while she was cooking.',
          turkish: 'O yemek yaparken ben TV izliyordum.',
          note: 'While - eşzamanlı eylemler',
        ),
        GrammarExample(
          english: 'Wait here until I come back.',
          turkish: 'Ben dönene kadar burada bekle.',
          note: 'Until - süre',
        ),
        GrammarExample(
          english: 'As soon as he arrives, we will start the meeting.',
          turkish: 'O gelir gelmez toplantıya başlayacağız.',
          note: 'As soon as - hemen ardından',
        ),
        GrammarExample(
          english: 'By the time you arrive, I will have finished.',
          turkish: 'Sen geldiğinde bitirmiş olacağım.',
          note: 'By the time + Present → will have V3',
        ),
        GrammarExample(
          english: 'When I will see him, I will tell him.',
          turkish: 'Onu gördüğümde söyleyeceğim.',
          isCorrect: false,
          note: '❌ YANLIŞ! When + Present Simple olmalı',
        ),
      ],
      commonMistakes: [
        '❌ When I will arrive... → ✅ When I arrive...',
        '❌ Before he will leave... → ✅ Before he leaves...',
        '❌ As soon as she will call... → ✅ As soon as she calls...',
        '❌ Until you will finish... → ✅ Until you finish...',
      ],
      keyPoints: [
        '🔑 Zaman bağlacından sonra ASLA "will" kullanılmaz!',
        '🔑 "By the time" → genellikle Perfect Tense ile kullanılır',
        '🔑 "While" süregelen eylemler için, "When" anlık olaylar için tercih edilir',
        '🔑 "Until" = "...e kadar", "By" = "...e kadar (deadline)"',
      ],
      comparison: '''
🆚 When vs While:
• When: Kısa eylem veya genel zaman
  "When I arrived, she was cooking."
• While: Uzun/süregelen eylem
  "While I was sleeping, the phone rang."

🆚 Until vs By the time:
• Until: Bir şeyin devam ettiği süre
  "Wait UNTIL I come." (Ben gelene KADAR bekle - bekleme devam eder)
• By the time: Bir şeyin tamamlandığı an
  "BY THE TIME I came, she had left." (Geldiğimde gitmişti - tamamlanmış)
''',
      examTip: '💡 YDS\'de zaman bağlacı + boşluk varsa, şıklarda "will" içeren cevabı hemen eleyin!',
    ),

    // 2. REASON CLAUSES
    GrammarSubtopic(
      id: 'reason_clauses',
      title: 'Reason Clauses',
      titleTr: 'Sebep Cümlecikleri',
      explanation: '''
Bir eylemin sebebini/nedenini açıklayan yan cümlelerdir. "Neden?" sorusuna cevap verir.

🎯 SEBEP BAĞLAÇLARI (+ CÜMLE):

• BECAUSE: Çünkü (En güçlü sebep, yeni bilgi)
• SINCE: ...diği için, madem ki (Bilinen sebep)
• AS: ...diği için (Zayıf sebep, cümle başında)
• NOW THAT: Artık, madem ki (Yeni durum)

🎯 SEBEP EDATLARI (+ İSİM/V-ing):

• BECAUSE OF: ...den dolayı + noun/V-ing
• DUE TO: ...den dolayı + noun (daha resmi)
• OWING TO: ...den ötürü + noun (resmi)
• ON ACCOUNT OF: ...den dolayı + noun
• THANKS TO: ...sayesinde + noun (olumlu)

💡 KRİTİK FARK:
• Conjunction → CÜMLE (Subject + Verb)
• Preposition → İSİM (Noun Phrase) veya V-ing
''',
      explanationEn: '''
These clauses give the reason for something. They answer the question "why?".

🎯 CONJUNCTIONS OF REASON (+ A CLAUSE):

• BECAUSE: the strongest, and used when the reason is new information
• SINCE: when the reason is already known to both speakers
• AS: a weaker reason, usually at the start of the sentence
• NOW THAT: given a situation that has just become true

🎯 PREPOSITIONS OF REASON (+ A NOUN or V-ing):

• BECAUSE OF + noun/V-ing
• DUE TO + noun, more formal
• OWING TO + noun, formal
• ON ACCOUNT OF + noun
• THANKS TO + noun, and positive in tone

💡 THE CRITICAL DIFFERENCE:
A conjunction is followed by a CLAUSE (subject + verb); a preposition is followed by a NOUN. "Because the rain" and "because of it rained" are both wrong.
''',
      formula: '''
Because/Since/As + Subject + Verb, Main Clause
Because of/Due to + Noun, Main Clause

"Because it rained, we stayed home."
"Because of the rain, we stayed home."
''',
      examples: [
        GrammarExample(
          english: 'I stayed home because I was sick.',
          turkish: 'Evde kaldım çünkü hastaydım.',
          note: 'Because + cümle',
        ),
        GrammarExample(
          english: 'Since you are here, let\'s start.',
          turkish: 'Madem buradasın, başlayalım.',
          note: 'Since - bilinen sebep',
        ),
        GrammarExample(
          english: 'Due to the bad weather, the flight was cancelled.',
          turkish: 'Kötü hava nedeniyle uçuş iptal edildi.',
          note: 'Due to + noun',
        ),
        GrammarExample(
          english: 'Thanks to your help, I passed the exam.',
          turkish: 'Yardımın sayesinde sınavı geçtim.',
          note: 'Thanks to - olumlu sonuç',
        ),
        GrammarExample(
          english: 'Because of it was raining, I stayed home.',
          turkish: 'Yağmur yağdığı için evde kaldım.',
          isCorrect: false,
          note: '❌ YANLIŞ! Because of + NOUN olmalı',
        ),
      ],
      commonMistakes: [
        '❌ Because of it rained... → ✅ Because it rained... / Because of THE RAIN...',
        '❌ Due to it was late... → ✅ Due to THE LATE HOUR... / Because it was late...',
        '❌ Thanks to he helped... → ✅ Thanks to HIS HELP...',
      ],
      keyPoints: [
        '🔑 Because/Since/As → CÜMLE alır',
        '🔑 Because of/Due to/Owing to → İSİM alır',
        '🔑 "Thanks to" → OLUMLU sonuç için',
        '🔑 V-ing kullanmak için: "Because of being late..."',
      ],
      examTip: '💡 YDS\'de boşluktan sonra CÜMLE mi İSİM mi var ona bakın. Cümle ise because/since, isim ise due to/because of.',
    ),

    // 3. CONTRAST CLAUSES
    GrammarSubtopic(
      id: 'contrast_clauses',
      title: 'Contrast/Concession Clauses',
      titleTr: 'Zıtlık/Karşıtlık Cümlecikleri',
      explanation: '''
Beklentinin aksine bir sonuç olduğunu gösteren cümlelerdir. "...e rağmen" anlamı taşır.

🎯 ZITLIK BAĞLAÇLARI (+ CÜMLE):

• ALTHOUGH / THOUGH / EVEN THOUGH: ...e rağmen, ...se de
• WHILE / WHEREAS: Oysa, halbuki (karşılaştırma)
• EVEN IF: ...bile, ...se bile

🎯 ZITLIK EDATLARI (+ İSİM):

• DESPITE / IN SPITE OF: ...e rağmen + noun/V-ing
• REGARDLESS OF: ...e bakmaksızın + noun
• NOTWITHSTANDING: ...e rağmen (çok resmi)

🎯 BAĞLANTI SÖZCÜĞÜ (YENİ CÜMLE):

• HOWEVER / NEVERTHELESS / NONETHELESS: Ancak, yine de
• STILL / YET: Yine de
• ON THE OTHER HAND / IN CONTRAST: Öte yandan

⚠️ KRİTİK FARK:
• Although/Though → Tek cümle içinde bağlar
• However → İki ayrı cümleyi bağlar, noktalama işareti gerekir!
''',
      explanationEn: '''
These sentences show a result that runs against expectation — the "even though" idea.

🎯 CONJUNCTIONS OF CONTRAST (+ A CLAUSE):

• ALTHOUGH / THOUGH / EVEN THOUGH
• WHILE / WHEREAS, for a straight comparison
• EVEN IF, for a hypothetical

🎯 PREPOSITIONS OF CONTRAST (+ A NOUN):

• DESPITE / IN SPITE OF + noun/V-ing
• REGARDLESS OF + noun
• NOTWITHSTANDING + noun, very formal

🎯 LINKING WORDS (STARTING A NEW SENTENCE):

• HOWEVER / NEVERTHELESS / NONETHELESS
• STILL / YET
• ON THE OTHER HAND / IN CONTRAST

⚠️ THE CRITICAL DIFFERENCE:
Although and though join two halves of ONE sentence. However joins TWO sentences and needs a full stop or a semicolon before it.
''',
      formula: '''
Although/Though + S + V, S + V
Despite/In spite of + Noun, S + V

"Although it rained, we went out."
"Despite the rain, we went out."

S + V. However, S + V.
"It rained. However, we went out."
''',
      examples: [
        GrammarExample(
          english: 'Although he is rich, he is not happy.',
          turkish: 'Zengin olmasına rağmen mutlu değil.',
          note: 'Although + cümle',
        ),
        GrammarExample(
          english: 'Despite being tired, she continued working.',
          turkish: 'Yorgun olmasına rağmen çalışmaya devam etti.',
          note: 'Despite + V-ing',
        ),
        GrammarExample(
          english: 'He is smart. However, he failed the exam.',
          turkish: 'Zeki. Ancak sınavda başarısız oldu.',
          note: 'However - iki ayrı cümle',
        ),
        GrammarExample(
          english: 'While John works hard, his brother is lazy.',
          turkish: 'John çok çalışırken, kardeşi tembel.',
          note: 'While - karşılaştırma',
        ),
        GrammarExample(
          english: 'Despite he was sick, he went to work.',
          turkish: 'Hasta olmasına rağmen işe gitti.',
          isCorrect: false,
          note: '❌ YANLIŞ! Despite + noun olmalı',
        ),
      ],
      commonMistakes: [
        '❌ Despite he was late... → ✅ Despite being late... / Although he was late...',
        '❌ Although the rain... → ✅ Although it rained... / Despite the rain...',
        '❌ However he is rich, ... → ✅ Although he is rich, ... / He is rich. However, ...',
        '❌ In spite of he tried... → ✅ In spite of his trying... / Although he tried...',
      ],
      keyPoints: [
        '🔑 Although/Though/Even though → CÜMLE',
        '🔑 Despite/In spite of → İSİM veya V-ing',
        '🔑 However → İki cümle arasında, noktalama işareti ile (. However, / ; however,)',
        '🔑 "Despite the fact that..." → cümle kabul eder (the fact that + S + V)',
      ],
      comparison: '''
🆚 Although vs However:
• Although: "Although he is 80, he is fit."
  (Tek cümle içinde bağlar)
• However: "He is 80. However, he is fit."
  (İki cümle bağlar, nokta/noktalı virgül gerekir)

🆚 While (zaman) vs While (zıtlık):
• Zaman: "While I was cooking, ..." (yaparken)
• Zıtlık: "While he is rich, his brother is poor." (oysa)
''',
      examTip: '💡 YDS\'de boşluktan sonra CÜMLE mi İSİM mi bakın. Cümle → although, İsim → despite.',
    ),

    // 4. PURPOSE CLAUSES
    GrammarSubtopic(
      id: 'purpose_clauses',
      title: 'Purpose Clauses',
      titleTr: 'Amaç Cümlecikleri',
      explanation: '''
Bir eylemin amacını/niyetini açıklayan yan cümlelerdir. "Niçin? Ne için?" sorusuna cevap verir.

🎯 AMAÇ YAPILARI:

• TO / IN ORDER TO / SO AS TO + V1: ...mak için
  "I went to the store to buy milk."

• SO THAT / IN ORDER THAT + S + can/will/may: ...sin diye
  "He studies hard so that he can pass."

• FOR + Noun / V-ing: ...için (isim için)
  "I bought a pen for writing."

⚠️ OLUMSUZ AMAÇ:

• IN ORDER NOT TO / SO AS NOT TO + V1: ...mamak için
  "I left early so as not to be late."

• SO THAT + S + won't/wouldn't: ...masın diye
  "He spoke quietly so that he wouldn't wake the baby."

💡 KRİTİK:
"For + V-ing" amaç değil, kullanım amacı belirtir.
"This knife is for cutting bread." (Ekmek kesmek İÇİN bir bıçak - genel amaç)
''',
      explanationEn: '''
These clauses explain the purpose of an action. They answer "what for?".

🎯 THE PATTERNS:

• TO / IN ORDER TO / SO AS TO + V1
  "I went to the store to buy milk."

• SO THAT / IN ORDER THAT + S + can/will/may
  "He studies hard so that he can pass."

• FOR + noun / V-ing
  "I bought a pen for writing."

⚠️ NEGATIVE PURPOSE:

• IN ORDER NOT TO / SO AS NOT TO + V1
  "I left early so as not to be late."

• SO THAT + S + won't/wouldn't
  "He spoke quietly so that he wouldn't wake the baby."

💡 CRITICAL:
"For + V-ing" states what something is generally used for, not why someone did something once.
"This knife is for cutting bread."
''',
      formula: '''
Main Clause + to/in order to/so as to + V1
Main Clause + so that + S + can/will/may/could/would + V1

"I study to pass the exam."
"I study so that I can pass the exam."
''',
      examples: [
        GrammarExample(
          english: 'She exercises every day to stay healthy.',
          turkish: 'Sağlıklı kalmak için her gün egzersiz yapar.',
          note: 'to + V1 (amaç)',
        ),
        GrammarExample(
          english: 'He spoke loudly so that everyone could hear.',
          turkish: 'Herkes duysun diye yüksek sesle konuştu.',
          note: 'so that + could (geçmiş)',
        ),
        GrammarExample(
          english: 'I woke up early in order not to miss the train.',
          turkish: 'Treni kaçırmamak için erken kalktım.',
          note: 'in order not to (olumsuz amaç)',
        ),
        GrammarExample(
          english: 'Take an umbrella so that you won\'t get wet.',
          turkish: 'Islanmayasın diye şemsiye al.',
          note: 'so that + won\'t (olumsuz sonuç)',
        ),
        GrammarExample(
          english: 'I study for to pass the exam.',
          turkish: 'Sınavı geçmek için çalışıyorum.',
          isCorrect: false,
          note: '❌ YANLIŞ! "for to" kullanılmaz!',
        ),
      ],
      commonMistakes: [
        '❌ I study for to pass. → ✅ I study TO pass.',
        '❌ So that I pass. → ✅ So that I CAN pass. (modal gerekir)',
        '❌ To not be late. → ✅ IN ORDER not to be late. / NOT TO be late.',
        '❌ I came for seeing you. → ✅ I came TO SEE you. (amaç için to V1)',
      ],
      commonMistakesEn: [
        '❌ I study for to pass. → ✅ I study TO pass.',
        '❌ So that I pass. → ✅ So that I CAN pass. (a modal is required)',
        '❌ To not be late. → ✅ IN ORDER not to be late. / NOT TO be late.',
        '❌ I came for seeing you. → ✅ I came TO SEE you. (purpose takes to + V1)',
      ],
      keyPoints: [
        '🔑 TO / IN ORDER TO → V1 alır',
        '🔑 SO THAT → Özne + can/could/will/would + V1 alır',
        '🔑 "For + V-ing" amaç değil, genel kullanım amacı bildirir',
        '🔑 Olumsuzda "in order not to" veya "so as not to" kullanılır',
      ],
      examTip: '💡 YDS\'de "so that" varsa arkasında ÖZNE + MODAL olmalı. "So that + V1" YANLIŞTIR!',
    ),

    // 5. RESULT CLAUSES
    GrammarSubtopic(
      id: 'result_clauses',
      title: 'Result Clauses',
      titleTr: 'Sonuç Cümlecikleri',
      explanation: '''
Bir eylemin sonucunu/neticelerini gösteren yapılardır.

🎯 SONUÇ YAPILARI:

• SO + ADJ/ADV + THAT: O kadar ...ki
  "He is SO tall THAT he can touch the ceiling."

• SUCH + (a/an) + (ADJ) + NOUN + THAT: O kadar/Öyle ...ki
  "It was SUCH a good movie THAT I watched it twice."

🎯 BAĞLANTI SÖZCÜKLERİ:

• SO / THEREFORE / THUS / HENCE: Bu yüzden, dolayısıyla
• AS A RESULT / CONSEQUENTLY: Sonuç olarak
• ACCORDINGLY: Buna göre

💡 SO vs SUCH Farkı:

SO + Sıfat/Zarf (Adjective/Adverb)
• "SO expensive" (o kadar pahalı)
• "SO quickly" (o kadar hızlı)

SUCH + (a/an) + İsim (Noun)
• "SUCH a beautiful day" (öyle güzel bir gün)
• "SUCH nice people" (öyle iyi insanlar)
''',
      explanationEn: '''
These structures show the result of something.

🎯 THE PATTERNS:

• SO + ADJ/ADV + THAT
  "He is SO tall THAT he can touch the ceiling."

• SUCH + (a/an) + (ADJ) + NOUN + THAT
  "It was SUCH a good film THAT I watched it twice."

🎯 LINKING WORDS:

• SO / THEREFORE / THUS / HENCE
• AS A RESULT / CONSEQUENTLY
• ACCORDINGLY

💡 SO vs SUCH:

SO + adjective or adverb
• "SO expensive"
• "SO quickly"

SUCH + (a/an) + noun
• "SUCH a beautiful day"
• "SUCH nice people"

The test is what follows: an adjective on its own takes SO, an adjective attached to a noun takes SUCH.
''',
      formula: '''
SO + Adj/Adv + THAT + S + V
  "He ran SO fast THAT he won."

SUCH + (a/an) + (Adj) + Noun + THAT + S + V
  "It was SUCH a boring film THAT I fell asleep."

S + V. Therefore/So, S + V.
''',
      examples: [
        GrammarExample(
          english: 'The movie was so boring that I fell asleep.',
          turkish: 'Film o kadar sıkıcıydı ki uyuyakaldım.',
          note: 'so + adj + that',
        ),
        GrammarExample(
          english: 'It was such a long journey that we got tired.',
          turkish: 'Öyle uzun bir yolculuktu ki yorulduk.',
          note: 'such + a + adj + noun + that',
        ),
        GrammarExample(
          english: 'There were such heavy traffic that we missed the flight.',
          turkish: 'Öyle yoğun trafik vardı ki uçağı kaçırdık.',
          note: 'such + adj + uncountable noun',
        ),
        GrammarExample(
          english: 'He didn\'t study. Therefore, he failed.',
          turkish: 'Çalışmadı. Bu yüzden başarısız oldu.',
          note: 'Therefore - sonuç',
        ),
        GrammarExample(
          english: 'It was such expensive that I didn\'t buy it.',
          turkish: 'O kadar pahalıydı ki almadım.',
          isCorrect: false,
          note: '❌ YANLIŞ! "SO expensive" olmalı (adj)',
        ),
      ],
      commonMistakes: [
        '❌ It was SUCH expensive... → ✅ It was SO expensive... (adj = so)',
        '❌ He is SO a good student... → ✅ He is SUCH a good student... (noun = such)',
        '❌ So beautiful weather... → ✅ SUCH beautiful weather... (noun var)',
        '❌ Such quickly that... → ✅ SO quickly that... (adverb = so)',
      ],
      keyPoints: [
        '🔑 SO + Sıfat/Zarf + that',
        '🔑 SUCH + (a/an) + İsim + that',
        '🔑 İstisna: so much/many/few/little + noun + that',
        '🔑 "Therefore, consequently, as a result" iki cümle arasında kullanılır',
      ],
      comparison: '''
🆚 SO vs SUCH:
• SO + Adjective: "so beautiful"
• SUCH + Noun: "such a beautiful day"
• SUCH + Adjective + Noun: "such beautiful weather" (uncountable)

⚠️ İSTİSNA (so + much/many/few/little + noun):
• "So MANY people" (o kadar çok insan)
• "So MUCH money" (o kadar çok para)
• "So FEW students" (o kadar az öğrenci)
• "So LITTLE time" (o kadar az zaman)
''',
      examTip: '💡 YDS\'de boşluktan sonra sıfat/zarf varsa SO, isim varsa SUCH gelir. "So + a/an" ASLA olmaz!',
    ),
  ],
);
