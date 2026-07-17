# Pronunciation Practice MVP

Last update: 2026-06-03 Europe/Istanbul

## Product Goal

Pronunciation Practice gives the learner a short English text, lets them listen
to a model voice, records their reading, transcribes the audio, and returns a
clear practice report.

The first version is intentionally a shadowing and readability report, not a
strict phoneme-level pronunciation diagnosis.

## Current MVP Flow

1. Flutter shows a CEFR-level text prompt.
2. The learner can play a model reading through existing Piper TTS.
3. The learner records their voice with the existing `record` package.
4. Flutter sends the temporary audio file to the existing backend Whisper proxy:
   `POST /api/chatbot/speech/transcribe`.
5. Flutter compares target text and detected transcript locally.
6. Flutter shows:
   - overall score
   - text-match score
   - reading-pace score
   - detected transcript
   - missing or unclear words
   - extra detected words

## Scoring Method

Source file:

- `flutter_vocabmaster/lib/services/pronunciation_report_service.dart`

The MVP uses word-level transcript alignment:

- Normalize target text and transcript.
- Tokenize into words.
- Use edit-distance alignment to detect matches, deletions, insertions, and
  substitutions.
- Compute text-match accuracy from word-level edit distance.
- Compute pace from words per minute.
- Combine:
  - 75% text-match accuracy
  - 25% pace score

This is useful for learner feedback because it catches omitted words, unclear
words, and overly fast/slow readings without claiming precise phonetic analysis.

## Thesis Positioning

This feature can be described as an AI-assisted pronunciation practice module
using:

- text-to-speech for reference audio
- automatic speech recognition for learner speech transcription
- word-level sequence alignment for feedback generation
- mobile UX for repeated self-practice

The thesis should explicitly state that the MVP evaluates transcript similarity
and reading fluency proxies. It does not yet perform acoustic phoneme-level
diagnosis or forced alignment.

## UI Labeling Policy (2026-07-08)

The report UI is titled "Reading Clarity Report" (TR: "Okuma Netligi Raporu"),
and the Practice-page card uses the same clarity framing. This is deliberate:
the MVP scores transcript alignment and pace, and the product must not claim
phoneme-level pronunciation accuracy before the forced-alignment/GOP upgrade
below ships. Keep "pronunciation" as the practice-mode name (it describes the
activity), but keep score/report labels clarity-based.

## Limitations

- Whisper transcription can mishear accented speech, background noise, or short
  single words.
- Word-level comparison cannot know whether a correctly transcribed word was
  pronounced natively.
- Pace scoring is approximate and should be treated as coaching feedback.
- Audio is processed transiently; the MVP does not store raw recordings.

## Future Work

Good next research/product upgrades:

- forced alignment for word timing
- phoneme-level feedback with confidence thresholds
- user progress history per sound cluster
- minimal-pair drills for Turkish-speaking learners
- AI-generated texts based on user weak areas
- teacher/exportable report view for thesis demos
