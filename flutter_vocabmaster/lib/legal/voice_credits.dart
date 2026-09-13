import 'package:flutter/foundation.dart';

/// The voices and the speech model the tutor speaks with, on the licence page.
///
/// Flutter's licence page lists every package the app is built from, but not what
/// runs on the server, and the voice the learner hears is made there. The model is
/// Kokoro-82M, Apache 2.0. When it cannot answer the server falls back to Piper
/// voices, and two of those carry obligations of their own: Jenny (Dioco) is licensed
/// for commercial use on condition of attribution, and amy and alan are CC BY-SA 4.0,
/// which requires credit and a link to the licence. Two voices the app used to ship,
/// lessac and RyanSpeech, were removed because their licences exclude commercial use
/// -- see VoiceLicenceTest on the server -- and are deliberately not listed.
///
/// Only what was checked against each licence's own source is written here.
class VoiceCredits {
  VoiceCredits._();

  static bool _registered = false;

  @visibleForTesting
  static const String kokoroPackage = 'Kokoro-82M (tutor voice)';

  @visibleForTesting
  static const String piperPackage = 'Piper voices (fallback tutor voices)';

  /// Adds the entries to [LicenseRegistry]. Safe to call more than once.
  static void register() {
    if (_registered) {
      return;
    }
    _registered = true;
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(<String>[kokoroPackage], '''
The tutor's voice is generated on KlioAI's servers with the Kokoro-82M text-to-speech model by hexgrad.

Licensed under the Apache License, Version 2.0.
https://www.apache.org/licenses/LICENSE-2.0
https://huggingface.co/hexgrad/Kokoro-82M''');
      yield const LicenseEntryWithLineBreaks(<String>[piperPackage], '''
When the primary voice is unavailable, replies are spoken with Piper voice models.
https://huggingface.co/rhasspy/piper-voices

en_GB-jenny_dioco: voice by Jenny (Dioco). Commercial use is licensed on condition of this attribution.

en_US-amy and en_GB-alan: from the mimic3-voices collection, licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0).
https://creativecommons.org/licenses/by-sa/4.0/

en_GB-cori: public domain.''');
    });
  }
}
