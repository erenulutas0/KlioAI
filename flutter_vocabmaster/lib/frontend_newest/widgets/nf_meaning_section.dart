import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../theme/nf_tokens.dart';
import 'nf_card.dart';
import 'nf_chip.dart';

/// One sense of a word, drawn as a section: the translation as its heading, an
/// optional definition under it, the sentences written for that sense, and the
/// affordance to add another sentence *for this sense* — which is the whole
/// point of the meanings model.
///
/// The same widget renders the **unassigned** group: sentences whose
/// `meaningId` is null (all backfilled data starts that way). That variant has
/// no edit/delete of its own — there is nothing to edit — and each of its
/// sentences carries an "assign" affordance instead, supplied by the page
/// through [onAssignSentence].
///
/// Purely presentational: every mutation leaves through a callback, so the
/// page owns the API calls, the offline path and the error copy. A callback
/// left null simply hides its affordance rather than rendering a dead control.
class NfMeaningSection extends StatelessWidget {
  const NfMeaningSection({
    super.key,
    required this.headword,
    required this.title,
    this.ordinal,
    this.definition,
    this.explainer,
    this.emptyLine,
    required this.sentences,
    this.unassigned = false,
    this.onAddSentence,
    this.onEditMeaning,
    this.onDeleteMeaning,
    this.onDeleteSentence,
    this.onAssignSentence,
    this.onSpeakSentence,
  });

  /// The word itself, highlighted wherever it appears inside a sentence.
  final String headword;

  /// The meaning's translation — the section heading. For the unassigned
  /// group, the group's name.
  final String title;

  /// 1-based position shown as a small "MEANING n" pill. Null hides the pill
  /// (the unassigned group, or the single fallback section).
  final int? ordinal;

  /// Optional definition, under the heading in quieter ink.
  final String? definition;

  /// One quiet line under the header. The unassigned section uses this to
  /// explain itself; the fallback section uses it to say why editing is off.
  final String? explainer;

  /// Shown instead of sentence rows when [sentences] is empty.
  final String? emptyLine;

  final List<Sentence> sentences;

  /// Marks the unassigned group: no ordinal, muted heading treatment.
  final bool unassigned;

  /// "Add sentence for this meaning". Null hides the row.
  final VoidCallback? onAddSentence;

  /// Edit this meaning. Null hides the pencil.
  final VoidCallback? onEditMeaning;

  /// Delete this meaning. Null hides the bin. The page surfaces the server's
  /// last-meaning refusal; this widget only reports the tap.
  final VoidCallback? onDeleteMeaning;

  /// Delete one sentence (after the page's own confirm step).
  final ValueChanged<Sentence>? onDeleteSentence;

  /// Assign one unassigned sentence to a meaning via the page's picker.
  final ValueChanged<Sentence>? onAssignSentence;

