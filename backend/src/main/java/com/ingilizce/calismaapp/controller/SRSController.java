package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.service.SRSService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * REST Controller for Spaced Repetition System (SRS)
 */
@RestController
@RequestMapping("/api/srs")
public class SRSController {

    @Autowired
    private SRSService srsService;

    /**
     * Get words that need review today
     * 
     * @return List of words to review
     */
    @GetMapping("/review-words")
    public ResponseEntity<List<Word>> getReviewWords(@RequestHeader("X-User-Id") Long userId) {
        try {
            List<Word> words = srsService.getWordsForReview(userId);
            return ResponseEntity.ok(words);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    /**
     * Submit a review result
     * 
     * @param request Map containing wordId and quality
     * @return Updated word
     * 
     *         Example request:
     *         {
     *         "wordId": 123,
     *         "quality": 4
     *         }
     */
    /** A malformed timing value is dropped rather than failing the review it accompanies. */
    private static Integer parseOptionalInt(Object value) {
        if (value == null) {
            return null;
        }
        try {
            int parsed = Integer.parseInt(value.toString().trim());
            return parsed >= 0 ? parsed : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    @PostMapping("/submit-review")
    public ResponseEntity<Word> submitReview(@RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, Object> request) {
        try {
            Long wordId = Long.valueOf(request.get("wordId").toString());
            int quality = Integer.parseInt(request.get("quality").toString());

            // Optional, and optional on purpose: an older client that sends neither still
            // logs a usable row. Refusing the review because it did not name its surface
            // would trade the learner's progress for a tidier analytics column.
            String source = request.get("source") == null
                    ? null
                    : request.get("source").toString();
            Integer responseMs = parseOptionalInt(request.get("responseMs"));

            Word updatedWord = srsService.submitReview(userId, wordId, quality, source, responseMs);
            return ResponseEntity.ok(updatedWord);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().build();
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    /**
     * Get SRS statistics
     * 
     * @return Statistics map
     * 
     *         Example response:
     *         {
     *         "dueToday": 5,
     *         "totalWords": 100,
     *         "reviewedWords": 80
     *         }
     */
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats(@RequestHeader("X-User-Id") Long userId) {
        try {
            Map<String, Object> stats = srsService.getStats(userId);
            return ResponseEntity.ok(stats);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }
}
