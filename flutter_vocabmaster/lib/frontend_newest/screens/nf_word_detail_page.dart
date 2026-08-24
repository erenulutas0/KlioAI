import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../services/api_service.dart';
import '../../services/xp_manager.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import '../widgets/nf_meaning_section.dart';
import '../widgets/nf_progress.dart';
import 'nf_words_page.dart' show strengthDotsFor;

/// The word detail screen: headword, SRS state, and the word's meanings as
/// sections — each with its own sentences and its own "add sentence"
/// affordance. This is the replacement for `lib/widgets/word_sentences_modal.dart`,
/// which showed one flat sentence list; the sections are what make "one
/// sentence per sense" a thing a learner can actually do.
///
/// Behaviour carried over from the legacy modal and the legacy word screens:
/// sentence list with the headword highlighted (inflections included), listen
/// via TTS, show/hide translation per sentence, add and delete sentences
/// through [AppStateProvider] so the offline queue keeps working.
///
/// New in this screen: meaning add/edit/delete over [ApiService], the
/// unassigned section for backfilled sentences, and assigning an unassigned
/// sentence to a meaning.
///
/// Write paths, deliberately split:
///  * sentence add with **no** meaning and every sentence delete go through
///    [AppStateProvider] — that path is offline-first and owns XP;
///  * anything that must carry a `meaningId` (meaning CRUD, meaning-attached
///    sentence adds) talks to [ApiService] directly, because the offline queue
///    does not know the field. Those actions need the network, and the screen
///    says so instead of silently dropping the link.
class NfWordDetailPage extends StatefulWidget {
  const NfWordDetailPage({super.key, required this.word, this.apiService});

  /// The word as the caller had it. The page re-fetches the server copy on
  /// open, because words loaded from the local database arrive without
  /// meanings and without sentence-to-meaning links.
  final Word word;

  /// Injectable for tests; defaults to the shared implementation.
  final ApiService? apiService;

  @override
  State<NfWordDetailPage> createState() => _NfWordDetailPageState();
}

class _NfWordDetailPageState extends State<NfWordDetailPage> {
  late final ApiService _api;
  final FlutterTts _tts = FlutterTts();

  /// The page's single copy of the word. Every mutation lands here first, so
  /// the screen never has to merge three disagreeing sources in build().
  late Word _word;

  /// True while the opening server fetch is in flight.
  bool _hydrating = false;

  /// The opening fetch failed — most likely offline. Meanings may be missing,
  /// and the screen says so rather than pretending the word has none.
  bool _hydrateFailed = false;

