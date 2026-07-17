import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/speech_transcript_policy.dart';

void main() {
  group('SpeechTranscriptPolicy.canAutoSend', () {
    test('rejects empty transcripts', () {
      expect(
        SpeechTranscriptPolicy.canAutoSend(
          transcript: '   ',
          finalResultReceived: true,
          confidence: 0.9,
        ),
        isFalse,
      );
    });

    test('rejects transcripts that have not finalized', () {
      expect(
        SpeechTranscriptPolicy.canAutoSend(
          transcript: 'I would like to practice speaking',
          finalResultReceived: false,
          confidence: 0.9,
        ),
        isFalse,
      );
    });

    test('rejects low-confidence final transcripts', () {
      expect(
        SpeechTranscriptPolicy.canAutoSend(
          transcript: 'I want to improve my pronunciation',
          finalResultReceived: true,
          confidence: 0.42,
        ),
        isFalse,
      );
    });

    test('accepts high-confidence final transcripts', () {
      expect(
        SpeechTranscriptPolicy.canAutoSend(
          transcript: 'I want to improve my pronunciation',
          finalResultReceived: true,
          confidence: 0.86,
        ),
        isTrue,
      );
    });

    test('treats missing confidence as usable when text is final', () {
      expect(
        SpeechTranscriptPolicy.canAutoSend(
          transcript: 'The app should help me speak naturally',
          finalResultReceived: true,
          confidence: -1,
        ),
        isTrue,
      );
    });
  });

  group('SpeechTranscriptPolicy.confidencePercent', () {
    test('formats usable confidence as a percent', () {
      expect(SpeechTranscriptPolicy.confidencePercent(0.654), 65);
      expect(SpeechTranscriptPolicy.confidencePercent(1.2), isNull);
      expect(SpeechTranscriptPolicy.confidencePercent(-1), isNull);
    });
  });
}
