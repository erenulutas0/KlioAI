-- Daily content cache table (e.g., daily words/tests) generated centrally.
-- Stored in Postgres so content survives Redis flush/restarts.

CREATE TABLE IF NOT EXISTS daily_content (
    id BIGSERIAL PRIMARY KEY,
    content_date DATE NOT NULL,
    content_type VARCHAR(50) NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_daily_content_date_type
    ON daily_content (content_date, content_type);

