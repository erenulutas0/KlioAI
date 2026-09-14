import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/rating_prompt_service.dart';

/// How often "how was this?" may be asked, across every place that asks it.
///
/// The question comes from the tutor and from the sheet after reading, writing and a daily
/// session, and one learner can finish all four in one evening. These pin the difference
/// between asking and nagging.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  RatingPromptService service() => RatingPromptService(clock: () => now);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 9, 14, 20);
  });

  test('a learner who has never been asked is asked', () async {
    expect(await service().shouldAsk('TUTOR'), isTrue);
  });

  test('one question an evening, whatever it is about', () async {
    await service().recordAsked('TUTOR');

    now = now.add(const Duration(hours: 2));
    expect(await service().shouldAsk('READING'), isFalse);

    now = now.add(const Duration(hours: 19));
    expect(await service().shouldAsk('READING'), isTrue);
  });

  test('the same feature waits days, not hours', () async {
    await service().recordAsked('TUTOR');

    now = now.add(const Duration(days: 1));
    expect(await service().shouldAsk('TUTOR'), isFalse);

    now = now.add(const Duration(days: 2, minutes: 1));
    expect(await service().shouldAsk('TUTOR'), isTrue);
  });

  test('closing it three times is taken as an answer', () async {
    await service().recordDismissed();
    await service().recordDismissed();
    expect(await service().shouldAsk('TUTOR'), isTrue);

    await service().recordDismissed();
    now = now.add(const Duration(days: 30));
    expect(await service().shouldAsk('TUTOR'), isFalse);
  });

  test('a rating between two closes starts the count again', () async {
    await service().recordDismissed();
    await service().recordDismissed();
    await service().recordAnswered();
    await service().recordDismissed();

    expect(await service().shouldAsk('SESSION'), isTrue);
  });

  test('asking to stop on one screen stops every screen, for good', () async {
    await service().recordOptedOut();
    // Nothing afterwards brings it back, not even a rating from a sheet already open.
    await service().recordAnswered();

    now = now.add(const Duration(days: 365));
    for (final String feature in <String>['TUTOR', 'READING', 'WRITING', 'SESSION']) {
      expect(await service().shouldAsk(feature), isFalse, reason: feature);
    }
  });

  test('a stamp it cannot read does not silence the question for ever', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      RatingPromptService.lastAnyKey: 'not a date',
    });

    expect(await service().shouldAsk('TUTOR'), isTrue);
  });

  test('low stars ask for a note, and only five open the store', () {
    expect(<int>[1, 2, 3].every(nfRatingWantsNote), isTrue);
    expect(<int>[4, 5].any(nfRatingWantsNote), isFalse);
    expect(nfRatingEarnsStoreReview(5), isTrue);
    expect(nfRatingEarnsStoreReview(4), isFalse);
  });
}
