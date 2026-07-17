# KlioAI Prompt Engineering Strategy

> Production-ready prompt architecture for the KlioAI English learning app.
> Grounded in the actual codebase: [PromptCatalog.java](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java), [ChatbotService.java](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/ChatbotService.java), [DailyWordsService.java](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/DailyWordsService.java), [AiProxyService.java](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/AiProxyService.java).

---

## 1. Diagnosis: Why Current Outputs Are Repetitive

### 1.1 Root Causes Found in Code

> [!NOTE]
> This table is the original diagnosis and is now partially stale. See §8 for
> a code-verified status update: "No conversation memory" and "Fixed speaking
> persona" are both DONE (shipped 2026-07-07); "No Turkish-specific
> interference awareness" is DONE for all 6 non-English source languages
> (2026-07-09); "No topic steering"/"No recent-word exclusion"/"No grammar
> pattern directives" are DONE (Phase 1, shipped prior to 2026-07-09). Only
> "`System.currentTimeMillis()` as only seed" (writing topics) is also DONE
> as of 2026-07-09 (see §10) — every row in this original table is now
> addressed in some form.

| Problem | Where | Evidence |
|---|---|---|
| **No topic steering** | [DailyWordsService L89-118](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/DailyWordsService.java#L89-L118) | Prompt says "Generate 5 Word of the Day" with only `date` as seed. The model defaults to safe/common intermediate words every time. |
| **No recent-word exclusion** | Same file | No `recentWords` or `exclude` list is passed. The model has no way to know what it generated yesterday. |
| **Static system prompt** | [PromptCatalog L22-58](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java#L22-L58) | `generateSentences` system prompt is the same every call. No topic hint, no grammar-pattern directive, no context variety. |
| **No conversation memory** | [ChatbotService L177-273](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/ChatbotService.java#L177-L273) | Chat sends only `system + user` messages. No conversation history → no follow-up, no topic evolution, no memory of past corrections. |
| **`System.currentTimeMillis()` as only seed** | [AiProxyService L276](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/AiProxyService.java#L276) | Writing topic uses `System.currentTimeMillis()` — this is not meaningful diversity. The model treats numeric seeds unreliably. |
| **No CEFR in daily words** | [DailyWordsService L92](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/DailyWordsService.java#L92) | Prompt says "intermediate" but doesn't specify A2/B1/B2. Model defaults to safe B1-ish words. |
| **No grammar pattern directives** | [PromptCatalog L33-36](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java#L33-L36) | Says "vary tense, sentence shape" but gives no concrete pattern list. The model interprets this as minor surface variation. |
| **Fixed speaking persona** | [ChatbotService L260-273](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/ChatbotService.java#L260-L273) | Default chat is always "Amy, American friend". No age/background/interest variation. |
| **No Turkish-specific interference awareness** | All translation prompts | No mention of common Turkish→English errors (article omission, SVO→SOV, tense confusion). |

### 1.2 What the Backend Should Pass into Prompts

| Data | Source | Purpose |
|---|---|---|
| `recentWords` (last 30 days) | PostgreSQL `daily_content` table | Exclude from daily word generation |
| `recentTopics` (last 7 days) | PostgreSQL `daily_content` payloads | Steer to fresh topic categories |
| `userCefrLevel` | User profile / Flutter settings | Match difficulty precisely |
| `userSourceLanguage` | `LearningLanguageProfile` | Tailor interference-aware corrections |
| `todayTopicSlot` | Derived from `dayOfYear % topicCount` | Deterministic topic rotation |
| `grammarPatternSlot` | Derived from `dayOfYear % patternCount` | Force different grammar each day |
| `recentSentencePatterns` | Redis cache per user (last 10 generations) | Avoid "I use X every day" repetition |
| `conversationHistory` | Redis/session (last N messages) | Multi-turn speaking coherence |
| `userWeakAreas` | Practice result analytics | Focus corrections on actual gaps |

### 1.3 Prompt Engineering vs. Database/Logic Split

| Concern | Solve with Prompt | Solve with Backend Logic |
|---|---|---|
| Topic diversity across days | ❌ | ✅ Topic rotation schedule (deterministic) |
| Word deduplication | ❌ | ✅ Query recent words, pass `exclude` list |
| CEFR-appropriate vocabulary | ✅ In prompt | ❌ |
| Grammar pattern variety | ✅ Explicit pattern in prompt | ✅ Select pattern per call |
| Sentence naturalness | ✅ Better prompt rules | ❌ |
| Anti-repetition of sentence starters | ✅ "Do not start with..." rules | ✅ Cache recent starters |
| Speaking persona variety | ✅ Rotate persona in system prompt | ✅ Select persona per session |
| Turkish interference awareness | ✅ In prompt | ❌ |
| Content safety | ✅ Safety guardrails in system prompt | ✅ Output validation |

---

## 2. Content Diversity Strategy

### 2.1 Topic Taxonomy for English Learners

Use **20 topic categories**, cycling deterministically:

```
TOPIC_TAXONOMY = [
  "Daily Life & Routines",        // A1-A2 heavy
  "Food & Cooking",               // A1-B1
  "Travel & Transportation",      // A2-B1
  "Health & Fitness",             // A2-B2
  "Technology & Internet",        // B1-B2
  "Environment & Nature",        // B1-C1
  "Education & Learning",        // A2-B2
  "Work & Careers",              // B1-C1
  "Entertainment & Media",       // A2-B1
  "Science & Discovery",         // B2-C1
  "Culture & Society",           // B1-C1
  "History & Heritage",          // B2-C2
  "Psychology & Emotions",       // B1-B2
  "Money & Economics",           // B2-C1
  "Sports & Competition",        // A2-B1
  "Art & Creativity",            // B1-B2
  "Law & Ethics",                // C1-C2
  "Space & Astronomy",           // B1-B2
  "Relationships & Communication", // A2-B2
  "Innovation & Future"          // B2-C2
]
```

**Selection formula:** `topicIndex = dayOfYear % 20`

### 2.2 CEFR-Aware Vocabulary and Sentence Rules

| Level | Word Frequency Band | Sentence Length | Grammar Ceiling | Example Patterns |
|---|---|---|---|---|
| **A1** | Top 500 most frequent | 4–8 words | Present simple, "there is/are" | "I like...", "She has..." |
| **A2** | Top 1500 | 6–12 words | Past simple, can/could, comparatives | "Last week I went...", "It was bigger than..." |
| **B1** | Top 3000 | 8–16 words | Present perfect, conditionals (1st), passive | "I have never been...", "If it rains..." |
| **B2** | Top 5000 | 10–20 words | 2nd/3rd conditionals, reported speech, modals | "Had she known...", "It is believed that..." |
| **C1** | Top 8000 + academic | 12–25 words | Inversion, subjunctive, cleft sentences | "Not only did...", "Were it not for..." |
| **C2** | Full range + idiomatic | 15–30+ words | All advanced, rhetorical, embedded clauses | "Compelling though the argument may be..." |

### 2.3 Anti-Repetition Rules

**Backend-enforced (Redis-backed):**

```java
// Key: daily:words:recent:{yyyy-MM} 
// Value: SET of recently generated words (last 30 days)
// TTL: 35 days

// Key: user:{userId}:sentence:starters
// Value: LIST of last 20 sentence opening words
// TTL: 7 days

// Key: user:{userId}:chat:topics  
// Value: LIST of last 10 conversation topics
// TTL: 24 hours
```

**Prompt-enforced (in user message):**

```
ANTI-REPETITION:
- Do NOT use these words (recently generated): [${excludeWords}]
- Do NOT start any sentence with: "I", "The", "She", "He", "It is" (vary openings)
- Each sentence must use a DIFFERENT grammatical subject
- At least 2 of 5 sentences must be questions, exclamations, or conditionals
```

### 2.4 Seed, Profile, History, and Difficulty Usage

| Input | How to Use | Example |
|---|---|---|
| **Date seed** | Topic rotation, not random noise | `topicIndex = dayOfYear % 20` |
| **User CEFR level** | Sets vocabulary band + grammar ceiling | `"Target CEFR: B1"` in prompt |
| **Recent history** | Exclusion list in prompt | `"EXCLUDE these words: [resilient, insight, enhance]"` |
| **Difficulty preference** | Mixed within each generation | `"Include 2 Easy, 2 Medium, 1 Hard word"` |
| **Source language** | Turkish-specific interference rules | `"Common Turkish learner errors: article omission, word order"` |

---

## 3. Production-Ready Prompt Templates

### 3.1 Daily Words Generation

**Replaces:** [DailyWordsService.generateDailyWordsPayload](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/DailyWordsService.java#L87-L145)

#### System Prompt
```
You are a professional English vocabulary curriculum designer for KlioAI.

LANGUAGE POLICY:
- Source/native language: ${sourceLanguage}
- Target/practice language: English
- Feedback language: ${feedbackLanguage}

CONTENT SAFETY:
- No violence, profanity, sexual content, or politically divisive material.
- No references to app features that do not exist.
- All examples must be culturally appropriate for adult language learners.

OUTPUT: Return ONLY a minified JSON object. No markdown, no explanations.
```

#### User Prompt Template
```
Generate 5 "Word of the Day" English vocabulary words.

TODAY'S TOPIC CATEGORY: ${topicCategory}
TARGET CEFR RANGE: ${cefrLevel} (mix 2 Easy, 2 Medium, 1 Hard within this band)
DATE: ${date}

EXCLUDE these recently used words: [${excludeWordsCSV}]

VOCABULARY RULES:
1. All 5 words must relate to "${topicCategory}" but span different sub-topics.
2. Include at least 2 different parts of speech (noun, verb, adjective, adverb).
3. Words must be genuinely useful for ${cefrLevel} learners, not obscure.
4. Pronunciation must use IPA notation.
5. Example sentences must demonstrate the word in a natural, memorable context.
6. ${sourceLanguage} translations must be natural, not word-for-word.
7. Synonyms should be at or below the target CEFR level.

DIVERSITY RULES:
- Do NOT pick the most obvious word for the topic (e.g., for "Food": avoid "eat", "cook").
- Pick words a learner would encounter in real English media about this topic.
- Example sentences must use varied subjects (not all "I" or "She").
- At least one example should be a question or exclamation.

JSON SCHEMA:
{
  "words": [
    {
      "id": 1,
      "word": "string",
      "pronunciation": "/IPA/",
      "translation": "string (${sourceLanguage})",
      "partOfSpeech": "Noun|Verb|Adjective|Adverb|Phrasal Verb",
      "definition": "string (English, max 15 words)",
      "exampleSentence": "string (English)",
      "exampleTranslation": "string (${sourceLanguage})",
      "synonyms": ["string", "string", "string"],
      "difficulty": "Easy|Medium|Hard",
      "cefrLevel": "A2|B1|B2|C1",
      "topicTag": "string (sub-topic within ${topicCategory})"
    }
  ]
}
```

#### Required Input Variables
| Variable | Source | Example |
|---|---|---|
| `topicCategory` | `TOPIC_TAXONOMY[dayOfYear % 20]` | `"Health & Fitness"` |
| `cefrLevel` | User profile or `"B1"` default | `"B1-B2"` |
| `date` | `LocalDate.now()` | `"2026-05-30"` |
| `excludeWordsCSV` | Last 30 days from `daily_content` | `"resilient, insight, enhance, diligent, subtle"` |
| `sourceLanguage` | `LearningLanguageProfile` | `"Turkish"` |
| `feedbackLanguage` | `LearningLanguageProfile` | `"Turkish"` |

#### Validation Rules
```java
// Post-generation validation
boolean isValid(JsonNode payload) {
    JsonNode words = payload.get("words");
    if (words == null || !words.isArray() || words.size() != 5) return false;
    
    Set<String> partOfSpeech = new HashSet<>();
    for (JsonNode word : words) {
        if (isBlank(word, "word") || isBlank(word, "pronunciation")
            || isBlank(word, "translation") || isBlank(word, "definition")
            || isBlank(word, "exampleSentence") || isBlank(word, "exampleTranslation"))
            return false;
        if (excludeWords.contains(word.get("word").asText().toLowerCase()))
            return false;  // Repetition leak
        partOfSpeech.add(word.get("partOfSpeech").asText());
    }
    return partOfSpeech.size() >= 2;  // At least 2 different POS
}
```

---

### 3.2 User Vocabulary Sentence Generation

**Replaces:** [PromptCatalog.generateSentences](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java#L21-L58)

#### System Prompt
```
You are a professional English sentence designer for vocabulary practice.

LANGUAGE POLICY:
- Source language: ${sourceLanguage}
- Target language: English
- Feedback in: ${feedbackLanguage}

CONTENT SAFETY:
- Age-appropriate, culturally sensitive content only.
- No violence, profanity, or sexually suggestive material.

OUTPUT: Return ONLY a minified JSON object. No markdown.
```

#### User Prompt Template
```
Generate 5 practice sentences using the word "${targetWord}" (${wordTranslation}).

TARGET CEFR: ${cefrLevel}
REQUESTED MIX: ${lengthMix}

MANDATORY GRAMMAR PATTERN DISTRIBUTION:
1. Sentence 1: ${grammarPattern1} (e.g., present perfect passive)
2. Sentence 2: ${grammarPattern2} (e.g., conditional type 2)
3. Sentence 3: ${grammarPattern3} (e.g., relative clause)
4. Sentence 4: ${grammarPattern4} (e.g., reported speech)
5. Sentence 5: ${grammarPattern5} (e.g., question form)

CONTEXT VARIETY (each sentence in a different setting):
- Academic/professional, casual/social, media/news, personal narrative, hypothetical

ANTI-MONOTONY RULES:
- Do NOT start more than 1 sentence with a pronoun (I, He, She, They).
- Do NOT use "every day", "always", or "usually" in more than 1 sentence.
- At least 1 sentence must be a question.
- At least 1 sentence must use the word in a NON-OBVIOUS meaning if the word is polysemous.
- Sentences must feel like they come from 5 different texts, not variations of one idea.

RECENTLY USED STARTERS (avoid these): [${recentStarters}]

JSON SCHEMA:
{
  "sentences": [
    {
      "englishSentence": "string",
      "turkishTranslation": "string (short meaning of target word here)",
      "turkishFullTranslation": "string (full natural ${sourceLanguage} sentence)",
      "grammarPattern": "string (which pattern was used)",
      "context": "string (academic|casual|media|personal|hypothetical)"
    }
  ]
}
```

#### Required Input Variables
| Variable | Source | Example |
|---|---|---|
| `targetWord` | User's selected word | `"determine"` |
| `wordTranslation` | From user's word list | `"belirlemek"` |
| `cefrLevel` | User profile | `"B1"` |
| `lengthMix` | Flutter request `lengths` | `"2 short, 2 medium, 1 long"` |
| `grammarPattern1-5` | Rotated from pattern bank (see below) | `"present perfect continuous"` |
| `recentStarters` | Redis `user:{id}:sentence:starters` | `"I, The, She"` |

#### Grammar Pattern Bank (rotate per call)
```java
List<List<String>> GRAMMAR_PATTERN_SETS = List.of(
    List.of("present simple active", "past continuous", "first conditional", "passive voice", "wh-question"),
    List.of("present perfect", "second conditional", "relative clause (who/which)", "imperative", "reported speech"),
    List.of("past simple", "present continuous", "third conditional", "gerund as subject", "tag question"),
    List.of("future with 'will'", "past perfect", "comparative/superlative", "infinitive of purpose", "embedded question"),
    List.of("used to + infinitive", "modal verb (should/might)", "cleft sentence", "passive reporting", "exclamatory")
);
// Select: patternSetIndex = (userId.hashCode() + callCount) % GRAMMAR_PATTERN_SETS.size()
```

---

### 3.3 Translation Practice Prompt

**Replaces:** [PromptCatalog.checkTranslation](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java#L65-L103) and [checkEnglishTranslation](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java#L110-L143)

#### System Prompt (EN→TR direction)
```
You are a supportive English-to-${sourceLanguage} translation coach for ${sourceLanguage}-speaking learners.

LANGUAGE POLICY:
- Source language: ${sourceLanguage}
- Target language: English
- Feedback language: ${feedbackLanguage}

EVALUATION PHILOSOPHY:
- Be GENEROUS. If the meaning is conveyed correctly, mark CORRECT even with minor style differences.
- Multiple valid translations exist for almost every sentence. Accept all reasonable ones.
- IGNORE: typos, capitalization, minor punctuation, extra/missing spaces.
- Mark INCORRECT only for: significant meaning errors, fundamental grammar breaks, or multiple major errors.

TURKISH LEARNER AWARENESS (when sourceLanguage=Turkish):
- Turkish learners often omit articles (a/the). If the ${sourceLanguage} translation correctly omits them (since ${sourceLanguage} has no articles), do NOT penalize.
- Word order differences are expected. Accept SOV-influenced translations if meaning is clear.
- Tense mapping between English and ${sourceLanguage} is not 1:1. Accept reasonable tense choices.

FEEDBACK STYLE:
- When CORRECT: Celebrate briefly in ${feedbackLanguage}. Optionally suggest a more natural phrasing as a "tip" (not a correction).
- When INCORRECT: Explain the error clearly and constructively in ${feedbackLanguage}. Show the correct version. Never be condescending.

OUTPUT: Return ONLY a JSON object. No markdown.
```

#### User Prompt Template
```
English sentence: "${englishSentence}"
User's ${sourceLanguage} translation: "${userTranslation}"

Evaluate the translation.

JSON SCHEMA:
{
  "isCorrect": boolean,
  "correctTranslation": "string (most natural ${sourceLanguage} translation)",
  "feedback": "string (${feedbackLanguage}, encouraging)",
  "alternativeTranslations": ["string", "string"],
  "errorType": "null | meaning | grammar | vocabulary | tense",
  "tip": "string | null (optional improvement suggestion even when correct)"
}
```

#### Validation Rules
```java
boolean isValid(Map<String, Object> result) {
    return result.containsKey("isCorrect")
        && result.get("isCorrect") instanceof Boolean
        && hasNonBlank(result, "correctTranslation")
        && hasNonBlank(result, "feedback");
}
```

---

### 3.4 Speaking Conversation Prompt

**Replaces:** [ChatbotService.buildChatSystemPrompt](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/ChatbotService.java#L177-L273)

> [!IMPORTANT]
> The biggest improvement here is adding **conversation history** and **persona rotation**.

#### System Prompt Template (with persona rotation)
```
You are ${personaName}, ${personaDescription}.

YOUR PERSONALITY:
${personaTraits}

LEARNER CONTEXT:
- Learner's CEFR level: ${cefrLevel}
- Learner's native language: ${sourceLanguage}
- Session topic (if any): ${sessionTopic}

RESPONSE RULES:
- Keep responses to ${maxSentences} sentences.
- Use vocabulary and grammar at or slightly above ${cefrLevel}.
- End with a question to keep the conversation going.
- Use natural spoken English: contractions, fillers, casual expressions.
${correctionPolicy}

CONVERSATION PHASE: ${phase}
${phaseGuidance}

CRITICAL:
- Do NOT mention you are an AI, a bot, or a language tool.
- Do NOT list grammar rules or give lecture-style explanations.
- Do NOT use emojis excessively (max 1 per message).
- If the user writes in ${sourceLanguage}, gently switch back to English.
```

#### Persona Bank (rotate per session)
```java
record Persona(String id, String name, String description, String traits) {}

List<Persona> PERSONA_BANK = List.of(
    new Persona("amy", "Amy", "a 28-year-old American graphic designer who loves hiking and coffee",
        "- Warm, curious, uses expressions like 'Oh cool!', 'That's awesome!'\n- Shares personal anecdotes about design projects and weekend trips"),
    new Persona("james", "James", "a 35-year-old British journalist who has traveled to 40 countries",
        "- Thoughtful, asks probing questions, uses 'quite', 'rather', 'brilliant'\n- Loves debating ideas and hearing different perspectives"),
    new Persona("sofia", "Sofia", "a 24-year-old Australian uni student studying environmental science",
        "- Energetic, uses Aussie slang like 'heaps', 'reckon', 'no worries'\n- Passionate about sustainability and beach culture"),
    new Persona("marcus", "Marcus", "a 40-year-old Canadian chef who runs a small restaurant",
        "- Patient, detail-oriented, uses food metaphors\n- Loves sharing cooking stories and asking about food culture"),
    new Persona("priya", "Priya", "a 30-year-old Indian-American software engineer who loves sci-fi",
        "- Analytical but friendly, uses tech references casually\n- Enjoys discussing movies, books, and future technology")
);
// Select: personaIndex = sessionId.hashCode() % PERSONA_BANK.size()
```

#### Conversation Phase System
```java
enum ConversationPhase {
    OPENING,    // First 1-2 messages: warm greeting, find topic
    DEEPENING,  // Messages 3-6: explore topic, share opinions
    CHALLENGE,  // Messages 7-10: introduce disagreement or complexity
    WINDING     // Messages 11+: summarize, reflect, close naturally
}

String phaseGuidance(ConversationPhase phase) {
    return switch (phase) {
        case OPENING -> "Start with a warm greeting. Find a topic the learner is interested in. Ask open-ended questions.";
        case DEEPENING -> "Explore the topic deeper. Share your own perspective. Ask 'why' and 'how' questions.";
        case CHALLENGE -> "Respectfully challenge an opinion. Introduce a new angle. Push the learner to argue their point.";
        case WINDING -> "Summarize what you discussed. Share a final thought. End warmly.";
    };
}
```

#### Scenario Roleplay Prompts Now CEFR-Tiered Too (2026-07-09)

The 4 scenario prompts (Sarah/HR, Dr. Johnson/academic, Alex/colleague,
Michael/manager — `ChatbotService.buildChatSystemPrompt`) previously ignored
the learner's profile entirely, unlike default chat mode. Deliberately scoped
narrow: only correction *frequency* (via the existing
`correctionFrequencyGuidance(cefrLevel)`) was added to each scenario's system
prompt. Vocabulary/register was intentionally left as-is — these scenarios
(job interview, academic defense, workplace conflict) are inherently
upper-intermediate+ situations, and simplifying the roleplay partner's
language for a low-level learner would undermine scenario realism more than
it would help. A low-level learner attempting these scenarios still gets a
professional-register roleplay partner, just one who doesn't correct their
English directly.

#### CEFR-Tiered Correction Policy
```java
String correctionPolicy(String cefrLevel) {
    return switch (cefrLevel) {
        case "A1", "A2" -> """
            CORRECTION: Do NOT correct errors directly. Simply model correct usage in your responses.
            If meaning is unclear, ask a clarifying question rather than pointing out the error.
            Priority: Keep them talking. Confidence > accuracy at this stage.
            """;
        case "B1" -> """
            CORRECTION: If the learner makes a clear grammar error, recast it naturally:
            - User: "I go to cinema yesterday"
            - You: "Oh nice, you went to the cinema! What did you watch?"
            Only recast 1 error per message. Never more.
            """;
        case "B2" -> """
            CORRECTION: You may gently point out errors using natural phrasing:
            - "By the way, we usually say 'I've been living here' rather than 'I live here since...'"
            Limit to 1 correction per 2-3 messages. Always sandwich between positive engagement.
            """;
        default -> """  
            CORRECTION: You can provide direct but friendly corrections:
            - "Small note: 'Despite of' should be 'Despite' — no 'of' needed. Your point was great though!"
            Correct up to 2 errors per message if they're significant. Focus on patterns, not one-off slips.
            """;
    };
}
```

#### Required Input Variables
| Variable | Source | Example |
|---|---|---|
| `personaName`, `personaDescription`, `personaTraits` | Persona bank rotation | See above |
| `cefrLevel` | User profile | `"B1"` |
| `sourceLanguage` | `LearningLanguageProfile` | `"Turkish"` |
| `sessionTopic` | Scenario or `"free conversation"` | `"job interview followup"` |
| `maxSentences` | CEFR-based: A1-A2=2, B1=3, B2+=4 | `"3"` |
| `correctionPolicy` | `correctionPolicy(cefrLevel)` | See above |
| `phase` | Derived from message count | `"DEEPENING"` |
| `phaseGuidance` | `phaseGuidance(phase)` | See above |
| `conversationHistory` | Last 6 messages from Redis session | System provides context |

---

### 3.5 Reading Exercise Prompt

**Enhances:** [AiProxyService.generateReadingPassage](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/AiProxyService.java#L148-L253)

#### User Prompt Template (additions to existing)
```
Generate a reading passage for ${cefrLevel} English learners.

TODAY'S TOPIC: ${specificTopic} (from category: ${topicCategory})

CONTENT REQUIREMENTS:
- The passage must tell a STORY or present a SPECIFIC ARGUMENT — not generic advice.
- Include at least one proper noun (person name, place, or organization).
- ${cefrLevel}-specific: ${levelConstraints}

QUESTION REQUIREMENTS:
- Question 1: FACTUAL (answer directly stated in text)
- Question 2: INFERENCE (requires reading between the lines)
- Question 3: VOCABULARY IN CONTEXT (what does word X mean in this passage?)
- Each question must have exactly 4 options with 1 correct answer.
- Distractors must be plausible but clearly wrong when the text is read carefully.
- "correctAnswerQuote" must be an EXACT quote from the passage text.

ANTI-REPETITION:
- Do NOT write about: ${recentReadingTopics}
- Do NOT use generic "daily routine" or "learning English" meta-topics for B2+.

JSON SCHEMA:
{
  "title": "string (engaging, specific — not 'Daily Reading')",
  "text": "string (passage text)",
  "wordCount": number,
  "keyVocabulary": ["word1", "word2", "word3"],
  "questions": [
    {
      "question": "string",
      "type": "factual|inference|vocabulary",
      "options": ["A text", "B text", "C text", "D text"],
      "correctAnswer": "A|B|C|D",
      "explanation": "string (why correct, ${feedbackLanguage})",
      "correctAnswerQuote": "string (exact text quote)"
    }
  ]
}
```

---

### 3.6 Writing Exercise Prompt

**Enhances:** [AiProxyService.generateWritingTopic](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/AiProxyService.java#L271-L289)

#### User Prompt Template
```
Generate a creative writing topic for ${cefrLevel} English learners.

TODAY'S CATEGORY: ${topicCategory}
WORD COUNT TARGET: ${wordCount}

TOPIC REQUIREMENTS:
- Must be SPECIFIC and ENGAGING — not generic like "Write about your daily routine."
- Should have a clear angle or constraint that guides the writer.
- Must be achievable at ${cefrLevel} with vocabulary they likely know.

GOOD EXAMPLES for B1:
- "A friend asks you to recommend a restaurant. Write an email explaining why they should go there."
- "You witnessed something unusual on your way to work. Describe what happened."

BAD EXAMPLES (too vague):
- "Write about technology." / "Describe your hobby."

EXCLUDE RECENT TOPICS: [${recentWritingTopics}]

JSON SCHEMA:
{
  "topic": "string (the writing prompt)",
  "description": "string (guidance for the writer, ${feedbackLanguage})",
  "level": "${cefrLevel}",
  "wordCount": "${wordCount}",
  "suggestedStructure": "string (e.g., 'Introduction → 2 body paragraphs → conclusion')",
  "vocabularyHints": ["word1", "word2", "word3"],
  "grammarFocus": "string (e.g., 'past simple narrative' for A2)"
}
```

---

## 4. Speaking Practice Improvement

### 4.1 Making Speaking Less Monotonous

| Problem | Solution |
|---|---|
| Same persona every time | **Persona rotation** (5+ personas, selected per session) |
| No topic evolution | **Conversation phases** (opening → deepening → challenge → winding) |
| No follow-up depth | **Multi-turn history** (send last 6 messages as context) |
| Same correction style | **CEFR-tiered correction** (A1: zero correction, C1: direct correction) |
| No real scenarios | **Scenario expansion** (add 8+ scenarios beyond current 4) |
| Predictable responses | **Varied response templates** (sometimes agree, sometimes disagree, sometimes redirect) |

### 4.2 Expanded Scenario Bank

```java
// Current: 4 scenarios (job_interview, academic_qa, disagreement, explaining_to_manager)
// Proposed: 12 scenarios covering diverse real-world needs

Map<String, ScenarioDef> SCENARIO_BANK = Map.ofEntries(
    // EXISTING (keep)
    entry("job_interview_followup", ...),
    entry("academic_presentation_qa", ...),
    entry("disagreement_colleague", ...),
    entry("explaining_to_manager", ...),
    
    // NEW: Daily Life
    entry("ordering_restaurant", new ScenarioDef(
        "Server at a restaurant",
        "You are Pat, a friendly waiter. The customer is ordering, asking about menu items, and making special requests.",
        "A1-B1")),
    entry("doctor_appointment", new ScenarioDef(
        "Doctor's receptionist, then doctor",
        "Phase 1: Receptionist schedules the appointment. Phase 2: Doctor asks about symptoms.",
        "A2-B2")),
    entry("apartment_viewing", new ScenarioDef(
        "Real estate agent showing an apartment",
        "Show the apartment, answer questions about rent, neighborhood, and lease terms.",
        "B1-B2")),
    
    // NEW: Professional
    entry("client_call", new ScenarioDef(
        "Client unhappy with a delivery delay",
        "You are the client. Be frustrated but reasonable. Make the learner practice de-escalation.",
        "B2-C1")),
    entry("team_standup", new ScenarioDef(
        "Team lead running a standup meeting",
        "Ask each person for updates. The learner must give theirs concisely.",
        "B1-B2")),
    
    // NEW: Social
    entry("making_plans_friend", new ScenarioDef(
        "Friend trying to make weekend plans",
        "Suggest activities, negotiate times, handle scheduling conflicts.",
        "A2-B1")),
    entry("neighbor_complaint", new ScenarioDef(
        "Neighbor with a polite complaint about noise",
        "Practice apologizing, explaining, and finding a compromise.",
        "B1-B2")),
    entry("debate_topic", new ScenarioDef(
        "Debate partner on a light topic",
        "Topic rotates: 'Is remote work better?', 'Should school start later?', etc.",
        "B2-C1"))
);
```

### 4.3 CEFR-Tiered Speaking Examples

#### A1/A2 Learner — Ordering at a Restaurant
```
System: You are Pat, a friendly waiter at a casual American restaurant.

RULES:
- Speak SLOWLY with simple vocabulary.
- Use short sentences (5-8 words max).
- If the learner seems stuck, offer choices: "Would you like chicken or fish?"
- Do NOT correct errors. Just respond naturally.
- Keep it to 2 sentences per message.

CONVERSATION FLOW:
1. Greet and ask if ready to order
2. Take the order, ask about drinks
3. Mention a special or dessert
4. Confirm the order

Example:
Pat: "Hi there! Welcome! Are you ready to order?"
User: "Yes, I want chicken."
Pat: "Great choice! And what would you like to drink?"
```

#### B1/B2 Learner — Explaining to Manager
```
System: You are Michael, a busy senior manager at a marketing firm.

RULES:
- Be professional but slightly pressed for time.
- Ask follow-up questions that require the learner to elaborate.
- If the learner uses vague language, ask for specifics.
- Recast 1 grammar error per message naturally.
- Keep responses to 3 sentences.

CONVERSATION FLOW:
1. Ask what they need to discuss (be slightly impatient)
2. Listen, then challenge their reasoning
3. Ask about impact/timeline
4. Give a decision or ask for a follow-up

Example:
Michael: "I've got 10 minutes before my next call. What did you need?"
User: "I want to talk about the project deadline. I think we need more time."
Michael: "More time? How much are we talking about, and what's causing the delay specifically?"
```

### 4.4 Balancing Conversation vs. Correction

> [!TIP]
> The golden rule: **Correction should never exceed 20% of any message.** 80% should be genuine engagement.

**Pattern: The Recast Sandwich**
```
[Engagement with topic] + [Natural recast of error] + [Follow-up question]

User: "Yesterday I go to the park and I see many peoples."
Bot: "Oh nice, the park sounds great! I love going to parks too — 
      especially when there are a lot of people enjoying the sun. 
      What did you do there?"
```

**What to correct vs. what to ignore:**

| Error Type | A1-A2 | B1 | B2+ |
|---|---|---|---|
| Article omission | Ignore | Ignore | Recast |
| Wrong tense | Ignore | Recast | Recast or note |
| Word order | Ignore | Ignore | Recast |
| Wrong preposition | Ignore | Recast | Note directly |
| Vocabulary misuse | Ignore | Recast | Note directly |
| Pronunciation (in text) | N/A | N/A | N/A |
| Run-on sentence | Ignore | Ignore | Note |

---

## 5. Sentence / Translation Practice Improvement

### 5.1 Generating Natural, Varied Sentences

**Current problem (from [PromptCatalog.generateSentences](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java#L33-L36)):** The prompt says "vary tense, sentence shape" but gives no concrete guidance. Models interpret this as swapping "I" for "She" or changing "use" to "used."

**Fix: Explicit Grammar Pattern Assignment**

Instead of saying "vary," assign a SPECIFIC pattern to each sentence slot:

```
Sentence 1 MUST use: ${grammarPattern1}
Sentence 2 MUST use: ${grammarPattern2}
...
```

The backend rotates through pattern sets (see Section 3.2), so consecutive calls produce genuinely different structures.

**Fix: Context Anchoring**

Each sentence must be from a different real-world context:

```
CONTEXT SLOTS:
1. Academic/educational setting
2. Casual conversation between friends
3. News/media report
4. Personal diary entry or internal monologue
5. Formal/professional communication
```

This prevents the "5 slightly different textbook sentences" problem.

### 5.2 Including Target Words Naturally

**Bad (current tendency):**
```
Target word: "determine"
→ "I need to determine the answer."
→ "She determined the result."
→ "They will determine the outcome."
```

**Good (with context anchoring + grammar patterns):**
```
Target word: "determine"
→ "What ultimately determined her decision to move abroad was the job offer, not the weather." (cleft-like emphasis, personal narrative)
→ "Researchers have yet to determine whether the new treatment has long-term side effects." (present perfect, academic)
→ "If you're determined enough, you can learn any language — it just takes consistent practice." (adjective form, motivational)
→ "The court will determine the outcome of the case next month." (future, legal/news)
→ "Hasn't anyone determined why the system keeps crashing?" (negative question, workplace)
```

**Prompt rules that force this:**
```
WORD USAGE RULES:
- Use the target word in at least 2 different grammatical forms if possible (verb, adjective, noun form).
- Never place the target word as the last word of the sentence.
- In at least 1 sentence, the target word should be part of a longer phrase or collocation, not stand alone.
- The target word must be essential to the sentence meaning — removing it should break the sentence.
```

### 5.3 Turkish-to-English Prompts Without Awkward Translations

**Current problem:** The system generates English sentences, translates to Turkish for the prompt, and Turkish learners translate back. But the Turkish source sentences often feel like "translated Turkish" — unnatural phrasings that no Turkish speaker would produce naturally.

**Fix: Generate Turkish-first for TR→EN direction**

```
When generating sentences for Turkish-to-English translation practice:

TURKISH SENTENCE RULES:
1. The Turkish sentence must sound like something a Turkish person would NATURALLY say or write.
2. Do NOT translate from English first. Think in Turkish first.
3. Use Turkish-specific expressions that have non-literal English equivalents:
   - "Canım sıkıldı" → "I'm bored" (not "My soul is squeezed")
   - "Ayağını denk al" → "Be careful" / "Watch your step"
   - "Gözden düşmek" → "To fall out of favor"
4. Include Turkish cultural context when natural (çay, bayram, komşuluk, etc.)
5. The English translation should be the NATURAL English equivalent, not a word-for-word translation.

COMMON TURKISH→ENGLISH CHALLENGE AREAS (focus on these):
- Articles: Turkish has no a/the. Include sentences where article choice matters.
- Tense mapping: Turkish -miş past vs English present perfect vs past simple.
- Word order: Turkish SOV → English SVO transformation.
- Prepositions: Turkish uses case suffixes, English uses prepositions.
- Relative clauses: Turkish uses participles, English uses who/which/that.
```

---

## 6. Implementation Recommendations

### 6.1 Backend Service Structure

```
PromptCatalog.java (current)
  └── Keep as the single source of prompt templates
  └── Add: topicRotation(), grammarPatternRotation(), personaRotation()
  └── Each method returns a PromptDef with dynamic template variables filled in

NEW: PromptContextService.java
  └── getRecentDailyWords(int days) → List<String>  (from daily_content)
  └── getRecentReadingTopics(int days) → List<String>
  └── getUserRecentStarters(Long userId) → List<String>  (from Redis)
  └── recordGeneratedWords(List<String> words)  (to Redis + daily_content)
  └── recordSentenceStarters(Long userId, List<String> starters)

NEW: ConversationSessionService.java
  └── getSessionHistory(String sessionId) → List<Message>
  └── appendMessage(String sessionId, String role, String content)
  └── getSessionPhase(String sessionId) → ConversationPhase
  └── rotatePersona(String sessionId) → Persona
```

### 6.2 Metadata Storage

#### PostgreSQL (already exists, extend)

```sql
-- Already exists: daily_content table
-- No schema change needed for daily words/reading/writing dedup.
-- Query recent payloads to extract used words/topics.

-- Optional: Add a lightweight prompt_audit table for quality tracking
CREATE TABLE prompt_audit (
    id BIGSERIAL PRIMARY KEY,
    scope VARCHAR(50) NOT NULL,          -- 'daily-words', 'generate-sentences', etc.
    prompt_version INT NOT NULL,
    model VARCHAR(100),
    input_hash VARCHAR(64),              -- SHA-256 of input variables
    output_valid BOOLEAN,
    tokens_used INT,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_prompt_audit_scope ON prompt_audit(scope, created_at);
```

#### Redis (extend existing usage)

```
# Daily word deduplication (already have daily_content, this is a fast lookup)
SET  daily:words:recent:2026-05        {"resilient","insight","enhance",...}
TTL  35 days

# Per-user sentence starter tracking
LIST user:42:sentence:starters          ["I","The","She","When","Although"]
TTL  7 days
MAXLEN 20

# Conversation session history
LIST chat:session:{sessionId}:messages   ["{role:user,content:...}", ...]
TTL  2 hours (or until session ends)
MAXLEN 20 (keep last 10 pairs)

# Topic tracking for reading/writing dedup
SET  daily:topics:reading:2026-05       {"climate","archaeology","music"}
TTL  35 days
```

### 6.3 Automated Prompt Quality Testing

#### Unit Test Approach

```java
@Test
void dailyWords_shouldProduceDiversePartsOfSpeech() {
    // Generate 5 consecutive days of daily words
    // Assert: across 25 words, at least 3 different POS types
    // Assert: no word appears more than once
    // Assert: all words have non-empty pronunciation, translation, example
}

@Test
void sentenceGeneration_shouldVaryGrammarPatterns() {
    // Generate sentences for "determine" with 3 different pattern sets
    // Assert: sentence structures are measurably different (no 2 start with same word)
    // Assert: at least 1 question form exists
}

@Test  
void translationCheck_shouldAcceptReasonableVariations() {
    // Submit 5 known-correct Turkish translations of an English sentence
    // Assert: all 5 marked isCorrect=true
    // Submit 3 clearly wrong translations
    // Assert: all 3 marked isCorrect=false
}
```

#### Batch Quality Check (weekly cron)

```java
@Scheduled(cron = "0 0 3 * * MON")  // Monday 3 AM
void weeklyPromptQualityCheck() {
    // 1. Generate 7 days of daily words with mock dates
    // 2. Check: no word repeats across the 7 days
    // 3. Check: topic coverage spans at least 5 different categories
    // 4. Check: all JSON schemas are valid
    // 5. Log results to prompt_audit table
    // 6. Alert if repeat rate > 10% or validation failure > 5%
}
```

### 6.4 A/B Test Ideas

| Test | Hypothesis | Metric | Effort |
|---|---|---|---|
| **Topic rotation vs. random** | Deterministic rotation produces more diverse words over 30 days | Unique word count per user per month | Low (backend change only) |
| **Grammar pattern assignment vs. "vary"** | Explicit patterns produce more structurally different sentences | User-rated variety score (in-app survey) | Medium |
| **Persona rotation vs. fixed Amy** | Multiple personas increase speaking session length | Avg messages per speaking session | Low |
| **Recast correction vs. no correction** | Recasts improve accuracy without reducing message count | Error reduction rate + messages per session | Medium |
| **Turkish-first generation** | Native-sounding Turkish sentences improve translation accuracy | Translation practice completion rate | Medium |

### 6.5 Free vs. Premium Strategy

#### Free Users (1500 tokens/day)

| Feature | Token Budget | Strategy |
|---|---|---|
| Daily Words | 0 (pre-generated, shared) | Same content for all users |
| 1 sentence generation | ~300 tokens | Use shorter system prompt, fewer examples |
| 1 translation check | ~200 tokens | Same quality prompt |
| 2-3 chat messages | ~600 tokens | Shorter max_tokens (150), simpler persona |
| Daily reading | 0 (pre-generated, shared) | Same content for all |
| **Total** | **~1100 tokens typical** | Leaves buffer for quota |

**Free prompt optimization:**
```java
String freeSystemPrompt = """
    You are a helpful English tutor. Keep responses concise.
    Return only valid JSON.
    """;
// ~20 tokens vs. ~150 tokens for premium system prompt
// Savings: ~130 tokens per call × 3 calls = 390 tokens saved
```

#### Premium Users (30000-60000 tokens/day)

| Feature | Token Budget | Strategy |
|---|---|---|
| Daily Words | 0 (shared) | Same + personalized word suggestions based on user's word list |
| Unlimited sentence gen | ~400 tokens each | Full system prompt with grammar patterns, context anchoring |
| Unlimited translation | ~300 tokens each | Full prompt with alternative translations, detailed feedback |
| Unlimited chat | ~500 tokens each | Full persona rotation, conversation history, correction |
| On-demand reading | ~800 tokens each | Custom level + topic, not just daily |
| On-demand writing | ~600 tokens each | Personalized topics based on interests |
| **Total** | **Budget rarely hit** | Focus on quality, not savings |

**Premium-exclusive features (MVP):**
- 🎯 "Practice My Weak Areas" — backend analyzes translation errors, generates targeted practice
- 📝 "Personalized Daily Words" — words selected from topics the user hasn't covered
- 🗣️ "Extended Conversations" — no message limit, full conversation history

---

## 7. MVP Implementation Path

### Phase 1: Quick Wins (1-2 days, no schema changes)

1. **Topic rotation in daily words** — add `topicIndex = dayOfYear % 20` and inject topic into prompt
2. **Grammar pattern sets in sentence generation** — add `GRAMMAR_PATTERN_SETS` to `PromptCatalog`, rotate per call
3. **Persona rotation in speaking** — add `PERSONA_BANK`, select by session
4. **Recent word exclusion** — query last 7 days of `daily_content`, extract words, pass as `EXCLUDE` list
5. **Anti-starter repetition** — add "Do NOT start with I, The, She" to sentence prompts

### Phase 2: Structural Improvements (3-5 days)

1. **`PromptContextService`** — new service to gather context data for prompts
2. **Redis sentence starter tracking** — store and retrieve per-user
3. **Conversation history for speaking** — send last 6 messages in chat requests
4. **CEFR-tiered correction policies** — different system prompts by level
5. **Conversation phases** — track message count, adjust phase guidance

### Phase 3: Quality & Analytics (1 week)

1. **`prompt_audit` table** — track schema validity, tokens, model
2. **Weekly quality cron** — automated diversity check
3. **Turkish-first generation for TR→EN** — separate prompt path for translation practice
4. **A/B test framework** — feature flags for prompt variants
5. **Premium personalization** — weak-area analysis, personalized topics

> [!NOTE]  
> Phase 1 changes are entirely within `PromptCatalog.java` and `DailyWordsService.java`. No Flutter changes, no migration, no API contract changes. They can ship immediately and the improvement will be visible to users on the next daily content generation cycle.

---

## 8. Status Update (2026-07-09): Per-L1 interference-awareness shipped

Section 1.1's "No Turkish-specific interference awareness" row and section 6's
Phase 3 item 3 both described this as unshipped. As of 2026-07-09, static,
hand-curated transfer-error notes exist in
[`PromptCatalog.interferenceNotesFor(String)`](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java)
for all 6 non-English source languages (Turkish, Spanish, Portuguese,
Indonesian, German, French) — not just Turkish, since the feature had never
actually been implemented for Turkish either despite the diagnosis table
implying it should exist.

Deliberately scoped to `checkEnglishTranslation` only (the flow where a
learner writes English starting from their native language — the direction
where L1-to-English transfer errors actually surface). `checkTranslation`
(writing in the learner's own language) does not receive this block, since
transfer-error patterns run the other direction. This is backend-logic data
(zero AI tokens, zero extra latency) injected as a labeled block into the
existing `checkEnglishTranslation` system prompt, per this doc's own §1.3
guidance ("Turkish interference awareness | ✅ In prompt | ❌" — i.e. prompt
content, not backend logic).

Not done at the time: `PromptContextService` extraction, Redis-backed
sentence-starter tracking, `prompt_audit` table, and the weekly quality cron
(Phase 2/3 remainder) were all still unimplemented.

---

## 9. Status Update (2026-07-09): Conversation memory/phases confirmed shipped; sentence-starter tracking added

A follow-up audit found §1.1's "No conversation memory" row and §1.1's "Fixed
speaking persona" row were both stale — conversation history (Redis-backed,
last 6 messages via `ConversationSessionService`), 4-phase conversation
tracking (`ConversationPhase`: OPENING/DEEPENING/CHALLENGE/WINDING), and
5-persona rotation were all shipped 2026-07-07, before this doc's own §8 was
written. Nothing further needed there.

Also shipped this session: **Redis-backed per-user sentence-starter
tracking** (§7 Phase 2 item 2, "recentSentencePatterns" from §1.2's data
table) via
[`SentenceStarterTrackingService`](file:///c:/flutter-project-main/backend/src/main/java/com/ingilizce/calismaapp/service/SentenceStarterTrackingService.java),
mirroring `ConversationSessionService`'s exact Redis pattern (degrade-safe,
24h TTL, last 10 starters as context). Wired into
`ChatbotController.generateSentences()`: injects "avoid starting with these
words" into the prompt when a user has history, and records the actual
starter words shown after every successful generation — including
cache-served responses, since the shared sentence cache means the same
learner could otherwise see the same starter word repeatedly across days
even without a fresh AI call.

Still not done: `PromptContextService` extraction (an organizational
refactor, not a behavior gap — history/phase/starter-tracking logic already
lives correctly in their respective services), `prompt_audit` table, weekly
quality cron, and A/B test framework (Phase 3).

---

## 10. Status Update (2026-07-09): Writing-topic day-to-day diversity fixed

§1.1's last unaddressed diagnosis row, "`System.currentTimeMillis()` as only
seed," is now fixed. Checked the actual call path first:
`DailyWritingTopicService` caches one writing topic per (date, level)
globally in `daily_content`, so the AI is only ever called once per day per
CEFR level — the practical problem was always day-to-day variety, not
per-request repetition, the same shape as the already-fixed daily-words gap.

`AiProxyService.generateWritingTopic()` now takes the content date's
day-of-year and reuses the existing `PromptCatalog.topicForDay(dayOfYear)`
rotating taxonomy (the same one daily words already use) to give the model
a concrete category instead of an opaque timestamp. The model still invents
the specific topic within that category, so within-category creative
variety is untouched — only the previously-nonexistent day-to-day category
drift is now real.

Deliberately left `generateExamBundle()`'s similar seed alone: exam
questions already receive an explicit `category` param from the caller, so
that seed is legitimately just an anti-repeat nonce, not the sole diversity
signal — a different bug shape, and TR-exam content is lower priority per
the strategy review's own market-order guidance.

With this, every row in §1.1's original diagnosis table now has a shipped
fix. Remaining open work across all three phases is exclusively Phase 3:
`PromptContextService` extraction, `prompt_audit` table, weekly quality
cron, A/B test framework — none of which are behavior gaps, and the
strategy review itself flags A/B testing as "overengineering right now"
before there's real user volume to test against.
