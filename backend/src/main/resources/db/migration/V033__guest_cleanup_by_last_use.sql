-- A guest is collected for not being used, not for being old.
--
-- V032's index served a cleanup that read created_at, and the cleanup was wrong: a learner
-- who had been talking to the tutor every day since January would have had their account,
-- their words and every conversation deleted on the thirty-first day, while they were using
-- it. What makes a guest account worth collecting is that nobody can get back into it -- the
-- refresh token is the only key, it lives thirty days, and it is renewed every time the app
-- is opened. So the two now agree: a guest last seen more than thirty days ago is a guest
-- whose session has expired and who has no email, no password and no Google account to sign
-- in with. That row is unreachable, and only then is it deleted.
--
-- COALESCE because last_seen_at is null until the first authenticated request, which is a
-- guest that was created and never used -- the commonest kind of all.

DROP INDEX IF EXISTS idx_users_guest_created_at;

CREATE INDEX IF NOT EXISTS idx_users_guest_last_active
    ON users ((COALESCE(last_seen_at, created_at)))
    WHERE is_guest = TRUE;
