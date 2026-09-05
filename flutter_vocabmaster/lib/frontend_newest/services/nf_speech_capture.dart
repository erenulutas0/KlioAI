import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../services/chatbot_service.dart';
import 'nf_spoken_pace.dart';

/// How a `start()` attempt ended.
/// How an attempt to start recording ended.
///
/// [micDenied] and [micBlocked] are separate because the way out of them is
/// different. A plain denial is answered by pressing the button again and
/// saying yes to the system prompt. A blocked permission shows no prompt at
/// all -- Android stops asking after two refusals, iOS after one -- so
/// pressing the button again does nothing, forever, and the only route back is
/// the system settings page. Collapsing the two left a learner tapping a
/// button that flashed grey text and never explained itself.
enum NfCaptureStart { started, busy, micDenied, micBlocked, failed }

/// How one hold-to-speak gesture ended.
enum NfCaptureOutcome {
  /// Whisper returned words.
  transcribed,

  /// Nothing was said, or Whisper heard nothing. Never uploaded, or uploaded
  /// and came back empty.
  silent,

  /// The button was tapped rather than held.
  tooShort,

  /// `stopAndTranscribe` was called with no recording running.
  notRecording,

  /// The recorder or the transcription service failed. [NfCaptureResult.error]
  /// carries the exception so the caller can run it through
  /// `AiErrorMessageFormatter` / `AiPaywallHandler`.
  failed,
}

@immutable
class NfCaptureResult {
  const NfCaptureResult._(
    this.outcome, {
    this.transcript = '',
    this.error,
    this.pace,
  });

  final NfCaptureOutcome outcome;

  /// Trimmed transcript. Non-empty only for [NfCaptureOutcome.transcribed].
  final String transcript;

  /// How fast this was spoken, or null when the clip was too short to say.
  /// Null is "nothing to report", never "slow".
  final NfSpokenPace? pace;

  /// The thrown object for [NfCaptureOutcome.failed], so the caller can decide
  /// between a paywall, a quota message and a generic retry.
  final Object? error;
}

/// Microphone capture for the new frontend's tutor tab: record while held,
/// screen out silence, hand the clip to the same backend Whisper proxy the
/// existing chat screen uses.
///
/// The transcription itself goes through [ChatbotService.transcribeSpeech] —
/// the identical call `lib/screens/ai_bot_chat_page.dart` makes, with the same
/// `peakDb` / `rangeDb` telemetry attached.
///
/// The silence gate below is duplicated from that screen rather than shared,
/// because it lives inside `_AIBotChatPageState._stopAndSend` and extracting it
/// would mean editing a screen this frontend is not allowed to touch. When the
/// two frontends are eventually merged, this class is the piece to promote into
/// `lib/services/` and delete from both callers — the constant and the
/// behaviour must stay in step until then.
class NfSpeechCapture extends ChangeNotifier {
  NfSpeechCapture({ChatbotService? chatbot, this.onMaxDurationReached})
      : _chatbot = chatbot ?? ChatbotService();

  final ChatbotService _chatbot;

  /// Fired when a recording hits [_maxDuration]. The owner should stop and send;
  /// this class deliberately does not send on its own, so the screen stays the
  /// only place that decides what happens to a transcript.
  final VoidCallback? onMaxDurationReached;

  /// Speech is dynamic; a room is not.
  ///
  /// Copied verbatim from the existing chat screen, including the value. Level
  /// alone cannot separate "noisy room" from "someone talking" — a phone beside
  /// a running computer clears any absolute threshold loose enough to be safe
  /// for a quiet learner. Dynamic range can: between a vowel and the pause after
  /// it, speech swings tens of decibels, while a fan stays flat whatever its
  /// level.
  ///
  /// 12 dB is far below what speech produces, because a false positive here
  /// deletes something a learner actually said.
  static const double _speechDynamicRangeDb = 12.0;

  /// Well under the length of a syllable, so nothing audible slips between
  /// samples. Also drives the live level meter, at 5 Hz.
  static const Duration _sampleInterval = Duration(milliseconds: 200);

