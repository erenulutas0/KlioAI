import 'package:flutter_test/flutter_test.dart';

/// The rule the profile header uses to decide whether to show PRO.
///
/// Extracted here as the pure decision it is. The screen showed "PRO Member" above a token
/// panel reading 0 / 8000 - the free tier - because the badge came from a separately loaded
/// subscription date while the panel came from the live entitlement. Same fact, two sources,
/// different answers, on one screen.
bool isPro({String? planCode, Object? explicitActive, String? subscriptionEndDate,
    required DateTime now}) {
  final plan = planCode?.trim().toUpperCase();
  if (plan != null && plan.isNotEmpty && plan != 'UNKNOWN') {
    return plan != 'FREE' && plan != 'FREE_TRIAL_7D';
  }
  if (explicitActive is bool && explicitActive) return true;
  if (explicitActive is String && explicitActive.toLowerCase() == 'true') return true;

  final raw = subscriptionEndDate?.trim();
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') return false;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return false;
  return parsed.isAfter(now);
}

void main() {
  final now = DateTime.utc(2026, 8, 22, 14, 0);

  test('the live plan code wins over a stale subscription date', () {
    // Exactly what was on screen: a cached date from just after the purchase, and a server
    // that had already moved the account back to free.
    expect(
      isPro(planCode: 'FREE', subscriptionEndDate: '2026-09-22T14:00:00Z', now: now),
      isFalse,
    );
  });

  test('a paid plan code shows PRO even with no date loaded yet', () {
    expect(isPro(planCode: 'PREMIUM', now: now), isTrue);
    expect(isPro(planCode: 'PREMIUM_PLUS', now: now), isTrue);
  });

  test('the free trial is not PRO', () {
    expect(isPro(planCode: 'FREE_TRIAL_7D', now: now), isFalse);
  });

  test('UNKNOWN means the server could not say, so fall through to the date', () {
    expect(isPro(planCode: 'UNKNOWN', subscriptionEndDate: '2026-09-22T14:00:00Z', now: now),
        isTrue);
    expect(isPro(planCode: 'UNKNOWN', subscriptionEndDate: '2026-07-22T14:00:00Z', now: now),
        isFalse);
  });

  test('an unreadable date does not grant the badge', () {
    // Used to return true "for backward compatibility" - entitlement granted on malformed
    // data, the same shape as a grading check defaulting to correct when it read nothing.
    expect(isPro(subscriptionEndDate: 'yakinda', now: now), isFalse);
    expect(isPro(subscriptionEndDate: '', now: now), isFalse);
    expect(isPro(subscriptionEndDate: 'null', now: now), isFalse);
    expect(isPro(now: now), isFalse);
  });

  test('an expired date is not PRO', () {
    expect(isPro(subscriptionEndDate: '2026-08-22T13:59:00Z', now: now), isFalse);
    expect(isPro(subscriptionEndDate: '2026-08-22T14:01:00Z', now: now), isTrue);
  });
}
