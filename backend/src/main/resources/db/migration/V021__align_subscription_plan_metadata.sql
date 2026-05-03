UPDATE subscription_plans
SET price = 149.99,
    currency = 'TRY',
    duration_days = 30,
    features = 'AI access with 30k daily token quota.'
WHERE name IN ('PREMIUM', 'PRO_MONTHLY');

UPDATE subscription_plans
SET price = 999.99,
    currency = 'TRY',
    duration_days = CASE WHEN name = 'PRO_ANNUAL' THEN 365 ELSE 30 END,
    features = 'AI access with 60k daily token quota.'
WHERE name IN ('PREMIUM_PLUS', 'PRO_ANNUAL');
