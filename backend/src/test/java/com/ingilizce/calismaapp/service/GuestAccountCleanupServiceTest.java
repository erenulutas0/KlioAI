package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.entity.FeatureRating;
import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.WordMeaning;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import com.ingilizce.calismaapp.repository.FeatureRatingRepository;
import com.ingilizce.calismaapp.repository.LanguageProfileRepository;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * A guest account is created for anyone who opens the app, so the rows nobody ever converted
 * have to go -- and everything keyed on them has to go with them, in an order no foreign key
 * objects to. The one thing this must never do is take an account that belongs to somebody.
 */
@SpringBootTest
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:guestcleanupdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class GuestAccountCleanupServiceTest {

    private static final LocalDateTime CUTOFF = LocalDateTime.now().minusDays(30);

    @Autowired
    private GuestAccountCleanupService service;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private LanguageProfileRepository languageProfileRepository;

    @Autowired
    private FeatureRatingRepository featureRatingRepository;

    @Autowired
    private DevicePushTokenRepository devicePushTokenRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        jdbcTemplate.update("DELETE FROM payment_transactions");
        jdbcTemplate.update("DELETE FROM sentences");
        jdbcTemplate.update("DELETE FROM word_meanings");
        jdbcTemplate.update("DELETE FROM words");
        jdbcTemplate.update("DELETE FROM language_profiles");
        jdbcTemplate.update("DELETE FROM feature_ratings");
        jdbcTemplate.update("DELETE FROM device_push_tokens");
        jdbcTemplate.update("DELETE FROM users");
    }

    private User user(boolean guest, LocalDateTime createdAt) {
        User user = new User("u-" + UUID.randomUUID() + "@test.com", "hash", "Someone");
        user.setGuest(guest);
        user.setCreatedAt(createdAt);
        return userRepository.save(user);
    }

    /** A learner who has actually used the app: a profile, a word with a sentence and a
     * meaning, a rating and a registered device. */
    private void givePossessions(User owner) {
        languageProfileRepository.save(LanguageProfile.defaultEnglishProfile(owner.getId()));

        Word word = new Word("ephemeral", "gecici", LocalDate.now());
        word.setUserId(owner.getId());
        Sentence sentence = new Sentence("It was an ephemeral thing.", "Gecici bir seydi.", "B1", word);
        word.getSentences().add(sentence);
        WordMeaning meaning = new WordMeaning(word, "gecici", null, 0);
        word.getMeanings().add(meaning);
        wordRepository.save(word);

        FeatureRating rating = new FeatureRating();
        rating.setUserId(owner.getId());
        rating.setFeature(FeatureRating.Feature.TUTOR);
        rating.setStars(5);
        featureRatingRepository.save(rating);

        DevicePushToken token = new DevicePushToken();
        token.setUserId(owner.getId());
        token.setToken("fcm-" + UUID.randomUUID());
        token.setPlatform("android");
        devicePushTokenRepository.save(token);
    }

    private long rowsFor(String table, Long userId) {
        Long count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM " + table + " WHERE user_id = ?", Long.class, userId);
        return count == null ? 0 : count;
    }

    @Test
    void anOldGuestGoesAndTakesEverythingKeyedOnItWithIt() {
        User guest = user(true, LocalDateTime.now().minusDays(45));
        givePossessions(guest);

        assertEquals(1, service.purgeBatch(CUTOFF, 100));

        assertTrue(userRepository.findById(guest.getId()).isEmpty());
        assertEquals(0, rowsFor("words", guest.getId()));
        assertEquals(0, rowsFor("language_profiles", guest.getId()));
        assertEquals(0, rowsFor("feature_ratings", guest.getId()));
        assertEquals(0, rowsFor("device_push_tokens", guest.getId()));
        // The tables that hang off a word rather than off the user: nothing may be left
        // pointing at a word id that is gone.
        assertEquals(0L, (long) jdbcTemplate.queryForObject("SELECT COUNT(*) FROM sentences", Long.class));
        assertEquals(0L, (long) jdbcTemplate.queryForObject("SELECT COUNT(*) FROM word_meanings", Long.class));
    }

    @Test
    void aGuestStillBeingUsedIsNotCollectedHoweverOldTheAccountIs() {
        // The rule was "created more than thirty days ago", which would have deleted the
        // account of a learner who had been talking to the tutor every day since they
        // installed it -- on the thirty-first day, mid-use. What makes a guest collectable is
        // that nobody can get back into it: its refresh token is the only key and it is
        // renewed on every launch.
        User daily = user(true, LocalDateTime.now().minusDays(120));
        daily.setLastSeenAt(LocalDateTime.now().minusHours(2));
        userRepository.save(daily);
        givePossessions(daily);

        assertEquals(0, service.purgeBatch(CUTOFF, 100));

        assertTrue(userRepository.findById(daily.getId()).isPresent());
        assertEquals(1, rowsFor("words", daily.getId()));
    }

    @Test
    void aGuestNobodyHasOpenedForLongerThanItsSessionLivesIsCollected() {
        User abandoned = user(true, LocalDateTime.now().minusDays(120));
        abandoned.setLastSeenAt(LocalDateTime.now().minusDays(45));
        userRepository.save(abandoned);

        assertEquals(1, service.purgeBatch(CUTOFF, 100));

        assertTrue(userRepository.findById(abandoned.getId()).isEmpty());
    }

    @Test
    void anAccountThatBelongsToSomebodyIsNeverTakenHoweverOldItIs() {
        User real = user(false, LocalDateTime.now().minusDays(400));
        givePossessions(real);
        User guest = user(true, LocalDateTime.now().minusDays(45));

        assertEquals(1, service.purgeBatch(CUTOFF, 100));

        assertTrue(userRepository.findById(real.getId()).isPresent());
        assertEquals(1, rowsFor("words", real.getId()));
        assertEquals(1, rowsFor("feature_ratings", real.getId()));
        assertTrue(userRepository.findById(guest.getId()).isEmpty());
    }

    @Test
    void aGuestInsideTheRetentionWindowIsStillWaitingForThemToComeBack() {
        User recent = user(true, LocalDateTime.now().minusDays(3));
        givePossessions(recent);

        assertEquals(0, service.purgeBatch(CUTOFF, 100));

        assertTrue(userRepository.findById(recent.getId()).isPresent());
        assertEquals(1, rowsFor("words", recent.getId()));
    }

    @Test
    void aGuestWhoPaidIsNotCollected() {
        User subscriber = user(true, LocalDateTime.now().minusDays(45));
        subscriber.setSubscriptionEndDate(LocalDateTime.now().plusDays(20));
        userRepository.save(subscriber);

        assertEquals(0, service.purgeBatch(CUTOFF, 100));

        assertTrue(userRepository.findById(subscriber.getId()).isPresent());
    }

    @Test
    void aRunIsBoundedByTheBatchSize() {
        List.of(40, 50, 60).forEach(days -> user(true, LocalDateTime.now().minusDays(days)));

        assertEquals(2, service.purgeBatch(CUTOFF, 2));
        assertEquals(1, userRepository.count());
        assertEquals(1, service.purgeBatch(CUTOFF, 2));
        assertEquals(0, service.purgeBatch(CUTOFF, 2));
    }

    @Test
    void nothingToCollectIsNotAnError() {
        User real = user(false, LocalDateTime.now().minusDays(400));

        assertEquals(0, service.purgeBatch(CUTOFF, 100));

        assertFalse(userRepository.findById(real.getId()).isEmpty());
    }
}
