import 'package:flutter/material.dart';
import 'grammar_data.dart';

/// CONDITIONALS (Advanced Grammar)
const conditionalsTopic = GrammarTopic(
  id: 'conditionals',
  title: 'Conditionals',
  titleTr: 'Koşul Cümleleri (If)',
  level: 'advanced',
  icon: Icons.call_split, // Yolları ayıran bir ikon
  color: Color(0xFFf59e0b),
  subtopics: [
    // 1. ZERO CONDITIONAL
    GrammarSubtopic(
      id: 'zero_conditional',
      title: 'Zero Conditional',
      titleTr: 'Tip 0: Genel Doğrular',
      explanation: '''
Bilimsel gerçekler, genel doğrular ve her zaman olan sonuçlar için kullanılır. "Eğer A olursa, B olur."

🎯 Ne zaman kullanılır?
• Doğa kanunları (Su 100 derecede kaynar)
• Genel alışkanlıklar (Yorulursam uyurum)
• Talimatlar (Kırmızı ışık yanarsa dur)
''',
      explanationEn: '''
Used for scientific facts, general truths and results that always follow. "If A happens, B happens."

🎯 When is it used?
• Laws of nature (Water boils at 100 degrees)
• General habits (If I get tired, I sleep)
• Instructions (If the light turns red, stop)

Both halves take the Present Simple. "Will" does not appear in either one.
''',
      formula: '''
If + Present Simple, Present Simple
''',
      examples: [
        GrammarExample(
          english: 'If you heat water to 100°C, it boils.',
          turkish: 'Suyu 100 dereceye ısıtırsan kaynar.',
          note: 'Bilimsel gerçek',
        ),
        GrammarExample(
          english: 'If I drink coffee at night, I can\'t sleep.',
          turkish: 'Gece kahve içersem uyuyamam.',
          note: 'Genel alışkanlık',
        ),
        GrammarExample(
          english: 'If the light turns red, stop.',
          turkish: 'Işık kırmızı yanarsa dur.',
          note: 'Talimat (Imperative)',
        ),
      ],
      keyPoints: [
        '🔑 Her iki tarafta da Present Simple kullanılır.',
        '🔑 "If" yerine "When" kullanılabilir, anlam değişmez. (When you heat water...)',
      ],
      keyPointsEn: [
        '🔑 Both halves take the Present Simple',
        '🔑 "When" can replace "if" with no change of meaning (When you heat water...)',
      ],
    ),

    // 2. FIRST CONDITIONAL
    GrammarSubtopic(
      id: 'first_conditional',
      title: 'First Conditional',
      titleTr: 'Tip 1: Gerçekleşmesi Muhtemel',
      explanation: '''
Gelecekte olması muhtemel olaylar için kullanılır.

🎯 Ne zaman kullanılır?
• Gelecek planları
• Uyarılar ve tehditler
• Vaatler
• Olasılıklar
''',
      explanationEn: '''
Used for events that are likely to happen in the future. The condition is real and the result is expected to follow.

🎯 When is it used?
• Plans for the future
• Warnings and threats
• Promises
• Realistic possibilities

The "if" half stays in the Present Simple even though it is about the future: "If it rains", never "If it will rain".
''',
      formula: '''
If + Present Simple, Will + V1
(Can/May/Should/Imperative de gelebilir)
''',
      formulaEn: '''
If + Present Simple, Will + V1
(Can/May/Should/Imperative are also possible)
''',
      examples: [
        GrammarExample(
          english: 'If it rains tomorrow, we will stay at home.',
          turkish: 'Yarın yağmur yağarsa evde kalacağız.',
          note: 'Muhtemel gelecek durumu',
        ),
        GrammarExample(
          english: 'If you study hard, you can pass the exam.',
          turkish: 'Sıkı çalışırsan sınavı geçebilirsin.',
          note: 'Yetenek/Olasılık (can)',
        ),
        GrammarExample(
          english: 'If you see him, tell him to call me.',
          turkish: 'Onu görürsen beni aramasını söyle.',
          note: 'Emir cümlesi',
        ),
      ],
      commonMistakes: [
        '❌ If it will rain... → ✅ If it rains...',
        '❌ If you will go... → ✅ If you go... (If cümlesinde will olmaz!)',
      ],
      commonMistakesEn: [
        '❌ If it will rain... → ✅ If it rains...',
        '❌ If you will go... → ✅ If you go... (no "will" in the if-clause)',
      ],
      keyPoints: [
        '🔑 If kısmında asla "will" kullanılmaz! (Gelecek anlamı taşısa bile Present Simple kullanılır)',
        '🔑 Unless = If not (Yapmazsan... = Unless you do...)',
      ],
      keyPointsEn: [
        '🔑 Never "will" in the if-clause — the Present Simple carries the future meaning',
        '🔑 Unless = if not ("Unless you study" = "If you don\'t study")',
      ],
    ),

    // 3. SECOND CONDITIONAL
    GrammarSubtopic(
      id: 'second_conditional',
      title: 'Second Conditional',
      titleTr: 'Tip 2: Hayali Durumlar (Şu an)',
      explanation: '''
Şu an veya yakın gelecek için hayali, gerçekleşmesi zor veya imkansız durumları anlatır.

🎯 Ne zaman kullanılır?
• "Yerinde olsam..." (If I were you)
• Piyango çıksa... (İhtimal düşük)
• Hayaller ve varsayımlar
''',
      explanationEn: '''
Describes imaginary, unlikely or impossible situations in the present or the near future.

🎯 When is it used?
• "If I were you..." — advice given as a hypothesis
• Winning the lottery and other long odds
• Dreams and suppositions

The past tense here is not about the past; it marks distance from reality. "Were" is used for every person: "If I were rich", not "If I was rich", in careful English.
''',
      formula: '''
If + Past Simple, Would + V1
(Could/Might da gelebilir)
''',
      formulaEn: '''
If + Past Simple, Would + V1
(Could/Might are also possible)
''',
      examples: [
        GrammarExample(
          english: 'If I had a million dollars, I would buy a house.',
          turkish: 'Bir milyon dolarım olsa (şu an yok), ev alırdım.',
          note: 'Hayali durum',
        ),
        GrammarExample(
          english: 'If I were you, I would accept the offer.',
          turkish: 'Senin yerinde olsam, teklifi kabul ederdim.',
          note: 'Tavsiye',
        ),
        GrammarExample(
          english: 'If she knew the answer, she would tell us.',
          turkish: 'Cevabı bilseydi (bilmiyor), bize söylerdi.',
          note: 'Gerçek dışı',
        ),
      ],
      commonMistakes: [
        '❌ If I was you... → ✅ If I were you... (Resmi/Gramatikal olarak were tercih edilir)',
        '❌ If I would go... → ✅ If I went... (If kısmında would olmaz!)',
      ],
      commonMistakesEn: [
        '❌ If I was you... → ✅ If I were you... ("were" is preferred in careful English)',
        '❌ If I would go... → ✅ If I went... (no "would" in the if-clause)',
      ],
      keyPoints: [
        '🔑 Past Simple kullanılır ama anlam GEÇMİŞ DEĞİL, ŞU ANDIR!',
        '🔑 "Be" fiili tüm şahıslar için "were" olur (I were, she were).',
        '🔑 If kısmında "would" kullanılmaz.',
      ],
      keyPointsEn: [
        '🔑 The Past Simple is used, but the meaning is the PRESENT, not the past',
        '🔑 "Be" becomes "were" for every person (I were, she were)',
        '🔑 No "would" in the if-clause',
      ],
    ),

    // 4. THIRD CONDITIONAL
    GrammarSubtopic(
      id: 'third_conditional',
      title: 'Third Conditional',
      titleTr: 'Tip 3: Geçmişteki Pişmanlıklar',
      explanation: '''
Geçmişte olmuş bitmiş olayları "keşke şöyle olsaydı" diye tersini hayal ederken kullanılır. Artık değiştirmek imkansızdır.

🎯 Ne zaman kullanılır?
• Pişmanlıklar (Keşke çalışsaydım)
• Eleştiriler (Daha dikkatli olmalıydın)
• Geçmişe dair varsayımlar
''',
      explanationEn: '''
Used to imagine the opposite of something that already happened. The past cannot be changed, so this is regret, criticism or supposition rather than a real condition.

🎯 When is it used?
• Regret (If I had studied...)
• Criticism (You should have been more careful)
• Supposition about the past

Both halves look one step further back than usual: had + V3 in the condition, would have + V3 in the result.
''',
      formula: '''
If + Past Perfect (had V3), Would have + V3
(Could have V3 / Might have V3)
''',
      examples: [
        GrammarExample(
          english: 'If I had studied harder, I would have passed the exam.',
          turkish: 'Daha sıkı çalışsaydım (çalışmadım), sınavı geçerdim (geçemedim).',
          note: 'Geçmiş pişmanlık',
        ),
        GrammarExample(
          english: 'If hadn\'t rained, we would have gone to the park.',
          turkish: 'Yağmur yağmasaydı, parka giderdik.',
          note: 'Geçmiş varsayım',
        ),
      ],
      commonMistakes: [
        '❌ If I would have studied... → ✅ If I had studied...',
        '❌ ...I would passed. → ✅ ...I would HAVE passed.',
      ],
      keyPoints: [
        '🔑 Tamamen geçmişi anlatır, geri dönüşü yoktur.',
        '🔑 If kısmında "Past Perfect", ana cümlede "Modal Perfect" kullanılır.',
      ],
      keyPointsEn: [
        '🔑 It is entirely about the past, and nothing about it can be changed',
        '🔑 Past Perfect in the if-clause, a perfect modal in the main clause',
      ],
      comparison: '''
🆚 2nd vs 3rd Conditional:
• Type 2 (Şu an): "If I had a car, I would drive." (Arabam yok, olsa sürerim - hayal)
• Type 3 (Geçmiş): "If I had had a car, I would have driven." (Arabam yoktu, olsa sürerdim - geçmiş)
''',
      comparisonEn: '''
🆚 Second vs third conditional:
• Type 2 (now): "If I had a car, I would drive." — I have no car; if I did, I would drive
• Type 3 (the past): "If I had had a car, I would have driven." — I had no car then, and it is too late now
''',
    ),

    // 5. MIXED CONDITIONALS
    GrammarSubtopic(
      id: 'mixed_conditional',
      title: 'Mixed Conditionals',
      titleTr: 'Karışık Koşullar',
      explanation: '''
Bazen koşul geçmişte, sonuç şu anda olabilir; veya koşul genel bir durum iken sonuç geçmişte kalmış olabilir.

🎯 En yaygın tip (Past Agent -> Present Result):
"Geçmişte şunu yapmasaydım (Type 3), şu an bu durumda olmazdım (Type 2)."
''',
      explanationEn: '''
Sometimes the condition sits in the past while its result sits in the present, or the condition is a general state while the result stayed in the past.

🎯 The commonest kind — past cause, present result:
"If I had not done that in the past (type 3), I would not be in this situation now (type 2)."

So the condition takes had + V3 and the result takes would + V1, mixing the shapes of the third and second conditionals.
''',
      formula: '''
If + Past Perfect (Type 3), Would + V1 (Type 2)
''',
      examples: [
        GrammarExample(
          english: 'If I had eaten breakfast (past), I wouldn\'t be hungry now (present).',
          turkish: 'Kahvaltı yapsaydım (yapmadım), şu an aç olmazdım.',
          note: 'Geçmiş sebep, şimdiki sonuç',
        ),
        GrammarExample(
          english: 'If he were a better player (general), he would have scored yesterday (past).',
          turkish: 'Daha iyi bir oyuncu olsaydı (genel), dün golü atardı (geçmiş).',
          note: 'Genel özellik, geçmiş sonuç',
        ),
      ],
      keyPoints: [
        '🔑 Cümlenin hangi kısmının hangi zamana ait olduğunu anlamak için zaman zarflarına (now, yesterday) bakın.',
      ],
      keyPointsEn: [
        '🔑 To see which half belongs to which time, look at the time expressions (now, yesterday)',
      ],
      examTip: '💡 YDS\'de "now, today" gibi ipuçları varsa Mixed Conditional düşünün.',
    ),
  ],
);
