CREATE TABLE IF NOT EXISTS notification_preferences (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE,
    daily_reminders_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    streak_guard_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    product_updates_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    subscription_alerts_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    social_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quiet_hours_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quiet_hours_start_local VARCHAR(5) NOT NULL DEFAULT '22:30',
    quiet_hours_end_local VARCHAR(5) NOT NULL DEFAULT '09:00',
    timezone VARCHAR(64) NOT NULL DEFAULT 'Europe/Istanbul',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_notification_preferences_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_daily
    ON notification_preferences(daily_reminders_enabled);

ALTER TABLE device_push_tokens
    ADD COLUMN IF NOT EXISTS timezone VARCHAR(64);

CREATE TABLE IF NOT EXISTS notification_delivery_log (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    device_push_token_id BIGINT,
    type VARCHAR(64) NOT NULL,
    title_hash VARCHAR(64),
    body_hash VARCHAR(64),
    status VARCHAR(32) NOT NULL,
    provider_message_id VARCHAR(255),
    provider_error_code VARCHAR(128),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_notification_delivery_log_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_notification_delivery_log_token FOREIGN KEY (device_push_token_id) REFERENCES device_push_tokens(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_user_created
    ON notification_delivery_log(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_type_created
    ON notification_delivery_log(type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_status_created
    ON notification_delivery_log(status, created_at DESC);
