-- Persist AI entitlement tier separately from subscription_end_date so
-- plan-aware quotas can distinguish PREMIUM vs PREMIUM_PLUS.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS ai_plan_code VARCHAR(32) NOT NULL DEFAULT 'FREE';

-- Backfill existing active subscribers conservatively as PREMIUM.
UPDATE users
SET ai_plan_code = 'PREMIUM'
WHERE subscription_end_date IS NOT NULL
  AND subscription_end_date > NOW()
  AND (ai_plan_code IS NULL OR ai_plan_code = '' OR ai_plan_code = 'FREE');
