import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/models/nf_plan_state.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_today_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';

/// The first screen, rendered — which nothing had ever done in a test.
///
/// The arithmetic behind the plan is checked in `nf_plan_state_test.dart`. This
/// is about the card surviving being drawn: the three steps are joined by a
/// spine now and the spacer that used to separate them is gone, so a row that
/// measures wrong overflows rather than merely looking wrong. In a test that
/// throws; on a phone it is a yellow-and-black band.
///
/// The provider is faked rather than driven. A real [AppStateProvider] reports
/// itself uninitialised until a user is set, and the card then renders its
/// loading skeleton — which has no steps and no spine, so a green run would
/// have proved nothing about the change. Setting a user instead starts
/// background hydration and leaves a timer pending past the end of the test.
/// Overriding the nine things the page reads is the only version that renders
/// the state these assertions are about.
class _LoadedAppState extends AppStateProvider {
  _LoadedAppState({this.words = const <Word>[], this.stats = const <String, dynamic>{}});

  List<Word> words;
  Map<String, dynamic> stats;

  @override
  bool get isInitialized => true;

  @override
  bool get isLoadingWords => false;

  @override
  List<Word> get allWords => words;

  @override
  Map<String, dynamic> get userStats => <String, dynamic>{
        'streak': 0,
        'xp': 0,
        'level': 1,
        'weeklyXP': 0,
        'dailyGoal': 5,
        'learnedToday': 0,
        ...stats,
      };

  @override
  String get userName => 'Eren';

  void setWords(List<Word> next) {
    words = next;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LoadedAppState appState;

  Future<void> showToday(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    List<Word> words = const <Word>[],
    Map<String, dynamic> stats = const <String, dynamic>{},
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    appState = _LoadedAppState(words: words, stats: stats);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<NfFrontendPreference>(
              create: (_) => NfFrontendPreference()),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NfTodayPage(),
        ),
      ),
    );
    await tester.pump();
  }

  Word word({DateTime? due}) => Word(
        id: due?.day ?? 1,
        englishWord: 'flight',
        turkishMeaning: 'uçuş',
        learnedDate: DateTime(2026, 8, 28),
        difficulty: 'easy',
        nextReviewDate: due,
      );

  testWidgets('the plan card draws its steps without overflowing',
      (WidgetTester tester) async {
    await showToday(tester, words: <Word>[word()]);
    expect(tester.takeException(), isNull);
    expect(find.text('0/${NfPlanState.stepCount}'), findsOneWidget);
  });

  testWidgets('and still fits a narrow phone', (WidgetTester tester) async {
    // The header carries two chips beside the title now. A 320-wide screen is
    // what finds that out first.
    await showToday(tester, size: const Size(320, 700), words: <Word>[word()]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a first saved word does not turn the day green',
      (WidgetTester tester) async {
    // An unscheduled deck reading as "nothing due" would put a check on the
    // review step for someone who has saved one word and reviewed nothing.
    await showToday(tester, words: <Word>[word()]);
    expect(find.text('0/${NfPlanState.stepCount}'), findsOneWidget);
  });

  testWidgets('the counter follows what has actually been finished',
      (WidgetTester tester) async {
    // Nothing due and the daily goal met: two of the three, and the card has
    // to say so rather than leaving it to be counted by eye.
    await showToday(
      tester,
      words: <Word>[word(due: DateTime(2030))],
      stats: <String, dynamic>{'dailyGoal': 5, 'learnedToday': 5},
    );
    expect(find.text('2/${NfPlanState.stepCount}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
