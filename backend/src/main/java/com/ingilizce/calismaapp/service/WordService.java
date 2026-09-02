package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.WordMeaning;
import com.ingilizce.calismaapp.entity.WordOrigin;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.dto.CreateWordRequest;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import org.hibernate.Hibernate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.Objects;
import java.util.Map;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
@Transactional
public class WordService {
    private static final int XP_NEW_WORD = 10;
    private static final int XP_NEW_WORD_SENTENCE = 5;

    /**
     * How a legacy {@code turkish_meaning} string splits into meanings: commas, semicolons,
     * or a slash with whitespace on both sides. The same rule V028 used for the backfill, so
     * a word created through the old client and one backfilled from the same string agree.
     */
    /** The separators that always split: a semicolon, or a slash with air on both sides. */
    private static final Pattern HARD_SEPARATOR = Pattern.compile("\\s*;\\s*|\\s+/\\s+");
    private static final Pattern COMMA = Pattern.compile("\\s*,\\s*");

    /**
     * A comma-separated piece this long is a clause, not a listed sense. Three, because two
     * covers every tagged sense ("(n) banka") and every short compound ("hasta olmak"), and
     * the clause that shipped -- "Bir şeyin alt kısmında" -- is four. See splitOnSeparators.
     */
    private static final int MAX_WORDS_PER_LISTED_SENSE = 3;
    private static final int MAX_TRANSLATION_LENGTH = 255;

    /** Deleting the last meaning is refused: a word with no meaning teaches nothing (HTTP 400). */
    public static class LastMeaningException extends RuntimeException {
        public LastMeaningException() {
            super("A word must keep at least one meaning");
        }
    }

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private SentenceRepository sentenceRepository;

    @Autowired
    private ProgressService progressService;

    @Autowired
    private SRSService srsService;

    @Autowired
    private LanguageProfileService languageProfileService;

    public List<Word> getAllWords(Long userId) {
        return getAllWords(userId, null);
    }

    /** @param languageProfileId a profile of the caller, or null for the active one. */
    public List<Word> getAllWords(Long userId, Long languageProfileId) {
        Long profileId = resolveProfileId(userId, languageProfileId);
        List<Word> words = wordRepository.findByUserIdAndLanguageProfileId(userId, profileId);
        hydrateSentencesForWords(words);
        return words;
    }

    public Page<Word> getWordsPage(Long userId, int page, int size) {
        return getWordsPage(userId, null, page, size);
    }

    public Page<Word> getWordsPage(Long userId, Long languageProfileId, int page, int size) {
        Long profileId = resolveProfileId(userId, languageProfileId);
        Page<Word> wordsPage = wordRepository.findByUserIdAndLanguageProfileId(userId, profileId, PageRequest.of(page, size));
        hydrateSentencesForWords(wordsPage.getContent());
        return wordsPage;
    }

    public List<Word> getWordsByDate(Long userId, LocalDate date) {
        Long profileId = resolveProfileId(userId, null);
        List<Word> words = wordRepository.findByUserIdAndLanguageProfileIdAndLearnedDate(userId, profileId, date);
        hydrateSentencesForWords(words);
        return words;
    }

    public List<Word> getWordsByDateRange(Long userId, LocalDate startDate, LocalDate endDate) {
        Long profileId = resolveProfileId(userId, null);
        List<Word> words = wordRepository.findByUserIdAndLanguageProfileIdAndDateRange(userId, profileId, startDate, endDate);
        hydrateSentencesForWords(words);
        return words;
    }

    public List<LocalDate> getAllDistinctDates(Long userId) {
        Long profileId = resolveProfileId(userId, null);
        return wordRepository.findDistinctDatesByUserIdAndLanguageProfileId(userId, profileId);
    }

