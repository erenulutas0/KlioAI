import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_onboarding_page.dart';

/// The tour's length is written down twice, and the two must agree.
///
/// `_kTourSlideCount` is not derived from the slides: the dots under the pager
/// and the profile step's index are both computed from it, while the slides
/// themselves are a literal list in `build`. Add a slide and forget the
/// constant and nothing throws — the pager simply has a page the dots do not
/// count, and "skip", which aims at `profilePageIndex`, lands on a tour slide
/// instead of the profile step.
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

  test('the profile step is the last page', () {
    // Skip and "replay from settings" both aim here. Off by one and they open
    // a tour slide the learner has already been shown.
    expect(NfOnboardingPage.profilePageIndex, NfOnboardingPage.pageCount - 1);
  });
}
