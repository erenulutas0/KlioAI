import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_subscription_page.dart';

/// Whether a subscription is active is a question about time, and this used to
/// answer it by asking whether the end-date field was filled in.
///
/// A Google Play test purchase has a compressed period — a monthly plan ends in
/// minutes — so within the same session the screen said "Aboneliğin aktif.
/// Bitiş: 24 Ağustos 2026" while the AI quota endpoint had correctly dropped
/// back to the free plan and the profile read "Ücretsiz plan". The same thing
/// happens to any real subscriber the day after theirs lapses.
void main() {
  String iso(Duration offset) =>
      DateTime.now().add(offset).toIso8601String();

  group('an explicit flag from the server always wins', () {
    test('true means active', () {
      expect(
        debugIsActiveSubscription(<String, dynamic>{
          'isActive': true,
          'subscriptionEndDate': iso(const Duration(days: -30)),
        }),
        isTrue,
      );
    });

    test('false means not active, whatever the date says', () {
      expect(
        debugIsActiveSubscription(<String, dynamic>{
          'isActive': false,
          'subscriptionEndDate': iso(const Duration(days: 30)),
        }),
        isFalse,
      );
    });
  });

  group('falling back to the end date', () {
    test('a future end date is active', () {
      expect(
        debugIsActiveSubscription(<String, dynamic>{
          'subscriptionEndDate': iso(const Duration(days: 30)),
        }),
        isTrue,
      );
    });

    test('an end date that has passed is not', () {
      expect(
        debugIsActiveSubscription(<String, dynamic>{
          'subscriptionEndDate': iso(const Duration(minutes: -5)),
        }),
        isFalse,
        reason: 'an expired subscription was reported as active',
      );
    });

    test('no end date is not active', () {
      expect(debugIsActiveSubscription(<String, dynamic>{}), isFalse);
      expect(
        debugIsActiveSubscription(<String, dynamic>{'subscriptionEndDate': null}),
        isFalse,
      );
      expect(
        debugIsActiveSubscription(<String, dynamic>{'endDate': '  '}),
        isFalse,
      );
    });

    test('a date shape we cannot read stays lenient', () {
      // Telling someone who paid that they did not is the worse mistake, and
      // this branch only runs when the server sent something unexpected.
      expect(
        debugIsActiveSubscription(<String, dynamic>{'endDate': 'sometime soon'}),
        isTrue,
      );
    });
  });
}
