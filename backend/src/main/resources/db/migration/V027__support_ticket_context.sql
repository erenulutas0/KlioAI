-- Machine-collected context on a support ticket, and a ticket type for flagging bad
-- generated content.
--
-- The gap this closes: for three months the app served hardcoded template sentences as if a
-- model had written them, and every one of those requests was recorded as a success. The
-- instrumentation could see that a call returned 200; it could not see that the sentence was
-- nonsense. Only a person can report that, and only if reporting costs them one tap.
--
-- Context is free-form JSON rather than columns because what is worth capturing will change
-- faster than the schema should, and an unrecognised key is better stored than dropped. It
-- carries the app version, the screen the report came from, and for a content report the
-- offending text -- so a tester does not have to write a bug report to be useful.

ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS context_json TEXT;

-- The type column is a string, so a new enum constant needs no schema change. Any CHECK
-- constraint on it would, though, so widen one if it exists.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE table_name = 'support_tickets' AND column_name = 'type'
    ) THEN
        BEGIN
            ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_type_check;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;
END $$;
