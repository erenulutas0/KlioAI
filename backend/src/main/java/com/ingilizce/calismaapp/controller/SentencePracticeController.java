package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.SentencePractice;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.service.SentencePracticeService;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.ArrayList;
import java.util.Map;
import java.util.HashMap;

@RestController
@RequestMapping("/api/sentences")
public class SentencePracticeController {
    private static final Logger log = LoggerFactory.getLogger(SentencePracticeController.class);

    @Autowired
    private SentencePracticeService sentencePracticeService;

    @Autowired
    private SentenceRepository sentenceRepository;

    // Get all sentences from both tables (User Scoped)
    @GetMapping
    public ResponseEntity<List<Map<String, Object>>> getAllSentences(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.min(Math.max(size, 1), 200);
        List<Map<String, Object>> allSentences = new ArrayList<>();

        // Get sentences from sentence_practices table
        List<SentencePractice> practiceSentences = sentencePracticeService
                .getPracticeSentencesPage(userId, normalizedPage, normalizedSize)
                .getContent();
        log.debug("Found {} practice sentences for user {}", practiceSentences.size(), userId);
        for (SentencePractice sp : practiceSentences) {
            Map<String, Object> sentenceMap = new HashMap<>();
            sentenceMap.put("id", "practice_" + sp.getId());
            sentenceMap.put("englishSentence", sp.getEnglishSentence());
            sentenceMap.put("turkishTranslation", sp.getTurkishTranslation());
            sentenceMap.put("sourceTranslation", sp.getTurkishTranslation());
            sentenceMap.put("sourceFullTranslation", sp.getTurkishTranslation());
            sentenceMap.put("difficulty", sp.getDifficulty());
            sentenceMap.put("createdDate", sp.getCreatedDate());
            sentenceMap.put("source", "practice");
            allSentences.add(sentenceMap);
        }

        // Get sentences from sentences table with word information
        List<Sentence> wordSentences = sentenceRepository
                .findAllWithWordByUserId(userId, PageRequest.of(normalizedPage, normalizedSize))
                .getContent();
        log.debug("Found {} word sentences for user {}", wordSentences.size(), userId);
        for (Sentence s : wordSentences) {
            Map<String, Object> sentenceMap = new HashMap<>();
            sentenceMap.put("id", "word_" + s.getId());
            sentenceMap.put("englishSentence", s.getSentence());
            sentenceMap.put("turkishTranslation", s.getTranslation());
            sentenceMap.put("sourceTranslation", s.getTranslation());
            sentenceMap.put("sourceFullTranslation", s.getTranslation());
            String difficulty = s.getDifficulty();
            if (difficulty == null || difficulty.trim().isEmpty()) {
                difficulty = "easy";
            } else {
                difficulty = difficulty.toLowerCase();
            }
            sentenceMap.put("difficulty", difficulty);
            sentenceMap.put("createdDate", s.getWord() != null ? s.getWord().getLearnedDate() : null);
            sentenceMap.put("source", "word");
            // Add word information
            if (s.getWord() != null) {
                sentenceMap.put("word", s.getWord().getEnglishWord());
                sentenceMap.put("wordTranslation", s.getWord().getTurkishMeaning());
                sentenceMap.put("sourceWordTranslation", s.getWord().getTurkishMeaning());
            }
            allSentences.add(sentenceMap);
        }

        return ResponseEntity.ok(allSentences);
    }

    @GetMapping("/practice/paged")
    public ResponseEntity<Page<SentencePractice>> getPracticeSentencesPaged(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.min(Math.max(size, 1), 200);
        return ResponseEntity.ok(
                sentencePracticeService.getPracticeSentencesPage(userId, normalizedPage,
                        normalizedSize));
    }

