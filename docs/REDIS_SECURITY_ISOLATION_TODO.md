# The security Redis is provisioned and unused

**Status:** open, not urgent. Found 2026-08-22 while resetting a development quota.

## What is wrong

Two Redis instances run in production and they are meant to hold different things:

| instance | policy | intent |
|---|---|---|
| `app-redis-main` | `allkeys-lru` | cache — evicting is fine |
| `app-redis-security` | `noeviction` | must never lose a key |

Four services ask for the second one by name — `AiTokenQuotaService`,
`AuthRateLimitService`, `AiRateLimitService`, `TrialAbuseProtectionService`, all with
`@Qualifier("securityStringRedisTemplate")`.

Every key they write is in the **main** instance. The security instance is **empty**.

```
vocabmaster-redis            → ai:tokens:day:*, ai:quota:day:*, auth:trial:device:*, auth:trial:ip:*
vocabmaster-redis-security   → (nothing)
```

## What it costs

The main instance evicts least-recently-used keys when it reaches its memory cap. The keys
sitting there include a learner's daily token counter, auth rate-limit state, and
trial-abuse records. Under memory pressure any of those can disappear with no error and no
log line: a quota silently resets, a rate-limit block silently lifts.

Not urgent today because there are no users — the main instance holds nine keys against a
256mb cap and will never evict. It becomes real the moment traffic does.

## What has been ruled out

- Container env is correct: `SPRING_DATA_REDIS_SECURITY_HOST=app-redis-security`,
  `SPRING_DATA_REDIS_HOST=app-redis-main`.
- DNS is correct: the two names resolve to different containers, `.3` and `.2`.
- Network aliases are correct on both containers.
- The `@Qualifier` has been on all four services since at least 2026-05-08, so this is not
  a recent regression and not a stale deployment.
- `RedisConfig` is an unconditional `@Configuration`, so the bean exists.
- No Redis connection error, no `NOAUTH`, no `WRONGPASS`, and no fallback warning in 24h of
  backend logs — the security template connects successfully, just not to the security
  instance.

So `securityRedisHost` is resolving to the main host, which means the `@Value` default in
`RedisConfig` — `${spring.data.redis.security.host:${spring.data.redis.host}}` — is being
taken even though the property is set. The reason for that is the open question.

## Where to look next

- `/actuator/env` is deliberately not exposed. Expose it briefly on a non-production boot,
  or log `securityRedisHost` at startup, and read what the field actually resolved to.
- Check whether the `docker` profile is active in the container
  (`SPRING_PROFILES_ACTIVE`); `application-docker.properties` is what declares
  `spring.data.redis.security.host`, and without that profile the value depends entirely on
  relaxed binding of the environment variable.
- If the cause turns out to be binding, replace the four `@Value` fields with a
  `@ConfigurationProperties` record, which binds explicitly rather than by convention.

## Already done

`RedisConfig` now logs the two endpoints at startup and warns `REDIS_SECURITY_NOT_ISOLATED`
when they are the same. That does not fix anything; it means the next person is told rather
than having to find it while doing something else.
