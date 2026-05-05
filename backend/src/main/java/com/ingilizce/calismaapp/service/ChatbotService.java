package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashMap;

@Service
public class ChatbotService {

  private static final Logger logger = LoggerFactory.getLogger(ChatbotService.class);
  private final AiCompletionProvider aiCompletionProvider;
  private final ObjectMapper objectMapper;
  @Autowired(required = false)
  private AiModelRoutingService aiModelRoutingService;

  public ChatbotService(AiCompletionProvider aiCompletionProvider) {
    this.aiCompletionProvider = aiCompletionProvider;
    this.objectMapper = new ObjectMapper();
  }

  public record AiCallResult(String content, int totalTokens, int promptTokens, int completionTokens) {
  }

  /**
   * Cümle üretme servisi - UNIVERSAL MODE
   */
  public AiCallResult generateSentences(String message) {
    PromptCatalog.PromptDef def = PromptCatalog.generateSentences();
    return callGroq(def, message);
  }

  /**
   * Çeviri kontrolü servisi
   */
  public AiCallResult checkTranslation(String message) {
    PromptCatalog.PromptDef def = PromptCatalog.checkTranslation();
    return callGroq(def, message);
  }

  /**
   * İngilizce Çeviri kontrolü servisi (TR -> EN)
   */
  public AiCallResult checkEnglishTranslation(String message) {
    PromptCatalog.PromptDef def = PromptCatalog.checkEnglishTranslation();
    return callGroq(def, message);
  }

  /**
   * İngilizce sohbet pratiği servisi - Buddy Mode
   */
  public AiCallResult chat(String message) {
    return chat(message, null, null);
  }

  /**
   * İngilizce sohbet pratiği servisi - Buddy Mode + optional scenario prompts (Flutter parity).
   */
  public AiCallResult chat(String message, String scenario, String scenarioContext) {
    String systemPrompt = buildChatSystemPrompt(scenario, scenarioContext);
    return callGroqText(systemPrompt, message, 220, "chat");
  }

  /**
   * IELTS/TOEFL Speaking test soruları üretme servisi
   */
  public AiCallResult generateSpeakingTestQuestions(String message) {
    PromptCatalog.PromptDef def = PromptCatalog.generateSpeakingTestQuestions();
    return callGroq(def, "Generate " + message + ". Return ONLY JSON.");
  }

  /**
   * IELTS/TOEFL Speaking test puanlama servisi
   */
  public AiCallResult evaluateSpeakingTest(String message) {
    PromptCatalog.PromptDef def = PromptCatalog.evaluateSpeakingTest();
    return callGroq(def, message + " Return ONLY JSON.");
  }

  private AiCallResult callGroq(PromptCatalog.PromptDef def, String userMessage) {
    List<Map<String, String>> messages = new ArrayList<>();

    Map<String, String> systemMsg = new HashMap<>();
    systemMsg.put("role", "system");
    systemMsg.put("content", def.systemPrompt() + "\n\nPROMPT_VERSION: " + def.version());
    messages.add(systemMsg);

    Map<String, String> userMsg = new HashMap<>();
    userMsg.put("role", "user");
    userMsg.put("content", userMessage);
    messages.add(userMsg);

    logger.info("Prompt {} v{}", def.id(), def.version());
    boolean jsonMode = def.output() == PromptCatalog.PromptOutput.JSON_OBJECT;

    Integer maxTokens = null;
    String scope = "chat";
    if ("chat_buddy".equals(def.id())) {
      maxTokens = 220;
      scope = "chat";
    } else if ("generate_sentences".equals(def.id())) {
      maxTokens = 900;
      scope = "generate-sentences";
    } else if ("check_translation_tr".equals(def.id()) || "check_translation_en".equals(def.id())) {
      maxTokens = 500;
      scope = "check-translation";
    } else if ("speaking_questions".equals(def.id())) {
      maxTokens = 600;
      scope = "speaking-generate";
    } else if ("speaking_evaluation".equals(def.id())) {
      maxTokens = 900;
      scope = "speaking-evaluate";
    }

    AiCompletionProvider.CompletionResult completion = aiCompletionProvider.chatCompletionWithUsage(
        messages,
        jsonMode,
        maxTokens,
        null,
        resolveModelForScope(scope));
    String raw = completion != null ? completion.content() : null;
    String normalized = normalizeJson(raw, def.output());
    return new AiCallResult(
        normalized,
        completion != null ? completion.totalTokens() : 0,
        completion != null ? completion.promptTokens() : 0,
        completion != null ? completion.completionTokens() : 0);
  }

  private AiCallResult callGroqText(String systemPrompt, String userMessage, Integer maxTokens, String scope) {
    List<Map<String, String>> messages = new ArrayList<>();

    Map<String, String> systemMsg = new HashMap<>();
    systemMsg.put("role", "system");
    systemMsg.put("content", systemPrompt);
    messages.add(systemMsg);

    Map<String, String> userMsg = new HashMap<>();
    userMsg.put("role", "user");
    userMsg.put("content", userMessage);
    messages.add(userMsg);

    AiCompletionProvider.CompletionResult completion = aiCompletionProvider.chatCompletionWithUsage(
        messages,
        false,
        maxTokens,
        null,
        resolveModelForScope(scope));
    return new AiCallResult(
        completion != null ? completion.content() : null,
        completion != null ? completion.totalTokens() : 0,
        completion != null ? completion.promptTokens() : 0,
        completion != null ? completion.completionTokens() : 0);
  }

