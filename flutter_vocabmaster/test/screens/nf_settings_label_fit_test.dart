import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// No settings label may hold a word too long for the row it is drawn in.
///
/// Flutter wraps at a word boundary when it can and inside the word when it
/// cannot, silently. On a real phone the German settings screen read
///
///     Erscheinun          Benachrichtigungseinstellung
///     gsbild              en
///
/// and had done since German shipped; Spanish did the same to "Apariencia"
/// the day it was added. Nothing failed — the text is present, it is not
/// clipped, no overflow stripe appears. It is simply cut in half.
///
/// This counts characters rather than measuring pixels, and that is a
/// deliberate retreat. The first version of this test laid each word out with
/// a TextPainter and compared it against the box the layout gave it, which is
/// the exact condition. It reported every locale as broken, Turkish included —
/// because the app draws in Baloo 2 and Nunito through `google_fonts`, which
/// fetches at runtime, so a widget test has no real font and measures a
/// placeholder whose every glyph is a square of the full font size. Each word
/// came back at exactly 15.0 logical pixels per character, roughly double the
/// truth. A guard that measures the wrong font with great precision is worse
/// than one that counts letters and says so.
///
/// The budgets below are calibrated from a device, not chosen:
///
///   narrow row (`settings.appearance`, sharing its width with two chips)
///     "Görünüm"          7   fits          (verified on screen)
///     "Apariencia"      10   breaks        (verified on screen)
///     "Erscheinungsbild" 16  breaks        (verified on screen)
///
///   ordinary row (icon, label, chevron)
///     "notificaciones"  14   fits          (verified on screen)
///     "Benachrichtigungseinstellungen" 30  breaks (verified on screen)
///
/// So 8 and 20. The first sits between a measured pass and a measured fail;
/// the second sits in a wide gap between them and is the softer number of the
/// two. Neither is a measurement, and a label that trips this test should be
/// checked on a screen before it is shortened.
void main() {
  const int narrowRowBudget = 8;
  const int ordinaryRowBudget = 20;

  /// Labels drawn on a settings row, with how much room that row leaves them.
  const budgets = <String, int>{
    'settings.appearance': narrowRowBudget,
    'settings.language.title': 14, // beside a chip naming the language
    'profile.notificationPrefs': ordinaryRowBudget,
    'profile.manageSubscription': ordinaryRowBudget,
    'settings.tour.cta': ordinaryRowBudget,
  };

  test('every settings label fits the row it is drawn in', () {
    final String source =
        File('lib/l10n/app_localizations.dart').readAsStringSync();
    expect(source, isNotEmpty,
        reason: 'run this from the flutter_vocabmaster directory');

    final offenders = <String>[];
    var checked = 0;

    for (final locale in AppLocalizations.supportedLocales) {
      final AppLocalizations l10n = AppLocalizations(locale);
      for (final MapEntry<String, int> entry in budgets.entries) {
        final String label = l10n.t(entry.key);
        expect(label, isNot(entry.key),
            reason: '${locale.languageCode} has no value for ${entry.key}');

        for (final String word in label.split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          checked++;
          if (word.length > entry.value) {
            offenders.add('  ${locale.languageCode}  ${entry.key}  '
                '"$word" is ${word.length} characters, budget ${entry.value}'
                '  (from "$label")');
          }
        }
      }
    }

    // A count, because a loop over an empty map passes every assertion made
    // about what it looped over.
    expect(checked, greaterThan(50),
        reason: 'only $checked words were checked, which is far too few');

    expect(offenders, isEmpty,
        reason: 'These are longer than the row can draw, so Flutter breaks '
            'them in half:\n${offenders.join('\n')}');
  });
}
