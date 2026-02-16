package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.dto.CreateWordRequest;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Objects;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@Transactional
public class WordService {
    private static final int XP_NEW_WORD = 10;
    private static final int XP_NEW_WORD_SENTENCE = 5;

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private SentenceRepository sentenceRepository;

    @Autowired
    private LeaderboardService leaderboardService;

    @Autowired
    private ProgressService progressService;

    @Autowired
    private ActivityPublisher activityPublisher;

    public List<Word> getAllWords(Long userId) {
        List<Word> words = wordRepository.findByUserId(userId);
        hydrateSentencesForWords(words);
        return words;
    }

    public Page<Word> getWordsPage(Long userId, int page, int size) {
        Page<Word> wordsPage = wordRepository.findByUserId(userId, PageRequest.of(page, size));
        hydrateSentencesForWords(wordsPage.getContent());
        return wordsPage;
    }

    public List<Word> getWordsByDate(Long userId, LocalDate date) {
        List<Word> words = wordRepository.findByUserIdAndLearnedDate(userId, date);
        hydrateSentencesForWords(words);
        return words;
    }

    public List<Word> getWordsByDateRange(Long userId, LocalDate startDate, LocalDate endDate) {
        List<Word> words = wordRepository.findByUserIdAndDateRange(userId, startDate, endDate);
        hydrateSentencesForWords(words);
        return words;
    }

    public List<LocalDate> getAllDistinctDates(Long userId) {
        return wordRepository.findDistinctDatesByUserId(userId);
    }

    @Transactional
    public Word saveWord(Word word) {
        Objects.requireNonNull(word, "word must not be null");
        if (word.getUserId() == null) {
            throw new IllegalArgumentException("word.userId is required");
        }

        boolean isNew = (word.getId() == null);

        // Idempotency: if same word already exists for user, return it without side effects
        if (isNew && word.getEnglishWord() != null) {
            Optional<Word> existing = wordRepository.findByUserIdAndEnglishWord(
                word.getUserId(),
                word.getEnglishWord()
            );
            if (existing.isPresent()) {
                return hydrateSentences(existing.get());
            }
        }

        Word savedWord = wordRepository.save(word);

        if (isNew) {
            // Gamification: Add 10 points
            try {
                // Note: incrementScore expects double, so passing 10.0
                leaderboardService.incrementScore(savedWord.getUserId(), 10.0);
            } catch (Exception e) {
                System.err.println("Leaderboard error: " + e.getMessage());
            }

            // Social: Log Activity
            try {
                activityPublisher.publishWordAdded(savedWord.getUserId(), savedWord.getEnglishWord());
            } catch (Exception e) {
                System.err.println("Activity publish error: " + e.getMessage());
            }

            progressService.awardXp(savedWord.getUserId(), XP_NEW_WORD, "New Word: " + word.getEnglishWord());
            progressService.updateStreak(savedWord.getUserId());
        }

        return hydrateSentences(savedWord);
    }

    // Overload for convenience if needed, though usually verification happens at
    // controller
    public Word createWord(CreateWordRequest request, Long userId) {
        Objects.requireNonNull(userId, "userId is required");
        Word word = new Word();
        word.setUserId(userId);
        word.setEnglishWord(request.getEnglish());
        word.setTurkishMeaning(request.getTurkish());
        word.setLearnedDate(LocalDate.parse(request.getAddedDate()));
        word.setNotes(request.getNotes());
        if (request.getDifficulty() != null) {
            word.setDifficulty(request.getDifficulty());
        }
        return saveWord(word);
    }

    public Optional<Word> getWordById(Long id) {
        return wordRepository.findById(id);
    }

    // Secure get method ensuring user owns the word
    public Optional<Word> getWordByIdAndUser(Long id, Long userId) {
        return wordRepository.findByIdAndUserId(id, userId);
    }

    public Optional<Word> getWordByIdAndUserWithSentences(Long id, Long userId) {
        Optional<Word> word = wordRepository.findByIdAndUserIdWithSentences(id, userId);
        word.ifPresent(this::normalizeLoadedSentences);
        return word;
    }

