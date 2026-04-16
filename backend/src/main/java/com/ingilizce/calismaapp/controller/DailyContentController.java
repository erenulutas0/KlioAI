package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.DailyExamPackService;
import com.ingilizce.calismaapp.service.DailyLevelSupport;
import com.ingilizce.calismaapp.service.DailyReadingService;
import com.ingilizce.calismaapp.service.DailyWritingTopicService;
import com.ingilizce.calismaapp.service.DailyWordsService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.repository.UserRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RequestHeader;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/content")
public class DailyContentController {

    private final DailyWordsService dailyWordsService;
    private final DailyExamPackService dailyExamPackService;
    private final DailyReadingService dailyReadingService;
    private final DailyWritingTopicService dailyWritingTopicService;
    private final AiTokenQuotaService aiTokenQuotaService;
    private final UserRepository userRepository;

    public DailyContentController(DailyWordsService dailyWordsService,
                                  DailyExamPackService dailyExamPackService,
                                  DailyReadingService dailyReadingService,
                                  DailyWritingTopicService dailyWritingTopicService,
                                  AiTokenQuotaService aiTokenQuotaService,
                                  UserRepository userRepository) {
        this.dailyWordsService = dailyWordsService;
        this.dailyExamPackService = dailyExamPackService;
        this.dailyReadingService = dailyReadingService;
        this.dailyWritingTopicService = dailyWritingTopicService;
        this.aiTokenQuotaService = aiTokenQuotaService;
        this.userRepository = userRepository;
    }

    @GetMapping("/daily-words")
    public ResponseEntity<Map<String, Object>> getDailyWords() {
        var words = dailyWordsService.getDailyWords(LocalDate.now(ZoneOffset.UTC));
        return ResponseEntity.ok(Map.of(
                "success", true,
                "words", words
        ));
    }

    @GetMapping("/daily-exam-pack")
    public ResponseEntity<Map<String, Object>> getDailyExamPack(
            @RequestParam(name = "exam", required = false, defaultValue = "yds") String exam) {
        var payload = dailyExamPackService.getDailyExamPack(LocalDate.now(ZoneOffset.UTC), exam);
        return ResponseEntity.ok(Map.of(
                "success", true,
                "data", payload
        ));
    }

    @GetMapping("/daily-reading")
    public ResponseEntity<Map<String, Object>> getDailyReading(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(name = "level", required = false, defaultValue = "B1") String level) {
        ResponseEntity<Map<String, Object>> blocked = enforceAiDailyAccess(userId);
        if (blocked != null) {
            return blocked;
        }

        String normalizedLevel = DailyLevelSupport.normalizeLevel(level);
        Map<String, Object> payload = dailyReadingService.getDailyReading(LocalDate.now(ZoneOffset.UTC), normalizedLevel);
        return ResponseEntity.ok(Map.of(
                "success", true,
                "level", normalizedLevel,
                "data", payload
        ));
    }

    @GetMapping("/daily-writing-topic")
    public ResponseEntity<Map<String, Object>> getDailyWritingTopic(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(name = "level", required = false, defaultValue = "B1") String level) {
        ResponseEntity<Map<String, Object>> blocked = enforceAiDailyAccess(userId);
        if (blocked != null) {
            return blocked;
        }

        String normalizedLevel = DailyLevelSupport.normalizeLevel(level);
        Map<String, Object> payload = dailyWritingTopicService.getDailyWritingTopic(LocalDate.now(ZoneOffset.UTC), normalizedLevel);
        return ResponseEntity.ok(Map.of(
                "success", true,
                "level", normalizedLevel,
                "data", payload
        ));
    }

    private ResponseEntity<Map<String, Object>> enforceAiDailyAccess(Long userId) {
        if (userId == null || userId <= 0) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("success", false, "error", "Invalid user context"));
        }

        if (aiTokenQuotaService == null) {
            boolean active = userRepository.findById(userId)
                    .map(com.ingilizce.calismaapp.entity.User::isSubscriptionActive)
                    .orElse(false);
            if (active) {
                return null;
            }
            return buildUpgradeRequiredResponse();
        }

        AiTokenQuotaService.Entitlement entitlement = aiTokenQuotaService.getEntitlement(userId);
        if (entitlement != null && entitlement.aiAccessEnabled()) {
            return null;
        }

        boolean active = userRepository.findById(userId)
                .map(com.ingilizce.calismaapp.entity.User::isSubscriptionActive)
                .orElse(false);
        if (active) {
            return null;
        }

        return buildUpgradeRequiredResponse();
    }

    private ResponseEntity<Map<String, Object>> buildUpgradeRequiredResponse() {
        Map<String, Object> payload = new HashMap<>();
        payload.put("success", false);
        payload.put("reason", "ai-access-disabled");
        payload.put("upgradeRequired", true);
        payload.put("error", "AI ozellikleri su an pasif. Devam etmek icin premium plana gecin.");
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(payload);
    }
}
