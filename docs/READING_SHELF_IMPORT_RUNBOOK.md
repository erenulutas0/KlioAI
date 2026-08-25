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

First find out whether that file already reads a `.env`:

```bash
cd /opt/vocabmaster/deploy
grep -n "env_file" docker-compose.app.yml
```

**If `env_file` is present**, no compose edit is needed. Put the variables in the
`.env` it points at and skip to *Running a job*.

**If it is not**, add the four lines once, next to the other `APP_` variables.
This preserves the indentation of the line it anchors to:

```bash
cd /opt/vocabmaster/deploy
cp docker-compose.app.yml docker-compose.app.yml.bak
awk '{print} /APP_SECURITY_JWT_SECRET:/{match($0,/^[ \t]*/); ind=substr($0,1,RLENGTH); print ind "APP_BOOKS_IMPORT_ON_STARTUP: ${APP_BOOKS_IMPORT_ON_STARTUP:-false}"; print ind "APP_BOOKS_TRANSLATE_ON_STARTUP: ${APP_BOOKS_TRANSLATE_ON_STARTUP:-0}"; print ind "APP_BOOKS_TRANSLATE_SLUG: ${APP_BOOKS_TRANSLATE_SLUG:-}"; print ind "APP_BOOKS_TRANSLATE_INTO: ${APP_BOOKS_TRANSLATE_INTO:-Turkish}"}' docker-compose.app.yml.bak > docker-compose.app.yml
docker compose -f docker-compose.app.yml config >/dev/null && echo "compose still valid"
```

The `${VAR:-default}` form means this is the only compose edit ever needed —
every later job is a `.env` change and a restart.

## Running a job

### 1. Import the shelf (free, do this first)

```bash
cd /opt/vocabmaster/deploy
echo "APP_BOOKS_IMPORT_ON_STARTUP=true" >> .env
docker compose -f docker-compose.app.yml up -d --force-recreate backend
docker compose -f docker-compose.app.yml logs --tail=200 backend | grep BOOKS
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
docker compose -f docker-compose.app.yml logs --tail=200 backend | grep "BOOKS translate"
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
