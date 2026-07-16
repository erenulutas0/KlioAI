import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/exam_models.dart';
import 'package:vocabmaster/models/voice_model.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/writing_practice_models.dart';

void main() {
  group('Sentence Model', () {
    test('fromJson creates a valid Sentence object', () {
      final json = {
        'id': 1,
        'sentence': 'Hello World',
        'translation': 'Merhaba Dünya',
        'wordId': 100,
        'difficulty': 'easy'
      };

      final sentence = Sentence.fromJson(json);

      expect(sentence.id, 1);
      expect(sentence.sentence, 'Hello World');
      expect(sentence.translation, 'Merhaba Dünya');
      expect(sentence.wordId, 100);
      expect(sentence.difficulty, 'easy');
    });

    test('fromJson handles different number types for ID', () {
      final json = {
        'id': 1.0, // double
        'sentence': 'Test',
        'translation': 'Test',
        'wordId': 5.5, // double
      };

      final sentence = Sentence.fromJson(json);
      expect(sentence.id, 1);
      expect(sentence.wordId, 5);
    });

    test('toJson returns correct map', () {
      final sentence = Sentence(
        id: 1,
        sentence: 'Test',
        translation: 'Test TR',
        wordId: 10,
        difficulty: 'hard',
      );

      final json = sentence.toJson();
      expect(json['id'], 1);
      expect(json['sentence'], 'Test');
      expect(json['difficulty'], 'hard');
    });
  });

  group('Word Model', () {
    test('fromJson creates a valid Word object', () {
      final json = {
        'id': 10,
        'englishWord': 'Example',
        'turkishMeaning': 'Örnek',
        'learnedDate': '2023-01-01',
        'difficulty': 'medium',
        'notes': 'Some notes',
        'sentences': [
          {
            'id': 1,
            'sentence': 'This is an example.',
            'translation': 'Bu bir örnektir.',
            'wordId': 10
          }
        ]
      };

      final word = Word.fromJson(json);

      expect(word.id, 10);
      expect(word.englishWord, 'Example');
      expect(word.turkishMeaning, 'Örnek');
      expect(word.learnedDate.year, 2023);
      expect(word.sentences.length, 1);
      expect(word.sentences.first.sentence, 'This is an example.');
    });

    test('fromJson handles empty sentences list', () {
      final json = {
        'id': 1,
        'englishWord': 'Test',
        'turkishMeaning': 'Test',
        'learnedDate': '2023-01-01',
        'sentences': null
      };

      final word = Word.fromJson(json);
      expect(word.sentences, isEmpty);
    });

    test('toJson returns correct map', () {
      final word = Word(
        id: 1,
        englishWord: 'Apple',
        turkishMeaning: 'Elma',
        learnedDate: DateTime(2023, 1, 1),
        difficulty: 'easy',
        sentences: [],
      );

      final json = word.toJson();
      expect(json['id'], 1);
      expect(json['englishWord'], 'Apple');
      expect(json['learnedDate'], '2023-01-01'); // Assuming standard format
    });
  });

  group('Exam Models', () {
    test('ExamBundle.fromJson maps nested meta sections and items', () {
      final bundle = ExamBundle.fromJson({
        'meta': {
          'exam': 'YDS',
          'mode': 'mini_test',
          'track': 'sosyal',
          'user_level_cefr': 'B2',
          'target_score_band': '70-80',
          'time_limit_minutes': 45,
          'total_questions': 2,
        },
        'sections': [
          {
            'name': 'reading',
            'items': [
              {
                'id': 'r1',
                'type': 'multiple_choice',
                'difficulty': 'hard',
                'skill_tags': ['inference', 42],
                'stem': 'What is implied by the passage?',
                'passage': 'A short passage.',
                'options': {'A': 'First', 'B': 'Second'},
                'correct': 'B',
                'explanation_tr': 'Cevap metinden cikarilir.',
                'explanation_en': 'The answer is implied.',
              }
            ],
          }
        ],
      });

      expect(bundle.meta.exam, 'YDS');
      expect(bundle.meta.mode, 'mini_test');
      expect(bundle.meta.track, 'sosyal');
      expect(bundle.meta.userLevelCefr, 'B2');
      expect(bundle.meta.targetScoreBand, '70-80');
      expect(bundle.meta.timeLimitMinutes, 45);
      expect(bundle.meta.totalQuestions, 2);

      final section = bundle.sections.single;
      expect(section.name, 'reading');
      final item = section.items.single;
      expect(item.id, 'r1');
      expect(item.difficulty, 'hard');
      expect(item.skillTags, ['inference', '42']);
      expect(item.passage, 'A short passage.');
      expect(item.options['B'], 'Second');
      expect(item.correct, 'B');
      expect(item.explanationEn, 'The answer is implied.');
    });

    test('ExamMeta and ExamItem use safe defaults for partial payloads', () {
      final meta = ExamMeta.fromJson({
        'exam': 'YOKDIL',
        'mode': 'full_exam',
      });
      final item = ExamItem.fromJson({
        'stem': 'Choose the best answer.',
      });

      expect(meta.timeLimitMinutes, 180);
      expect(meta.totalQuestions, 0);
      expect(meta.track, isNull);

      expect(item.id, '');
      expect(item.type, '');
      expect(item.difficulty, 'medium');
      expect(item.skillTags, isEmpty);
      expect(item.options, isEmpty);
      expect(item.correct, '');
    });
  });

  group('Writing Practice Models', () {
    test('TopicData.fromJson converts missing and non-string values safely',
        () {
      final topic = TopicData.fromJson({
        'topic': 'Describe a delayed trip',
        'description': 123,
        'level': 'B1',
      });

      expect(topic.topic, 'Describe a delayed trip');
      expect(topic.description, '123');
      expect(topic.level, 'B1');
      expect(topic.wordCount, '');
    });

    test('EvaluationData.fromJson maps lists and feedback defaults', () {
      final evaluation = EvaluationData.fromJson({
        'score': 82,
        'strengths': ['clear structure'],
        'improvements': ['use more connectors'],
        'grammar': 'Good tense control.',
        'vocabulary': 'Appropriate.',
        'coherence': 'Logical.',
        'overall': 'Strong attempt.',
      });

      expect(evaluation.score, 82);
      expect(evaluation.strengths, ['clear structure']);
      expect(evaluation.improvements, ['use more connectors']);
      expect(evaluation.grammar, 'Good tense control.');
      expect(evaluation.contextRelevance, '');
    });
  });

  group('VoiceModel', () {
    test('serializes and deserializes the selected Piper voice', () {
      const voice = VoiceModel(
        id: 'alan',
        name: 'Alan',
        gender: 'male',
        accent: 'British',
        locale: 'en_GB',
        piperVoice: 'alan',
        avatarUrl: 'https://example.test/alan.png',
        sampleText: 'Let us practise clearly.',
      );

      final decoded = VoiceModel.fromJsonString(voice.toJsonString());

      expect(decoded, voice);
      expect(decoded.genderEmoji, '👨');
      expect(decoded.genderText, 'Erkek');
      expect(decoded.toJson()['piperVoice'], 'alan');
    });

    test('fromJson falls back to the default female American voice shape', () {
      final voice = VoiceModel.fromJson({});

      expect(voice.id, '');
      expect(voice.name, '');
      expect(voice.gender, 'female');
      expect(voice.accent, 'American');
      expect(voice.locale, 'en_US');
      expect(voice.piperVoice, 'amy');
      expect(voice.genderEmoji, '👩');
      expect(voice.genderText, 'Kadın');
    });

    test('available voices expose unique ids and both US and UK locales', () {
      final voices = VoiceModel.availableVoices;
      final ids = voices.map((voice) => voice.id).toSet();
      final locales = voices.map((voice) => voice.locale).toSet();

      expect(ids, hasLength(voices.length));
      expect(locales, containsAll(['en_US', 'en_GB']));
      expect(voices.any((voice) => voice.gender == 'male'), isTrue);
      expect(voices.any((voice) => voice.gender == 'female'), isTrue);
    });
  });
}
