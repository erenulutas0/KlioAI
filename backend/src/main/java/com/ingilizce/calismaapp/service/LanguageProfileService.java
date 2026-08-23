package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.WordMeaning;
import com.ingilizce.calismaapp.entity.WordOrigin;
import com.ingilizce.calismaapp.repository.LanguageProfileRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.function.Supplier;

/**
 * Language profiles (V028): one row per target language a user is learning, exactly one of
 * them active. Every word-reading path that needs "the user's words" asks
 * {@link #ensureDefaultProfile(Long)} for the active profile and scopes by it.
 *
 * <p>The V028 backfill gives every existing user a Turkish -> English profile, so in
 * practice the "create on the fly" branch only runs for a user created after the migration
 * whose first request is a read. It still has to exist: a read path that 500s on a missing
 * row would lock a brand-new learner out of their own (empty) word list.
 */
@Service
@Transactional
public class LanguageProfileService {

    private static final Logger log = LoggerFactory.getLogger(LanguageProfileService.class);

    /** Same set {@link LearningLanguageProfile} accepts; the column is varchar(8). */
    private static final Set<String> SUPPORTED_LEVELS = Set.of("A1", "A2", "B1", "B2", "C1", "C2");
    private static final int MAX_LANGUAGE_LENGTH = 32;
    private static final int MAX_GOAL_LENGTH = 32;

    /** Thrown when a profile for the requested target language already exists (HTTP 409). */
    public static class DuplicateTargetLanguageException extends RuntimeException {
        public DuplicateTargetLanguageException(String targetLanguage) {
            super("A profile for " + targetLanguage + " already exists");
        }
    }

    private final LanguageProfileRepository languageProfileRepository;

    /** Null only in unit tests that construct the service with the repository alone. */
    private final WordRepository wordRepository;

    /**
     * REQUIRES_NEW template for the one insert that can race (see
     * {@link #createDefaultProfile(Long)}). Null in unit tests, where the insert runs inline.
     */
    private final TransactionTemplate newTransaction;

