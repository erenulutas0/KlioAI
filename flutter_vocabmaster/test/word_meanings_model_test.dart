import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/language_profile.dart';
import 'package:vocabmaster/models/word.dart';

/// A word now has one or more meanings and belongs to a language profile; a sentence
/// may be attached to one meaning. The server that sends those keys is not deployed
/// at the same moment as the client that reads them, so the model must read both the
/// new shape and the old one without any screen noticing the difference.
Map<String, dynamic> legacyWordJson({String meaning = 'içgörü'}) => {
      'id': 7,
      'englishWord': 'insight',
      'turkishMeaning': meaning,
      'learnedDate': '2026-08-09',
      'difficulty': 'easy',
      'sentences': [
        {
          'id': 70,
          'sentence': 'She had a sudden insight.',
          'translation': 'Aniden bir içgörü yaşadı.',
          'wordId': 7,
        }
      ],
    };

Map<String, dynamic> newWordJson() => {
      ...legacyWordJson(meaning: '⭐ içgörü, kavrayış'),
      'languageProfileId': 3,
      'origin': 'daily_words',
      'meanings': [
        {'id': 1, 'translation': 'içgörü', 'definition': null, 'position': 0},
        {
          'id': 2,
          'translation': 'kavrayış',
          'definition': 'deep understanding',
          'position': 1,
        },
      ],
      'sentences': [
        {
          'id': 70,
          'sentence': 'She had a sudden insight.',
          'translation': 'Aniden bir içgörü yaşadı.',
          'wordId': 7,
          'meaningId': 1,
        },
        {
          'id': 71,
          'sentence': 'Unassigned example.',
          'translation': 'Atanmamış örnek.',
          'wordId': 7,
          'meaningId': null,
        },
      ],
    };

