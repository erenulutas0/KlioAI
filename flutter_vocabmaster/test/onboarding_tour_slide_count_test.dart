import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_onboarding_page.dart';

/// The tour's length is written down twice, and the two must agree.
///
/// `_kTourSlideCount` is not derived from the slides: the dots under the pager
/// and the profile step's index are both computed from it, while the slides
/// themselves are a literal list in `build`. Add a slide and forget the
/// constant and nothing throws — the pager simply has a page the dots do not
/// count, and the primary button reads "Continue" on what is really the last
/// page.
///
/// Read from the source rather than pumped, deliberately. Pumping the real page
/// needs the frontend-preference provider, the learning-language provider and a
/// first-run language decision, none of which have anything to do with the
/// question being asked. Counting the slides where they are declared answers it
/// directly.
void main() {
  test('the slide count matches the slides the pager actually holds', () {
    final File source =
        File('lib/frontend_newest/screens/nf_onboarding_page.dart');
    expect(source.existsSync(), isTrue,
        reason: 'run this from the flutter_vocabmaster directory');

    final String code = source.readAsStringSync();

    // Only the constructions inside the pager: `_TourSlide(` appears once more
    // as the class declaration and once in its constructor.
    final int declared = RegExp(r'_TourSlide\(\s*\n\s*icon:')
        .allMatches(code)
        .length;

    expect(declared, greaterThan(0),
        reason: 'the scanner found no slides at all, so it is measuring '
            'nothing — check the pattern before trusting a pass');
    expect(NfOnboardingPage.pageCount, declared + 1,
        reason: 'pageCount is the tour plus the profile step. The pager holds '
            '$declared tour slides, so pageCount should be ${declared + 1} '
            'and _kTourSlideCount should be $declared.');
  });

  test('the learner meets Amy before the tour, not after it', () {
    // The profile step was the fifth of five pages: four slides about features
    // nobody had used yet, and only then the three questions that decide what
    // every screen afterwards shows. It is first now, and this is the guard --
    // the ordering lives in two constants and a literal list, and a later edit
    // that reshuffles the list without them would silently put it back.
    expect(NfOnboardingPage.profilePageIndex, 0);
    expect(NfOnboardingPage.tourStartIndex, 1);
    expect(NfOnboardingPage.tourStartIndex, NfOnboardingPage.profilePageIndex + 1);
  });

  test('the pager really opens on the profile step', () {
    // The constants above are only a claim about the list; this reads the list.
    final String code =
        File('lib/frontend_newest/screens/nf_onboarding_page.dart')
            .readAsStringSync();
    final int childrenAt = code.indexOf('children: const <Widget>[');
    expect(childrenAt, greaterThan(0));

    final int profileAt = code.indexOf('_ProfileStep(),', childrenAt);
    final int firstSlideAt = code.indexOf('_TourSlide(', childrenAt);

    expect(profileAt, greaterThan(0), reason: 'the profile step left the pager');
    expect(profileAt, lessThan(firstSlideAt),
        reason: 'the tour is back in front of Amy');
  });

  test('replaying the tour from Settings does not reopen the questions', () {
    // The row is labelled "Replay app tour"; the profile has its own card in
    // Settings. Landing on the questions again would be answering a different
    // request from the one the learner made.
    final String settings =
        File('lib/frontend_newest/screens/nf_settings_page.dart')
            .readAsStringSync();

    expect(settings, contains('NfOnboardingPage.tourStartIndex'));
  });
}
