-- Ensure at most one progress row per user.
-- Keep the oldest row when duplicates exist.
DELETE FROM user_progress up
USING (
    SELECT user_id, MIN(id) AS keep_id
    FROM user_progress
    WHERE user_id IS NOT NULL
    GROUP BY user_id
    HAVING COUNT(*) > 1
) dup
WHERE up.user_id = dup.user_id
  AND up.id <> dup.keep_id;

CREATE UNIQUE INDEX IF NOT EXISTS ux_user_progress_user_id
    ON user_progress (user_id)
    WHERE user_id IS NOT NULL;
