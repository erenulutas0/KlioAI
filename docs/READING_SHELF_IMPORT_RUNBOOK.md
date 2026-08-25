# Reading Shelf: Import and Translation Runbook

How the six shipped books get into the database, and how they get translated.

Both are one-off content jobs. You run them once per book and then never again.

## Why this is not an API call

`BookAdminController` exposes `/api/admin/books/*` and is the natural way to do
this. It is unreachable today, and deliberately so:

- `User.role` is initialised to `USER`, and nothing in the codebase promotes
  anyone to `ADMIN`.
- The endpoints check `hasRole("ADMIN")`, which no account can satisfy.

Minting an admin account to run a content job would grant a real user permanent
access to every other admin power in the app. That is a large, lasting change to
make for a job that runs twice. So the shelf loads from a switch on the
*deployment* instead of a role on a *person*: `BookShelfBootstrap` runs at boot,
reads four environment variables, and does nothing at all unless they are set.

The endpoints stay in place for when there is a real admin account.

## The four variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `APP_BOOKS_IMPORT_ON_STARTUP` | `false` | Import the whole shelf at boot. Free, idempotent by slug. |
| `APP_BOOKS_TRANSLATE_ON_STARTUP` | `0` | Sentences to translate at boot. **Spends money.** `0` disables it. |
| `APP_BOOKS_TRANSLATE_SLUG` | *(blank)* | Which book. Blank means the first shelved book with untranslated sentences left. |
| `APP_BOOKS_TRANSLATE_INTO` | `Turkish` | Target language. |

Both jobs are safe to leave switched on by accident, which is the point — a flag
that is dangerous when forgotten will eventually be forgotten:

- Import re-segments text that is already in the build. Running it again after a
  segmenter fix corrects every book in place.
- Translation only ever looks at sentences with no translation yet. The second
  boot after a finished book asks the model for nothing and spends nothing.

A failure in either never fails the deployment. A missing book is a missing
feature; a backend that will not start is an outage for the whole app.

## Production: where the switches live

Production does **not** use the repository's `docker-compose.yml`. It uses
`/opt/vocabmaster/deploy/docker-compose.app.yml` on the VPS, which is not in the
repository — `scripts/deploy-backend-vps.ps1` only checks that it exists, and
never uploads it. So the variables have to be added there, once.

Do not infer this from the compose file. `env_file:` being present proves
nothing about whether the `.env` you just edited reaches the container: on this
stack the deploy directory's `.env` feeds `${...}` *substitution* inside the
compose file, and only keys named in a service's `environment:` block are
injected into it. Appending to `.env` and restarting therefore looks like it
worked and changes nothing at all.

The only answer that settles it comes from inside the running container:

```bash
cd /opt/vocabmaster/deploy
docker compose -f docker-compose.app.yml exec -T backend env | grep APP_BOOKS
```

**If the variables are listed**, they are reaching the app. Skip to *Running a
job*.

**If nothing prints**, name them in the backend service's `environment:` block.
This copies the indentation of the line it anchors to, and the `test` refuses to
go on unless that anchor is unique:

```bash
cd /opt/vocabmaster/deploy
n=$(grep -c "APP_SECURITY_JWT_SECRET:" docker-compose.app.yml) && echo "anchors: $n" && test "$n" = "1"
cp docker-compose.app.yml docker-compose.app.yml.bak
awk '{print} /APP_SECURITY_JWT_SECRET:/{match($0,/^[ 	]*/); ind=substr($0,1,RLENGTH); print ind "APP_BOOKS_IMPORT_ON_STARTUP: ${APP_BOOKS_IMPORT_ON_STARTUP:-false}"; print ind "APP_BOOKS_TRANSLATE_ON_STARTUP: ${APP_BOOKS_TRANSLATE_ON_STARTUP:-0}"; print ind "APP_BOOKS_TRANSLATE_SLUG: ${APP_BOOKS_TRANSLATE_SLUG:-}"; print ind "APP_BOOKS_TRANSLATE_INTO: ${APP_BOOKS_TRANSLATE_INTO:-Turkish}"}' docker-compose.app.yml.bak > docker-compose.app.yml
grep -n "APP_BOOKS" docker-compose.app.yml
docker compose -f docker-compose.app.yml config >/dev/null && echo "compose still valid"
```

