import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/api_service.dart';
import '../../services/groq_service.dart';
import '../../utils/sentence_tokens.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// The dictionary, in the new frontend's paint.
///
/// Behaviour is the union of the two legacy screens it replaces:
/// `dictionary_page.dart` (local-collection hit first, per-meaning selection,
/// save-to-today) and `quick_dictionary_page.dart` (the detailed AI lookup with
/// types and definitions, tappable example-sentence words). Presentation is
/// this frontend's own.
///
/// The one behavioural upgrade is deliberate and named by the phase-1 brief:
/// saving goes through `ApiService.createWord(meanings:)`, so each selected
/// sense becomes a real meaning row on the server and each example sentence is
/// attached to *its* meaning via `meaningId` — instead of the legacy path that
/// flattened everything into one comma-joined string.
class NfDictionaryPage extends StatefulWidget {
  const NfDictionaryPage({
    super.key,
    this.apiService,
  });

  /// Injectable for tests. Defaults to the shared [ApiService].
  final ApiService? apiService;

  @override
  State<NfDictionaryPage> createState() => _NfDictionaryPageState();
}

/// One sense as the detailed AI lookup returns it. Local to this page: the
/// server's own `WordMeaning` model has ids and positions this transient
/// result does not have yet.
@immutable
class _NfLookupMeaning {
  const _NfLookupMeaning({
    required this.type,
    required this.translation,
    required this.definition,
    required this.example,
    required this.exampleTranslation,
  });

  final String type;
  final String translation;
  final String definition;
  final String example;
  final String exampleTranslation;

  /// What gets stored as the meaning's translation. The type tag rides along
  /// exactly as the legacy quick dictionary stored it ("(n) elma"), so words
  /// saved from here look the same as words saved before this screen existed.
  String get storedTranslation =>
      type.trim().isEmpty ? translation : '(${type.trim()}) $translation';
}

class _NfDictionaryPageState extends State<NfDictionaryPage> {
  late final ApiService _apiService;
  final TextEditingController _searchController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSearching = false;
  bool _isSaving = false;
  bool _hasSearched = false;
  String? _errorMessage;

  /// Non-null when the query matched a word already in the collection. The AI
  /// is never consulted for those.
  Word? _localResult;

  String _searchedWord = '';
  String _phonetic = '';
  List<_NfLookupMeaning> _meanings = const <_NfLookupMeaning>[];

