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
| `APP_BOOKS_TRANSLATE_MODEL` | *(blank)* | Which model translates. Blank uses the configured default. |

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

The backend service takes its environment from `env_file`, not from the deploy
directory's `.env`:

```yaml
  backend:
    env_file:
      - ../secrets/backend.env
      - ../secrets/redis.env
      - ../secrets/redis-security.env
```

So the switches go in `/opt/vocabmaster/secrets/backend.env`. Everything in that
file is injected into the container as-is; no compose edit is needed at all.

`/opt/vocabmaster/deploy/.env` is a different thing wearing the same name. It
feeds `${...}` substitution *inside* the compose file, so a key that the compose
file never mentions goes nowhere. Appending `APP_BOOKS_*` there looks like it
worked, restarts cleanly, and sets nothing.

Append with a leading newline and keep a backup — this file holds secrets, and
if it does not end in one, a plain append lands on the same line as the last
value and corrupts it:

```bash
cd /opt/vocabmaster
cp secrets/backend.env secrets/backend.env.bak
printf '\nAPP_BOOKS_IMPORT_ON_STARTUP=true\n' >> secrets/backend.env
tail -2 secrets/backend.env
```

Blank lines in an env file are ignored, so the leading newline is free
insurance. `tail -2` shows only what you just added, not the secrets above it.

Then confirm it actually arrived, from inside the running container. This is the
only check that settles it — a restart that changed nothing looks identical to
one that worked:

```bash
cd /opt/vocabmaster/deploy
docker compose -f docker-compose.app.yml up -d --force-recreate backend
sleep 25 && docker compose -f docker-compose.app.yml exec -T backend env | grep APP_BOOKS
```

If that prints nothing, stop. Nothing downstream can work, and the log will be
empty in a way that looks like broken code rather than an unset variable.

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

## Comparing two models on the same sentences

The shelf is translated once and read for years, so a better model is a one-off
cost against a permanent gain. The difference is small enough in money that the
only real question is whether it is visible in the Turkish -- and the only way
to answer that is to run the same sentences through both and read them.

Peter Rabbit is the book for this: 58 sentences, so a full pass is seconds and
fractions of a cent.

Translation only touches sentences that have no translation yet, so pointing a
second model at an already-translated book does nothing at all. Re-import first
-- it replaces the sentences, which drops their translations with them:

```bash
cd /opt/vocabmaster
sed -i '/APP_BOOKS_/d' secrets/backend.env
printf '
APP_BOOKS_IMPORT_ON_STARTUP=true
APP_BOOKS_TRANSLATE_ON_STARTUP=100
APP_BOOKS_TRANSLATE_SLUG=peter-rabbit
APP_BOOKS_TRANSLATE_MODEL=openai/gpt-oss-120b
' >> secrets/backend.env
cd deploy && docker compose -f docker-compose.app.yml up -d --force-recreate backend
sleep 60 && docker compose -f docker-compose.app.yml logs --tail=500 backend | grep BOOKS
```

Then read the same ten sentences and compare them against the previous model's,
which the log line records by name. Judge the concrete nouns hardest: a learner
taps a word to find out what it means, so "blackberries" coming back as the
wrong berry teaches them the wrong word, while a slightly stiff clause does not.

## Freezing a book someone has read

Machine translation is good at the easy end of this shelf and poor at the hard
one -- about a fifth of Peter Rabbit's sentences came back with a real error,
four fifths of Conrad's. A wrong translation teaches worse than none, because a
learner cannot see that it is wrong, so a book is only shown with translations
once a person has read them.

Reading them is not enough on its own: an import rewrites every sentence row, so
the next one throws the reading away. What was checked has to go into
`backend/src/main/resources/books/verified/<slug>.tsv`, which the import applies
and the translation run then skips.

Export what is in the database as the file's own format -- `-At -F` gives
tuples-only, tab-separated output, which is exactly it:

```bash
docker exec -i vocabmaster-postgres psql -U postgres -d EnglishApp -At -F$'	'   -c "SELECT s.text, s.translation FROM book_sentences s JOIN books b ON b.id = s.book_id       WHERE b.slug = 'peter-rabbit' AND s.translation IS NOT NULL ORDER BY s.sentence_index;"
```

Paste that under the file's header, commit, and the book is reproducible: every
later import restores exactly the translation that was read, and no model is
ever asked for those sentences again.

Two counts guard it. The import logs `verified=applied/onFile`, and they should
be equal — a difference means sentences that no longer match their corrections,
which is otherwise completely silent. And `VerifiedTranslationsTest` fails the
build on any line that matches nothing in the book.

## The audio cache is what makes listening affordable

The reader speaks a sentence by asking Piper for it, and Piper is a native
process forked per request on the same box that serves everything else. What
keeps that from being a per-tap cost is the cache: synthesis is deterministic
for a given (voice, text), so a sentence is generated once and every later
reader of that book is served the file.

The cache therefore has to outlive the container. In the repository's
`docker-compose.yml` it does — a named `tts_cache` volume mounted at
`/var/cache/piper-tts`. Production uses `docker-compose.app.yml`, which is not
in the repository, so this is worth confirming there rather than assuming:

```bash
cd /opt/vocabmaster/deploy
grep -n "piper-tts" docker-compose.app.yml
docker compose -f docker-compose.app.yml exec -T backend sh -lc 'ls /var/cache/piper-tts | wc -l'
```

The first should name a volume, not just the environment variable. The second
should be non-zero once anyone has played a sentence, and should stay non-zero
across a `--force-recreate`. If it resets, the cache lives inside the container
and every restart throws away every sentence anyone has ever listened to --
which is invisible except as CPU on a shared machine.

## Checking the result

```sql
SELECT b.slug, COUNT(*) AS sentences,
       COUNT(s.translation) AS translated
FROM books b JOIN book_sentences s ON s.book_id = b.id
GROUP BY b.slug ORDER BY b.slug;
```
