package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.dto.CreateWordRequest;
import com.ingilizce.calismaapp.service.WordService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.Map;

@RestController
@RequestMapping("/api/words")
public class WordController {

    @Autowired
    private WordService wordService;

    @GetMapping
    public List<Word> getAllWords(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.min(Math.max(size, 1), 200);
        return wordService.getWordsPage(userId, normalizedPage, normalizedSize).getContent();
    }

    @GetMapping("/paged")
    public ResponseEntity<Page<Word>> getWordsPage(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.min(Math.max(size, 1), 200);
        return ResponseEntity.ok(wordService.getWordsPage(userId, normalizedPage, normalizedSize));
    }

    @GetMapping("/{id}")
    public ResponseEntity<Word> getWordById(@PathVariable Long id,
            @RequestHeader("X-User-Id") Long userId) {
        Optional<Word> word = wordService.getWordByIdAndUserWithSentences(id, userId);
        return word.map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/{id}/sentences")
    public ResponseEntity<List<com.ingilizce.calismaapp.entity.Sentence>> getWordSentences(@PathVariable Long id,
            @RequestHeader("X-User-Id") Long userId) {
        Optional<Word> word = wordService.getWordByIdAndUserWithSentences(id, userId);
        if (word.isPresent()) {
            return ResponseEntity.ok(word.get().getSentences());
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/date/{date}")
    public List<Word> getWordsByDate(@PathVariable @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestHeader("X-User-Id") Long userId) {
        return wordService.getWordsByDate(userId, date);
    }

    @GetMapping("/dates")
    public List<LocalDate> getAllDistinctDates(
            @RequestHeader("X-User-Id") Long userId) {
        return wordService.getAllDistinctDates(userId);
    }

    @GetMapping("/range")
    public List<Word> getWordsByDateRange(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
            @RequestHeader("X-User-Id") Long userId) {
        return wordService.getWordsByDateRange(userId, startDate, endDate);
    }

    @PostMapping
    public Word createWord(@RequestBody Word word,
            @RequestHeader("X-User-Id") Long userId) {
        word.setUserId(userId);
        return wordService.saveWord(word);
    }

    @PutMapping("/{id}")
    public ResponseEntity<Word> updateWord(@PathVariable Long id, @RequestBody Word wordDetails,
            @RequestHeader("X-User-Id") Long userId) {
        Word updatedWord = wordService.updateWord(id, wordDetails, userId);
        if (updatedWord != null) {
            return ResponseEntity.ok(updatedWord);
        }
        return ResponseEntity.notFound().build();
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteWord(@PathVariable Long id,
            @RequestHeader("X-User-Id") Long userId) {
        wordService.deleteWord(id, userId);
        return ResponseEntity.ok().build();
    }

    // Sentence management endpoints
    @PostMapping("/{wordId}/sentences")
    public ResponseEntity<Word> addSentence(@PathVariable Long wordId, @RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId) {
        String sentence = request.get("sentence");
        String translation = request.get("translation");
        String difficulty = request.get("difficulty");

        Word updatedWord = wordService.addSentence(wordId, sentence, translation, difficulty, userId);
        if (updatedWord != null) {
            return ResponseEntity.ok(updatedWord);
        }
        return ResponseEntity.notFound().build();
    }

    @DeleteMapping("/{wordId}/sentences/{sentenceId}")
    public ResponseEntity<Word> deleteSentence(@PathVariable Long wordId, @PathVariable Long sentenceId,
            @RequestHeader("X-User-Id") Long userId) {
        Word updatedWord = wordService.deleteSentence(wordId, sentenceId, userId);
        if (updatedWord != null) {
            return ResponseEntity.ok(updatedWord);
        }
        return ResponseEntity.notFound().build();
    }
}
