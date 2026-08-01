import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/screens/repeat_page.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

class _FakeApiService extends ApiService {
  _FakeApiService(this.words);

  final List<Word> words;

  @override
  Future<List<Word>> getAllWords() async => words;
}

/// Keeps the real provider's network client out of these layout-only tests.
class _FakeAppStateProvider extends AppStateProvider {
  @override
  Future<Word?> submitWordReview({
    required int wordId,
    required int quality,
    String? source,
    int? responseMs,
  }) async =>
      null;
}

Word _word(int id, String english, {DateTime? nextReviewDate}) => Word(
      id: id,
      englishWord: english,
      turkishMeaning: 'anlam-$id',
      learnedDate: DateTime(2026, 7, 1),
      difficulty: 'easy',
      nextReviewDate: nextReviewDate,
    );

Future<void> _pumpRepeatPage(
  WidgetTester tester,
  List<Word> words, {
  required bool dueOnly,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>(
            create: (_) => _FakeAppStateProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        home: RepeatPage(
          apiService: _FakeApiService(words),
          dueOnly: dueOnly,
        ),
      ),
    ),
  );
  // RepeatPage runs looping background animations; bounded pumps only. Must
  // clear the 300ms/400ms staggered-animation timers or the binding complains
  // about pending timers at teardown.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  final now = DateTime.now();
  final overdue = now.subtract(const Duration(days: 2));
  final dueToday = now;
  final notYetDue = now.add(const Duration(days: 3));

  testWidgets('dueOnly session holds just the words the scheduler brought up',
      (tester) async {
    await _pumpRepeatPage(
      tester,
      [
        _word(1, 'overdue', nextReviewDate: overdue),
        _word(2, 'later', nextReviewDate: notYetDue),
        _word(3, 'today', nextReviewDate: dueToday),
        _word(4, 'unscheduled'),
      ],
      dueOnly: true,
    );

    // Header counts only the due words — this is what the home card promised.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('overdue'), findsOneWidget);
    expect(find.text('later'), findsNothing);
  });

  testWidgets('a word due later today still counts as due', (tester) async {
    await _pumpRepeatPage(
      tester,
      [
        _word(1, 'endofday',
            nextReviewDate: DateTime(now.year, now.month, now.day, 23, 30)),
        _word(2, 'later', nextReviewDate: notYetDue),
      ],
      dueOnly: true,
    );

    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('endofday'), findsOneWidget);
  });

  testWidgets('falls back to the full deck when nothing is due',
      (tester) async {
    await _pumpRepeatPage(
      tester,
      [
        _word(1, 'later', nextReviewDate: notYetDue),
        _word(2, 'unscheduled'),
      ],
      dueOnly: true,
    );

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('later'), findsOneWidget);
  });

  testWidgets('the normal entry point still loads every word', (tester) async {
    await _pumpRepeatPage(
      tester,
      [
        _word(1, 'overdue', nextReviewDate: overdue),
        _word(2, 'later', nextReviewDate: notYetDue),
        _word(3, 'unscheduled'),
      ],
      dueOnly: false,
    );

    expect(find.text('1 / 3'), findsOneWidget);
  });
}