  /// One mutation at a time. Cheap, and it prevents the classic double-tap
  /// duplicate sentence.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _word = widget.word;
    // Negative ids are local-only words the sync queue has not pushed yet;
    // the server has nothing to say about them.
    if (_word.id > 0) {
      unawaited(_hydrate());
    }
    _api = widget.apiService ?? ApiService();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _hydrate() async {
    setState(() {
      _hydrating = true;
      _hydrateFailed = false;
    });
    try {
      final Word fresh = await _api.getWordById(_word.id);
      if (!mounted) return;
      setState(() {
        _word = fresh;
        _hydrating = false;
      });
    } catch (e) {
      debugPrint('NfWordDetailPage: hydrate failed ($e)');
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _hydrateFailed = true;
      });
    }
  }

  /// Provider results come from the local database, which stores neither
  /// meanings nor sentence-to-meaning links. Adopting such a word wholesale
  /// would wipe both off the screen — so the provider copy wins on sentences
  /// and SRS fields, while meanings and known links are carried over.
  Word _mergeProviderWord(Word providerWord) {
    final Map<int, int?> knownLinks = <int, int?>{
      for (final Sentence s in _word.sentences) s.id: s.meaningId,
    };
    final List<Sentence> sentences = providerWord.sentences.map((Sentence s) {
      final int? known = knownLinks[s.id];
      if (s.meaningId != null || known == null) return s;
      return Sentence(
        id: s.id,
        sentence: s.sentence,
        translation: s.translation,
        wordId: s.wordId,
        difficulty: s.difficulty,
        createdAt: s.createdAt,
        meaningId: known,
      );
    }).toList();

    return Word(
      id: providerWord.id,
      englishWord: providerWord.englishWord.isNotEmpty
          ? providerWord.englishWord
          : _word.englishWord,
      turkishMeaning: providerWord.turkishMeaning.isNotEmpty
          ? providerWord.turkishMeaning
          : _word.turkishMeaning,
      learnedDate: providerWord.learnedDate,
      notes: providerWord.notes ?? _word.notes,
      difficulty: providerWord.difficulty,
      nextReviewDate: providerWord.nextReviewDate ?? _word.nextReviewDate,
      reviewCount: providerWord.reviewCount,
      easeFactor: providerWord.easeFactor ?? _word.easeFactor,
      lastReviewDate: providerWord.lastReviewDate ?? _word.lastReviewDate,
      sentences: sentences,
      meanings: _word.meanings,
      languageProfileId:
          providerWord.languageProfileId ?? _word.languageProfileId,
      origin: providerWord.origin ?? _word.origin,
    );
  }

  Word _withoutSentence(Word word, int sentenceId) {
    return _cloneWith(
      word,
      sentences:
          word.sentences.where((Sentence s) => s.id != sentenceId).toList(),
    );
  }

  /// Local application of a successful meaning delete: the meaning goes, its
  /// sentences become unassigned — exactly what the server does.
  Word _withMeaningDeleted(Word word, int meaningId) {
    return _cloneWith(
      word,
      meanings:
          word.meanings.where((WordMeaning m) => m.id != meaningId).toList(),
      sentences: word.sentences.map((Sentence s) {
        if (s.meaningId != meaningId) return s;
        return Sentence(
          id: s.id,
          sentence: s.sentence,
          translation: s.translation,
          wordId: s.wordId,
          difficulty: s.difficulty,
          createdAt: s.createdAt,
        );
      }).toList(),
    );
  }

  static Word _cloneWith(
    Word word, {
    List<Sentence>? sentences,
    List<WordMeaning>? meanings,
  }) {
    return Word(
      id: word.id,
      englishWord: word.englishWord,
      turkishMeaning: word.turkishMeaning,
      learnedDate: word.learnedDate,
      notes: word.notes,
      difficulty: word.difficulty,
      nextReviewDate: word.nextReviewDate,
      reviewCount: word.reviewCount,
      easeFactor: word.easeFactor,
      lastReviewDate: word.lastReviewDate,
      sentences: sentences ?? word.sentences,
      meanings: meanings ?? word.meanings,
      languageProfileId: word.languageProfileId,
      origin: word.origin,
    );
  }

  // ---------------------------------------------------------------------------
  // Actions: speech
  // ---------------------------------------------------------------------------

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.setLanguage('en-US');
    await _tts.speak(text);
  }

  // ---------------------------------------------------------------------------
  // Actions: meanings
  // ---------------------------------------------------------------------------

  Future<void> _addMeaning() async {
    final _MeaningDraft? draft = await _showMeaningEditor();
    if (draft == null || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      final Word updated = await _api.addWordMeaning(
        wordId: _word.id,
        translation: draft.translation,
        definition: draft.definition,
      );
      if (!mounted) return;
      setState(() => _word = updated);
      _nudgeProviderSync();
    } catch (e) {
      debugPrint('NfWordDetailPage: add meaning failed ($e)');
      // TODO(i18n): needs a key
      _showMessage('The meaning could not be saved. Are you online?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editMeaning(WordMeaning meaning) async {
    final _MeaningDraft? draft = await _showMeaningEditor(existing: meaning);
    if (draft == null || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      final Word updated = await _api.updateWordMeaning(
        wordId: _word.id,
        meaningId: meaning.id,
        translation: draft.translation,
        // Always sent, so clearing a definition sticks; the server leaves
        // only *absent* fields untouched.
        definition: draft.definition ?? '',
      );
      if (!mounted) return;
      setState(() => _word = updated);
      _nudgeProviderSync();
    } catch (e) {
      debugPrint('NfWordDetailPage: update meaning failed ($e)');
      // TODO(i18n): needs a key
      _showMessage('The meaning could not be updated. Are you online?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMeaning(WordMeaning meaning) async {
    final bool confirmed = await _confirm(
      // TODO(i18n): needs a key
      title: 'Delete this meaning?',
      // TODO(i18n): needs a key
      body: 'Its sentences stay on the word and move to Unassigned.',
      // TODO(i18n): needs a key
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      final Word? updated = await _api.deleteWordMeaning(
        wordId: _word.id,
        meaningId: meaning.id,
      );
      if (!mounted) return;
      setState(
        () => _word = updated ?? _withMeaningDeleted(_word, meaning.id),
      );
      _nudgeProviderSync();
    } on ApiLastMeaningException catch (e) {
      // The server's last-meaning rule, surfaced with the server's own reason:
      // a word with no meaning teaches nothing.
      _showMessage(e.message);
    } catch (e) {
      debugPrint('NfWordDetailPage: delete meaning failed ($e)');
      // TODO(i18n): needs a key
      _showMessage('The meaning could not be deleted. Are you online?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions: sentences
  // ---------------------------------------------------------------------------

  Future<void> _addSentence({WordMeaning? defaultMeaning}) async {
    final _SentenceDraft? draft = await _showSentenceEditor(
      defaultMeaningId: defaultMeaning?.id,
    );
    if (draft == null || !mounted || _busy) return;

    final AppStateProvider appState = context.read<AppStateProvider>();
    if (appState.hasSentenceForWord(_word, draft.sentence)) {
      // TODO(i18n): needs a key
      _showMessage('This sentence is already on the word.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (draft.meaningId == null) {
        await _addSentenceViaProvider(appState, draft);
      } else {
        await _addSentenceWithMeaning(appState, draft);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The legacy path, verbatim: [AppStateProvider.addSentenceToWord] writes to
  /// the local database first and queues the API call, so this works offline
  /// and awards the sentence XP itself.
  Future<void> _addSentenceViaProvider(
    AppStateProvider appState,
    _SentenceDraft draft,
  ) async {
    final Word? updated = await appState.addSentenceToWord(
      wordId: _word.id,
      sentence: draft.sentence,
      translation: draft.translation,
      difficulty: _word.difficulty,
    );
    if (!mounted) return;
    if (updated == null) {
      // TODO(i18n): needs a key
      _showMessage('The sentence could not be added.');
      return;
    }
    setState(() => _word = _mergeProviderWord(updated));
  }

  /// A meaning-attached add has to reach the server itself: the offline queue
  /// has no field for `meaningId`. When the server cannot be reached the
  /// sentence still gets saved — through the offline path, unassigned — and
  /// the screen says exactly that instead of losing the learner's typing.
  Future<void> _addSentenceWithMeaning(
    AppStateProvider appState,
    _SentenceDraft draft,
  ) async {
    try {
      final Word updated = await _api.addSentenceToWord(
        wordId: _word.id,
        sentence: draft.sentence,
        translation: draft.translation,
        difficulty: _word.difficulty,
        meaningId: draft.meaningId,
      );
      if (!mounted) return;
      setState(() => _word = updated);
      // Same XP, same source label and same content-keyed transaction id the
      // provider path uses, so the reward cannot double up if the two paths
      // ever see the same sentence.
      unawaited(appState.addXPForAction(
        XPActionTypes.addSentence,
        source: 'Cümle Ekleme',
        transactionId:
            'sentence_${_word.id}_${draft.sentence.toLowerCase().hashCode}',
      ));
      _nudgeProviderSync();
    } catch (e) {
      debugPrint('NfWordDetailPage: meaning-attached add failed ($e)');
      if (!mounted) return;
      await _addSentenceViaProvider(appState, draft);
      if (!mounted) return;
      // TODO(i18n): needs a key
      _showMessage(
        'Saved without its meaning — the server could not be reached. '
        'Assign it from Unassigned later.',
      );
    }
  }

  Future<void> _deleteSentence(Sentence sentence) async {
    final bool confirmed = await _confirm(
      // TODO(i18n): needs a key
      title: 'Delete this sentence?',
      // TODO(i18n): needs a key
      body: 'This cannot be undone.',
      // TODO(i18n): needs a key
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      final bool deleted =
          await context.read<AppStateProvider>().deleteSentenceFromWord(
                wordId: _word.id,
                sentenceId: sentence.id,
              );
      if (!mounted) return;
      if (deleted) {
        setState(() => _word = _withoutSentence(_word, sentence.id));
      } else {
        // TODO(i18n): needs a key
        _showMessage('The sentence could not be deleted.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// There is no "move sentence" endpoint, so assigning is a re-create: the
  /// same text is added under the chosen meaning, then the unassigned original
  /// is deleted. Add first, delete second — a failure mid-way duplicates a
  /// sentence, which is recoverable; the other order can lose one.
  Future<void> _assignSentence(Sentence sentence) async {
    final WordMeaning? target = await _showAssignPicker();
    if (target == null || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      final Word updated = await _api.addSentenceToWord(
        wordId: _word.id,
        sentence: sentence.sentence,
        translation: sentence.translation,
        difficulty: sentence.difficulty ?? _word.difficulty,
        meaningId: target.id,
      );
      if (!mounted) return;
      setState(() => _word = updated);

      final bool deleted =
          await context.read<AppStateProvider>().deleteSentenceFromWord(
                wordId: _word.id,
                sentenceId: sentence.id,
              );
      if (!mounted) return;
      if (deleted) {
        setState(() => _word = _withoutSentence(_word, sentence.id));
      } else {
        // The copy under the meaning exists; the unassigned original is still
        // there. Refetch so the screen shows the true (duplicated) state
        // rather than guessing.
        unawaited(_hydrate());
        // TODO(i18n): needs a key
        _showMessage(
          'Assigned, but the old copy could not be removed. '
          'You can delete it from Unassigned.',
        );
      }
      _nudgeProviderSync();
    } catch (e) {
      debugPrint('NfWordDetailPage: assign failed ($e)');
      // TODO(i18n): needs a key
      _showMessage('Could not assign the sentence. Are you online?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Kicks the provider's own reload, whose background sync pulls the server
  /// copy — including changes made here over the API — into the local
  /// database, so the words list does not lag this screen for long.
  void _nudgeProviderSync() {
    unawaited(context.read<AppStateProvider>().refreshWords());
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    final List<WordMeaning> meanings = List<WordMeaning>.of(_word.meanings)
      ..sort((WordMeaning a, WordMeaning b) {
        final int byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
      });

    final Map<int, List<Sentence>> byMeaning = <int, List<Sentence>>{
      for (final WordMeaning m in meanings) m.id: <Sentence>[],
    };
    final List<Sentence> unassigned = <Sentence>[];
    for (final Sentence s in _word.sentences) {
      final List<Sentence>? bucket =
          s.meaningId == null ? null : byMeaning[s.meaningId];
      if (bucket != null) {
        bucket.add(s);
      } else {
        unassigned.add(s);
      }
    }

    final bool serverBacked = _word.id > 0;

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              // TODO(i18n): needs a key
              title: 'Word details',
              tokens: t,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s26,
                ),
                children: <Widget>[
                  _buildHeadwordCard(t),
                  if (_hydrating && meanings.isEmpty) ...<Widget>[
                    const SizedBox(height: NfSpace.s20),
                    Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: NfStroke.iconHeavy,
                          valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                        ),
                      ),
                    ),
                  ],
                  if (meanings.isEmpty && !_hydrating)
                    ..._buildFallbackSection(serverBacked)
                  else
                    for (int i = 0; i < meanings.length; i++) ...<Widget>[
                      const SizedBox(height: NfSpace.s14),
                      NfMeaningSection(
                        headword: _word.englishWord,
                        title: meanings[i].translation,
                        ordinal: i + 1,
                        definition: meanings[i].definition,
                        sentences: byMeaning[meanings[i].id] ?? const <Sentence>[],
                        // TODO(i18n): needs a key
                        emptyLine: 'No sentences for this meaning yet.',
                        onAddSentence: _busy
                            ? null
                            : () => unawaited(
                                _addSentence(defaultMeaning: meanings[i])),
                        onEditMeaning: !serverBacked || _busy
                            ? null
                            : () => unawaited(_editMeaning(meanings[i])),
                        onDeleteMeaning: !serverBacked || _busy
                            ? null
                            : () => unawaited(_deleteMeaning(meanings[i])),
                        onDeleteSentence: _busy
                            ? null
                            : (Sentence s) => unawaited(_deleteSentence(s)),
                        onSpeakSentence: (Sentence s) =>
                            unawaited(_speak(s.sentence)),
                      ),
                    ],
                  if (meanings.isNotEmpty && unassigned.isNotEmpty) ...<Widget>[
                    const SizedBox(height: NfSpace.s14),
                    NfMeaningSection(
                      headword: _word.englishWord,
                      // TODO(i18n): needs a key
                      title: 'Unassigned sentences',
                      unassigned: true,
                      // TODO(i18n): needs a key
                      explainer:
                          'Not linked to a meaning yet — assign each one to '
                          'the sense it shows.',
                      sentences: unassigned,
                      onDeleteSentence: _busy
                          ? null
                          : (Sentence s) => unawaited(_deleteSentence(s)),
                      onAssignSentence: !serverBacked || _busy
                          ? null
                          : (Sentence s) {
                              if (s.id > 0) {
                                unawaited(_assignSentence(s));
                              } else {
                                // A locally created sentence still waiting to
                                // sync has no server row to re-create from.
                                // TODO(i18n): needs a key
                                _showMessage(
                                  'This sentence is still syncing — try again '
                                  'in a moment.',
                                );
                              }
                            },
                      onSpeakSentence: (Sentence s) =>
                          unawaited(_speak(s.sentence)),
                    ),
                  ],
                  if (serverBacked) ...<Widget>[
                    const SizedBox(height: NfSpace.s18),
                    NfSecondaryButton(
                      // TODO(i18n): needs a key
                      label: 'Add meaning',
                      icon: Icons.add_rounded,
                      tone: NfButtonTone.primary,
                      busy: _busy,
                      onPressed: _busy ? null : () => unawaited(_addMeaning()),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadwordCard(NfTokens t) {
    final DateTime today = _startOfDay(DateTime.now());
    final bool due = _isDue(_word, today);
    final bool isNew = !due && _word.reviewCount <= 0;

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  _word.englishWord,
                  style: NfTokens.display(size: NfFont.s23, color: t.ink),
                ),
              ),
              const SizedBox(width: NfSpace.s8),
              Semantics(
                button: true,
                // TODO(i18n): needs a key
                label: 'Listen',
                excludeSemantics: true,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_speak(_word.englishWord)),
                    child: Container(
                      width: NfSize.minTap,
                      height: NfSize.minTap,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.raised,
                        borderRadius: NfRadius.iconTileAll,
                        border: Border.fromBorderSide(t.side),
                      ),
                      child: Icon(
                        Icons.volume_up_rounded,
                        size: 20,
                        color: t.primaryText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s10),
          Row(
            children: <Widget>[
              if (due)
                const NfChip(
                  // TODO(i18n): needs a key
                  label: 'DUE',
                  variant: NfChipVariant.streak,
                  dense: true,
                )
              else if (isNew)
                const NfChip(
                  // TODO(i18n): needs a key
                  label: 'NEW',
                  variant: NfChipVariant.selected,
                  dense: true,
                ),
              if (due || isNew) const SizedBox(width: NfSpace.s10),
              Expanded(
                child: Text(
                  _srsLine(due),
                  style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: NfSpace.s10),
              NfStrengthDots(strength: strengthDotsFor(_word)),
            ],
          ),
          if (_hydrateFailed) ...<Widget>[
            const SizedBox(height: NfSpace.s10),
            Text(
              // TODO(i18n): needs a key
              'Could not reach the server — showing what is saved on this '
              'device. Meanings may be missing.',
              style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  /// A word with no meaning rows still has its joined translation string, so
  /// the screen renders that as a single read-only section rather than an
  /// alarming empty state. Reasons this happens: the word has not synced yet
  /// (negative id), the server was unreachable, or an older backend.
  List<Widget> _buildFallbackSection(bool serverBacked) {
    final String meaning = _word.displayMeaning;
    String? explainer;
    if (!serverBacked) {
      // TODO(i18n): needs a key
      explainer = 'Meanings can be edited once this word has finished syncing.';
    } else if (_hydrateFailed) {
      // TODO(i18n): needs a key
      explainer = 'Meanings can be edited once the server is reachable.';
    }

    return <Widget>[
      const SizedBox(height: NfSpace.s14),
      NfMeaningSection(
        headword: _word.englishWord,
        title: meaning.isEmpty ? _word.englishWord : meaning,
        explainer: explainer,
        sentences: _word.sentences,
        // TODO(i18n): needs a key
        emptyLine: 'No example sentences yet.',
        onAddSentence:
            _busy ? null : () => unawaited(_addSentence(defaultMeaning: null)),
        onDeleteSentence:
            _busy ? null : (Sentence s) => unawaited(_deleteSentence(s)),
        onSpeakSentence: (Sentence s) => unawaited(_speak(s.sentence)),
      ),
    ];
  }

  String _srsLine(bool due) {
    // TODO(i18n): needs a key — every string below, and a plural rule.
    final String reviews = _word.reviewCount == 1
        ? 'Reviewed once'
        : 'Reviewed ${_word.reviewCount} times';
    if (_word.reviewCount <= 0) {
      return 'Not reviewed yet';
    }
    if (due) {
      return '$reviews · due now';
    }
    final DateTime? next = _word.nextReviewDate;
    if (next == null) {
      return reviews;
    }
    return '$reviews · next on ${next.day}.${next.month}.${next.year}';
  }

  // ---------------------------------------------------------------------------
  // Sheets and dialogs
  // ---------------------------------------------------------------------------

  Future<_MeaningDraft?> _showMeaningEditor({WordMeaning? existing}) {
    final NfTokens t = NfTokens.of(context);
    return showModalBottomSheet<_MeaningDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NfTokens.transparent,
      builder: (BuildContext sheetContext) => _SheetFrame(
        tokens: t,
        child: _MeaningEditorSheet(tokens: t, existing: existing),
      ),
    );
  }

  Future<_SentenceDraft?> _showSentenceEditor({int? defaultMeaningId}) {
    final NfTokens t = NfTokens.of(context);
    final List<WordMeaning> meanings = _word.meanings;
    return showModalBottomSheet<_SentenceDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NfTokens.transparent,
      builder: (BuildContext sheetContext) => _SheetFrame(
        tokens: t,
        child: _SentenceEditorSheet(
          tokens: t,
          meanings: meanings,
          initialMeaningId: defaultMeaningId,
        ),
      ),
    );
  }

  Future<WordMeaning?> _showAssignPicker() {
    final NfTokens t = NfTokens.of(context);
    final List<WordMeaning> meanings = _word.meanings;
    return showModalBottomSheet<WordMeaning>(
      context: context,
      backgroundColor: NfTokens.transparent,
      builder: (BuildContext sheetContext) => _SheetFrame(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              // TODO(i18n): needs a key
              'Which meaning does this sentence show?',
              style: NfTokens.display(size: NfFont.s18, color: t.ink),
            ),
            const SizedBox(height: NfSpace.s12),
            for (final WordMeaning m in meanings)
              Padding(
                padding: const EdgeInsets.only(bottom: NfSpace.s8),
                child: NfCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NfSpace.s14,
                    vertical: NfSpace.s12,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        m.translation,
                        style: NfTokens.body(
                          size: NfFont.s145,
                          weight: NfTokens.bodyEmphasisWeight,
                          color: t.ink,
                        ),
                      ),
                      if (m.definition != null &&
                          m.definition!.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: NfSpace.s4),
                        Text(
                          m.definition!,
                          style: NfTokens.body(
                            size: NfFont.s125,
                            color: t.inkMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final NfTokens t = NfTokens.of(context);
    final String cancelLabel = context.tr('common.cancel');
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: t.surface,
        surfaceTintColor: NfTokens.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: NfRadius.cardAll,
          side: t.side,
        ),
        title: Text(
          title,
          style: NfTokens.display(size: NfFont.s18, color: t.ink),
        ),
        content: Text(
          body,
          style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: NfTokens.body(
                size: NfFont.s14,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.inkMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: NfTokens.body(
                size: NfFont.s14,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.wrong,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.ink,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SRS helpers (same reading as the words list, so the two screens agree)
// ---------------------------------------------------------------------------

bool _isDue(Word word, DateTime today) {
  final DateTime? next = word.nextReviewDate;
  return next != null && !_startOfDay(next).isAfter(today);
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

// ---------------------------------------------------------------------------
// Sheet results
// ---------------------------------------------------------------------------

class _MeaningDraft {
  const _MeaningDraft({required this.translation, this.definition});

  final String translation;
  final String? definition;
}

class _SentenceDraft {
  const _SentenceDraft({
    required this.sentence,
    required this.translation,
    this.meaningId,
  });

  final String sentence;
  final String translation;

  /// Null means "no specific meaning": the sentence lands in Unassigned.
  final int? meaningId;
}

// ---------------------------------------------------------------------------
// Sheet chrome
// ---------------------------------------------------------------------------

/// The bottom-sheet surface in this frontend's paint. Tokens come in as a
/// parameter: the sheet's route sits above the page's `NfThemeScope`, so
/// `NfTokens.of` inside it would fall back to the device brightness and ignore
/// the learner's in-app choice.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.tokens, required this.child});

  final NfTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(NfRadius.card),
            topRight: Radius.circular(NfRadius.card),
          ),
          border: Border(
            top: tokens.side,
            left: tokens.side,
            right: tokens.side,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NfSpace.s16,
              NfSpace.s16,
              NfSpace.s16,
              NfSpace.s16,
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meaning editor
// ---------------------------------------------------------------------------

class _MeaningEditorSheet extends StatefulWidget {
  const _MeaningEditorSheet({required this.tokens, this.existing});

  final NfTokens tokens;
  final WordMeaning? existing;

  @override
  State<_MeaningEditorSheet> createState() => _MeaningEditorSheetState();
}

class _MeaningEditorSheetState extends State<_MeaningEditorSheet> {
  late final TextEditingController _translation =
      TextEditingController(text: widget.existing?.translation ?? '');
  late final TextEditingController _definition =
      TextEditingController(text: widget.existing?.definition ?? '');

  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _canSave = _translation.text.trim().isNotEmpty;
    _translation.addListener(_revalidate);
  }

  void _revalidate() {
    final bool next = _translation.text.trim().isNotEmpty;
    if (next != _canSave) {
      setState(() => _canSave = next);
    }
  }

  @override
  void dispose() {
    _translation.removeListener(_revalidate);
    _translation.dispose();
    _definition.dispose();
    super.dispose();
  }

  void _save() {
    final String definition = _definition.text.trim();
    Navigator.of(context).pop(_MeaningDraft(
      translation: _translation.text.trim(),
      definition: definition.isEmpty ? null : definition,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = widget.tokens;
    final bool editing = widget.existing != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          // TODO(i18n): needs a key
          editing ? 'Edit meaning' : 'Add meaning',
          style: NfTokens.display(size: NfFont.s18, color: t.ink),
        ),
        const SizedBox(height: NfSpace.s14),
        _SheetField(
          tokens: t,
          controller: _translation,
          // TODO(i18n): needs a key
          label: 'Translation',
          // TODO(i18n): needs a key
          hint: 'e.g. bank (river edge)',
        ),
        const SizedBox(height: NfSpace.s12),
        _SheetField(
          tokens: t,
          controller: _definition,
          // TODO(i18n): needs a key
          label: 'Definition (optional)',
          // TODO(i18n): needs a key
          hint: 'A short note on when this sense applies',
          maxLines: 2,
        ),
        const SizedBox(height: NfSpace.s16),
        NfPrimaryButton(
          // TODO(i18n): needs a key
          label: editing ? 'Save meaning' : 'Add meaning',
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sentence editor
// ---------------------------------------------------------------------------

class _SentenceEditorSheet extends StatefulWidget {
  const _SentenceEditorSheet({
    required this.tokens,
    required this.meanings,
    this.initialMeaningId,
  });

  final NfTokens tokens;
  final List<WordMeaning> meanings;

  /// Preselects the meaning of the section the add was launched from. Null
  /// preselects "no specific meaning".
  final int? initialMeaningId;

  @override
  State<_SentenceEditorSheet> createState() => _SentenceEditorSheetState();
}

class _SentenceEditorSheetState extends State<_SentenceEditorSheet> {
  final TextEditingController _sentence = TextEditingController();
  final TextEditingController _translation = TextEditingController();

  late int? _meaningId = widget.initialMeaningId;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _sentence.addListener(_revalidate);
    _translation.addListener(_revalidate);
  }

  void _revalidate() {
    final bool next = _sentence.text.trim().isNotEmpty &&
        _translation.text.trim().isNotEmpty;
    if (next != _canSave) {
      setState(() => _canSave = next);
    }
  }

  @override
  void dispose() {
    _sentence.removeListener(_revalidate);
    _translation.removeListener(_revalidate);
    _sentence.dispose();
    _translation.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_SentenceDraft(
      sentence: _sentence.text.trim(),
      translation: _translation.text.trim(),
      meaningId: _meaningId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = widget.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          // TODO(i18n): needs a key
          'Add sentence',
          style: NfTokens.display(size: NfFont.s18, color: t.ink),
        ),
        const SizedBox(height: NfSpace.s14),
        _SheetField(
          tokens: t,
          controller: _sentence,
          // TODO(i18n): needs a key
          label: 'Sentence',
          // TODO(i18n): needs a key
          hint: 'An example sentence using the word',
          maxLines: 2,
        ),
        const SizedBox(height: NfSpace.s12),
        _SheetField(
          tokens: t,
          controller: _translation,
          // TODO(i18n): needs a key
          label: 'Translation',
          // TODO(i18n): needs a key
          hint: 'What the sentence means',
          maxLines: 2,
        ),
        if (widget.meanings.isNotEmpty) ...<Widget>[
          const SizedBox(height: NfSpace.s14),
          Text(
            // TODO(i18n): needs a key
            'For which meaning?',
            style: NfTokens.body(
              size: NfFont.s13,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.inkMuted,
            ),
          ),
          const SizedBox(height: NfSpace.s8),
          Wrap(
            spacing: NfSpace.s8,
            runSpacing: NfSpace.s8,
            children: <Widget>[
              NfChip(
                // TODO(i18n): needs a key
                label: 'No specific meaning',
                variant: _meaningId == null
                    ? NfChipVariant.selected
                    : NfChipVariant.unselected,
                onTap: () => setState(() => _meaningId = null),
              ),
              for (final WordMeaning m in widget.meanings)
                NfChip(
                  label: m.translation,
                  variant: _meaningId == m.id
                      ? NfChipVariant.selected
                      : NfChipVariant.unselected,
                  onTap: () => setState(() => _meaningId = m.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: NfSpace.s16),
        NfPrimaryButton(
          // TODO(i18n): needs a key
          label: 'Add sentence',
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sheet pieces
// ---------------------------------------------------------------------------

/// A labelled text field in this frontend's control styling: raised fill, 2px
/// border, and the border — not a glow — as the focus ring.
class _SheetField extends StatefulWidget {
  const _SheetField({
    required this.tokens,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });

  final NfTokens tokens;
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;

  @override
  State<_SheetField> createState() => _SheetFieldState();
}

class _SheetFieldState extends State<_SheetField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final NfTokens t = widget.tokens;
    final bool focused = _focus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.label,
          style: NfTokens.body(
            size: NfFont.s13,
            weight: NfTokens.bodyEmphasisWeight,
            color: t.inkMuted,
          ),
        ),
        const SizedBox(height: NfSpace.s6),
        Container(
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: NfRadius.controlAll,
            border:
                Border.fromBorderSide(focused ? t.sideOf(t.primary) : t.side),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NfSpace.s12,
            vertical: NfSpace.s12,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            maxLines: widget.maxLines,
            cursorColor: t.primary,
            style: NfTokens.body(size: NfFont.s15, color: t.ink),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: NfTokens.body(size: NfFont.s15, color: t.inkFaint),
            ),
          ),
        ),
      ],
    );
  }
}

/// The pushed-page header, same shape as `NfNotificationsPage`'s.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.tokens,
    required this.onBack,
  });

  final String title;
  final NfTokens tokens;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            iconSize: NfFont.s22,
            color: tokens.ink,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.display(size: NfFont.s20, color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}