`compose still valid` prints happily when awk inserted nothing, which is exactly
the case where you want to be stopped — so check that the `grep` really lists
four lines.

Written as `${VAR:-default}` so the compose file names the keys once and `.env`
still supplies the values: this is the only compose edit ever needed, and every
later job is a `.env` change plus a restart. Confirm it with the `exec ... env`
check above before trusting it.

## New code needs a deploy, not a restart

`docker compose up -d --force-recreate backend` rebuilds nothing. It recreates
the container from the image that is already there, which is exactly what a job
below needs — the variables are read fresh at boot — and is useless for shipping
code. New backend code reaches the VPS only through the deploy workflow, which
rsyncs the source and runs `docker compose build`.

So: deploy once when the code changes, recreate freely when only `.env` changed.

## Running a job

`up -d` returns as soon as the container starts; Spring Boot needs the better
part of a minute after that, and the bootstrap logs during boot. So there is a
window in which the job has not run yet and the log looks empty.

Do not try to catch it with `logs -f --tail=0` after the fact: that prints only
lines written from the moment you start following, and the boot lines are
already behind you. Wait for the boot to finish, then read back over it:

```bash
sleep 45 && docker compose -f docker-compose.app.yml logs --tail=500 backend | grep BOOKS
```

A translation run of a few hundred sentences takes longer than that. If the
line has not appeared, wait and run the `logs` half again — it reads history,
so it is safe to repeat.

### 1. Import the shelf (free, do this first)

```bash
cd /opt/vocabmaster/deploy
echo "APP_BOOKS_IMPORT_ON_STARTUP=true" >> .env
docker compose -f docker-compose.app.yml up -d --force-recreate backend
sleep 45 && docker compose -f docker-compose.app.yml logs --tail=500 backend | grep BOOKS
```

Expect one line per book and a total. Then take the switch back out:

```bash
sed -i '/APP_BOOKS_IMPORT_ON_STARTUP/d' .env
```

### 2. Translate a sample, and read the price

Never translate the whole shelf first. Translate a hundred sentences, read what
it actually cost, and only then decide.

```bash
cd /opt/vocabmaster/deploy
printf 'APP_BOOKS_TRANSLATE_ON_STARTUP=100\nAPP_BOOKS_TRANSLATE_SLUG=peter-rabbit\n' >> .env
docker compose -f docker-compose.app.yml up -d --force-recreate backend
sleep 45 && docker compose -f docker-compose.app.yml logs --tail=500 backend | grep "BOOKS translate"
```

The line that matters ends with `tokensPerSentence=N`. Multiply it by the
sentence count of the whole shelf (`BookLibraryTest` logs that total) and the
entire library's bill is known before any of it is spent.

**Remove the switch when the job is done**, or every restart runs another batch:

```bash
sed -i '/APP_BOOKS_TRANSLATE/d' .env
docker compose -f docker-compose.app.yml up -d --force-recreate backend
```

### 3. Translate the rest

Same as step 2 with a larger ceiling. Leave `APP_BOOKS_TRANSLATE_SLUG` unset to
work down the shelf: the bootstrap picks the first book that still has
untranslated sentences, so repeated deploys move through the library in order.

Batches commit individually, so a run that dies halfway keeps what it finished.
Run it again to pick up the rest.

## Checking the result

```sql
SELECT b.slug, COUNT(*) AS sentences,
       COUNT(s.translation) AS translated
FROM books b JOIN book_sentences s ON s.book_id = b.id
GROUP BY b.slug ORDER BY b.slug;
```