    @Autowired
    public LanguageProfileService(LanguageProfileRepository languageProfileRepository,
            WordRepository wordRepository, PlatformTransactionManager transactionManager) {
        this.languageProfileRepository = languageProfileRepository;
        this.wordRepository = wordRepository;
        this.newTransaction = new TransactionTemplate(transactionManager);
        this.newTransaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /** Unit-test constructor: no orphan-word adoption, inserts run in the caller's transaction. */
    public LanguageProfileService(LanguageProfileRepository languageProfileRepository) {
        this.languageProfileRepository = languageProfileRepository;
        this.wordRepository = null;
        this.newTransaction = null;
    }

    @Transactional(readOnly = true)
    public List<LanguageProfile> listProfiles(Long userId) {
        requireUserId(userId);
        return languageProfileRepository.findByUserIdOrderByCreatedAtAscIdAsc(userId);
    }

    /**
     * The user's active profile, creating the default Turkish -> English one when the user has
     * no profile at all. If rows exist but none is active (which the API never produces, but a
     * hand edit could), the oldest one is activated rather than failing every read.
     */
    public LanguageProfile ensureDefaultProfile(Long userId) {
        requireUserId(userId);
        Optional<LanguageProfile> active = languageProfileRepository.findByUserIdAndIsActiveTrue(userId);
        if (active.isPresent()) {
            return adoptOrphanWords(userId, active.get());
        }

        List<LanguageProfile> existing = languageProfileRepository.findByUserIdOrderByCreatedAtAscIdAsc(userId);
        if (!existing.isEmpty()) {
            LanguageProfile oldest = existing.get(0);
            log.warn("LANGUAGE_PROFILE_NONE_ACTIVE userId={} activating profileId={}", userId, oldest.getId());
            oldest.setActive(true);
            return adoptOrphanWords(userId, languageProfileRepository.save(oldest));
        }

        return adoptOrphanWords(userId, createDefaultProfile(userId));
    }

    /**
     * Inserts the default profile, tolerating the one race this check-then-insert has: a new
     * user's first two reads (the shipped client fires {@code /srs/stats} and {@code /words}
     * together) both find no profile and both insert. The insert runs in its own transaction
     * so the loser's unique-key violation does not poison the caller's transaction (on
     * PostgreSQL an aborted transaction rejects every later statement), and the loser then
     * reads the row the winner committed.
     */
    private LanguageProfile createDefaultProfile(Long userId) {
        try {
            LanguageProfile created = inOwnTransaction(
                    () -> languageProfileRepository.save(LanguageProfile.defaultEnglishProfile(userId)));
            log.info("LANGUAGE_PROFILE_DEFAULT_CREATED userId={}", userId);
            // Re-read in the caller's persistence context when the insert ran in its own.
            return newTransaction == null || created.getId() == null
                    ? created
                    : languageProfileRepository.findById(created.getId()).orElse(created);
        } catch (DataIntegrityViolationException raced) {
            log.info("LANGUAGE_PROFILE_DEFAULT_RACED userId={}", userId);
            return languageProfileRepository.findByUserIdAndIsActiveTrue(userId)
                    .or(() -> languageProfileRepository.findByUserIdAndTargetLanguage(userId,
                            LanguageProfile.DEFAULT_TARGET_LANGUAGE))
                    .orElseThrow(() -> raced);
        }
    }

    private LanguageProfile inOwnTransaction(Supplier<LanguageProfile> insert) {
        if (newTransaction == null) {
            return insert.get();
        }
        return newTransaction.execute(status -> insert.get());
    }

    /**
     * Gives every word of the user that no profile claims a home, so it shows up again in
     * the profile-scoped list, date, due and stats queries. Such rows should not exist after
     * the V028 backfill, but pre-V028 code running against the V028 schema (the documented
     * rollback procedure) or a hand insert creates them, and nothing else repairs them.
     *
     * <p>They go to the user's English profile, not necessarily the active one: every
     * orphan was written by code that only knew English. Origin and meanings are derived the
     * same way {@code WordService.saveWord} derives them for a word the shipped client sends.
     */
    private LanguageProfile adoptOrphanWords(Long userId, LanguageProfile fallback) {
        if (wordRepository == null) {
            return fallback;
        }
        List<Word> orphans = wordRepository.findByUserIdAndLanguageProfileIsNull(userId);
        if (orphans.isEmpty()) {
            return fallback;
        }
        LanguageProfile home = languageProfileRepository
                .findByUserIdAndTargetLanguage(userId, LanguageProfile.DEFAULT_TARGET_LANGUAGE)
                .orElse(fallback);
        for (Word word : orphans) {
            word.setLanguageProfile(home);
            if (word.getOrigin() == null || word.getOrigin().isBlank()) {
                word.setOrigin(WordOrigin.hasDailyWordsMarker(word.getTurkishMeaning())
                        ? WordOrigin.DAILY_WORDS
                        : WordOrigin.MANUAL);
            }
            if (word.getMeanings().isEmpty()) {
                List<String> translations = WordService.splitMeaningString(word.getTurkishMeaning());
                for (int i = 0; i < translations.size(); i++) {
                    word.addMeaning(new WordMeaning(null, translations.get(i), null, i));
                }
            }
        }
        wordRepository.saveAll(orphans);
        log.warn("LANGUAGE_PROFILE_ORPHAN_WORDS_ADOPTED userId={} profileId={} count={}",
                userId, home.getId(), orphans.size());
        return fallback;
    }

    /** Alias that reads as what callers mean at the call site. */
    public LanguageProfile getActiveProfile(Long userId) {
        return ensureDefaultProfile(userId);
    }

    public Optional<LanguageProfile> getProfile(Long userId, Long profileId) {
        requireUserId(userId);
        if (profileId == null) {
            return Optional.empty();
        }
        return languageProfileRepository.findByIdAndUserId(profileId, userId);
    }

    /**
     * Creates a profile. The first profile a user creates becomes active; later ones do not
     * steal the active flag -- switching is an explicit {@link #activate(Long, Long)} call.
     *
     * @throws IllegalArgumentException when a language is missing or a level is unknown (400)
     * @throws DuplicateTargetLanguageException when the target language already has a profile (409)
     */
    public LanguageProfile createProfile(Long userId, String sourceLanguage, String targetLanguage,
            String level, String learningGoal) {
        requireUserId(userId);
        String source = requireLanguage(sourceLanguage, "sourceLanguage");
        String target = requireLanguage(targetLanguage, "targetLanguage");
        String normalizedLevel = normalizeLevel(level);
        String normalizedGoal = normalizeGoal(learningGoal);

        if (languageProfileRepository.existsByUserIdAndTargetLanguage(userId, target)) {
            throw new DuplicateTargetLanguageException(target);
        }

        boolean first = languageProfileRepository.findByUserId(userId).isEmpty();
        LanguageProfile profile = new LanguageProfile(userId, source, target, normalizedLevel, normalizedGoal, first);
        return languageProfileRepository.save(profile);
    }

    /**
     * Updates level and/or goal. A null argument leaves the field alone; an explicitly blank
     * goal clears it, because "no goal" is a valid state and the column is nullable.
     */
    public LanguageProfile updateProfile(Long userId, Long profileId, String level, String learningGoal) {
        LanguageProfile profile = getProfile(userId, profileId)
                .orElseThrow(() -> new NoSuchElementException("Language profile not found: " + profileId));
        if (level != null) {
            profile.setLevel(normalizeLevel(level));
        }
        if (learningGoal != null) {
            profile.setLearningGoal(normalizeGoal(learningGoal));
        }
        return languageProfileRepository.save(profile);
    }

    /**
     * Makes one profile active and every other profile of the user inactive, in that order of
     * statements so the invariant holds at commit. Activating the already-active profile is
     * a no-op that still returns it.
     */
    public LanguageProfile activate(Long userId, Long profileId) {
        LanguageProfile profile = getProfile(userId, profileId)
                .orElseThrow(() -> new NoSuchElementException("Language profile not found: " + profileId));
        if (profile.isActive()) {
            return profile;
        }
        languageProfileRepository.deactivateAllByUserId(userId);
        profile.setActive(true);
        return languageProfileRepository.save(profile);
    }

    private static void requireUserId(Long userId) {
        if (userId == null || userId <= 0) {
            throw new IllegalArgumentException("X-User-Id must be a positive number");
        }
    }

    private static String requireLanguage(String value, String field) {
        String trimmed = Objects.toString(value, "").trim();
        if (trimmed.isEmpty()) {
            throw new IllegalArgumentException(field + " is required");
        }
        if (trimmed.length() > MAX_LANGUAGE_LENGTH) {
            throw new IllegalArgumentException(field + " is too long");
        }
        // "english" and "English" are the same profile; the unique key is on the stored form.
        return trimmed.substring(0, 1).toUpperCase(Locale.ROOT) + trimmed.substring(1);
    }

    private static String normalizeLevel(String level) {
        String trimmed = Objects.toString(level, "").trim();
        if (trimmed.isEmpty()) {
            return LanguageProfile.DEFAULT_LEVEL;
        }
        String upper = trimmed.toUpperCase(Locale.ROOT);
        if (!SUPPORTED_LEVELS.contains(upper)) {
            throw new IllegalArgumentException("level must be one of A1, A2, B1, B2, C1, C2");
        }
        return upper;
    }

    private static String normalizeGoal(String goal) {
        String trimmed = Objects.toString(goal, "").trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        if (trimmed.length() > MAX_GOAL_LENGTH) {
            throw new IllegalArgumentException("learningGoal is too long");
        }
        return trimmed;
    }
}