  /// Which meanings go into the save. Empty means "all of them" — the same
  /// convention the legacy dictionary used, so the button can always do
  /// something useful.
  final Set<int> _selectedIndices = <int>{};

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    unawaited(_initTts());
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<void> _search() async {
    final String query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _localResult = null;
        _meanings = const <_NfLookupMeaning>[];
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _errorMessage = null;
      _localResult = null;
      _meanings = const <_NfLookupMeaning>[];
      _selectedIndices.clear();
    });

    // 1. The learner's own collection first — no tokens spent on a word they
    // already have, and the result carries their own sentences.
    final AppStateProvider appState = context.read<AppStateProvider>();
    for (final Word word in appState.allWords) {
      if (word.englishWord.toLowerCase() == query.toLowerCase()) {
        setState(() {
          _localResult = word;
          _isSearching = false;
        });
        return;
      }
    }

    // 2. The AI dictionary.
    try {
      final Map<String, dynamic> result =
          await GroqService.lookupWordDetailed(query);
      if (!mounted) return;

      // The backend ships a stand-in payload with HTTP 200 when a generation
      // comes back empty or malformed, and marks it with `fallback`. It must
      // render as an error, never as an entry: the legacy screens once showed
      // it as a real card with a live save button, and the error string could
      // be written into the learner's vocabulary permanently.
      if (result['fallback'] == true) {
        setState(() {
          _isSearching = false;
          _errorMessage = context.tr('dict.err.lookupFailed');
        });
        return;
      }

      final List<dynamic> meaningsData = result['meanings'] as List? ?? [];
      setState(() {
        _searchedWord = result['word']?.toString() ?? query;
        _phonetic = result['phonetic']?.toString() ?? '';
        _meanings = meaningsData
            .whereType<Map>()
            .map(
              (m) => _NfLookupMeaning(
                type: m['type']?.toString() ?? '',
                translation: m['turkishMeaning']?.toString() ?? '',
                definition: m['englishDefinition']?.toString() ?? '',
                example: m['example']?.toString() ?? '',
                exampleTranslation: m['exampleTranslation']?.toString() ?? '',
              ),
            )
            .where((m) => m.translation.trim().isNotEmpty)
            .toList(growable: false);
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        setState(() {
          _errorMessage = AiErrorMessageFormatter.forError(e);
          _isSearching = false;
        });
        return;
      }
      final String message = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : AiErrorMessageFormatter.forError(e);
      setState(() {
        _errorMessage = message;
        _isSearching = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Save to today
  // ---------------------------------------------------------------------------

  List<_NfLookupMeaning> get _meaningsToSave {
    if (_selectedIndices.isEmpty) return _meanings;
    return <_NfLookupMeaning>[
      for (int i = 0; i < _meanings.length; i++)
        if (_selectedIndices.contains(i)) _meanings[i],
    ];
  }

  Future<void> _saveToToday() async {
    final List<_NfLookupMeaning> chosen = _meaningsToSave;
    if (chosen.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      // Phase-1 path: the word is created WITH its meanings in one request, so
      // each sense is a real row the learner can attach sentences to later.
      // This has to reach the server — the offline queue carries no `meanings`
      // field — so `_saveThroughQueue` below covers the case where it cannot.
      final Word created = await _apiService.createWord(
        english: _searchedWord,
        turkish: chosen.map((m) => m.storedTranslation).join(', '),
        addedDate: DateTime.now(),
        difficulty: 'medium',
        meanings: <Map<String, dynamic>>[
          for (final _NfLookupMeaning m in chosen)
            <String, dynamic>{
              'translation': m.storedTranslation,
              if (m.definition.trim().isNotEmpty) 'definition': m.definition,
            },
        ],
      );

      // The freshest server copy of the word, for the provider to adopt below.
      Word latest = created;

      // Each example sentence goes under the meaning it illustrates. The id is
      // matched by translation because that is the only key both sides share;
      // a miss degrades to an unassigned sentence, which is the legacy shape.
      for (final _NfLookupMeaning m in chosen) {
        if (m.example.trim().isEmpty) continue;
        int? meaningId;
        for (final meaning in created.meanings) {
          if (meaning.translation.trim() == m.storedTranslation.trim()) {
            meaningId = meaning.id;
            break;
          }
        }
        try {
          latest = await _apiService.addSentenceToWord(
            wordId: created.id,
            sentence: m.example,
            translation: m.exampleTranslation,
            difficulty: 'medium',
            meaningId: meaningId,
          );
        } catch (e) {
          // The word is already saved; losing its example over a dropped
          // connection would be the worst of both. The queued write carries no
          // meaning id, so the sentence arrives unassigned and the word screen
          // offers it under "Unassigned sentences" to place later.
          debugPrint('NfDictionaryPage: queueing example sentence instead ($e)');
          if (!mounted) return;
          await context.read<AppStateProvider>().addSentenceToWord(
                wordId: created.id,
                sentence: m.example,
                translation: m.exampleTranslation,
                difficulty: 'medium',
              );
        }
      }

      if (!mounted) return;
      // Adopt before refreshing. `refreshWords` reads the local cache, which
      // this word is not in - it was created straight on the server, because
      // the offline queue cannot carry meanings. Without this the learner is
      // told the word was saved and their list does not change.
      final AppStateProvider appState = context.read<AppStateProvider>();
      await appState.adoptServerWord(latest);
      if (!mounted) return;
      unawaited(appState.refreshWords());
      _showMessage(context.tr('dict.saved'));
      // Re-run the search so the screen now shows the word as "Saved".
      unawaited(_search());
    } catch (e) {
      if (!mounted) return;
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      // A quota or entitlement refusal is an answer, not a failed delivery —
      // retrying it through the queue would just save a word the server said
      // no to. Anything else is most likely the connection, and the learner's
      // word should survive it.
      if (e is ApiQuotaExceededException) {
        _showMessage(AiErrorMessageFormatter.forQuota(e));
      } else {
        await _saveThroughQueue(chosen, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Saves the word the way the previous dictionary always did: through
  /// [AppStateProvider], which writes to the local database and queues the
  /// server call for the next connection.
  ///
  /// This is the offline path. The queue has no column for meanings, so the
  /// senses collapse back into the one joined translation string and the
  /// examples arrive unassigned — but the learner keeps the word, its
  /// sentences and the XP, which the meaning-aware path drops entirely when
  /// the server cannot be reached.
  Future<void> _saveThroughQueue(
    List<_NfLookupMeaning> chosen,
    Object originalError,
  ) async {
    final AppStateProvider appState = context.read<AppStateProvider>();
    try {
      final Word? created = await appState.addWord(
        english: _searchedWord,
        turkish: chosen.map((m) => m.storedTranslation).join(', '),
        addedDate: DateTime.now(),
        difficulty: 'medium',
        source: 'quick_dictionary',
      );
      if (created == null) {
        throw StateError('the word could not be stored locally');
      }
      for (final _NfLookupMeaning m in chosen) {
        if (m.example.trim().isEmpty) continue;
        await appState.addSentenceToWord(
          wordId: created.id,
          sentence: m.example,
          translation: m.exampleTranslation,
          difficulty: 'medium',
        );
      }
      if (!mounted) return;
      _showMessage(context.tr('dict.savedOffline'));
      unawaited(_search());
    } catch (fallbackError) {
      debugPrint('NfDictionaryPage: offline save also failed ($fallbackError)');
      if (!mounted) return;
      _showMessage(AiErrorMessageFormatter.forError(originalError));
    }
  }

  void _showMessage(String text) {
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tappable example words
  // ---------------------------------------------------------------------------

  void _showWordInContextSheet(String word, String sentence) {
    final NfTokens t = NfTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(NfRadius.card)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NfSpace.s20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 40,
                  height: NfSize.pressDepth,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: NfRadius.pillAll,
                  ),
                ),
                const SizedBox(height: NfSpace.s16),
                Text(
                  '"$word"',
                  style:
                      NfTokens.display(size: NfFont.s22, color: t.primaryText),
                ),
                const SizedBox(height: NfSpace.s8),
                Text(
                  context.tr('dict.sheet.prompt'),
                  style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                ),
                const SizedBox(height: NfSpace.s20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: NfSecondaryButton(
                        label: context.tr('dict.search'),
                        icon: Icons.search_rounded,
                        tone: NfButtonTone.primary,
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          // Only fills the box; the learner decides whether to
                          // spend the lookup — same as the legacy screen.
                          _searchController.text = word;
                        },
                      ),
                    ),
                    const SizedBox(width: NfSpace.s12),
                    Expanded(
                      child: NfSecondaryButton(
                        label: context.tr('dict.sheet.viewNow'),
                        icon: Icons.visibility_outlined,
                        tone: NfButtonTone.primary,
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          unawaited(_showWordMeaningInContext(word, sentence));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NfSpace.s8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showWordMeaningInContext(String word, String sentence) async {
    final NfTokens t = NfTokens.of(context);

    // `barrierDismissible: false` stops a tap on the barrier but not the
    // Android back button, which pops the dialog like any route. Once it is
    // gone an unconditional `Navigator.pop` takes the dictionary page down
    // instead — the learner cancels a slow lookup and the screen vanishes under
    // them a few seconds later. This flag is what makes the later pop refer to
    // the dialog and nothing else.
    bool loaderIsUp = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: CircularProgressIndicator(
            strokeWidth: NfStroke.border,
            color: t.primary,
          ),
        ),
      ).whenComplete(() => loaderIsUp = false),
    );

    void dismissLoader() {
      if (!loaderIsUp || !mounted) return;
      loaderIsUp = false;
      Navigator.pop(context);
    }

    try {
      final String meaning =
          await GroqService.explainWordInSentence(word, sentence);
      if (!mounted) return;
      dismissLoader();

      // From the page context, like the loading dialog above it. A dialog route
      // sits over this page's NfTheme, so resolving inside the builder would
      // give the two dialogs in one flow opposite palettes.
      final NfTokens dt = NfTokens.of(context);
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            backgroundColor: dt.surface,
            shape: RoundedRectangleBorder(
              borderRadius: NfRadius.cardAll,
              side: dt.side,
            ),
            title: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dt.primarySoft,
                    borderRadius: NfRadius.iconTileAll,
                  ),
                  child: Icon(Icons.lightbulb_outline_rounded,
                      size: 18, color: dt.primaryText),
                ),
                const SizedBox(width: NfSpace.s12),
                Expanded(
                  child: Text(
                    '"$word"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NfTokens.display(
                        size: NfFont.s18, color: dt.primaryText),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('dict.inContext.title'),
                  style: NfTokens.body(size: NfFont.s125, color: dt.inkMuted),
                ),
                const SizedBox(height: NfSpace.s8),
                Text(
                  meaning,
                  style: NfTokens.body(size: NfFont.s15, color: dt.ink),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  context.tr('common.close'),
                  style: NfTokens.display(
                      size: NfFont.s14, color: dt.primaryText),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      // Not `Navigator.canPop`: that is true for any pushed page, so it popped
      // the dictionary whenever the learner had already dismissed the loader.
      dismissLoader();
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final String message = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : AiErrorMessageFormatter.forError(e);
      _showMessage(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// The palette comes from the `NfThemeScope` the shell wraps this route in.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(t),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NfSpace.s16,
                NfSpace.s4,
                NfSpace.s16,
                NfSpace.s12,
              ),
              child: _buildSearchArea(t),
            ),
            Expanded(child: _buildContent(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s4,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: NfFont.s22,
            color: t.ink,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Text(
              context.tr('nav.dictionary'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.display(size: NfFont.s20, color: t.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchArea(NfTokens t) {
    return Column(
      children: <Widget>[
        TextField(
          controller: _searchController,
          style: NfTokens.body(size: NfFont.s15, color: t.ink),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => unawaited(_search()),
          decoration: InputDecoration(
            hintText: context.tr('dict.searchHint'),
            hintStyle: NfTokens.body(size: NfFont.s15, color: t.inkFaint),
            prefixIcon: Icon(Icons.search_rounded, color: t.inkMuted),
            filled: true,
            fillColor: t.raised,
            border: OutlineInputBorder(
              borderRadius: NfRadius.controlAll,
              borderSide: t.side,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: NfRadius.controlAll,
              borderSide: t.side,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: NfRadius.controlAll,
              borderSide: t.sideOf(t.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NfSpace.s16,
              vertical: NfSpace.s14,
            ),
          ),
        ),
        const SizedBox(height: NfSpace.s12),
        NfPrimaryButton(
          label: context.tr('dict.search'),
          icon: Icons.search_rounded,
          busy: _isSearching,
          onPressed: _isSearching ? null : () => unawaited(_search()),
        ),
      ],
    );
  }

  Widget _buildContent(NfTokens t) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircularProgressIndicator(
              strokeWidth: NfStroke.border,
              color: t.primary,
            ),
            const SizedBox(height: NfSpace.s16),
            Text(
              context.tr('common.loading'),
              style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
            ),
          ],
        ),
      );
    }

    if (_errorMessage case final String message) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NfSpace.s26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.error_outline_rounded, size: 48, color: t.wrong),
              const SizedBox(height: NfSpace.s16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return _buildEmptyState(t);
    }

    if (_localResult case final Word word) {
      return _buildLocalResult(t, word);
    }

    if (_meanings.isEmpty) {
      return Center(
        child: Text(
          context.tr('dict.noResult'),
          style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
        ),
      );
    }

    return _buildAiResult(t);
  }

  Widget _buildEmptyState(NfTokens t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primarySoft,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(t.sideOf(t.primary)),
            ),
            child: Icon(Icons.menu_book_outlined,
                size: 44, color: t.primaryText),
          ),
          const SizedBox(height: NfSpace.s20),
          Text(
            context.tr('dict.emptyTitle'),
            style: NfTokens.display(size: NfFont.s17, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s6),
          Text(
            context.tr('dict.emptyBody'),
            style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
          ),
        ],
      ),
    );
  }

  /// The word is already in the collection: show it and say so, no save
  /// button. The legacy dictionary behaved exactly this way.
  Widget _buildLocalResult(NfTokens t, Word word) {
    final String? example =
        word.sentences.isNotEmpty ? word.sentences.first.sentence : null;
    final String exampleTranslation =
        word.sentences.isNotEmpty ? word.sentences.first.translation : '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s4,
        NfSpace.s16,
        NfSpace.s26,
      ),
      children: <Widget>[
        NfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      word.englishWord,
                      style: NfTokens.display(size: NfFont.s25, color: t.ink),
                    ),
                  ),
                  _SpeakButton(
                    tokens: t,
                    onTap: () => unawaited(_speak(word.englishWord)),
                  ),
                  const SizedBox(width: NfSpace.s8),
                  NfChip(
                    label: context.tr('dict.savedBadge'),
                    icon: Icons.check_rounded,
                    variant: NfChipVariant.correct,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: NfSpace.s14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(NfSpace.s14),
                decoration: BoxDecoration(
                  color: t.raised,
                  borderRadius: NfRadius.tileAll,
                ),
                child: Text(
                  word.displayMeaning,
                  style: NfTokens.body(size: NfFont.s15, color: t.ink),
                ),
              ),
              if (example != null && example.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: NfSpace.s12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(NfSpace.s14),
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: NfRadius.tileAll,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.tr('dict.example'),
                        style: NfTokens.body(
                          size: NfFont.s115,
                          weight: NfTokens.bodyEmphasisWeight,
                          color: t.primaryText,
                        ),
                      ),
                      const SizedBox(height: NfSpace.s4),
                      Text(
                        '"$example"',
                        style: NfTokens.body(size: NfFont.s14, color: t.ink),
                      ),
                      if (exampleTranslation.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: NfSpace.s6),
                        Text(
                          '"$exampleTranslation"',
                          style: NfTokens.body(
                              size: NfFont.s13, color: t.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The save button's label. Three keys rather than one with a count, because
  /// "1 meaning" / "N meanings" is an English plural rule: Turkish takes the
  /// singular noun after any number, and German inflects the noun itself. The
  /// zero case is its own sentence, not a count at all — no selection means
  /// "save everything", which is what the button then does.
  String _saveButtonLabel(int selectedCount) {
    if (selectedCount == 0) {
      return context.tr('dict.saveAll');
    }
    if (selectedCount == 1) {
      return context.tr('dict.saveOne');
    }
    return context.tr('dict.saveN').replaceAll('{n}', '$selectedCount');
  }

  Widget _buildAiResult(NfTokens t) {
    final int selectedCount = _selectedIndices.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s4,
        NfSpace.s16,
        NfSpace.s26,
      ),
      children: <Widget>[
        NfCard(
          backgroundColor: t.primarySoft,
          borderColor: t.primary,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _searchedWord,
                      style: NfTokens.display(size: NfFont.s25, color: t.ink),
                    ),
                    if (_phonetic.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s4),
                      Text(
                        _phonetic,
                        style: NfTokens.body(
                            size: NfFont.s14, color: t.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              _SpeakButton(
                tokens: t,
                onTap: () => unawaited(_speak(_searchedWord)),
              ),
            ],
          ),
        ),
        const SizedBox(height: NfSpace.s16),
        Text(
          context.tr('dict.meaningsCount')
              .replaceAll('{n}', '${_meanings.length}'),
          style: NfTokens.display(size: NfFont.s17, color: t.ink),
        ),
        const SizedBox(height: NfSpace.s10),
        for (int i = 0; i < _meanings.length; i++) ...<Widget>[
          _buildMeaningCard(t, i, _meanings[i]),
          const SizedBox(height: NfSpace.s12),
        ],
        const SizedBox(height: NfSpace.s8),
        NfPrimaryButton(
          label: _saveButtonLabel(selectedCount),
          icon: Icons.add_circle_outline_rounded,
          busy: _isSaving,
          onPressed: _isSaving ? null : () => unawaited(_saveToToday()),
        ),
        const SizedBox(height: NfSpace.s10),
        Text(
          context.tr('dict.selectHint'),
          textAlign: TextAlign.center,
          style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
        ),
      ],
    );
  }

  Widget _buildMeaningCard(NfTokens t, int index, _NfLookupMeaning meaning) {
    final bool isSelected = _selectedIndices.contains(index);

    return NfCard(
      backgroundColor: isSelected ? t.primarySoft : t.surface,
      borderColor: isSelected ? t.primary : t.border,
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIndices.remove(index);
          } else {
            _selectedIndices.add(index);
          }
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _SelectionBadge(
                tokens: t,
                index: index,
                selected: isSelected,
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Text(
                  meaning.translation,
                  style: NfTokens.body(
                    size: NfFont.s16,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.ink,
                  ),
                ),
              ),
              if (meaning.type.trim().isNotEmpty) ...<Widget>[
                const SizedBox(width: NfSpace.s8),
                NfChip(
                  label: meaning.type.trim().toUpperCase(),
                  variant: isSelected
                      ? NfChipVariant.selected
                      : NfChipVariant.unselected,
                  dense: true,
                ),
              ],
            ],
          ),
          if (meaning.definition.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: NfSpace.s8),
            Text(
              meaning.definition,
              style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
            ),
          ],
          if (meaning.example.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: NfSpace.s12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(NfSpace.s12),
              decoration: BoxDecoration(
                color: t.raised,
                borderRadius: NfRadius.tileAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildInteractiveSentence(t, meaning.example),
                  if (meaning.exampleTranslation.trim().isNotEmpty)
                    ...<Widget>[
                      const SizedBox(height: NfSpace.s6),
                      Text(
                        meaning.exampleTranslation,
                        style: NfTokens.body(
                            size: NfFont.s125, color: t.inkMuted),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The example sentence, word by word. The searched word is highlighted and
  /// inert; every other word opens the search-or-explain sheet. Splitting and
  /// matching go through [SentenceTokens] — the rules live there, not here.
  Widget _buildInteractiveSentence(NfTokens t, String sentence) {
    final List<String> tokens = SentenceTokens.split(sentence);

    return Wrap(
      children: tokens.map((String token) {
        if (token.trim().isEmpty) {
          return Text(
            token,
            style: NfTokens.body(size: NfFont.s14, color: t.ink),
          );
        }

        final String cleanWord = SentenceTokens.word(token);
        final bool isSearched =
            SentenceTokens.isSearched(cleanWord, _searchedWord);

        if (isSearched) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NfSpace.s4,
            ),
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(NfRadius.tile / 2),
            ),
            child: Text(
              token,
              style: NfTokens.body(
                size: NfFont.s14,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.primaryText,
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _showWordInContextSheet(cleanWord, sentence),
          child: Text(
            token,
            style: NfTokens.body(
              size: NfFont.s14,
              color: t.ink,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PIECES
// ═══════════════════════════════════════════════════════════════════════════

/// Pronounce button with a full [NfSize.minTap] hit area.
class _SpeakButton extends StatelessWidget {
  const _SpeakButton({required this.tokens, required this.onTap});

  final NfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('common.pronounce'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: NfSize.minTap,
            height: NfSize.minTap,
            child: Icon(Icons.volume_up_outlined,
                size: 22, color: tokens.primaryText),
          ),
        ),
      ),
    );
  }
}

/// The numbered circle that flips to a check when its meaning is selected.
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({
    required this.tokens,
    required this.index,
    required this.selected,
  });

  final NfTokens tokens;
  final int index;
  final bool selected;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? tokens.primary : tokens.raised,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          selected ? tokens.sideOf(tokens.primaryShadow) : tokens.sideStrong,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: tokens.primaryInk)
          : Text(
              '${index + 1}',
              style: NfTokens.display(
                size: NfFont.s13,
                color: tokens.inkMuted,
              ),
            ),
    );
  }
}
