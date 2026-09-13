import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_settings_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/legal/voice_credits.dart';
import 'package:vocabmaster/providers/language_provider.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';

/// The attribution two of the tutor's voices are licensed on.
///
/// Jenny (Dioco) may be used commercially on condition of attribution, and amy and
/// alan are CC BY-SA 4.0. The voice is made on the server, so no package licence
/// covers it: without these entries and a way to reach them, the app was using
/// both on terms it was not meeting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the voices and the model are on the licence page', () async {
    VoiceCredits.register();
    VoiceCredits.register();

    final List<LicenseEntry> entries = await LicenseRegistry.licenses.toList();
    final List<String> packages =
        entries.expand((LicenseEntry e) => e.packages).toList();

    expect(packages.where((String p) => p == VoiceCredits.kokoroPackage), hasLength(1),
        reason: 'registered twice, listed twice');
    expect(packages, contains(VoiceCredits.piperPackage));

    final String piper = entries
        .firstWhere((LicenseEntry e) => e.packages.contains(VoiceCredits.piperPackage))
        .paragraphs
        .map((LicenseParagraph p) => p.text)
        .join('\n');
    expect(piper, contains('Jenny (Dioco)'));
    expect(piper, contains('CC BY-SA 4.0'));
    // Removed because their licences exclude commercial use; naming them here would
    // read as though the app still uses them.
    expect(piper, isNot(contains('lessac')));
    expect(piper.toLowerCase(), isNot(contains('ryan')));
  });

  testWidgets('settings has a way to reach it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final LearningLanguageProvider learning = LearningLanguageProvider();
    await learning.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningLanguageProvider>.value(value: learning),
          ChangeNotifierProvider<LanguageProvider>(create: (_) => LanguageProvider()),
          ChangeNotifierProvider<NfFrontendPreference>(
              create: (_) => NfFrontendPreference()),
        ],
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: NfSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder row = find.byKey(const ValueKey<String>('settings-licenses'));
    await tester.scrollUntilVisible(row, 200);
    expect(find.text('Lisanslar ve atıflar'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
