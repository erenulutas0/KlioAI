# The security Redis is provisioned and unused

**Status:** fixed 2026-08-23. Found 2026-08-22 while resetting a development quota.
Kept as the write-up of how it was found, because the shape recurs.

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

**Ruled out on 2026-08-23.** The startup line added below printed, in production:

```
Redis split: cache=app-redis-main:6379/0 security=app-redis-security:6379/0
```

So the property resolves correctly and the security connection factory is built against the
right host. The earlier theory — that the `@Value` default was being taken — is wrong.

That leaves two candidates, and they are distinguishable:

1. The bean injected into the four services is not `securityStringRedisTemplate`. Spring
   Boot auto-configures its own `StringRedisTemplate` on the `@Primary` factory, so two
   beans of that type exist; if the `@Qualifier` is not being honoured, the services get the
   cache one. Note the constructors carry `@Autowired(required = false)` on the *parameter*
   alongside the `@Qualifier`, which is unusual enough to be worth suspecting.
2. Something writes those keys that is not one of the four services. Ruled unlikely: the
   prefixes are private constants and grep finds no other writer.

**The decisive test**, which has not been run yet: make one AI call through the app, then
scan both instances for `ai:tokens:day:*`. Whichever instance the new key lands in is the
answer, and it takes two minutes.

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

## The cause

The security template's factory parameter is resolved by type. Two
`LettuceConnectionFactory` beans exist, so Spring took the `@Primary` one — the cache —
because nothing named which was wanted:

```java
public StringRedisTemplate securityStringRedisTemplate(
        LettuceConnectionFactory securityRedisConnectionFactory)   // resolved by TYPE
```

Every layer above this was correct and said so: the hostnames, DNS, the active profiles,
and the startup line printing two distinct endpoints. The factory really was built against
`app-redis-security`. The template just never received it.

Adding `@Qualifier("securityRedisConnectionFactory")` to that parameter fixes it, and
`RedisSecurityIsolationTest` fails without it — it was written first and reproduced the bug
before the fix went in:

```
expected: <security-host.invalid> but was: <cache-host.invalid>
```

A related fact worth knowing: there is only one `StringRedisTemplate` bean in the context.
Spring Boot's auto-configured one never appears, so all four security services share the
single `securityStringRedisTemplate` — which is why one mis-resolved parameter moved every
quota counter, rate limit and abuse record onto the cache at once.

## What it cost

Nothing yet — there are no users, and nine keys against a 256mb cap never triggered an
eviction. Had traffic arrived first, quotas would have reset and rate-limit blocks lifted at
random, with no error and no log line anywhere.
