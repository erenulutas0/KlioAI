import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/rating_prompt_service.dart';
import '../theme/nf_tokens.dart';

/// Where a rating is: waiting for stars, waiting for a note, or done.
enum NfRatingStage { asking, note, thanks }

/// The state of one rating, kept outside the widget that draws it.
///
/// The tutor shows the question inside its conversation list, and a list throws away the
/// state of a row that scrolls off screen. Held in a row, a note half written would vanish
/// when the learner scrolled up to reread the conversation, and the question would come back
/// unanswered -- to be answered, and sent, a second time. Held here, the row is only a view.
class NfRatingController extends ChangeNotifier {
  NfRatingController({required this.onSubmit});

  /// Called exactly once, with the stars and the note, or null when there is none.
  final Future<void> Function(int stars, String? note) onSubmit;

  final TextEditingController note = TextEditingController();

  NfRatingStage _stage = NfRatingStage.asking;
  int _stars = 0;
  bool _submitted = false;

  NfRatingStage get stage => _stage;
  int get stars => _stars;
  bool get submitted => _submitted;

  void choose(int value) {
    if (_submitted || value < 1 || value > 5) {
      return;
    }
    _stars = value;
    if (nfRatingWantsNote(value)) {
      _stage = NfRatingStage.note;
      notifyListeners();
      return;
    }
    _submit(null);
  }

  void send() => _submit(note.text);

  void skip() => _submit(null);

  /// A low rating still waiting on its note goes out without one: the stars are the part
  /// that was answered. Called when the conversation it belongs to ends.
  void flush() {
    if (!_submitted && _stars > 0) {
      _submit(null);
    }
  }

  void _submit(String? text) {
    if (_submitted || _stars == 0) {
      return;
    }
    _submitted = true;
    _stage = NfRatingStage.thanks;
    notifyListeners();
    final String? trimmed = text?.trim();
    unawaited(onSubmit(_stars, trimmed == null || trimmed.isEmpty ? null : trimmed)
        .catchError((Object e) => debugPrint('Rating not sent: $e')));
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }
}

/// Five stars, one tap each.
class NfStarRow extends StatelessWidget {
  const NfStarRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 34,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 1; i <= 5; i++)
          Semantics(
            button: true,
            label: context.tr('rating.star').replaceAll('{n}', '$i'),
            child: InkResponse(
              key: ValueKey<String>('rating-star-$i'),
              onTap: onChanged == null ? null : () => onChanged!(i),
              radius: size * 0.7,
              child: Padding(
                padding: const EdgeInsets.all(NfSpace.s4),
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: i <= value ? t.streak : t.inkFaint,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "How was this?" -- stars, then a note when the stars are low, then thanks.
class NfRatingCard extends StatelessWidget {
  const NfRatingCard({
    super.key,
    required this.controller,
    required this.title,
    this.onDismiss,
    this.onDontAskAgain,
  });

  final NfRatingController controller;
  final String title;

  /// The close button, shown while the question is unanswered. Null hides it.
  final VoidCallback? onDismiss;

  /// A "don't ask again" link under the stars. Null hides it.
  final VoidCallback? onDontAskAgain;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            key: const ValueKey<String>('rating-card'),
            padding: const EdgeInsets.fromLTRB(
                NfSpace.s16, NfSpace.s14, NfSpace.s12, NfSpace.s14),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(NfRadius.card),
              border: Border.fromBorderSide(t.side),
            ),
            child: switch (controller.stage) {
              NfRatingStage.asking => _asking(context, t),
              NfRatingStage.note => _note(context, t),
              NfRatingStage.thanks => _thanks(context, t),
            },
          ),
        );
      },
    );
  }

  Widget _asking(BuildContext context, NfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: NfSpace.s4),
                child: Text(title,
                    style: NfTokens.body(size: NfFont.s15, color: t.ink, weight: FontWeight.w700)),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                key: const ValueKey<String>('rating-dismiss'),
                tooltip: context.tr('rating.close'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: t.inkFaint, size: 20),
                onPressed: onDismiss,
              ),
          ],
        ),
        const SizedBox(height: NfSpace.s4),
        Text(context.tr('rating.subtitle'),
            style: NfTokens.body(size: NfFont.s13, color: t.inkMuted)),
        const SizedBox(height: NfSpace.s10),
        Center(child: NfStarRow(value: controller.stars, onChanged: controller.choose)),
        if (onDontAskAgain != null)
          Center(
            child: TextButton(
              key: const ValueKey<String>('rating-dont-ask'),
              onPressed: onDontAskAgain,
              child: Text(context.tr('rating.dontAsk'),
                  style: NfTokens.body(size: NfFont.s13, color: t.inkFaint)),
            ),
          ),
      ],
    );
  }

  Widget _note(BuildContext context, NfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(child: NfStarRow(value: controller.stars, onChanged: null, size: 26)),
        const SizedBox(height: NfSpace.s10),
        Text(context.tr('rating.note.title'),
            style: NfTokens.body(size: NfFont.s15, color: t.ink, weight: FontWeight.w700)),
        const SizedBox(height: NfSpace.s8),
        TextField(
          key: const ValueKey<String>('rating-note'),
          controller: controller.note,
          maxLines: 3,
          minLines: 2,
          maxLength: 500,
          style: NfTokens.body(size: NfFont.s14, color: t.ink),
          decoration: InputDecoration(
            hintText: context.tr('rating.note.hint'),
            hintStyle: NfTokens.body(size: NfFont.s14, color: t.inkFaint),
            counterStyle: NfTokens.body(size: NfFont.s115, color: t.inkFaint),
            filled: true,
            fillColor: t.raised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NfRadius.control),
              borderSide: t.side,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NfRadius.control),
              borderSide: t.side,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NfRadius.control),
              borderSide: BorderSide(color: t.primary, width: NfStroke.border),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('rating-skip'),
              onPressed: controller.skip,
              child: Text(context.tr('rating.skip'),
                  style: NfTokens.body(size: NfFont.s14, color: t.inkMuted)),
            ),
            const SizedBox(width: NfSpace.s8),
            FilledButton(
              key: const ValueKey<String>('rating-send'),
              style: FilledButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.primaryInk,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NfRadius.pill)),
              ),
              onPressed: controller.send,
              child: Text(context.tr('rating.send')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _thanks(BuildContext context, NfTokens t) {
    return Row(
      children: <Widget>[
        Icon(Icons.favorite_rounded, color: t.correct, size: 20),
        const SizedBox(width: NfSpace.s10),
        Expanded(
          child: Text(context.tr('rating.thanks'),
              style: NfTokens.body(size: NfFont.s14, color: t.ink, weight: FontWeight.w600)),
        ),
      ],
    );
  }
}