  private String buildChatSystemPrompt(String scenario, String scenarioContext) {
    String contextStr = (scenarioContext != null && !scenarioContext.trim().isEmpty())
        ? "SPECIFIC CONTEXT FOR THIS CONVERSATION: " + scenarioContext.trim()
        : "";

    if ("job_interview_followup".equals(scenario)) {
      return """
You are Sarah, an HR Manager at a tech company. The user just had a job interview with you yesterday and is now following up.
%s

SCENARIO RULES:
- Act professional but friendly like a real HR manager
- Ask clarifying questions about their qualifications for the position
- Discuss next steps, timeline, salary expectations naturally
- Give realistic feedback and make them practice professional communication
- Keep responses to 2-3 sentences, ask follow-up questions

CONTEXT: The interview went reasonably well. Be encouraging but professional.
""".formatted(contextStr);
    }

    if ("academic_presentation_qa".equals(scenario)) {
      return """
You are Dr. Johnson, a professor attending an academic presentation. The user just finished presenting their research/project.
%s

SCENARIO RULES:
- Ask challenging but fair academic questions based on their topic
- Challenge their methodology, conclusions, or data
- Be skeptical but respectful like a real professor
- Push them to defend their work with evidence
- Keep responses to 2-3 sentences, always ask probing questions

EXAMPLE QUESTIONS:
- "Interesting approach, but have you considered the limitations of..."
- "How would you respond to criticism that..."
- "What evidence supports your conclusion that..."
""".formatted(contextStr);
    }

    if ("disagreement_colleague".equals(scenario)) {
      return """
You are Alex, a colleague who has a different opinion on a work project. There's a professional disagreement that needs to be resolved.
%s

SCENARIO RULES:
- Disagree respectfully but firmly with the user's view
- Push back on their points while staying professional
- Make them practice diplomatic language
- Don't give in easily - make them convince you
- Keep responses to 2-3 sentences

CONTEXT: You believe the project should go in a different direction or have a different approach. Help them practice handling workplace conflict professionally.

EXAMPLE RESPONSES:
- "I see your point, but I still think..."
- "That's one way to look at it, however..."
- "I understand, but what about the risks of..."
""".formatted(contextStr);
    }

    if ("explaining_to_manager".equals(scenario)) {
      return """
You are Michael, a busy senior manager. The user needs to explain a decision, mistake, or request to you.
%s

SCENARIO RULES:
- Be professional but slightly impatient (you're busy)
- Ask pointed questions about ROI, timeline, resources
- Challenge vague explanations - ask for specifics regarding the context
- Make them practice clear, concise professional communication
- Keep responses to 2-3 sentences

CONTEXT: You're a results-oriented manager who values clear, direct communication.

EXAMPLE RESPONSES:
- "I only have a few minutes. What's the bottom line?"
- "What's the timeline and budget impact?"
- "Who approved this decision?"
""".formatted(contextStr);
    }

    // Default: normal chat mode.
    return """
You are Amy, a warm and friendly American chat buddy.

RESPONSE RULES:
- Keep responses to 2-3 SHORT sentences MAX.
- Be warm and show you care, but stay concise.
- Always end with ONE simple question to keep chatting.
- Use casual language: contractions, fillers like "Oh!", "Hmm", "You know".

IMPORTANT:
- NO long paragraphs. Keep it SHORT.
- Sound like a real friend texting, not an AI assistant.
- If user makes grammar mistakes, just respond naturally.
""";
  }

  private String resolveModelForScope(String scope) {
    if (aiModelRoutingService == null) {
      return null;
    }
    return aiModelRoutingService.resolveModelForScope(scope);
  }

  private String normalizeJson(String raw, PromptCatalog.PromptOutput output) {
    if (raw == null || output == PromptCatalog.PromptOutput.TEXT) {
      return raw;
    }

    String cleaned = raw.trim()
        .replaceAll("```json", "")
        .replaceAll("```", "")
        .trim();

    int objStart = cleaned.indexOf('{');
    int objEnd = cleaned.lastIndexOf('}');
    int arrStart = cleaned.indexOf('[');
    int arrEnd = cleaned.lastIndexOf(']');

    if (arrStart >= 0 && arrEnd > arrStart && (objStart < 0 || arrStart < objStart)) {
      cleaned = cleaned.substring(arrStart, arrEnd + 1).trim();
    } else if (objStart >= 0 && objEnd > objStart) {
      cleaned = cleaned.substring(objStart, objEnd + 1).trim();
    }

    try {
      Object parsed = objectMapper.readValue(cleaned, Object.class);
      if (output == PromptCatalog.PromptOutput.JSON_OBJECT && !(parsed instanceof Map)) {
        throw new IllegalArgumentException("Expected JSON object");
      }
      if (output == PromptCatalog.PromptOutput.JSON_ARRAY) {
        if (parsed instanceof List) {
          return cleaned;
        }
        if (parsed instanceof Map map && map.containsKey("sentences") && map.get("sentences") instanceof List) {
          return cleaned;
        }
        throw new IllegalArgumentException("Expected JSON array (or object with sentences list)");
      }
      return cleaned;
    } catch (Exception ex) {
      logger.warn("AI JSON validation failed for output type {}. Returning raw response.", output, ex);
      return raw;
    }
  }
}
