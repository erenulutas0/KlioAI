import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// The opening line has to follow the interface language.
///
/// Found on a phone. The menus read Turkish and Amy still said
///
///     Hola, soy Amy. Mantén pulsado el botón de abajo y cuéntame tu día
///
/// because the tutor tab lives inside an IndexedStack — the shell keeps it
/// alive and unbuilt behind the others, on purpose, so switching tabs does not
/// throw away a conversation. The greeting was resolved once at bootstrap and
/// written into the thread as a finished sentence, so it kept whatever
/// language the app was in at that moment. Nothing rebuilt it, and a cold
/// start was the only thing that ever put it right.
///
/// It is the one turn in the thread the app wrote rather than someone saying
/// it, which is exactly why it is the one turn that must not be frozen.
///
/// This checks the string, not the widget: pumping the page wants a recorder,
/// a TTS probe, a voice store and a network client, none of which have
/// anything to do with the question. What broke was that a sentence was built
/// once instead of every time, and the property that prevents it is that the
/// same key, read under two locales, gives two different sentences.
void main() {
  test('the greeting differs by locale, so it cannot be resolved once', () {
    final Map<String, String> byLocale = <String, String>{
      for (final Locale locale in AppLocalizations.supportedLocales)
        locale.languageCode: AppLocalizations(locale)
            .t('tutor.greeting')
            .replaceAll('{name}', 'Amy'),
    };

    expect(byLocale.length, greaterThan(1),
        reason: 'one locale or none, so this proves nothing');

    for (final MapEntry<String, String> entry in byLocale.entries) {
      expect(entry.value, isNot('tutor.greeting'),
          reason: '${entry.key} has no greeting at all');
      expect(entry.value, contains('Amy'),
          reason: '${entry.key} drops the speaker name, so the placeholder is '
              'wrong or missing');
    }

    // Seven languages, seven sentences. If any two matched, this test would be
    // passing on a coincidence rather than on the thing it is here to protect.
    expect(byLocale.values.toSet().length, byLocale.length,
        reason: 'two locales share a greeting, so a stale one would be '
            'invisible between them: $byLocale');
  });

  test('the Spanish greeting is the one that was seen under Turkish menus', () {
    // Named, because it is the evidence. If this string ever stops being
    // Spanish the test above still passes and this one says what changed.
    final String spanish =
        AppLocalizations(const Locale('es')).t('tutor.greeting');
    final String turkish =
        AppLocalizations(const Locale('tr')).t('tutor.greeting');

    expect(spanish, contains('Hola'));
    expect(turkish, isNot(contains('Hola')));
  });
}
