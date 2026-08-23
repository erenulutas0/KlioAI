package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.dto.CreateWordRequest;
import com.ingilizce.calismaapp.service.WordService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.Map;

@RestController
@RequestMapping("/api/words")
public class WordController {

    @Autowired
    private WordService wordService;

    // languageProfileId is optional and new (V028): omitted, the active profile's words are
    // returned, which is what the shipped client gets without knowing profiles exist.
    @GetMapping
    public List<Word> getAllWords(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size,
            @RequestParam(required = false) Long languageProfileId) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.min(Math.max(size, 1), 200);
        if (languageProfileId == null) {
            return wordService.getWordsPage(userId, normalizedPage, normalizedSize).getContent();
        }
        return wordService.getWordsPage(userId, languageProfileId, normalizedPage, normalizedSize).getContent();
    }

    @GetMapping("/paged")
    public ResponseEntity<Page<Word>> getWordsPage(
            @RequestHeader("X-User-Id") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(required = false) Long languageProfileId) {
        int normalizedPage = Math.max(page, 0);
        int normalizedSize = Math.min(Math.max(size, 1), 200);
        if (languageProfileId == null) {
            return ResponseEntity.ok(wordService.getWordsPage(userId, normalizedPage, normalizedSize));
        }
        return ResponseEntity.ok(wordService.getWordsPage(userId, languageProfileId, normalizedPage, normalizedSize));
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
        // POST creates. The body binds straight into the entity, so an "id" in it would turn
        // saveWord into a merge over whatever row carries that id -- any user's -- replacing
        // its owner, wiping its meanings (past the last-meaning guard) and detaching it from
        // its profile. The shipped client never sends one; nothing legitimate does.
        word.setId(null);
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
    public ResponseEntity<Word> addSentence(@PathVariable Long wordId, @RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId) {
        String sentence = stringValue(request.get("sentence"));
        String translation = firstNonBlank(
                stringValue(request.get("sourceTranslation")),
                stringValue(request.get("translation")),
                stringValue(request.get("turkishTranslation")));
        String difficulty = stringValue(request.get("difficulty"));
        // Optional and new (V028): the shipped client never sends it, so its sentences stay
        // unassigned. A value that is not one of the word's meanings is a 400.
        Long meaningId = longValue(request.get("meaningId"));

        Word updatedWord = wordService.addSentence(wordId, sentence, translation, difficulty, userId, meaningId);
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

    // Meaning management endpoints (V028)
    @PostMapping("/{wordId}/meanings")
    public ResponseEntity<?> addMeaning(@PathVariable Long wordId, @RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            Word updatedWord = wordService.addMeaning(wordId, userId,
                    stringValue(request.get("translation")),
                    stringValue(request.get("definition")));
            return ResponseEntity.status(HttpStatus.CREATED).body(updatedWord);
        } catch (NoSuchElementException ex) {
            return ResponseEntity.notFound().build();
        }
    }

    @PutMapping("/{wordId}/meanings/{meaningId}")
    public ResponseEntity<?> updateMeaning(@PathVariable Long wordId, @PathVariable Long meaningId,
            @RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            Word updatedWord = wordService.updateMeaning(wordId, meaningId, userId,
                    stringValue(request.get("translation")),
                    stringValue(request.get("definition")));
            return ResponseEntity.ok(updatedWord);
        } catch (NoSuchElementException ex) {
            return ResponseEntity.notFound().build();
        }
    }

    @DeleteMapping("/{wordId}/meanings/{meaningId}")
    public ResponseEntity<?> deleteMeaning(@PathVariable Long wordId, @PathVariable Long meaningId,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            return ResponseEntity.ok(wordService.deleteMeaning(wordId, meaningId, userId));
        } catch (NoSuchElementException ex) {
            return ResponseEntity.notFound().build();
        } catch (WordService.LastMeaningException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
        }
    }

    private String stringValue(Object value) {
        return value == null ? null : value.toString();
    }

    private Long longValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number number) {
            return number.longValue();
        }
        String text = value.toString().trim();
        if (text.isEmpty()) {
            return null;
        }
        try {
            return Long.valueOf(text);
        } catch (NumberFormatException ex) {
            throw new IllegalArgumentException("meaningId must be a number");
        }
    }

    private String firstNonBlank(String... values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value;
            }
        }
        return null;
    }
}