  /// Read one sentence aloud.
  final ValueChanged<Sentence>? onSpeakSentence;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NfSpace.s16,
              NfSpace.s14,
              NfSpace.s8,
              NfSpace.s14,
            ),
            child: _buildHeader(context, t),
          ),
          if (sentences.isEmpty && emptyLine != null) ...<Widget>[
            _divider(t),
            Padding(
              padding: const EdgeInsets.all(NfSpace.s16),
              child: Text(
                emptyLine!,
                style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
              ),
            ),
          ] else
            for (final Sentence sentence in sentences) ...<Widget>[
              _divider(t),
              _NfSentenceTile(
                sentence: sentence,
                headword: headword,
                onDelete: onDeleteSentence == null
                    ? null
                    : () => onDeleteSentence!(sentence),
                onAssign: onAssignSentence == null
                    ? null
                    : () => onAssignSentence!(sentence),
                onSpeak: onSpeakSentence == null
                    ? null
                    : () => onSpeakSentence!(sentence),
              ),
            ],
          if (onAddSentence != null) ...<Widget>[
            _divider(t),
            _AddSentenceRow(onTap: onAddSentence!),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Padding(
                // Lines the text up with the 44px icon targets beside it.
                padding: const EdgeInsets.only(top: NfSpace.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (ordinal != null) ...<Widget>[
                      NfChip(
                        label: context.tr('word.meaningOrdinal').replaceAll('{n}', '$ordinal'),
                        variant: NfChipVariant.selected,
                        dense: true,
                      ),
                      const SizedBox(height: NfSpace.s8),
                    ],
                    Text(
                      title,
                      style: NfTokens.display(
                        size: NfFont.s17,
                        color: unassigned ? t.inkMuted : t.ink,
                      ),
                    ),
                    if (definition != null &&
                        definition!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s4),
                      Text(
                        definition!,
                        style:
                            NfTokens.body(size: NfFont.s13, color: t.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onEditMeaning != null)
              _IconAction(
                icon: Icons.edit_outlined,
                semanticLabel: context.tr('word.editMeaning'),
                color: t.inkMuted,
                onTap: onEditMeaning!,
              ),
            if (onDeleteMeaning != null)
              _IconAction(
                icon: Icons.delete_outline_rounded,
                semanticLabel: context.tr('word.deleteMeaning'),
                color: t.inkMuted,
                onTap: onDeleteMeaning!,
              ),
          ],
        ),
        if (explainer != null && explainer!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: NfSpace.s6),
          Padding(
            padding: const EdgeInsets.only(right: NfSpace.s8),
            child: Text(
              explainer!,
              style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
            ),
          ),
        ],
      ],
    );
  }

  static Widget _divider(NfTokens t) {
    return Divider(
      height: NfStroke.border,
      thickness: NfStroke.border,
      color: t.border,
    );
  }
}

