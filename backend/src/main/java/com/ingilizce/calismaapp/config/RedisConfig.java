package com.ingilizce.calismaapp.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.data.redis.connection.RedisPassword;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceClientConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

import java.time.Duration;

@Configuration
public class RedisConfig {

    private static final org.slf4j.Logger log =
            org.slf4j.LoggerFactory.getLogger(RedisConfig.class);

    @Value("${spring.data.redis.host}")
    private String redisHost;

    @Value("${spring.data.redis.port}")
    private int redisPort;

    @Value("${spring.data.redis.password:}")
    private String redisPassword;

    @Value("${spring.data.redis.database:0}")
    private int redisDatabase;

    @Value("${spring.data.redis.timeout:2000ms}")
    private Duration redisTimeout;

    @Value("${spring.data.redis.security.host:${spring.data.redis.host}}")
    private String securityRedisHost;

    @Value("${spring.data.redis.security.port:${spring.data.redis.port}}")
    private int securityRedisPort;

    @Value("${spring.data.redis.security.password:${spring.data.redis.password:}}")
    private String securityRedisPassword;

    @Value("${spring.data.redis.security.database:0}")
    private int securityRedisDatabase;

    @Value("${spring.data.redis.security.timeout:${spring.data.redis.timeout:2000ms}}")
    private Duration securityRedisTimeout;

    @Bean
    @Primary
    public LettuceConnectionFactory redisConnectionFactory() {
        return buildConnectionFactory(redisHost, redisPort, redisPassword, redisDatabase, redisTimeout);
    }

    @Bean(name = "securityRedisConnectionFactory")
    public LettuceConnectionFactory securityRedisConnectionFactory() {
        return buildConnectionFactory(
                securityRedisHost,
                securityRedisPort,
                securityRedisPassword,
                securityRedisDatabase,
                securityRedisTimeout);
    }

    @Bean
    public RedisTemplate<String, Object> redisTemplate(LettuceConnectionFactory redisConnectionFactory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(redisConnectionFactory);
        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.afterPropertiesSet();
        return template;
    }

    /**
     * The qualifier is load-bearing, not decoration.
     *
     * <p>There are two {@link LettuceConnectionFactory} beans and this parameter is resolved
     * by type. With two candidates Spring takes the {@code @Primary} one — the cache — unless
     * something names which is wanted. Matching on the parameter name is not something to
     * rely on: it needs parameter names retained at compile time, and it fails silently when
     * they are not, which is exactly what happened. Everything downstream looked correct;
     * the security Redis simply sat empty in production for months while quota counters and
     * rate-limit state accumulated in an instance configured to evict them.
     */
    @Bean(name = "securityStringRedisTemplate")
    public StringRedisTemplate securityStringRedisTemplate(
            @Qualifier("securityRedisConnectionFactory")
            LettuceConnectionFactory securityRedisConnectionFactory) {
        StringRedisTemplate template = new StringRedisTemplate();
        template.setConnectionFactory(securityRedisConnectionFactory);
        template.afterPropertiesSet();
        return template;
    }

    /**
     * Says out loud when the security Redis is not actually being used.
     *
     * <p>There are two instances on purpose. The main one runs {@code allkeys-lru} and is a
     * cache: under memory pressure it drops whatever was least recently touched. The
     * security one runs {@code noeviction} because what lives there must never disappear -
     * daily AI token counters, auth rate-limit state, trial-abuse records. A counter that
     * silently vanishes resets a learner's quota; a rate-limit block that vanishes unblocks
     * whoever it was holding back.
     *
     * <p>On 2026-08-22 the security instance was found completely empty in production while
     * every one of those keys sat in the main one, with correct hostnames in the container
     * environment, correct DNS, and no connection error in the logs. Nothing anywhere said
     * so. This log line is the thing that would have said so on the first boot.
     */
    @jakarta.annotation.PostConstruct
    void reportWhereSecurityStateIsActuallyGoing() {
        boolean sameEndpoint = redisHost.equals(securityRedisHost)
                && redisPort == securityRedisPort
                && redisDatabase == securityRedisDatabase;
        if (sameEndpoint) {
            log.warn("REDIS_SECURITY_NOT_ISOLATED host={} port={} db={} -"
                            + " quota counters, rate limits and abuse records are sharing the"
                            + " cache instance and can be evicted under memory pressure",
                    securityRedisHost, securityRedisPort, securityRedisDatabase);
        } else {
            log.info("Redis split: cache={}:{}/{} security={}:{}/{}",
                    redisHost, redisPort, redisDatabase,
                    securityRedisHost, securityRedisPort, securityRedisDatabase);
        }
    }

    private LettuceConnectionFactory buildConnectionFactory(String host,
                                                            int port,
                                                            String password,
                                                            int database,
                                                            Duration timeout) {
        RedisStandaloneConfiguration redisConfig = new RedisStandaloneConfiguration(host, port);
        redisConfig.setDatabase(database);
        if (password != null && !password.isBlank()) {
            redisConfig.setPassword(RedisPassword.of(password));
        }

        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
                .commandTimeout(timeout != null ? timeout : Duration.ofSeconds(2))
                .shutdownTimeout(Duration.ZERO)
                .build();

        return new LettuceConnectionFactory(redisConfig, clientConfig);
    }
}