    @GetMapping("/{id}")
    public ResponseEntity<SentencePractice> getSentenceById(@PathVariable Long id,
            @RequestHeader("X-User-Id") Long userId) {
        Optional<SentencePractice> sentence = sentencePracticeService.getSentenceByIdAndUser(id,
                userId);
        return sentence.map(ResponseEntity::ok).orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<SentencePractice> createSentence(@RequestBody SentencePractice sentencePractice,
            @RequestHeader("X-User-Id") Long userId) {
        sentencePractice.setUserId(userId);
        SentencePractice savedSentence = sentencePracticeService.saveSentence(sentencePractice);
        return ResponseEntity.ok(savedSentence);
    }

    @PutMapping("/{id}")
    public ResponseEntity<SentencePractice> updateSentence(@PathVariable Long id,
            @RequestBody SentencePractice sentencePractice,
            @RequestHeader("X-User-Id") Long userId) {
        SentencePractice updatedSentence = sentencePracticeService.updateSentence(id, sentencePractice,
                userId);
        if (updatedSentence != null) {
            return ResponseEntity.ok(updatedSentence);
        }
        return ResponseEntity.notFound().build();
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteSentence(@PathVariable String id,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            if (id.startsWith("practice_")) {
                Long numericId = Long.parseLong(id.substring(9));
                boolean deleted = sentencePracticeService.deleteSentence(numericId, userId);
                if (deleted) {
                    return ResponseEntity.ok().build();
                }
                return ResponseEntity.notFound().build();
            } else if (id.startsWith("word_")) {
                Long sentenceId = Long.parseLong(id.substring(5));
                Optional<Sentence> sentence = sentenceRepository.findByIdAndWordUserId(sentenceId, userId);
                if (sentence.isEmpty()) {
                    return ResponseEntity.notFound().build();
                }
                sentenceRepository.delete(sentence.get());
                return ResponseEntity.ok().build();
            } else {
                Long numericId = Long.parseLong(id);
                boolean deleted = sentencePracticeService.deleteSentence(numericId, userId);
                if (deleted) {
                    return ResponseEntity.ok().build();
                }
                return ResponseEntity.notFound().build();
            }
        } catch (NumberFormatException e) {
            return ResponseEntity.badRequest().build();
        } catch (Exception e) {
            log.error("Sentence delete failed for id={} userId={}: {}", id, userId, e.getMessage());
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/difficulty/{difficulty}")
    public ResponseEntity<List<SentencePractice>> getSentencesByDifficulty(@PathVariable String difficulty,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            SentencePractice.DifficultyLevel difficultyLevel = SentencePractice.DifficultyLevel
                    .valueOf(difficulty.toUpperCase(java.util.Locale.ROOT));
            List<SentencePractice> sentences = sentencePracticeService.getSentencesByDifficulty(userId,
                    difficultyLevel);
            return ResponseEntity.ok(sentences);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/date/{date}")
    public ResponseEntity<List<SentencePractice>> getSentencesByDate(@PathVariable String date,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            LocalDate localDate = LocalDate.parse(date);
            List<SentencePractice> sentences = sentencePracticeService.getSentencesByDate(userId,
                    localDate);
            return ResponseEntity.ok(sentences);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/dates")
    public ResponseEntity<List<LocalDate>> getAllDistinctDates(
            @RequestHeader("X-User-Id") Long userId) {
        List<LocalDate> dates = sentencePracticeService.getAllDistinctDates(userId);
        return ResponseEntity.ok(dates);
    }

    @GetMapping("/date-range")
    public ResponseEntity<List<SentencePractice>> getSentencesByDateRange(
            @RequestParam String startDate,
            @RequestParam String endDate,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            LocalDate start = LocalDate.parse(startDate);
            LocalDate end = LocalDate.parse(endDate);
            List<SentencePractice> sentences = sentencePracticeService.getSentencesByDateRange(userId,
                    start, end);
            return ResponseEntity.ok(sentences);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/stats")
    public ResponseEntity<Object> getStatistics(
            @RequestHeader("X-User-Id") Long userId) {

        // Count from sentence_practices table
        long practiceTotal = sentencePracticeService.getTotalSentenceCount(userId);
        long practiceEasy = sentencePracticeService.getSentenceCountByDifficulty(userId,
                SentencePractice.DifficultyLevel.EASY);
        long practiceMedium = sentencePracticeService.getSentenceCountByDifficulty(userId,
                SentencePractice.DifficultyLevel.MEDIUM);
        long practiceHard = sentencePracticeService.getSentenceCountByDifficulty(userId,
                SentencePractice.DifficultyLevel.HARD);

        // Count from sentences table with actual difficulty
        long wordTotal = sentenceRepository.countByUserId(userId);
        long wordEasy = sentenceRepository.countByDifficultyAndUserId("easy", userId);
        long wordMedium = sentenceRepository.countByDifficultyAndUserId("medium", userId);
        long wordHard = sentenceRepository.countByDifficultyAndUserId("hard", userId);

        long totalCount = practiceTotal + wordTotal;
        long easyCount = practiceEasy + wordEasy;
        long mediumCount = practiceMedium + wordMedium;
        long hardCount = practiceHard + wordHard;

        return ResponseEntity.ok(new Object() {
            public final long total = totalCount;
            public final long easy = easyCount;
            public final long medium = mediumCount;
            public final long hard = hardCount;
        });
    }
}
