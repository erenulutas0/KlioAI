import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/screens/translation_practice_page.dart';
import 'package:vocabmaster/services/chatbot_service.dart';
import 'package:vocabmaster/services/learning_language_service.dart';

class _FakeChatbotService extends ChatbotService {
  String? generatedWord;
  String? generatedDirection;
  String? checkedOriginalSentence;
  String? checkedUserTranslation;
  String? checkedDirection;

  @override
  Future<Map<String, dynamic>> generateSentences({
    required String word,
    List<String> levels = const ['B1'],
    List<String> lengths = const ['medium'],
    bool checkGrammar = false,
    bool fresh = false,
    String direction = 'EN_TO_TR',
  }) async {
    generatedWord = word;
    generatedDirection = direction;
    return {
      'sentences': [
        'The delayed train changed our plans.',
        'A short delay gave us time for coffee.',
      ],
      'translations': [
        'El tren retrasado cambió nuestros planes.',
        'Un pequeño retraso nos dio tiempo para café.',
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> checkTranslation({
    required String originalSentence,
    required String userTranslation,
    required String direction,
    String? referenceSentence,
  }) async {
    checkedOriginalSentence = originalSentence;
    checkedUserTranslation = userTranslation;
    checkedDirection = direction;
    return {
      'isCorrect': true,
      'feedback': 'Nice work. The meaning is clear.',
      'correctTranslation': 'El tren retrasado cambió nuestros planes.',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TranslationPracticePage uses source-language direction labels',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'learning_source_language': 'Spanish',
      'learning_english_level': 'B2',
      'learning_goal': 'Travel',
    });

    final learningProvider = LearningLanguageProvider();
    await learningProvider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: learningProvider,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TranslationPracticePage(subMode: 'manual'),
        ),
      ),
    );
    await tester.pump();

    expect(LearningLanguageService.sourceLanguage, 'Spanish');
    expect(find.text('EN → ES'), findsOneWidget);
    expect(find.text('ES → EN'), findsOneWidget);
    expect(find.text('Mixed'), findsOneWidget);
    expect(find.text('EN → TR'), findsNothing);
    expect(find.text('TR → EN'), findsNothing);
  });

  testWidgets('TranslationPracticePage generates and checks Spanish flow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'learning_source_language': 'Spanish',
      'learning_english_level': 'B2',
      'learning_goal': 'Travel',
    });

    final learningProvider = LearningLanguageProvider();
    await learningProvider.initialize();
    final chatbotService = _FakeChatbotService();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: learningProvider,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TranslationPracticePage(
            selectedWord: Word(
              id: 1,
              englishWord: 'delay',
              turkishMeaning: 'retraso',
              learnedDate: DateTime(2026),
              difficulty: 'easy',
            ),
            selectedLevels: const ['B2'],
            selectedLengths: const ['medium'],
            chatbotService: chatbotService,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('translation-generate-button')));
    await tester.pump();
    await tester.pump();

    expect(chatbotService.generatedWord, 'delay');
    expect(chatbotService.generatedDirection, 'TARGET_TO_SOURCE');
    expect(find.text('The delayed train changed our plans.'), findsOneWidget);
    expect(find.text('EN → ES'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('translation-input-0')),
      'El tren retrasado cambió nuestros planes.',
    );
    await tester.tap(find.byKey(const ValueKey('translation-check-0')));
    await tester.pump();
    await tester.pump();

    expect(chatbotService.checkedOriginalSentence,
        'The delayed train changed our plans.');
    expect(chatbotService.checkedUserTranslation,
        'El tren retrasado cambió nuestros planes.');
    expect(chatbotService.checkedDirection, 'TARGET_TO_SOURCE');
    expect(find.text('Nice work. The meaning is clear.'), findsOneWidget);
  });
}
