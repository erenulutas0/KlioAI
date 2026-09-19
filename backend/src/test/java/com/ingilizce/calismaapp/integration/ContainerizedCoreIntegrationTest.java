package com.ingilizce.calismaapp.integration;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.LocalDate;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import com.ingilizce.calismaapp.service.GuestAccountCleanupService;

import java.sql.Timestamp;
import java.time.LocalDateTime;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers(disabledWithoutDocker = true)
@TestPropertySource(properties = {
        "logging.level.org.flywaydb.core.internal.sqlscript.DefaultSqlScriptExecutor=ERROR",
        "logging.level.io.lettuce.core.protocol.ConnectionWatchdog=ERROR"
})
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class ContainerizedCoreIntegrationTest {
    private static final long PERF_USER_ID = 99001L;
    private static final int PERF_WORD_ROWS = 20000;
    private static final int PERF_SENTENCE_ROWS = 20000;
    private static volatile boolean queryPlanSeeded = false;

    @Container
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
            .withDatabaseName("EnglishApp")
            .withUsername("postgres")
            .withPassword("postgres");

    @Container
    static final GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
            .withExposedPorts(6379);

    @DynamicPropertySource
    static void overrideProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");

        registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        registry.add("spring.flyway.enabled", () -> "true");
        registry.add("spring.flyway.baseline-on-migrate", () -> "false");
        registry.add("spring.flyway.validate-on-migrate", () -> "true");

        registry.add("spring.data.redis.host", redis::getHost);
        registry.add("spring.data.redis.port", () -> redis.getMappedPort(6379));
        registry.add("spring.data.redis.password", () -> "");
        registry.add("spring.data.redis.timeout", () -> "2000ms");

        registry.add("app.features.community.enabled", () -> "false");
        registry.add("app.socketio.enabled", () -> "false");
        registry.add("groq.api.key", () -> "dummy-key");
    }

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @Autowired
    private GuestAccountCleanupService guestAccountCleanupService;

    @Test
    @Order(1)
    void flywayShouldCreateCoreSchemaOnCleanPostgres() {
        Integer usersTable = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='users'",
                Integer.class);
        Integer wordsTable = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='words'",
                Integer.class);
        Integer migrations = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM flyway_schema_history WHERE success = true",
                Integer.class);

        org.junit.jupiter.api.Assertions.assertNotNull(usersTable);
        org.junit.jupiter.api.Assertions.assertNotNull(wordsTable);
        org.junit.jupiter.api.Assertions.assertNotNull(migrations);
        org.junit.jupiter.api.Assertions.assertEquals(1, usersTable);
        org.junit.jupiter.api.Assertions.assertEquals(1, wordsTable);
        org.junit.jupiter.api.Assertions.assertTrue(migrations >= 11,
                "Expected at least 11 successful migrations, got " + migrations);
    }

    @Test
    @Order(2)
    void flywayShouldApplyAllExpectedCoreVersions() {
        List<String> rawVersions = jdbcTemplate.queryForList(
                "SELECT version FROM flyway_schema_history WHERE success = true AND version IS NOT NULL ORDER BY installed_rank",
                String.class);

        List<Integer> applied = rawVersions.stream()
                .map(Integer::parseInt)
                .collect(Collectors.toList());

        List<Integer> expected = Arrays.asList(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
        org.junit.jupiter.api.Assertions.assertTrue(applied.containsAll(expected),
                "Missing expected Flyway versions. Applied: " + applied);
    }

    @Test
    @Order(3)
    void redisShouldBeReachableForCacheOperations() {
        String key = "tc:cache:" + UUID.randomUUID();

        redisTemplate.opsForValue().set(key, "ok");
        Object value = redisTemplate.opsForValue().get(key);
        redisTemplate.delete(key);

        org.junit.jupiter.api.Assertions.assertEquals("ok", value);
    }

    @Test
    @Order(4)
    void cleanDbSmokeShouldExposeCriticalReadEndpointAndStartWithEmptyWorkTables() throws Exception {
        Integer wordCount = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM words", Integer.class);
        Integer sentenceCount = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM sentence_practices", Integer.class);
        Integer reviewCount = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM word_reviews", Integer.class);

        org.junit.jupiter.api.Assertions.assertEquals(0, wordCount);
        org.junit.jupiter.api.Assertions.assertEquals(0, sentenceCount);
        org.junit.jupiter.api.Assertions.assertEquals(0, reviewCount);

        mockMvc.perform(get("/api/subscription/plans"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(greaterThanOrEqualTo(1))));
    }

    @Test
    @Order(5)
    void coreFlowShouldWorkAgainstPostgresAndRedis() throws Exception {
        mockMvc.perform(get("/api/subscription/plans"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(greaterThanOrEqualTo(1))));

        String uniqueEmail = "tc_" + UUID.randomUUID() + "@test.com";
        Map<String, String> registerRequest = new HashMap<>();
        registerRequest.put("email", uniqueEmail);
        registerRequest.put("password", "password123");
        registerRequest.put("displayName", "TC User");

        String registerBody = mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(registerRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode registerJson = objectMapper.readTree(registerBody);
        long userId = registerJson.path("userId").asLong();
        org.junit.jupiter.api.Assertions.assertTrue(userId > 0);

        Map<String, Object> wordRequest = new HashMap<>();
        wordRequest.put("englishWord", "containerized");
        wordRequest.put("turkishMeaning", "konteyner");
        wordRequest.put("learnedDate", LocalDate.now().toString());
        wordRequest.put("difficulty", "medium");

        mockMvc.perform(post("/api/words")
                        .header("X-User-Id", String.valueOf(userId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(wordRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.englishWord").value("containerized"));

        mockMvc.perform(get("/api/words/paged")
                        .param("page", "0")
                        .param("size", "10")
                        .header("X-User-Id", String.valueOf(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content", hasSize(1)))
                .andExpect(jsonPath("$.totalElements").value(1));

        Map<String, Object> sentencePracticeRequest = new HashMap<>();
        sentencePracticeRequest.put("englishSentence", "I test with containers.");
        sentencePracticeRequest.put("turkishTranslation", "Konteynerlerle test ederim.");
        sentencePracticeRequest.put("difficulty", "EASY");

        mockMvc.perform(post("/api/sentences")
                        .header("X-User-Id", String.valueOf(userId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sentencePracticeRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.englishSentence").value("I test with containers."));

        mockMvc.perform(get("/api/sentences/practice/paged")
                        .param("page", "0")
                        .param("size", "10")
                        .header("X-User-Id", String.valueOf(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content", hasSize(1)))
                .andExpect(jsonPath("$.totalElements").value(1));
    }

    @Test
    @Order(6)
    void queryPlanGuard_ShouldUseDifficultyCompositeIndexForSentencePractices() throws Exception {
        seedQueryPlanDatasetIfNeeded();

        JsonNode explain = explainJson(
                "SELECT id, user_id, difficulty, created_date " +
                        "FROM sentence_practices " +
                        "WHERE user_id = " + PERF_USER_ID + " AND difficulty = 'EASY' " +
                        "ORDER BY created_date DESC LIMIT 100");

        JsonNode plan = explain.path("Plan");
        Set<String> indexes = new HashSet<>();
        collectIndexNames(plan, indexes);

        org.junit.jupiter.api.Assertions.assertTrue(
                indexes.contains("idx_sentence_practices_user_difficulty_created_date"),
                "Expected difficulty composite index not used. Plan indexes: " + indexes);
        org.junit.jupiter.api.Assertions.assertFalse(
                hasNodeType(plan, "Seq Scan"),
                "Unexpected Seq Scan in sentence_practices difficulty query plan.");
        org.junit.jupiter.api.Assertions.assertTrue(
                explain.path("Execution Time").asDouble() < 1500.0,
                "Sentence difficulty query latency guard exceeded: " + explain.path("Execution Time").asDouble() + "ms");
    }

    @Test
    @Order(7)
    void queryPlanGuard_ShouldUseReviewDateIndexForWordReviewsDateQuery() throws Exception {
        seedQueryPlanDatasetIfNeeded();

        JsonNode explain = explainJson(
                "SELECT id, word_id, review_date " +
                        "FROM word_reviews " +
                        "WHERE review_date = CURRENT_DATE - 3");

        JsonNode plan = explain.path("Plan");
        Set<String> indexes = new HashSet<>();
        collectIndexNames(plan, indexes);

        org.junit.jupiter.api.Assertions.assertTrue(
                indexes.contains("idx_word_reviews_review_date"),
                "Expected review_date index not used. Plan indexes: " + indexes);
        org.junit.jupiter.api.Assertions.assertFalse(
                hasNodeType(plan, "Seq Scan"),
                "Unexpected Seq Scan in word_reviews date query plan.");
        org.junit.jupiter.api.Assertions.assertTrue(
                explain.path("Execution Time").asDouble() < 1500.0,
                "Word review date query latency guard exceeded: " + explain.path("Execution Time").asDouble() + "ms");
    }

    @Test
    @Order(8)
    void iyzicoCallbackShouldBeIdempotentAndUpdateSubscriptionOnce() throws Exception {
        Long planId = jdbcTemplate.queryForObject(
                "SELECT id FROM subscription_plans ORDER BY id LIMIT 1",
                Long.class);
        org.junit.jupiter.api.Assertions.assertNotNull(planId);

        String seed = UUID.randomUUID().toString().replace("-", "");
        String email = "tc_callback_" + seed + "@test.com";
        String userTag = "tc_cb_" + seed.substring(0, 10);

        Long userId = jdbcTemplate.queryForObject(
                "INSERT INTO users (email, password_hash, display_name, user_tag, role, created_at, is_active, is_email_verified, is_premium, is_online) " +
                        "VALUES (?, ?, ?, ?, 'USER', NOW(), true, true, false, false) RETURNING id",
                Long.class,
                email,
                "x",
                "Callback User",
                userTag);
        org.junit.jupiter.api.Assertions.assertNotNull(userId);

        String token = "tc-callback-" + UUID.randomUUID();
        jdbcTemplate.update(
                "INSERT INTO payment_transactions (transaction_id, user_id, plan_id, amount, status, payment_provider, created_at) " +
                        "VALUES (?, ?, ?, ?, 'PENDING', 'IYZICO', NOW())",
                token,
                userId,
                planId,
                new BigDecimal("149.99"));

        mockMvc.perform(post("/api/subscription/callback/iyzico").param("token", token))
                .andExpect(status().isOk())
                .andExpect(content().string("Payment successful and subscription updated."));

        String statusAfterFirst = jdbcTemplate.queryForObject(
                "SELECT status FROM payment_transactions WHERE transaction_id = ?",
                String.class,
                token);
        org.junit.jupiter.api.Assertions.assertEquals("SUCCESS", statusAfterFirst);

        Timestamp firstEndDate = jdbcTemplate.queryForObject(
                "SELECT subscription_end_date FROM users WHERE id = ?",
                Timestamp.class,
                userId);
        org.junit.jupiter.api.Assertions.assertNotNull(firstEndDate);

        mockMvc.perform(post("/api/subscription/callback/iyzico").param("token", token))
                .andExpect(status().isOk())
                .andExpect(content().string("Payment already processed."));

        Timestamp secondEndDate = jdbcTemplate.queryForObject(
                "SELECT subscription_end_date FROM users WHERE id = ?",
                Timestamp.class,
                userId);
        org.junit.jupiter.api.Assertions.assertNotNull(secondEndDate);
        org.junit.jupiter.api.Assertions.assertEquals(firstEndDate.toInstant(), secondEndDate.toInstant());
    }

    private void seedQueryPlanDatasetIfNeeded() {
        if (queryPlanSeeded) {
            return;
        }
        synchronized (ContainerizedCoreIntegrationTest.class) {
            if (queryPlanSeeded) {
                return;
            }

            jdbcTemplate.execute(
                    "INSERT INTO users (id, email, password_hash, display_name, user_tag, role, is_active, is_email_verified, is_premium, is_online, created_at) " +
                            "VALUES (" + PERF_USER_ID + ", 'perf_" + PERF_USER_ID + "@local.test', 'x', 'Perf User', 'perf_" + PERF_USER_ID + "', 'USER', true, true, false, false, NOW()) " +
                            "ON CONFLICT (id) DO NOTHING");

            jdbcTemplate.execute(
                    "INSERT INTO words (user_id, english_word, turkish_meaning, learned_date, difficulty, next_review_date, review_count, ease_factor, last_review_date) " +
                            "SELECT " + PERF_USER_ID + ", " +
                            "'qg_word_' || g, " +
                            "'qg_tr_' || g, " +
                            "CURRENT_DATE - ((g % 365)::int), " +
                            "CASE WHEN g % 3 = 0 THEN 'easy' WHEN g % 3 = 1 THEN 'medium' ELSE 'hard' END, " +
                            "CURRENT_DATE - ((g % 30)::int), " +
                            "(g % 10), " +
                            "2.5, " +
                            "CURRENT_DATE - ((g % 7)::int) " +
                            "FROM generate_series(1, " + PERF_WORD_ROWS + ") g " +
                            "ON CONFLICT (user_id, english_word) DO NOTHING");

            jdbcTemplate.execute("DELETE FROM sentence_practices WHERE user_id = " + PERF_USER_ID);
            jdbcTemplate.execute(
                    "INSERT INTO sentence_practices (user_id, english_sentence, turkish_translation, difficulty, created_date) " +
                            "SELECT " + PERF_USER_ID + ", " +
                            "'qg_sentence_' || g, " +
                            "'qg_sentence_tr_' || g, " +
                            "CASE WHEN g % 3 = 0 THEN 'EASY' WHEN g % 3 = 1 THEN 'MEDIUM' ELSE 'HARD' END, " +
                            "CURRENT_DATE - ((g % 365)::int) " +
                            "FROM generate_series(1, " + PERF_SENTENCE_ROWS + ") g");

            jdbcTemplate.execute(
                    "DELETE FROM word_reviews wr " +
                            "USING words w " +
                            "WHERE wr.word_id = w.id AND w.user_id = " + PERF_USER_ID);

            jdbcTemplate.execute(
                    "INSERT INTO word_reviews (word_id, review_date, review_type, notes, was_correct, response_time_seconds) " +
                            "SELECT w.id, " +
                            "CURRENT_DATE - (gs % 5), " +
                            "'daily', " +
                            "NULL, " +
                            "(gs % 2 = 0), " +
                            "(gs % 30) " +
                            "FROM words w " +
                            "JOIN generate_series(1, 3) gs ON true " +
                            "WHERE w.user_id = " + PERF_USER_ID + " AND w.id % 4 = 0");

            jdbcTemplate.execute("ANALYZE words");
            jdbcTemplate.execute("ANALYZE sentence_practices");
            jdbcTemplate.execute("ANALYZE word_reviews");

            queryPlanSeeded = true;
        }
    }

    private JsonNode explainJson(String sql) throws Exception {
        String explainSql = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + sql;
        String json = jdbcTemplate.queryForObject(explainSql, String.class);
        org.junit.jupiter.api.Assertions.assertNotNull(json);
        return objectMapper.readTree(json).get(0);
    }

    @Test
    @Order(9)
    void guestCleanupShouldRunAgainstTheSchemaFlywayBuilt() {
        // Every other test of the cleanup runs on H2, whose schema Hibernate derives from the
        // entities. The cleanup does not go through Hibernate: it is twenty hand-written
        // DELETEs naming tables and columns directly, five of which belong to tables no entity
        // maps a foreign key for. A wrong name there is invisible until 03:30 on the server.
        // This runs the whole statement list against the schema the migrations actually build.
        jdbcTemplate.update(
                "INSERT INTO users (email, password_hash, display_name, user_tag, created_at, is_guest)"
                        + " VALUES (?, ?, ?, ?, ?, TRUE)",
                "guest-old@guest.klioai.app", "x", "Guest", "#90001",
                Timestamp.valueOf(LocalDateTime.now().minusDays(60)));
        jdbcTemplate.update(
                "INSERT INTO users (email, password_hash, display_name, user_tag, created_at, is_guest)"
                        + " VALUES (?, ?, ?, ?, ?, TRUE)",
                "guest-new@guest.klioai.app", "x", "Guest", "#90002",
                Timestamp.valueOf(LocalDateTime.now().minusDays(1)));
        jdbcTemplate.update(
                "INSERT INTO users (email, password_hash, display_name, user_tag, created_at, is_guest)"
                        + " VALUES (?, ?, ?, ?, ?, FALSE)",
                "real-person@example.com", "x", "Eren", "#90003",
                Timestamp.valueOf(LocalDateTime.now().minusDays(60)));
        // Created long ago, used this morning: the rule is last use, not age.
        jdbcTemplate.update(
                "INSERT INTO users (email, password_hash, display_name, user_tag, created_at, last_seen_at, is_guest)"
                        + " VALUES (?, ?, ?, ?, ?, ?, TRUE)",
                "guest-daily@guest.klioai.app", "x", "Guest", "#90004",
                Timestamp.valueOf(LocalDateTime.now().minusDays(120)),
                Timestamp.valueOf(LocalDateTime.now().minusHours(2)));
        Long oldGuestId = jdbcTemplate.queryForObject(
                "SELECT id FROM users WHERE email = ?", Long.class, "guest-old@guest.klioai.app");
        // One child in a table with no foreign key to users, which is the case a cascade would
        // have missed.
        jdbcTemplate.update(
                "INSERT INTO feature_ratings (user_id, feature, stars) VALUES (?, 'TUTOR', 5)",
                oldGuestId);

        int deleted = guestAccountCleanupService.purgeBatch(LocalDateTime.now().minusDays(30), 50);

        org.junit.jupiter.api.Assertions.assertTrue(deleted >= 1, "the guest older than the window was not collected");
        org.junit.jupiter.api.Assertions.assertEquals(0, (int) jdbcTemplate.queryForObject(
                "SELECT count(*) FROM users WHERE email = 'guest-old@guest.klioai.app'", Integer.class));
        org.junit.jupiter.api.Assertions.assertEquals(0, (int) jdbcTemplate.queryForObject(
                "SELECT count(*) FROM feature_ratings WHERE user_id = ?", Integer.class, oldGuestId));
        org.junit.jupiter.api.Assertions.assertEquals(1, (int) jdbcTemplate.queryForObject(
                "SELECT count(*) FROM users WHERE email = 'guest-new@guest.klioai.app'", Integer.class),
                "a guest created yesterday is not old enough to collect");
        org.junit.jupiter.api.Assertions.assertEquals(1, (int) jdbcTemplate.queryForObject(
                "SELECT count(*) FROM users WHERE email = 'real-person@example.com'", Integer.class),
                "an account somebody signed in to was deleted");
        org.junit.jupiter.api.Assertions.assertEquals(1, (int) jdbcTemplate.queryForObject(
                "SELECT count(*) FROM users WHERE email = 'guest-daily@guest.klioai.app'", Integer.class),
                "a guest who used the app this morning was collected for being old");
    }

    private void collectIndexNames(JsonNode node, Set<String> names) {
        if (node.has("Index Name")) {
            names.add(node.get("Index Name").asText());
        }
        if (node.has("Plans")) {
            for (JsonNode child : node.get("Plans")) {
                collectIndexNames(child, names);
            }
        }
    }

    private boolean hasNodeType(JsonNode node, String targetType) {
        if (targetType.equals(node.path("Node Type").asText())) {
            return true;
        }
        if (node.has("Plans")) {
            for (JsonNode child : node.get("Plans")) {
                if (hasNodeType(child, targetType)) {
                    return true;
                }
            }
        }
        return false;
    }
}
