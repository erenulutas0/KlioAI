CREATE TABLE IF NOT EXISTS device_push_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    token TEXT NOT NULL,
    platform VARCHAR(32),
    device_id VARCHAR(128),
    app_version VARCHAR(64),
    locale VARCHAR(32),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_device_push_tokens_token
    ON device_push_tokens(token);

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_user_enabled
    ON device_push_tokens(user_id, enabled);

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_last_seen
    ON device_push_tokens(last_seen_at DESC);