    @Transactional
    public Word saveWord(Word word) {
        Objects.requireNonNull(word, "word must not be null");
        if (word.getUserId() == null) {
            throw new IllegalArgumentException("word.userId is required");
        }

        // A client-supplied id is a sync hint, not authority. This used to fall straight
        // through to wordRepository.save(word) - a JPA merge of a detached entity - which
        // meant three things at once: no ownership check, so any caller could overwrite any
        // word row by id and make it theirs; the incoming entity's empty meanings list,
        // under cascade ALL + orphanRemoval, deleted every meaning the word had, bypassing
        // the last-meaning guard; and languageProfile came back null. The shipped client
        // really does send ids here (Word.toJson includes one, and offline sync replays
        // creations), so the id cannot simply be rejected either.
        if (word.getId() != null) {
            Optional<Word> owned = wordRepository.findByIdAndUserId(word.getId(), word.getUserId());
            if (owned.isPresent()) {
                Word managed = owned.get();
                if (word.getEnglishWord() != null && !word.getEnglishWord().isBlank()) {
                    managed.setEnglishWord(word.getEnglishWord());
                }
                if (word.getLearnedDate() != null) {
                    managed.setLearnedDate(word.getLearnedDate());
                }
                managed.setNotes(word.getNotes());
                if (word.getDifficulty() != null) {
                    managed.setDifficulty(word.getDifficulty());
                }
                // Offline sync replays SRS state; honour it only when actually carried.
                if (word.getNextReviewDate() != null) {
                    managed.setNextReviewDate(word.getNextReviewDate());
                }
                if (word.getReviewCount() != null) {
                    managed.setReviewCount(word.getReviewCount());
                }
                if (word.getEaseFactor() != null) {
                    managed.setEaseFactor(word.getEaseFactor());
                }
                if (word.getLastReviewDate() != null) {
                    managed.setLastReviewDate(word.getLastReviewDate());
                }
                applyMeaningEdit(managed, word);
                return hydrateSentences(wordRepository.save(managed));
            }
            // Not this user's word (a stale local id, or someone else's row): never merge
            // over it. Fall through and create under the caller's own account - the
            // englishWord idempotency check below still applies, so a replayed sync does
            // not duplicate.
            word.setId(null);
        }

        boolean isNew = true;

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

        if (isNew) {
            // Without this the word is stored with next_review_date NULL, and the due query
            // (findByUserIdAndNextReviewDateLessThanEqual) can never match it because NULL
            // fails <= in SQL. A word therefore only entered the scheduler once it had
            // already been reviewed -- which it could not be, because it never became due.
            // Measured on production before this fix: 18 of 20 stored words had no
            // schedule, and the only two that did were reviewed through the generic
            // "review everything" screen.
            srsService.initializeWordForSRS(word);

            // V028: every word belongs to a profile, carries its provenance, and has at
            // least one meaning. The shipped client sends none of these; they are derived.
            if (word.getLanguageProfile() == null) {
                word.setLanguageProfile(languageProfileService.ensureDefaultProfile(word.getUserId()));
            }
            if (word.getOrigin() == null || word.getOrigin().isBlank()) {
                word.setOrigin(WordOrigin.hasDailyWordsMarker(word.getTurkishMeaning())
                        ? WordOrigin.DAILY_WORDS
                        : WordOrigin.MANUAL);
            }
            prepareMeaningsForNewWord(word);
        }

        Word savedWord = wordRepository.save(word);

        if (isNew) {
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
            word.setLearnedDate(wordDetails.getLearnedDate());
            word.setNotes(wordDetails.getNotes());
            applyMeaningEdit(word, wordDetails);
            Word updatedWord = wordRepository.save(word);
            return hydrateSentences(updatedWord);
        }
        return null;
    }