  static const Duration _maxDuration = Duration(seconds: 60);

  /// Hold-to-speak makes an accidental press trivially easy in a way the old
  /// tap-to-toggle microphone did not, and a 100 ms clip still costs a request.
  /// Set well under a deliberate one-word answer (~350 ms including the time to
  /// let go) so this can only ever catch a stray tap — and the caller says so
  /// out loud rather than dropping it silently.
  static const Duration _minimumHold = Duration(milliseconds: 300);

  static const int _meterSamples = 24;

  /// Quietest level the meter bothers to draw. Below this it is all noise floor.
  static const double _meterFloorDb = -50.0;

  final AudioRecorder _recorder = AudioRecorder();

  /// Recent microphone levels, oldest first, each normalised to 0..1. Separate
  /// from [notifyListeners] so a 5 Hz meter does not rebuild the whole screen.
  final ValueNotifier<List<double>> levels =
      ValueNotifier<List<double>>(const <double>[]);

  bool _recording = false;
  bool _transcribing = false;
  bool _disposed = false;
  String? _path;
  DateTime? _startedAt;
  Timer? _maxTimer;
  Timer? _sampleTimer;

  /// Loudest and quietest samples of the current recording, in dBFS.
  double _peakDb = -160.0;
  double _floorDb = 0.0;

  bool get isRecording => _recording;
  bool get isTranscribing => _transcribing;
  bool get isBusy => _recording || _transcribing;

  Future<NfCaptureStart> start() async {
    if (_recording || _transcribing) {
      return NfCaptureStart.busy;
    }

    final PermissionStatus status;
    try {
      status = await Permission.microphone.request();
    } catch (e) {
      // A platform that cannot even answer the question cannot record either.
      debugPrint('NfSpeechCapture permission error: $e');
      return NfCaptureStart.failed;
    }
    if (status != PermissionStatus.granted) {
      // `restricted` belongs with permanently denied rather than with denied:
      // it is iOS parental controls, where no prompt will ever appear either.
      return status == PermissionStatus.permanentlyDenied ||
              status == PermissionStatus.restricted
          ? NfCaptureStart.micBlocked
          : NfCaptureStart.micDenied;
    }
    if (_disposed) {
      return NfCaptureStart.failed;
    }

    final String path;
    try {
      final Directory dir = await getTemporaryDirectory();
      path =
          '${dir.path}/klioai_nf_speech_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('NfSpeechCapture start error: $e');
      return NfCaptureStart.failed;
    }

    if (_disposed) {
      // Torn down mid-await: stop and bin the clip rather than leak a recorder.
      unawaited(_recorder.stop());
      unawaited(_deleteQuietly(path));
      return NfCaptureStart.failed;
    }

    _recording = true;
    _path = path;
    _startedAt = DateTime.now();
    _peakDb = -160.0;
    _floorDb = 0.0;
    levels.value = const <double>[];
    _notify();

    _maxTimer?.cancel();
    _maxTimer = Timer(_maxDuration, () {
      if (_recording) {
        onMaxDurationReached?.call();
      }
    });

    _sampleTimer?.cancel();
    _sampleTimer = Timer.periodic(_sampleInterval, (_) => _sample());

    return NfCaptureStart.started;
  }

