# Knowing when it breaks

## What was actually there

`monitoring/` holds twenty-two Prometheus alert rules, an Alertmanager routing
table and Grafana dashboards. None of it could ever have woken anybody:

- **Prometheus was never deployed.** `docker ps` on the VPS lists the backend,
  Caddy, Postgres and two Redis instances. No Prometheus, no Alertmanager, no
  exporters — and no `monitoring/` directory on the server at all.
- **The alert receiver is a test stub.** `docker-compose.monitoring.yml` points
  Alertmanager at `alert-webhook`, which is `mendhak/http-https-echo` — a
  container that prints what it receives to its own stdout. Even fully
  deployed, every alert would have ended in a log nobody reads.

So the alerting had the worst possible shape: it looked configured, and every
alarm resolved to the same silence as everything working.

## What replaces it, for now

Two checks on a free external uptime service, and nothing new running on the
server. External matters: a monitor living on the same machine cannot report
that the machine is gone.

| Check | URL | Meaning of a failure |
|---|---|---|
| Backend | `https://api.klioai.app/actuator/health` | The server, database or Redis is gone |
| AI provider | `https://api.klioai.app/api/ops/ai-status` | Groq is failing, or the probe has stopped running |

Both are public and unauthenticated, because a monitor cannot log in.
`/api/ops/ai-status` answers with one word and a timestamp: no counts, no model
names, no provider errors.

### Setting it up

On UptimeRobot (or any equivalent — Better Stack, Hetrix, Cronitor):

1. **New monitor → HTTP(s)**, URL `https://api.klioai.app/actuator/health`,
   interval 5 minutes.
2. **New monitor → HTTP(s)**, URL `https://api.klioai.app/api/ops/ai-status`,
   interval 5 minutes.
3. Add a notification channel that reaches a phone. Email is the default and is
   the one most easily missed; the mobile app's push, or a Telegram bot, is
   better for something you want to know about at 2am.

Nothing else. No token, no container, no config file on the server.

## What `/api/ops/ai-status` means

The synthetic probe calls the AI provider every 15 minutes with a fixed cheap
prompt, outside all per-user quota accounting. The endpoint reports what it
learned:

| Status | HTTP | When |
|---|---|---|
| `UP` | 200 | The last probe got the expected answer |
| `UNKNOWN` | 200 | No probe yet and the process started recently, or probing is switched off |
| `DOWN` | 503 | Two consecutive probes failed |
| `STALE` | 503 | No probe has run for 45 minutes |

Three of those choices are deliberate and worth keeping:

**Two failures, not one.** Providers blip. A monitor that pages on every blip
gets muted, and a muted monitor is the same as no monitor.

**`UNKNOWN` is quiet.** A restart leaves up to fifteen minutes before the first
probe fires. Paging on every deploy would train you to ignore it.

**`STALE` alerts.** If the scheduler dies, the last answer stops being current,
and reporting `UP` from hour-old evidence would repeat exactly the mistake this
document is about — a monitor that cannot tell "checked, fine" from "not
checking". `STALE` also wins over `DOWN` when both apply, because "I have not
looked recently" is the honest statement.

## Why not a Spring HealthIndicator

A new indicator joins the aggregate behind `/actuator/health`, which is what
the container's own healthcheck polls. A Groq outage would then have marked the
container unhealthy and had Docker restart a backend that was working perfectly.

## When to revisit

When there is enough traffic that the question changes from "is it up?" to
"what is slow, and since when?". At that point the Prometheus stack earns its
six containers — and its Alertmanager needs a real receiver before it is worth
starting. The rules under `monitoring/prometheus/alerts/` are still there and
still correct; they are waiting on a stack to run them, and
`docs/MONITORING_SCRAPE_TOKEN.md` covers the credential they will need.
