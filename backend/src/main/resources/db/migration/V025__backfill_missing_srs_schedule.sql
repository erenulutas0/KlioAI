-- Words added before SRS initialisation was wired into WordService.saveWord were stored
-- with next_review_date NULL. The due query uses next_review_date <= :today, and NULL never
-- satisfies <=, so those words could never surface for review -- and a word only got a
-- schedule by being reviewed, which it could not be. Measured on production: 18 of 20 rows
-- had no schedule.
--
-- Give every unscheduled word a date, and fill the other SM-2 columns with the same
-- defaults initializeWordForSRS uses. The dates are spread over the coming week rather than
-- all landing today, so a user with a large backlog is not handed one enormous session on
-- the day this ships.

UPDATE words w
SET next_review_date = CURRENT_DATE + s.offset_days,
    review_count     = COALESCE(w.review_count, 0),
    ease_factor      = COALESCE(w.ease_factor, 2.5)
FROM (
    -- ROW_NUMBER() is bigint and PostgreSQL has no date + bigint operator, so the cast is
    -- load-bearing: without it Flyway fails on startup and the backend does not come up.
    SELECT id,
           (((ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id) - 1) % 7))::int AS offset_days
    FROM words
    WHERE next_review_date IS NULL
) s
WHERE w.id = s.id;
