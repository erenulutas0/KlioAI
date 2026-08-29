import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_repository.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_grammar_quiz_page.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_grammar_topic_page.dart';
import 'package:vocabmaster/frontend_newest/theme/nf_theme_scope.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// What the quiz is a quiz about.
///
/// Practice is one button at the bottom of a topic page whose subtopic cards
/// open one at a time. It used to send only the topic — "Tenses", which has
/// twelve subtopics — while the prompt asks for "5 questions testing ONLY this
/// grammar topic". Someone who had just read Past Perfect Continuous got five
/// questions drawn from anywhere in the tense system. Nothing was malformed,
/// every guard passed, and from the learner's side it reads as a quiz that has
/// nothing to do with the lesson.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GrammarTopic topicWithSubtopics() {
    final GrammarTopic topic = GrammarRepository.getAllTopics().firstWhere(
      (GrammarTopic t) => t.subtopics.length > 1,
      orElse: () => throw StateError('no topic has more than one subtopic'),
    );
    return topic;
  }

  Future<void> showTopic(WidgetTester tester, GrammarTopic topic) async {
    tester.view.physicalSize = const Size(500, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<NfFrontendPreference>(
        create: (_) => NfFrontendPreference(),
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: NfThemeScope(child: NfGrammarTopicPage(topic: topic)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Practice asks about the subtopic that is open', (tester) async {
    final GrammarTopic topic = topicWithSubtopics();
    final GrammarSubtopic open = topic.subtopics.first;

    await showTopic(tester, topic);
    await tester.tap(find.byKey(const ValueKey('grammar-practice-quiz')));
    // The route transition needs its frames. The quiz page's own request runs
    // during them and comes back as the test binding's 400, which the page
    // turns into an error message -- irrelevant here, since the question is
    // what the page was asked to be about, not what came back.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final NfGrammarQuizPage quiz =
        tester.widget(find.byType(NfGrammarQuizPage));
    expect(quiz.topic.id, topic.id);
    expect(quiz.subtopic?.id, open.id,
        reason: 'the quiz was opened while "${open.title}" was the expanded '
            'card, so that is what the learner had just read');
  });

  test('the request names the topic and the subtopic together', () {
    final GrammarTopic topic = topicWithSubtopics();
    final GrammarSubtopic sub = topic.subtopics.first;

    final String both = NfGrammarQuizPage.requestedTopicFor(topic, sub);
    expect(both, contains(topic.title));
    expect(both, contains(sub.title));

    // Both halves, not just the subtopic. Eighteen of the eighty-six subtopic
    // titles name no grammar point on their own — "Ability", "Possibility",
    // "Zero Article", "Other Inversions" — and a generator asked for
    // "Ability" writes about anything at all.
    expect(NfGrammarQuizPage.requestedTopicFor(topic, null), topic.title,
        reason: 'with every card collapsed there is no lesson to narrow to, '
            'so the whole topic is the honest request');
  });

  test('no subtopic would send an empty half', () {
    // The composition joins two strings. A blank one produces "Tenses: " or
    // ": Ability", either of which asks the generator for less than the old
    // behaviour did.
    for (final GrammarTopic topic in GrammarRepository.getAllTopics()) {
      expect(topic.title.trim(), isNotEmpty, reason: 'topic ${topic.id}');
      for (final GrammarSubtopic sub in topic.subtopics) {
        expect(sub.title.trim(), isNotEmpty,
            reason: 'subtopic ${sub.id} in ${topic.id}');
      }
    }
  });
}
