package com.ingilizce.calismaapp.config;

import org.springframework.beans.factory.annotation.Value;
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

    @Bean(name = "securityStringRedisTemplate")
    public StringRedisTemplate securityStringRedisTemplate(
            LettuceConnectionFactory securityRedisConnectionFactory) {
        StringRedisTemplate template = new StringRedisTemplate();
        template.setConnectionFactory(securityRedisConnectionFactory);
        template.afterPropertiesSet();
        return template;
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
