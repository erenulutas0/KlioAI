-- A learner gets an account on first launch, before they have told us who they are.
--
-- Until now the app asked for Google sign-in before it would show anything at all. In thirty
-- days 235 people opened it and 40 accounts came out of that: the other 195 were asked to
-- hand over an identity for a product they had not been allowed to try yet. A guest account
-- is created silently instead (POST /api/auth/guest), the learner talks to the tutor in the
-- first minute, and signing in with Google later turns this same row into a real account
-- (AuthController#googleLogin). Their words, their conversations and their id survive the
-- sign-in rather than being the price of it.
--
-- One column rather than a second table, because a guest is not a different kind of user:
-- it is a user whose name we do not know yet. Everything already keyed on users(id) keeps
-- working untouched, and conversion is an UPDATE of this row, not a copy of it.
--
-- The email is a generated guest-<uuid>@guest.klioai.app. The column is NOT NULL UNIQUE and
-- half the app reads it, so a guest needs one; that subdomain has no MX record, so the
-- address can never receive mail and no password reset can ever reach it. Conversion
-- overwrites it with the real one.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE;

-- The only query that reads this column across the whole table is the nightly cleanup's
-- "guests older than the retention window" (GuestAccountCleanupService). Partial on purpose:
-- guests that live long enough to be collected are a small minority of users, and a plain
-- index on created_at would be paid for on every insert by the accounts that belong to people.
CREATE INDEX IF NOT EXISTS idx_users_guest_created_at
    ON users (created_at)
    WHERE is_guest = TRUE;
