ALTER TABLE device_push_tokens
    ADD COLUMN IF NOT EXISTS daily_reminders_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_daily_reminders
    ON device_push_tokens(enabled, daily_reminders_enabled);
