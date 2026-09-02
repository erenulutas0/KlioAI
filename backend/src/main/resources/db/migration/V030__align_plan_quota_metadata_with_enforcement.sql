-- What each plan promises, made equal to what the code actually grants.
--
-- Three things had drifted apart, and all three were visible to a paying
-- customer while being invisible to us:
--
--   FREE said "1500 daily AI token quota" (V023). Enforcement gives 8000.
--
--   PRO_ANNUAL said "60k daily token quota", because V021 updated it in the
--   same statement as PREMIUM_PLUS. It never had 60k: AiPlanTier resolves a
--   plan name by looking for "PLUS" first and then "PREMIUM|PRO", and
--   PRO_ANNUAL contains PRO, so it has always resolved to PREMIUM. The
--   annual subscriber was advertised twice the quota of the monthly one and
--   given exactly the same.
--
--   PRO_ANNUAL was priced 999.99 here while the store sells it at 1199.99.
--
-- The quota is now 100000 for both PRO plans, matching
-- premium-daily-token-quota-per-user in application-prod.properties. Annual
-- buys a discount, not a bigger allowance -- which is the ordinary shape of
-- these things and removes the reason the two rows ever differed.
--
-- PREMIUM_PLUS keeps no product and no price change. It is raised to 250k
-- only so the ladder stays in order: leaving it at 60k under a 100k PREMIUM
-- would be a tier that costs more and gives less, waiting for someone to sell
-- it by mistake.

UPDATE subscription_plans
SET features = 'Base app access with 8k daily AI token quota.'
WHERE name = 'FREE';

UPDATE subscription_plans
SET price = 149.99,
    currency = 'TRY',
    duration_days = 30,
    features = 'AI access with 100k daily token quota.'
WHERE name IN ('PREMIUM', 'PRO_MONTHLY');

UPDATE subscription_plans
SET price = 1199.99,
    currency = 'TRY',
    duration_days = 365,
    features = 'AI access with 100k daily token quota.'
WHERE name = 'PRO_ANNUAL';

UPDATE subscription_plans
SET features = 'AI access with 250k daily token quota.'
WHERE name = 'PREMIUM_PLUS';