  /// Stops the recording and, if it sounded like speech, transcribes it.
  Future<NfCaptureResult> stopAndTranscribe({String locale = 'en_US'}) async {
    if (!_recording) {
      return const NfCaptureResult._(NfCaptureOutcome.notRecording);
    }

    final DateTime? startedAt = _startedAt;
    final double peakDb = _peakDb;
    final double rangeDb = _peakDb - _floorDb;
    String? path = _path;

    _maxTimer?.cancel();
    _sampleTimer?.cancel();
    try {
      path = await _recorder.stop() ?? path;
    } catch (e) {
      debugPrint('NfSpeechCapture stop error: $e');
    }

    final int durationMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;

    _recording = false;
    _path = null;
    _startedAt = null;
    levels.value = const <double>[];
    _notify();

    if (path == null || path.trim().isEmpty) {
      return const NfCaptureResult._(NfCaptureOutcome.failed);
    }

    if (durationMs < _minimumHold.inMilliseconds) {
      await _deleteQuietly(path);
      return const NfCaptureResult._(NfCaptureOutcome.tooShort);
    }

    // Never heard anything, so never ask what was said.
    //
    // Whisper does not return nothing for silence — it returns text, and this
    // screen sends whatever arrives straight to the tutor. A learner who holds
    // the button and hesitates would watch the tutor answer something they
    // never said, and pay for it out of their daily tokens. Whether there was
    // any sound at all is measurable here, before anything is uploaded.
    if (rangeDb < _speechDynamicRangeDb) {
      debugPrint('NfSpeechCapture skipping upload: '
          'peak=${peakDb.toStringAsFixed(1)} '
          'range=${rangeDb.toStringAsFixed(1)} dB');
      await _deleteQuietly(path);
      return const NfCaptureResult._(NfCaptureOutcome.silent);
    }

    _transcribing = true;
    _notify();
    try {
      // The detailed call, not the string one: it is the same request, and
      // the word timings come back on it instead of being thrown away.
      final SpeechTranscription result = await _chatbot.transcribeSpeechDetailed(
        audioPath: path,
        durationMs: durationMs,
        locale: locale,
        peakDb: peakDb,
        rangeDb: rangeDb,
      );
      final String trimmed = result.text.trim();
      if (trimmed.isEmpty) {
        return const NfCaptureResult._(NfCaptureOutcome.silent);
      }
      return NfCaptureResult._(
        NfCaptureOutcome.transcribed,
        transcript: trimmed,
        pace: NfSpokenPace.from(result.words),
      );
    } catch (e) {
      return NfCaptureResult._(NfCaptureOutcome.failed, error: e);
    } finally {
      await _deleteQuietly(path);
      _transcribing = false;
      _notify();
    }
  }

  /// Abandons the current recording without uploading it.
  Future<void> cancel() async {
    if (!_recording) {
      return;
    }

    _maxTimer?.cancel();
    _sampleTimer?.cancel();
    String? path = _path;
    try {
      path = await _recorder.stop() ?? path;
    } catch (e) {
      debugPrint('NfSpeechCapture cancel error: $e');
    }

    _recording = false;
    _path = null;
    _startedAt = null;
    levels.value = const <double>[];
    _notify();

    if (path != null && path.trim().isNotEmpty) {
      await _deleteQuietly(path);
    }
  }

  Future<void> _sample() async {
    if (!_recording) {
      return;
    }

    double current;
    try {
      final Amplitude amplitude = await _recorder.getAmplitude();
      current = amplitude.current;
      if (current > _peakDb) {
        _peakDb = current;
      }
      if (current < _floorDb) {
        _floorDb = current;
      }
    } catch (_) {
      // If the platform will not report amplitude, make the range look like
      // speech so the clip is still sent: refusing to transcribe something a
      // learner really said is the worse mistake, and the server-side checks
      // still apply. Same fail-open choice as the existing chat screen.
      _peakDb = 0;
      _floorDb = -160.0;
      current = _meterFloorDb;
    }

    if (_disposed || !_recording) {
      return;
    }

    final List<double> next = <double>[...levels.value, _normalise(current)];
    if (next.length > _meterSamples) {
      next.removeAt(0);
    }
    levels.value = next;
  }

  static double _normalise(double db) {
    if (db.isNaN) {
      return 0;
    }
    final double clamped = db.clamp(_meterFloorDb, 0.0).toDouble();
    return (clamped - _meterFloorDb) / -_meterFloorDb;
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // A leftover temp file is not worth reporting.
    }
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _maxTimer?.cancel();
    _sampleTimer?.cancel();
    final String? path = _path;
    if (_recording) {
      unawaited(_recorder.stop());
      if (path != null) {
        unawaited(_deleteQuietly(path));
      }
    }
    unawaited(_recorder.dispose());
    levels.dispose();
    super.dispose();
  }
}