    /**
     * Applies the meaning part of a PUT so the two representations cannot drift: meanings
     * sent explicitly win; otherwise a changed {@code turkishMeaning} is split into meanings
     * with the same rule the create path uses. Either way {@code turkishMeaning} ends up as
     * the joined translations (daily-words star kept), because the shipped client reads that
     * string and the new client reads the meanings.
     *
     * <p>Reconciled by translation rather than rebuilt: a meaning whose translation survives
     * keeps its id, its definition and the sentences attached to it. Sentences under a
     * meaning that goes away become unassigned, as in {@link #deleteMeaning}. A PUT whose
     * string is blank, or whose meanings are all blank, leaves the meanings alone -- a word
     * with no meaning teaches nothing -- and re-derives the string from them.
     */
    private void applyMeaningEdit(Word word, Word wordDetails) {
        List<WordMeaning> wanted = new ArrayList<>();
        Map<String, WordMeaning> seen = new LinkedHashMap<>();
        for (WordMeaning provided : wordDetails.getMeanings()) {
            if (provided == null) {
                continue;
            }
            String translation = cleanTranslation(provided.getTranslation());
            if (translation.isEmpty() || seen.containsKey(translation.toLowerCase(Locale.ROOT))) {
                continue;
            }
            WordMeaning copy = new WordMeaning(null, translation, cleanDefinition(provided.getDefinition()), wanted.size());
            seen.put(translation.toLowerCase(Locale.ROOT), copy);
            wanted.add(copy);
        }

        if (wanted.isEmpty()) {
            String newString = wordDetails.getTurkishMeaning();
            boolean unchanged = Objects.equals(
                    cleanTranslation(newString), cleanTranslation(word.getTurkishMeaning()));
            if (unchanged) {
                // Same meaning text (a star added or dropped is not a meaning change): the
                // caller's string is stored as it always was and the meanings stay.
                word.setTurkishMeaning(newString);
                return;
            }
            List<String> translations = splitMeaningString(newString);
            if (translations.isEmpty()) {
                if (word.getMeanings().isEmpty()) {
                    word.setTurkishMeaning(newString);
                } else {
                    syncTurkishMeaning(word);
                }
                return;
            }
            for (int i = 0; i < translations.size(); i++) {
                wanted.add(new WordMeaning(null, translations.get(i), null, i));
            }
            // The star the caller sent (or kept) is what syncTurkishMeaning preserves.
            word.setTurkishMeaning(newString);
        }

        reconcileMeanings(word, wanted);
        syncTurkishMeaning(word);
    }

    /** Makes the word's meanings match {@code wanted} while keeping rows whose translation survives. */
    private void reconcileMeanings(Word word, List<WordMeaning> wanted) {
        Map<String, WordMeaning> existingByKey = new LinkedHashMap<>();
        for (WordMeaning existing : word.getMeanings()) {
            if (existing.getTranslation() != null) {
                existingByKey.putIfAbsent(existing.getTranslation().trim().toLowerCase(Locale.ROOT), existing);
            }
        }

        List<WordMeaning> result = new ArrayList<>();
        for (WordMeaning target : wanted) {
            WordMeaning kept = existingByKey.remove(target.getTranslation().toLowerCase(Locale.ROOT));
            if (kept != null) {
                kept.setTranslation(target.getTranslation());
                if (target.getDefinition() != null) {
                    kept.setDefinition(target.getDefinition());
                }
                kept.setPosition(result.size());
                result.add(kept);
            } else {
                target.setPosition(result.size());
                result.add(target);
            }
        }

        for (WordMeaning removed : new ArrayList<>(word.getMeanings())) {
            if (result.contains(removed)) {
                continue;
            }
            if (removed.getId() != null) {
                for (Sentence sentence : sentenceRepository.findByMeaningId(removed.getId())) {
                    sentence.setMeaning(null);
                }
            }
            word.removeMeaning(removed);
        }
        word.setMeanings(result);
    }

    // Sentence management methods
    @Transactional
    public Word addSentence(Long wordId, String sentence, String translation, String difficulty, Long userId) {
        return addSentence(wordId, sentence, translation, difficulty, userId, null);
    }

