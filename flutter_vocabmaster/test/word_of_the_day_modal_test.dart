import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/widgets/word_of_the_day_modal.dart';
import 'test_helper.dart';

const _ttsChannel = MethodChannel('flutter_tts');

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupTestEnv();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ttsChannel, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ttsChannel, null);
  });

  AppStateProvider buildAppState({
    required bool wordAdded,
    required bool sentenceAdded,
    required Map<String, dynamic> wordData,
  }) {
    return _TestAppStateProvider(
      wordAdded: wordAdded,
      sentenceAdded: sentenceAdded,
      wordData: wordData,
    );
  }

  Widget buildTestApp({
    required AppStateProvider appState,
    required Map<String, dynamic> wordData,
  }) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WordOfTheDayModal(
          wordData: wordData,
          onClose: () {},
          enableAnimations: false,
          enableTts: false,
          initialStep: 5,
        ),
      ),
    );
  }

  String tr(String key) => AppLocalizations(const Locale('tr')).t(key);

  testWidgets('Step 6 shows add buttons when word not added', (tester) async {
    final wordData = {
      'word': 'Focus',
      'translation': 'Odak',
      'exampleSentence': 'Stay focused.',
      'exampleTranslation': 'Odakli kal.',
      'difficulty': 'easy',
      'partOfSpeech': 'noun',
      'pronunciation': 'foh-kus',
    };

    final appState = buildAppState(
      wordAdded: false,
      sentenceAdded: false,
      wordData: wordData,
    );

    await tester
        .pumpWidget(buildTestApp(appState: appState, wordData: wordData));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(tr('wotd.addWithSentence')), findsOneWidget);
    expect(find.text(tr('wotd.addWordOnly')), findsOneWidget);
    expect(find.text(tr('wotd.wordAdded')), findsNothing);
  });

  testWidgets('Step 6 shows add sentence when word added but sentence missing',
      (tester) async {
    final wordData = {
      'word': 'Focus',
      'translation': 'Odak',
      'exampleSentence': 'Stay focused.',
      'exampleTranslation': 'Odakli kal.',
      'difficulty': 'easy',
      'partOfSpeech': 'noun',
      'pronunciation': 'foh-kus',
    };

    final appState = buildAppState(
      wordAdded: true,
      sentenceAdded: false,
      wordData: wordData,
    );

    await tester
        .pumpWidget(buildTestApp(appState: appState, wordData: wordData));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(tr('wotd.wordAdded')), findsOneWidget);
    expect(find.text(tr('wotd.addSentenceToo')), findsOneWidget);
  });

  testWidgets('Step 6 shows completed state when word and sentence added',
      (tester) async {
    final wordData = {
      'word': 'Focus',
      'translation': 'Odak',
      'exampleSentence': 'Stay focused.',
      'exampleTranslation': 'Odakli kal.',
      'difficulty': 'easy',
      'partOfSpeech': 'noun',
      'pronunciation': 'foh-kus',
    };

    final appState = buildAppState(
      wordAdded: true,
      sentenceAdded: true,
      wordData: wordData,
    );

    await tester
        .pumpWidget(buildTestApp(appState: appState, wordData: wordData));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(tr('wotd.wordSentenceAdded')), findsOneWidget);
    expect(find.text(tr('wotd.addSentenceToo')), findsNothing);
  });
}

class _TestAppStateProvider extends AppStateProvider {
  final bool wordAdded;
  final bool sentenceAdded;
  final Map<String, dynamic> wordData;

  _TestAppStateProvider({
    required this.wordAdded,
    required this.sentenceAdded,
    required this.wordData,
  });

  @override
  Word? findWordByEnglish(String english) {
    if (!wordAdded) return null;
    return Word(
      id: 1,
      englishWord: wordData['word'] as String,
      turkishMeaning: wordData['translation'] as String,
      learnedDate: DateTime.now(),
      difficulty: 'easy',
      sentences: sentenceAdded
          ? [
              Sentence(
                id: 10,
                sentence: wordData['exampleSentence'] as String,
                translation: wordData['exampleTranslation'] as String,
                wordId: 1,
                difficulty: 'easy',
              )
            ]
          : [],
    );
  }

  @override
  bool hasSentenceForWord(Word word, String sentence) {
    return sentenceAdded;
  }
}