void main() {
  group('Word.fromJson against the old server', () {
    test('missing keys leave the new fields empty and the old ones intact', () {
      final word = Word.fromJson(legacyWordJson());

      expect(word.meanings, isEmpty);
      expect(word.languageProfileId, isNull);
      expect(word.origin, isNull);
      expect(word.turkishMeaning, 'içgörü');
      expect(word.displayMeaning, 'içgörü');
      expect(word.sentences.single.meaningId, isNull);
    });

    test('provenance still comes from the marker when origin is absent', () {
      expect(Word.fromJson(legacyWordJson(meaning: '⭐ içgörü')).isFromDailyWords,
          isTrue);
      expect(Word.fromJson(legacyWordJson(meaning: '★ içgörü')).isFromDailyWords,
          isTrue);
      expect(
          Word.fromJson(legacyWordJson(meaning: 'içgörü')).isFromDailyWords,
          isFalse);
    });
  });

  group('Word.fromJson against the new server', () {
    test('reads meanings, profile and origin', () {
      final word = Word.fromJson(newWordJson());

      expect(word.languageProfileId, 3);
      expect(word.origin, 'daily_words');
      expect(word.meanings.length, 2);
      expect(word.meanings.first.id, 1);
      expect(word.meanings.first.translation, 'içgörü');
      expect(word.meanings.first.definition, isNull);
      expect(word.meanings.first.position, 0);
      expect(word.meanings.last.definition, 'deep understanding');
      expect(word.meanings.last.position, 1);
    });

    test('origin wins over the marker for provenance', () {
      final fromOrigin = Word.fromJson({
        ...legacyWordJson(meaning: 'temiz anlam'),
        'origin': 'daily_words',
      });
      expect(fromOrigin.isFromDailyWords, isTrue);

      final manualWithStaleMarker = Word.fromJson({
        ...legacyWordJson(meaning: '⭐ içgörü'),
        'origin': 'manual',
      });
      expect(manualWithStaleMarker.isFromDailyWords, isFalse);
    });

    test('a malformed meaning entry is skipped, not fatal', () {
      final word = Word.fromJson({
        ...legacyWordJson(),
        'meanings': [
          'not a map',
          {'id': 5, 'translation': 'içgörü'},
        ],
      });

      expect(word.meanings.length, 1);
      expect(word.meanings.single.id, 5);
    });

    test('toJson carries the new keys so a round trip keeps them', () {
      final word = Word.fromJson(newWordJson());
      final again = Word.fromJson(word.toJson());

      expect(again.meanings.length, 2);
      expect(again.languageProfileId, 3);
      expect(again.origin, 'daily_words');
      expect(again.sentences.first.meaningId, 1);
    });
  });

  group('displayMeaning precedence', () {
    test('meanings win when present', () {
      final word = Word.fromJson(newWordJson());
      expect(word.displayMeaning, 'içgörü, kavrayış');
    });

    test('falls back to the stripped turkishMeaning when meanings are empty',
        () {
      final word = Word.fromJson(legacyWordJson(meaning: '⭐ içgörü'));
      expect(word.displayMeaning, 'içgörü');
    });

    test('blank translations do not count as meanings', () {
      final word = Word.fromJson({
        ...legacyWordJson(meaning: '★ kavrayış'),
        'meanings': [
          {'id': 1, 'translation': '   '},
        ],
      });
      expect(word.displayMeaning, 'kavrayış');
    });
  });

  group('Sentence meaningId', () {
    test('is read when present and null when absent or null', () {
      final word = Word.fromJson(newWordJson());
      expect(word.sentences[0].meaningId, 1);
      expect(word.sentences[1].meaningId, isNull);

      final legacy = Sentence.fromJson({
        'id': 1,
        'sentence': 'Hello',
        'translation': 'Merhaba',
        'wordId': 9,
      });
      expect(legacy.meaningId, isNull);
    });

    test('tolerates a numeric-looking string or a double', () {
      expect(
        Sentence.fromJson({
          'id': 1,
          'sentence': 'x',
          'translation': 'y',
          'wordId': 9,
          'meaningId': '12',
        }).meaningId,
        12,
      );
      expect(
        Sentence.fromJson({
          'id': 1,
          'sentence': 'x',
          'translation': 'y',
          'wordId': 9,
          'meaningId': 4.0,
        }).meaningId,
        4,
      );
    });

    test('toJson only writes meaningId when it is set', () {
      final attached = Sentence(
        id: 1,
        sentence: 'x',
        translation: 'y',
        wordId: 9,
        meaningId: 3,
      );
      final unassigned = Sentence(
        id: 2,
        sentence: 'x',
        translation: 'y',
        wordId: 9,
      );

      expect(attached.toJson()['meaningId'], 3);
      expect(unassigned.toJson().containsKey('meaningId'), isFalse);
    });
  });

  group('LanguageProfile', () {
    test('parses the server shape', () {
      final profile = LanguageProfile.fromJson({
        'id': 3,
        'sourceLanguage': 'Turkish',
        'targetLanguage': 'English',
        'level': 'B2',
        'learningGoal': 'Exam',
        'isActive': true,
        'createdAt': '2026-08-23T10:15:00',
      });

      expect(profile.id, 3);
      expect(profile.sourceLanguage, 'Turkish');
      expect(profile.targetLanguage, 'English');
      expect(profile.level, 'B2');
      expect(profile.learningGoal, 'Exam');
      expect(profile.isActive, isTrue);
      expect(profile.createdAt, DateTime(2026, 8, 23, 10, 15));
    });

    test('fills the defaults the schema promises', () {
      final profile = LanguageProfile.fromJson({
        'id': '4',
        'sourceLanguage': 'Turkish',
        'targetLanguage': 'English',
        'level': '',
        'learningGoal': null,
      });

      expect(profile.id, 4);
      expect(profile.level, 'B1');
      expect(profile.learningGoal, isNull);
      expect(profile.isActive, isFalse);
      expect(profile.createdAt, isNull);
    });

    test('round-trips through toJson', () {
      final profile = LanguageProfile.fromJson({
        'id': 3,
        'sourceLanguage': 'Turkish',
        'targetLanguage': 'English',
        'level': 'C1',
        'learningGoal': 'Work',
        'isActive': true,
      });
      final again = LanguageProfile.fromJson(profile.toJson());

      expect(again.id, 3);
      expect(again.level, 'C1');
      expect(again.learningGoal, 'Work');
      expect(again.isActive, isTrue);
    });
  });
}