    /**
     * As {@link #addSentence(Long, String, String, String, Long)}, optionally attaching the
     * sentence to one of the word's meanings. A null {@code meaningId} leaves the sentence
     * unassigned, which the UI shows under every meaning.
     *
     * @throws IllegalArgumentException when {@code meaningId} is not a meaning of this word
     */
    @Transactional
    public Word addSentence(Long wordId, String sentence, String translation, String difficulty, Long userId,
            Long meaningId) {
        Optional<Word> wordOpt = getWordByIdAndUser(wordId, userId);
        if (wordOpt.isPresent()) {
            Word word = wordOpt.get();
            WordMeaning meaning = meaningId != null ? requireMeaningOfWord(word, meaningId) : null;

            // Idempotency: if same sentence already exists, return word without side effects
            if (sentence != null) {
                List<Sentence> existingSentences = sentenceRepository
                        .findByWordIdAndSentenceAndTranslation(wordId, sentence, translation);
                if (!existingSentences.isEmpty()) {
                    // The one side effect worth having: an unassigned copy of this sentence
                    // learns its meaning when the caller now knows it.
                    if (meaning != null) {
                        for (Sentence existing : existingSentences) {
                            if (existing.getMeaning() == null) {
                                existing.setMeaning(meaning);
                            }
                        }
                    }
                    return hydrateSentences(word);
                }
            }

            Sentence newSentence = new Sentence(sentence, translation, difficulty != null ? difficulty : "easy", word);
            newSentence.setMeaning(meaning);
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
        // sentence.word is lazy, so this is a Hibernate proxy; the controller serialises the
        // returned word after the session closes, and Jackson cannot serialise a proxy.
        Word owningWord = sentence.getWord() == null ? null : Hibernate.unproxy(sentence.getWord(), Word.class);
        if (owningWord == null || owningWord.getId() == null) {
            return null;
        }

        // Keep response consistent even if the caller used a different wordId.
        owningWord.removeSentence(sentence);
        sentenceRepository.delete(sentence);
        return hydrateSentences(owningWord);
    }

    // Meaning management methods (V028)

    /**
     * Adds a meaning at the end of the word's list. Adding a translation the word already
     * has (case-insensitively) returns the word unchanged, like the other "add" paths here.
     *
     * @throws NoSuchElementException when the word is not the caller's (404)
     * @throws IllegalArgumentException when the translation is blank (400)
     */
    @Transactional
    public Word addMeaning(Long wordId, Long userId, String translation, String definition) {
        Word word = requireWordOfUser(wordId, userId);
        String cleanTranslation = cleanTranslation(translation);
        if (cleanTranslation.isEmpty()) {
            throw new IllegalArgumentException("translation is required");
        }
        for (WordMeaning existing : word.getMeanings()) {
            if (sameTranslation(existing.getTranslation(), cleanTranslation)) {
                return hydrateSentences(word);
            }
        }
        int position = word.getMeanings().stream().mapToInt(WordMeaning::getPosition).max().orElse(-1) + 1;
        word.addMeaning(new WordMeaning(null, cleanTranslation, cleanDefinition(definition), position));
        syncTurkishMeaning(word);
        return hydrateSentences(wordRepository.save(word));
    }

    /**
     * Edits a meaning's translation and/or definition. A null argument leaves that field as
     * it is; a blank definition clears it; a blank translation is refused.
     */
    @Transactional
    public Word updateMeaning(Long wordId, Long meaningId, Long userId, String translation, String definition) {
        Word word = requireWordOfUser(wordId, userId);
        WordMeaning meaning = findMeaningOfWord(word, meaningId)
                .orElseThrow(() -> new NoSuchElementException("Meaning not found: " + meaningId));
        if (translation != null) {
            String cleanTranslation = cleanTranslation(translation);
            if (cleanTranslation.isEmpty()) {
                throw new IllegalArgumentException("translation must not be blank");
            }
            meaning.setTranslation(cleanTranslation);
        }
        if (definition != null) {
            meaning.setDefinition(cleanDefinition(definition));
        }
        syncTurkishMeaning(word);
        return hydrateSentences(wordRepository.save(word));
    }

    /**
     * Removes a meaning. Sentences attached to it become unassigned rather than deleted: the
     * learner wrote them, and they still illustrate the word.
     *
     * @throws LastMeaningException when it is the word's only meaning (400)
     */
    @Transactional
    public Word deleteMeaning(Long wordId, Long meaningId, Long userId) {
        Word word = requireWordOfUser(wordId, userId);
        WordMeaning meaning = findMeaningOfWord(word, meaningId)
                .orElseThrow(() -> new NoSuchElementException("Meaning not found: " + meaningId));
        if (word.getMeanings().size() <= 1) {
            throw new LastMeaningException();
        }
        // Detach through the loaded entities rather than a bulk UPDATE so the persistence
        // context and the row agree; Hibernate flushes these updates before the delete.
        for (Sentence sentence : sentenceRepository.findByMeaningId(meaningId)) {
            sentence.setMeaning(null);
        }
        word.removeMeaning(meaning);
        syncTurkishMeaning(word);
        return hydrateSentences(wordRepository.save(word));
    }

    /**
     * Splits a legacy comma-joined meaning string into clean, de-duplicated translations with
     * the daily-words star stripped. Blank input gives an empty list.
     */
    public static List<String> splitMeaningString(String turkishMeaning) {
        if (turkishMeaning == null || turkishMeaning.isBlank()) {
            return List.of();
        }
        Map<String, String> byKey = new LinkedHashMap<>();
        for (String part : splitOnSeparators(turkishMeaning)) {
            String clean = cleanTranslation(part);
            if (clean.isEmpty()) {
                continue;
            }
            byKey.putIfAbsent(clean.toLowerCase(Locale.ROOT), clean);
        }
        return new ArrayList<>(byKey.values());
    }

    /**
     * The separator split, with one exception for the comma.
     *
     * <p>A comma between short pieces is a list of senses: {@code gecikme, ertelemek} is two
     * meanings, and so is {@code (n) banka, (n) kıyı}. A comma before a long piece is Turkish
     * punctuation inside one meaning: {@code Bir şeyin alt kısmında, üstünde değil} is a single
     * sense of "underneath" with a clarifying clause, and splitting it put "üstünde değil." on
     * the word screen as a meaning of its own, which is not a meaning of anything.
     *
     * <p>So if any comma-separated piece runs to {@value #MAX_WORDS_PER_LISTED_SENSE} words or
     * more, the comma is treated as punctuation and the whole run stays together. Semicolons
     * and spaced slashes split unconditionally -- nobody writes a clause with those. The
     * short-piece cases are the contract with the V028 backfill and are unchanged.
     */
    private static List<String> splitOnSeparators(String text) {
        List<String> out = new ArrayList<>();
        for (String run : HARD_SEPARATOR.split(text)) {
            // Blank pieces are dropped before anything is decided. Java's split discards
            // trailing empties, so ", , " came back as a single piece, was judged "one
            // sense" and kept verbatim -- and the test that says separators alone are not
            // meanings caught it.
            List<String> pieces = new ArrayList<>();
            for (String piece : COMMA.split(run)) {
                if (!piece.isBlank()) {
                    pieces.add(piece);
                }
            }
            if (pieces.isEmpty()) {
                continue;
            }
            boolean listOfSenses = pieces.size() > 1;
            for (String piece : pieces) {
                if (piece.trim().split("\\s+").length >= MAX_WORDS_PER_LISTED_SENSE) {
                    listOfSenses = false;
                    break;
                }
            }
            if (listOfSenses) {
                out.addAll(pieces);
            } else {
                out.add(run);
            }
        }
        return out;
    }

    private Long resolveProfileId(Long userId, Long languageProfileId) {
        if (languageProfileId == null) {
            return languageProfileService.ensureDefaultProfile(userId).getId();
        }
        return languageProfileService.getProfile(userId, languageProfileId)
                .map(LanguageProfile::getId)
                .orElseThrow(() -> new NoSuchElementException("Language profile not found: " + languageProfileId));
    }

    /**
     * Gives a new word its meanings. Meanings sent explicitly are cleaned, de-duplicated and
     * renumbered; otherwise they come from the {@code turkishMeaning} string. When only the
     * meanings were sent, the legacy string is filled in so the shipped client sees it.
     */
    private void prepareMeaningsForNewWord(Word word) {
        List<WordMeaning> provided = new ArrayList<>(word.getMeanings());
        List<WordMeaning> cleaned = new ArrayList<>();
        Map<String, WordMeaning> seen = new LinkedHashMap<>();
        for (WordMeaning meaning : provided) {
            if (meaning == null) {
                continue;
            }
            String translation = cleanTranslation(meaning.getTranslation());
            if (translation.isEmpty()) {
                continue;
            }
            String key = translation.toLowerCase(Locale.ROOT);
            if (seen.containsKey(key)) {
                continue;
            }
            WordMeaning copy = new WordMeaning(null, translation, cleanDefinition(meaning.getDefinition()), cleaned.size());
            seen.put(key, copy);
            cleaned.add(copy);
        }

        if (cleaned.isEmpty()) {
            List<String> translations = splitMeaningString(word.getTurkishMeaning());
            for (int i = 0; i < translations.size(); i++) {
                cleaned.add(new WordMeaning(null, translations.get(i), null, i));
            }
        } else if (word.getTurkishMeaning() == null || word.getTurkishMeaning().isBlank()) {
            word.setTurkishMeaning(joinTranslations(cleaned));
        }

        word.setMeanings(cleaned);
    }

    /**
     * Rewrites the denormalised {@code turkishMeaning} from the meanings. A daily-words star
     * the old string carried is kept in front, because the shipped client reads provenance
     * from that character and nothing else.
     */
    private void syncTurkishMeaning(Word word) {
        String old = word.getTurkishMeaning();
        String joined = joinTranslations(word.getMeanings());
        String marker = null;
        if (old != null && old.contains(WordOrigin.DAILY_WORDS_MARKER_EMOJI)) {
            marker = WordOrigin.DAILY_WORDS_MARKER_EMOJI;
        } else if (old != null && old.contains(WordOrigin.DAILY_WORDS_MARKER_BLACK_STAR)) {
            marker = WordOrigin.DAILY_WORDS_MARKER_BLACK_STAR;
        }
        word.setTurkishMeaning(marker != null ? marker + " " + joined : joined);
    }

    private static String joinTranslations(List<WordMeaning> meanings) {
        return meanings.stream()
                .map(WordMeaning::getTranslation)
                .filter(Objects::nonNull)
                .collect(Collectors.joining(", "));
    }

    private static String cleanTranslation(String value) {
        if (value == null) {
            return "";
        }
        String clean = value
                .replace(WordOrigin.DAILY_WORDS_MARKER_EMOJI, "")
                .replace(WordOrigin.DAILY_WORDS_MARKER_BLACK_STAR, "")
                .trim();
        return clean.length() > MAX_TRANSLATION_LENGTH ? clean.substring(0, MAX_TRANSLATION_LENGTH) : clean;
    }

    private static String cleanDefinition(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static boolean sameTranslation(String a, String b) {
        return a != null && b != null && a.trim().equalsIgnoreCase(b.trim());
    }

    private Word requireWordOfUser(Long wordId, Long userId) {
        return getWordByIdAndUser(wordId, userId)
                .orElseThrow(() -> new NoSuchElementException("Word not found: " + wordId));
    }

    private static Optional<WordMeaning> findMeaningOfWord(Word word, Long meaningId) {
        if (meaningId == null) {
            return Optional.empty();
        }
        return word.getMeanings().stream()
                .filter(meaning -> meaningId.equals(meaning.getId()))
                .findFirst();
    }

    private static WordMeaning requireMeaningOfWord(Word word, Long meaningId) {
        return findMeaningOfWord(word, meaningId)
                .orElseThrow(() -> new IllegalArgumentException("meaningId does not belong to this word: " + meaningId));
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