    public void deleteWord(Long id, Long userId) {
        Optional<Word> word = getWordByIdAndUser(id, userId);
        if (word.isPresent()) {
            wordRepository.deleteById(id);
        }
        // If not found or not owned, do nothing (or throw exception)
    }

    @Transactional
    public Word updateWord(Long id, Word wordDetails, Long userId) {
        Optional<Word> optionalWord = getWordByIdAndUser(id, userId);
        if (optionalWord.isPresent()) {
            Word word = optionalWord.get();
            word.setEnglishWord(wordDetails.getEnglishWord());
            word.setTurkishMeaning(wordDetails.getTurkishMeaning());
            word.setLearnedDate(wordDetails.getLearnedDate());
            word.setNotes(wordDetails.getNotes());
            Word updatedWord = wordRepository.save(word);
            return hydrateSentences(updatedWord);
        }
        return null;
    }

    // Sentence management methods
    @Transactional
    public Word addSentence(Long wordId, String sentence, String translation, String difficulty, Long userId) {
        Optional<Word> wordOpt = getWordByIdAndUser(wordId, userId);
        if (wordOpt.isPresent()) {
            Word word = wordOpt.get();

            // Idempotency: if same sentence already exists, return word without side effects
            if (sentence != null) {
                List<Sentence> existingSentences = sentenceRepository
                        .findByWordIdAndSentenceAndTranslation(wordId, sentence, translation);
                if (!existingSentences.isEmpty()) {
                    return hydrateSentences(word);
                }
            }

            Sentence newSentence = new Sentence(sentence, translation, difficulty != null ? difficulty : "easy", word);
            word.addSentence(newSentence);
            progressService.awardXp(userId, XP_NEW_WORD_SENTENCE, "New Sentence for: " + word.getEnglishWord());
            Word updatedWord = wordRepository.save(word);
            return hydrateSentences(updatedWord);
        }
        return null;
    }

    @Transactional
    public Word deleteSentence(Long wordId, Long sentenceId, Long userId) {
        // Hardening: wordId may be stale/mismatched on the client during offline->online
        // transitions. Sentence ownership is enforced via sentence.word.userId.
        Optional<Sentence> sentenceOpt = sentenceRepository.findByIdAndWordUserId(sentenceId, userId);
        if (sentenceOpt.isEmpty()) {
            return null;
        }

        Sentence sentence = sentenceOpt.get();
        Word owningWord = sentence.getWord();
        if (owningWord == null || owningWord.getId() == null) {
            return null;
        }

        // Keep response consistent even if the caller used a different wordId.
        owningWord.removeSentence(sentence);
        sentenceRepository.delete(sentence);
        return hydrateSentences(owningWord);
    }

    private Word hydrateSentences(Word word) {
        if (word == null) {
            return null;
        }
        hydrateSentencesForWords(List.of(word));
        return word;
    }

    private void hydrateSentencesForWords(List<Word> words) {
        if (words == null || words.isEmpty()) {
            return;
        }

        List<Long> wordIds = words.stream()
                .map(Word::getId)
                .filter(Objects::nonNull)
                .toList();

        if (wordIds.isEmpty()) {
            for (Word word : words) {
                word.setSentences(new ArrayList<>());
            }
            return;
        }

        List<Sentence> allSentences = sentenceRepository.findByWordIdIn(wordIds);
        if (allSentences == null) {
            allSentences = List.of();
        }

        Map<Long, List<Sentence>> sentencesByWordId = allSentences.stream()
                .filter(sentence -> sentence.getWord() != null && sentence.getWord().getId() != null)
                .collect(Collectors.groupingBy(
                        sentence -> sentence.getWord().getId(),
                        Collectors.toList()));

        for (Word word : words) {
            List<Sentence> sentences = new ArrayList<>(sentencesByWordId.getOrDefault(word.getId(), List.of()));
            for (Sentence sentence : sentences) {
                sentence.setWord(word);
            }
            word.setSentences(sentences);
        }
    }

    private void normalizeLoadedSentences(Word word) {
        List<Sentence> sentences = new ArrayList<>(word.getSentences());
        for (Sentence sentence : sentences) {
            sentence.setWord(word);
        }
        word.setSentences(sentences);
    }
}
