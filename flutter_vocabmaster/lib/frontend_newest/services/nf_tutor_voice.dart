import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/voice_model.dart';

/// Who the learner's tutor currently is, shared across the new frontend.
///
/// The tutor tab is not the only screen that names the speaker — the Today tab
/// offers a shortcut into the conversation and greets them by name. Before this
/// existed the tab owned the preference privately, so Today hardcoded "Amy" and
/// went on saying it after the learner switched to Ryan.
///
/// A plain [ValueNotifier] rather than a provider: the value has to be readable
/// from `initState` and from a screen that is not below any particular subtree,
/// and registering it in `main.dart` would mean editing a file outside this
/// frontend for a single string.
class NfTutorVoice {
  const NfTutorVoice._();

  /// Shared with `lib/screens/ai_bot_chat_page.dart` on purpose: while both
  /// frontends ship in one build, the learner should not have to introduce
  /// themselves to a different tutor depending on which UI they opened.
  static const String prefsKey = 'selected_voice';

  /// The two speakers in the approved design. Both are looked up in
  /// [VoiceModel.availableVoices] so the avatar, Piper voice and locale stay
  /// defined in exactly one place.
  static final List<VoiceModel> speakers = <VoiceModel>[
    _byId('amy'),
    _byId('ryan'),
  ];

  /// The speaker on screen. Starts at the default and is corrected by
  /// [ensureLoaded]; listeners are notified when either that read or a
  /// [select] changes it.
  static final ValueNotifier<VoiceModel> current =
      ValueNotifier<VoiceModel>(speakers.first);

  static Future<void>? _loading;

  /// Reads the stored speaker once per process. Repeat calls await the first
  /// read rather than starting another, so several screens may call this in
  /// their `initState` without racing each other.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(prefsKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final VoiceModel saved = VoiceModel.fromJsonString(stored);
      // This frontend offers two speakers. A voice picked in the old chat
      // screen that is not one of them leaves the default standing rather than
      // naming a speaker the switcher cannot get back to.
      current.value = speakers.firstWhere(
        (VoiceModel candidate) => candidate.id == saved.id,
        orElse: () => speakers.first,
      );
    } catch (error) {
      debugPrint('NfTutorVoice load failed: $error');
    }
  }

  /// Records the learner's choice. The in-memory value moves first so the UI
  /// never waits on the disk write.
  static Future<void> select(VoiceModel voice) async {
    current.value = voice;
    // A later call to [ensureLoaded] must not overwrite this with the older
    // stored value, so mark the read as already done.
    _loading ??= Future<void>.value();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, voice.toJsonString());
    } catch (error) {
      debugPrint('NfTutorVoice save failed: $error');
    }
  }

  static VoiceModel _byId(String id) => VoiceModel.availableVoices.firstWhere(
        (VoiceModel voice) => voice.id == id,
        orElse: () => VoiceModel.availableVoices.first,
      );
}