/// The full-width "add sentence for this meaning" row at the bottom of a
/// section. A row rather than a button so it reads as part of the section it
/// adds to, not as a page-level action.
class _AddSentenceRow extends StatelessWidget {
  const _AddSentenceRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Semantics(
      button: true,
      label: context.tr('word.addSentenceForMeaning'),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 48, // clears NfSize.minTap
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.add_rounded, size: 18, color: t.primaryText),
                const SizedBox(width: NfSpace.s6),
                Text(
                  // TODO(i18n): needs a key
                  context.tr('word.addSentence'),
                  style:
                      NfTokens.display(size: NfFont.s14, color: t.primaryText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One sentence inside a section.
///
/// Carries over the legacy modal's behaviour per sentence: the difficulty
/// badge, the listen action, the headword highlighted inside the sentence
/// (inflections included), and the show/hide translation toggle — restated in
/// this design's tokens instead of glass and glow.
class _NfSentenceTile extends StatefulWidget {
  const _NfSentenceTile({
    required this.sentence,
    required this.headword,
    required this.onDelete,
    required this.onAssign,
    required this.onSpeak,
  });

  final Sentence sentence;
  final String headword;
  final VoidCallback? onDelete;
  final VoidCallback? onAssign;
  final VoidCallback? onSpeak;

  @override
  State<_NfSentenceTile> createState() => _NfSentenceTileState();
}

class _NfSentenceTileState extends State<_NfSentenceTile> {
  bool _showTranslation = false;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final Sentence s = widget.sentence;
    final bool hasTranslation = s.translation.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _DifficultyChip(difficulty: s.difficulty),
              const Spacer(),
              if (widget.onSpeak != null)
                _IconAction(
                  icon: Icons.volume_up_rounded,
                  semanticLabel: context.tr('word.listen'),
                  color: t.primaryText,
                  onTap: widget.onSpeak!,
                ),
              if (widget.onDelete != null)
                _IconAction(
                  icon: Icons.delete_outline_rounded,
                  semanticLabel: context.tr('word.deleteSentence'),
                  color: t.inkFaint,
                  onTap: widget.onDelete!,
                ),
            ],
          ),
          const SizedBox(height: NfSpace.s6),
          Padding(
            padding: const EdgeInsets.only(right: NfSpace.s8),
            child: Text.rich(
              TextSpan(children: _highlightSpans(t)),
            ),
          ),
          if (_showTranslation && hasTranslation) ...<Widget>[
            const SizedBox(height: NfSpace.s10),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(right: NfSpace.s8),
              padding: const EdgeInsets.all(NfSpace.s12),
              decoration: BoxDecoration(
                color: t.raised,
                borderRadius: NfRadius.tileAll,
                border: Border.fromBorderSide(t.side),
              ),
              child: Text(
                s.translation,
                style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
              ),
            ),
          ],
          if (hasTranslation || widget.onAssign != null) ...<Widget>[
            const SizedBox(height: NfSpace.s8),
            Wrap(
              spacing: NfSpace.s8,
              runSpacing: NfSpace.s4,
              children: <Widget>[
                if (hasTranslation)
                  NfChip(
                    label: _showTranslation
                        ? context.tr('word.hideTranslation')
                        : context.tr('word.showTranslation'),
                    icon: _showTranslation
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    variant: NfChipVariant.unselected,
                    dense: true,
                    onTap: () =>
                        setState(() => _showTranslation = !_showTranslation),
                  ),
                if (widget.onAssign != null)
                  NfChip(
                    label: context.tr('word.assignToMeaning'),
                    icon: Icons.label_outline_rounded,
                    variant: NfChipVariant.selected,
                    dense: true,
                    onTap: widget.onAssign,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The sentence with every occurrence of the headword highlighted.
  ///
  /// Same matching rule as the legacy modal: inflected forms are swallowed
  /// whole ("recovered", "recovering"), because a highlight that stops at
  /// "recover" and leaves "ed" outside looks broken. The highlight itself is a
  /// tinted text run, not a glowing chip — this design does not glow.
  List<TextSpan> _highlightSpans(NfTokens t) {
    final String sentence = widget.sentence.sentence;
    final TextStyle base =
        NfTokens.body(size: NfFont.s15, color: t.ink, height: 1.5);
    final String needle = widget.headword.trim();

    if (needle.isEmpty) {
      return <TextSpan>[TextSpan(text: sentence, style: base)];
    }

    final RegExp regex = RegExp(
      "[A-Za-z']*${RegExp.escape(needle)}[A-Za-z']*",
      caseSensitive: false,
    );
    final Iterable<RegExpMatch> matches = regex.allMatches(sentence);
    if (matches.isEmpty) {
      return <TextSpan>[TextSpan(text: sentence, style: base)];
    }

    final TextStyle highlight = base.copyWith(
      color: t.primaryText,
      fontWeight: NfTokens.bodyEmphasisWeight,
      backgroundColor: t.primarySoft,
    );

    final List<TextSpan> spans = <TextSpan>[];
    int lastEnd = 0;
    for (final RegExpMatch match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: sentence.substring(lastEnd, match.start),
          style: base,
        ));
      }
      spans.add(TextSpan(
        text: sentence.substring(match.start, match.end),
        style: highlight,
      ));
      lastEnd = match.end;
    }
    if (lastEnd < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(lastEnd), style: base));
    }
    return spans;
  }
}

/// The easy/medium/hard badge, in this frontend's semantic colours. Semantic
/// meaning never changes: green is "easy/correct", amber is "warm", red is
/// "hard/wrong" — the same reading those tokens have everywhere else.
class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.difficulty});

  final String? difficulty;

  @override
  Widget build(BuildContext context) {
    final String value = (difficulty ?? 'medium').trim().toLowerCase();

    final String label;
    final NfChipVariant variant;
    switch (value) {
      case 'easy':
      case 'kolay':
        label = context.tr('word.difficulty.easy');
        variant = NfChipVariant.correct;
        break;
      case 'hard':
      case 'zor':
        label = context.tr('word.difficulty.hard');
        variant = NfChipVariant.wrong;
        break;
      case 'medium':
      case 'orta':
      default:
        label = context.tr('word.difficulty.medium');
        variant = NfChipVariant.streak;
        break;
    }

    return NfChip(label: label, variant: variant, dense: true);
  }
}

/// A 44x44 icon target. The glyph is small; the target is not.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.semanticLabel,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: NfSize.minTap,
            height: NfSize.minTap,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}
