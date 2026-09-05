import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/services/nf_spoken_pace.dart';
import 'package:vocabmaster/services/chatbot_service.dart';

/// The one thing the tutor can honestly say about *how* something was said.
///
/// Pronunciation scoring is what every speaking-first competitor sells, and it
/// is not available here: Whisper gives no per-word confidence, and the one
/// confidence it does give — avg_logprob, per segment — is documented in this
/// repo as firing on unusual accents. Every learner here has one by that
/// model's standards, so a score built on it would mark a Turkish speaker for
/// sounding Turkish.
///
/// Timings carry no such judgement, which is why these tests care most about
/// the cases where the answer is *nothing*: a rate invented from two words is
/// worse than no rate, because it looks like a measurement.
void main() {
  /// Words a fifth of a second long, [gap] seconds apart, starting at [from].
  List<NfWordTiming> speech(
    int count, {
    double gap = 0.2,
    double from = 0.5,
    double wordLength = 0.3,
  }) {
    final List<NfWordTiming> words = <NfWordTiming>[];
    double cursor = from;
    for (int i = 0; i < count; i++) {
      words.add(NfWordTiming(
        word: 'w$i',
        start: cursor,
        end: cursor + wordLength,
      ));
      cursor += wordLength + gap;
    }
    return words;
  }

  test('nothing at all is not a rate of zero', () {
    expect(NfSpokenPace.from(const <NfWordTiming>[]), isNull);
  });

  test('a short answer stays unmeasured rather than measured badly', () {
    // "Yes, I did." over a second and a half is 160 words per minute by
    // arithmetic and tells nobody anything true about how they speak.
    expect(NfSpokenPace.from(speech(4)), isNull);
  });

  test('enough words but too little time is still not enough', () {
    // Ten words rattled off in two seconds: the sample is too short for the
    // rate to be about anything but that one burst.
    expect(NfSpokenPace.from(speech(10, gap: 0.0, wordLength: 0.2)), isNull);
  });

  test('a real turn reports a rate', () {
    // 12 words, 0.3s each, 0.2s apart. Word i starts at 0.5 + i*0.5, so the
    // last one ends at 6.3 and the span is 5.8 seconds -- measured from the
    // first word, not from zero.
    final NfSpokenPace pace = NfSpokenPace.from(speech(12))!;

    expect(pace.wordCount, 12);
    expect(pace.spokenSeconds, closeTo(5.8, 0.01));
    expect(pace.wordsPerMinute, 124);
  });

  test('the rate is measured over speech, not over the held button', () {
    // The clip starts long before the first word because the button is held
    // first. Counting that silence would report someone as half as fast as
    // they spoke.
    final NfSpokenPace early = NfSpokenPace.from(speech(12, from: 0.2))!;
    final NfSpokenPace late = NfSpokenPace.from(speech(12, from: 9.0))!;

    expect(early.wordsPerMinute, late.wordsPerMinute);
  });

  test('hesitation is counted, ordinary rhythm is not', () {
    final List<NfWordTiming> words = speech(12);
    // Gaps, in order: 0.9s before "because", 1.8s before "I", 0.2s, 1.5s
    // before "maybe", 0.2s. Three of them clear 0.8s; the two short ones are
    // the rhythm of a sentence and must not count.
    final List<NfWordTiming> withPauses = <NfWordTiming>[
      ...words.take(4),
      NfWordTiming(word: 'because', start: 3.2, end: 3.6),
      NfWordTiming(word: 'I', start: 5.4, end: 5.6),
      NfWordTiming(word: 'think', start: 5.8, end: 6.1),
      NfWordTiming(word: 'maybe', start: 7.6, end: 8.0),
      NfWordTiming(word: 'yes', start: 8.2, end: 8.5),
    ];

    expect(NfSpokenPace.from(words)!.longPauses, 0,
        reason: '0.2s between words is speech, not hesitation');
    expect(NfSpokenPace.from(withPauses)!.longPauses, 3);
  });

  test('words that run together are not negative pauses', () {
    // The model overlaps neighbours when they are said as one, which is the
    // opposite of hesitating.
    final List<NfWordTiming> slurred = <NfWordTiming>[
      for (int i = 0; i < 12; i++)
        NfWordTiming(word: 'w$i', start: i * 0.4, end: i * 0.4 + 0.5),
    ];

    final NfSpokenPace pace = NfSpokenPace.from(slurred)!;
    expect(pace.longPauses, 0);
    expect(pace.wordsPerMinute, greaterThan(0));
  });

  test('a malformed word costs that word, not the transcript', () {
    // Model output that has crossed a JSON boundary. One unreadable entry
    // must not take the turn with it.
    expect(NfWordTiming.fromJson(null), isNull);
    expect(NfWordTiming.fromJson(<String, Object?>{'word': 'hi'}), isNull);
    expect(
        NfWordTiming.fromJson(
            <String, Object?>{'word': '', 'start': 0, 'end': 1}),
        isNull);

    final NfWordTiming? ok = NfWordTiming.fromJson(
        <String, Object?>{'word': 'hi', 'start': 1, 'end': 1.4});
    expect(ok, isNotNull);
    expect(ok!.word, 'hi');
    expect(ok.start, 1.0);
    expect(ok.end, 1.4);
  });
}
