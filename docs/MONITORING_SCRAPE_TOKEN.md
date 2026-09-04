# Letting Prometheus read the metrics

## What was wrong

`management.endpoints.web.exposure.include=health,prometheus` turned the
metrics endpoint on in production. `SecurityConfig` permitted only
`/actuator/health`, and `app.security.jwt.enforce-auth=true` sends everything
else to `anyRequest().authenticated()`. So `/actuator/prometheus` answered
**401** — to the internet, correctly, and to Prometheus, which had no
credentials in its scrape config.

The consequence was not a missing graph. `up{job="backend-actuator"}` stayed
**0**, so every rule under `monitoring/prometheus/alerts/` evaluated against no
data and could never fire. The alerting looked configured and saw nothing.

## Why a token

Two alternatives were considered and rejected against this topology:

**An IP allowlist.** Prometheus reaches the backend over the Docker network
(`backend:8082`); Caddy reaches it from the host through the published port.
Both arrive from private addresses, so no source check can tell an internal
scrape from an internet request.

**A separate management port.** `management.server.port` moves *all* actuator
endpoints, and the public `https://api.klioai.app/actuator/health` is
load-bearing: `scripts/deploy-backend-vps.ps1` smoke-tests it after every
deploy, and `smoke-prod-readiness.ps1`, `verify-rollout.ps1`,
`smoke-authenticated-ai-chat.ps1` and `smoke-security-cors-headers.ps1` all
call it. Moving it would break the deploy pipeline.

A bearer token is independent of both the edge configuration and the network
layout, and `MetricsScrapeTokenTest` pins its behaviour.

## Setting it up on the VPS

The token is not in git. It has to exist in two places with the same value.

Generate one:

```bash
openssl rand -hex 32
```

**1. The backend.** Add it to the environment the backend container reads
(the `.env` beside `docker-compose.yml`):

```
APP_OPS_METRICS_SCRAPE_TOKEN=<the value>
```

**2. Prometheus.** Write the same value, with no trailing newline, to the file
the compose mounts:

```bash
printf '%s' '<the value>' > monitoring/prometheus/scrape-token
chmod 600 monitoring/prometheus/scrape-token
```

Then restart both:

```bash
docker compose up -d backend
docker compose -f docker-compose.monitoring.yml up -d prometheus
```

## Checking it worked

From the VPS:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat monitoring/prometheus/scrape-token)" http://localhost:8082/actuator/prometheus
```

`200` means the scrape can read it. Then confirm Prometheus agrees — this is
the number that actually matters, because it is what the alert rules see:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=up{job="backend-actuator"}' | grep -o '"value":\[[^]]*\]'
```

The value must be `"1"`. While it is `0`, every alert is blind regardless of
what the rules say.

And confirm the endpoint is still shut to the internet:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://api.klioai.app/actuator/prometheus
```

`401` is the expected answer. A `200` there means the token leaked into a
request path that the edge forwards, and the token should be rotated.

## If the token is unset

`MetricsScrapeToken` treats an empty value as "no token configured" and
rejects every request, so a missing setting leaves the endpoint behind normal
authentication rather than opening it. The failure mode is blind alerting, not
public metrics — which is the safe direction, and the state this document
exists to get out of.
