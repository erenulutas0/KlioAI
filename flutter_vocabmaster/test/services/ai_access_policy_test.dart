import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/ai_access_policy.dart';

void main() {
  group('hasPracticeAccess', () {
    test('allows access when aiAccessEnabled is true', () {
      expect(
        hasPracticeAccess({
          'aiAccessEnabled': true,
          'subscriptionEndDate': null,
        }),
        isTrue,
      );
    });

    test('denies access when aiAccessEnabled is explicitly false', () {
      expect(
        hasPracticeAccess({
          'aiAccessEnabled': false,
          'trialActive': true,
          'tokenLimit': 25000,
        }),
        isFalse,
      );
    });

    test('allows access for active free trial snapshot', () {
      expect(
        hasPracticeAccess({
          'trialActive': true,
          'planCode': 'FREE_TRIAL_7D',
        }),
        isTrue,
      );
    });

    test('falls back to active subscription date', () {
      expect(
        hasPracticeAccess({
          'subscriptionEndDate': DateTime.now()
              .toUtc()
              .add(const Duration(days: 7))
              .toIso8601String(),
        }),
        isTrue,
      );
    });

    test('allows access for fresh account when quota snapshot is not merged yet', () {
      expect(
        hasPracticeAccess({
          'aiPlanCode': 'FREE',
          'createdAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        }),
        isTrue,
      );
    });

    test('denies fresh-account fallback when trialEligible is false', () {
      expect(
        hasPracticeAccess({
          'aiPlanCode': 'FREE',
          'trialEligible': false,
          'createdAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        }),
        isFalse,
      );
    });
  });
}

