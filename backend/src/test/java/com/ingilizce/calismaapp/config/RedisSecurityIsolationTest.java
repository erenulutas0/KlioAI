package com.ingilizce.calismaapp.config;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.context.TestPropertySource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

/**
 * The security template must actually talk to the security instance.
 *
 * <p>Two Redis instances run in production with different eviction policies. The cache one
 * drops least-recently-used keys under memory pressure; the security one is configured
 * never to, because what lives there is daily AI token counters, auth rate-limit state and
 * trial-abuse records. A counter that silently vanishes resets a learner's quota; a block
 * that vanishes unblocks whoever it was holding.
 *
 * <p>In production the security instance was found completely empty while every one of
 * those keys sat in the cache. The hostnames were right, DNS resolved, the profile was
 * loaded, and startup logged the two endpoints correctly — the connection factory really is
 * built against the right host. What was wrong is one step further in: the template's
 * factory parameter is resolved by type, there are two beans of that type, and Spring falls
 * back to the {@code @Primary} one unless something disambiguates.
 *
 * <p>Nothing about that is visible in configuration, which is why it survived months. It is
 * visible here.
 */
@SpringBootTest
@TestPropertySource(properties = {
        "spring.data.redis.host=cache-host.invalid",
        "spring.data.redis.security.host=security-host.invalid"
})
class RedisSecurityIsolationTest {

    @Autowired
    @Qualifier("securityStringRedisTemplate")
    private StringRedisTemplate securityTemplate;

    // Named, not left to type resolution. Two beans of this type exist and leaving the
    // choice implicit is the very mistake this test was written about.
    @Autowired
    @Qualifier("redisConnectionFactory")
    private LettuceConnectionFactory cacheFactory;

    @Autowired
    @Qualifier("securityRedisConnectionFactory")
    private LettuceConnectionFactory securityFactory;

    @Test
    void theSecurityTemplateTalksToTheSecurityInstance() {
        LettuceConnectionFactory factory =
                (LettuceConnectionFactory) securityTemplate.getConnectionFactory();

        assertEquals("security-host.invalid", factory.getHostName(),
                "the security template is connected to the cache instance, so quota counters "
                        + "and rate limits can be evicted");
    }

    @Test
    void theTwoFactoriesPointAtDifferentInstances() {
        // If these ever collapse to one host the split is decorative, whatever the compose
        // file says: one instance evicts under pressure and the other does not.
        assertEquals("cache-host.invalid", cacheFactory.getHostName());
        assertEquals("security-host.invalid", securityFactory.getHostName());
        assertNotEquals(cacheFactory.getHostName(), securityFactory.getHostName());
    }

    @Test
    void theSecurityTemplateUsesTheSecurityFactoryAndNotTheCacheOne() {
        // The bug: this parameter resolves by type, both factories match, and Spring took
        // the @Primary one. The template's host was the cache's while every hostname in
        // configuration and every startup log said otherwise.
        assertNotEquals(cacheFactory.getHostName(),
                ((LettuceConnectionFactory) securityTemplate.getConnectionFactory()).getHostName());
    }
}
