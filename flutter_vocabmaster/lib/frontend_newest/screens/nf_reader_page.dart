import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/book.dart';
import '../../models/word.dart';
import '../../services/api_service.dart';
import '../../providers/app_state_provider.dart';
import '../../services/groq_service.dart';
import '../../utils/sentence_tokens.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';

/// Reading a book, one sentence at a time.
///
/// The learning here is the tap, not the translation. A reader meets a word
/// they do not know, taps it, is told what it means *in this sentence*, and
/// puts it in their deck with this sentence as its context. That path runs
/// through the same dictionary the rest of the app uses.
///
/// Sentence translations are shown when a book has them and simply absent when
/// it does not, which is most of the shelf. That is deliberate: a translation
/// that is wrong teaches worse than no translation at all, because a learner
/// has no way to see that it is wrong.
class NfReaderPage extends StatefulWidget {
  const NfReaderPage({
    super.key,
    required this.slug,
    required this.title,
    this.startAt = 0,
    this.sentenceCount = 0,
    this.apiService,
  });

  final String slug;
  final String title;

  /// The sentence to open at — the reader's bookmark.
  final int startAt;

  /// How long the book is, from the shelf.
  ///
  /// Only used to notice a finished book. Zero means "not told", and then the
  /// reader simply opens at [startAt].
  final int sentenceCount;

  /// Injectable for tests. Defaults to the shared [ApiService].
  final ApiService? apiService;

  @override
  State<NfReaderPage> createState() => _NfReaderPageState();
}

class _NfReaderPageState extends State<NfReaderPage> {
  /// How many sentences to fetch at a time.
  ///
  /// Enough to fill a screen several times over, so scrolling is smooth, and
  /// small enough that opening a six-thousand-sentence book is instant.
  static const int _windowSize = 60;

  late final ApiService _api;
  final ScrollController _scroll = ScrollController();

  final List<ReaderSentence> _sentences = <ReaderSentence>[];
  int _sentenceCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// The furthest sentence this reader has reached in this sitting.
  int _reached = 0;

  /// Pending progress write. Progress is saved as they read, but a write per
  /// scroll frame would be hundreds of requests for one chapter.
  Timer? _progressDebounce;
  int _savedProgress = 0;

  /// Where to open the book.
  ///
  /// A reader who finished it gets the first page, not the last line. Opening
  /// a finished book at its bookmark showed one sentence and a screenful of
  /// nothing, with no way to scroll back — which is a strange way to be told
  /// "you have read this".
  int get _openAt =>
      widget.sentenceCount > 1 && widget.startAt >= widget.sentenceCount - 1
          ? 0
          : widget.startAt;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    // _reached keeps the bookmark even when the view opens elsewhere: reading
    // a finished book again should not tell the shelf you are back at the
    // start.
    _reached = widget.startAt;
    _savedProgress = widget.startAt;
    _scroll.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _progressDebounce?.cancel();
    // Leaving the page is the moment a bookmark matters most, and the debounce
    // may still be pending. Fire it now rather than losing the last few
    // sentences they read.
    _flushProgress();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ReaderWindow window = await _api.getBookSentences(
        slug: widget.slug,
        from: _openAt,
        size: _windowSize,
      );
      if (!mounted) return;
      setState(() {
        _sentences
          ..clear()
          ..addAll(window.sentences);
        _sentenceCount = window.sentenceCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Reopens the book at its first sentence.
  ///
  /// A window that starts at the bookmark cannot be scrolled back past it, so
  /// without this there is no way to re-read a chapter — or to read a finished
  /// book again.
  ///
  /// Deliberately does not touch the bookmark. "How far have I got" and "where
  /// am I looking" are different questions, and the server only ever moves a
  /// bookmark forward anyway; re-reading chapter one should not tell the shelf
  /// you are back at the start.
  Future<void> _restart() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ReaderWindow window = await _api.getBookSentences(
        slug: widget.slug,
        from: 0,
        size: _windowSize,
      );
      if (!mounted) return;
      setState(() {
        _sentences
          ..clear()
          ..addAll(window.sentences);
        _sentenceCount = window.sentenceCount;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _sentences.isEmpty) return;
    final int next = _sentences.last.index + 1;
    if (_sentenceCount > 0 && next >= _sentenceCount) return;

    setState(() => _loadingMore = true);
    try {
      final ReaderWindow window = await _api.getBookSentences(
        slug: widget.slug,
        from: next,
        size: _windowSize,
      );
      if (!mounted) return;
      setState(() {
        _sentences.addAll(window.sentences);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A failed page is not a failed book: the reader keeps what they have and
      // the next scroll tries again.
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _sentences.isEmpty) return;

    final double position = _scroll.position.pixels;
    final double max = _scroll.position.maxScrollExtent;
    if (max > 0 && position > max - 600) {
      _loadMore();
    }

    // Rough but honest: how far down the loaded text they are, mapped onto the
    // sentence indices actually loaded. Precise per-sentence tracking would
    // need a viewport observer for a bookmark that is only ever approximate.
    if (max <= 0) return;
    final double fraction = (position / max).clamp(0, 1);
    final int first = _sentences.first.index;
    final int span = _sentences.last.index - first;
    final int here = first + (span * fraction).round();
    if (here > _reached) {
      // setState, not a bare assignment: the header's percentage and bar read
      // _reached, and without a rebuild they sit at zero for the whole book
      // while the shelf behind them shows the real number. Crossing a sentence
      // boundary is rare enough that rebuilding here costs nothing.
      setState(() => _reached = here);
      _scheduleProgress();
    }
  }

  void _scheduleProgress() {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(seconds: 3), _flushProgress);
  }

  void _flushProgress() {
    if (_reached <= _savedProgress) return;
    final int target = _reached;
    _savedProgress = target;
    // Fire and forget: a bookmark that fails to save is worth retrying on the
    // next scroll, not worth interrupting someone's reading with.
    unawaited(
      _api
          .saveBookProgress(slug: widget.slug, sentenceIndex: target)
          .catchError((Object _) => target),
    );
  }

  Future<void> _onWordTapped(String rawToken, ReaderSentence sentence) async {
    final String word = SentenceTokens.word(rawToken);
    if (word.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => ReaderWordSheet(
        word: word,
        sentence: sentence.text,
        sentenceTranslation: sentence.translation,
        api: _api,
        // The server keeps the word either way; this is what puts it in front
        // of the learner. Without it the save succeeds, the sheet says so, and
        // the Words screen goes on showing the list it loaded at startup --
        // which reads, to the person who just saved it, exactly like the save
        // having failed.
        onSaved: (Word saved) =>
            context.read<AppStateProvider>().adoptServerWord(saved),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(t),
            Expanded(child: _buildBody(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    // Same arithmetic as the shelf card, and for the same reason: the index is
    // a position in 0..count-1, so the count is one too many to divide by.
    final double fraction = _sentenceCount <= 1
        ? 0
        : (_reached / (_sentenceCount - 1)).clamp(0, 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          NfSpace.s12, NfSpace.s8, NfSpace.s16, NfSpace.s8),
      child: Column(
        children: <Widget>[
          Row(
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
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.ink,
                    fontSize: NfFont.s16,
                    fontWeight: NfTokens.bodyEmphasisWeight,
                  ),
                ),
              ),
              if (_sentences.isNotEmpty && _sentences.first.index > 0)
                IconButton(
                  onPressed: _restart,
                  iconSize: NfFont.s18,
                  color: t.inkMuted,
                  icon: const Icon(Icons.restart_alt_rounded),
                  tooltip: context.tr('books.restart'),
                ),
              if (_sentenceCount > 0)
                Text(
                  '%${(fraction * 100).round()}',
                  style: TextStyle(
                    color: t.inkMuted,
                    fontSize: NfFont.s12,
                    fontWeight: NfTokens.bodyEmphasisWeight,
                  ),
                ),
            ],
          ),
          const SizedBox(height: NfSpace.s6),
          ClipRRect(
            borderRadius: BorderRadius.circular(NfSpace.s4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: NfSpace.s4,
              backgroundColor: t.raised,
              valueColor: AlwaysStoppedAnimation<Color>(t.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NfTokens t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NfSpace.s26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.wifi_off_rounded, size: NfFont.s25 * 2, color: t.inkFaint),
              const SizedBox(height: NfSpace.s16),
              Text(
                context.tr('books.error.book'),
                style: TextStyle(
                  color: t.ink,
                  fontSize: NfFont.s16,
                  fontWeight: NfTokens.bodyEmphasisWeight,
                ),
              ),
              const SizedBox(height: NfSpace.s16),
              TextButton(
                onPressed: _loadInitial,
                child: Text(context.tr('books.retry')),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          NfSpace.s18, NfSpace.s8, NfSpace.s18, NfSpace.s26),
      itemCount: _sentences.length + (_loadingMore ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i >= _sentences.length) {
          return const Padding(
            padding: EdgeInsets.all(NfSpace.s16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildSentence(t, _sentences[i], i);
      },
    );
  }

  Widget _buildSentence(NfTokens t, ReaderSentence sentence, int position) {
    final bool showsChapter = position == 0 ||
        _sentences[position - 1].chapterIndex != sentence.chapterIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showsChapter && sentence.chapterTitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: NfSpace.s26),
          Text(
            sentence.chapterTitle,
            style: TextStyle(
              color: t.inkMuted,
              fontSize: NfFont.s13,
              fontWeight: NfTokens.bodyEmphasisWeight,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: NfSpace.s12),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: NfSpace.s14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildTappableText(t, sentence),
              if (sentence.hasTranslation) ...<Widget>[
                const SizedBox(height: NfSpace.s6),
                Text(
                  sentence.translation!,
                  style: TextStyle(
                    color: t.inkFaint,
                    fontSize: NfFont.s14,
                    fontWeight: NfTokens.bodyWeight,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTappableText(NfTokens t, ReaderSentence sentence) {
    return _TappableSentence(
      text: sentence.text,
      onWordTapped: (String token) => _onWordTapped(token, sentence),
    );
  }
}

/// One sentence, with every word its own tap target.
///
/// Stateful because of the recognizers. [TapGestureRecognizer] holds resources
/// and must be disposed, and a novel is thousands of words: created inline in a
/// `build` they would leak one per word per rebuild, and a reader would watch
/// the page get slower the longer they stayed on it. Owning them here ties each
/// one's life to the sentence that uses it.
class _TappableSentence extends StatefulWidget {
  const _TappableSentence({
    required this.text,
    required this.onWordTapped,
  });

  final String text;
  final void Function(String token) onWordTapped;

  @override
  State<_TappableSentence> createState() => _TappableSentenceState();
}

class _TappableSentenceState extends State<_TappableSentence> {
  List<String> _tokens = const <String>[];
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _rebuildTokens();
  }

  @override
  void didUpdateWidget(_TappableSentence old) {
    super.didUpdateWidget(old);
    // A recycled list row can be handed a different sentence. Rebuilding the
    // recognizers is what keeps a tap on row three from looking up row nine's
    // word.
    if (old.text != widget.text) {
      _rebuildTokens();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _rebuildTokens() {
    _disposeRecognizers();
    _tokens = SentenceTokens.split(widget.text);
    for (final String token in _tokens) {
      if (token.trim().isEmpty) continue;
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => widget.onWordTapped(token),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    // Built as one RichText rather than a wrap of widgets so the text flows
    // like prose. Whitespace tokens are kept as plain spans: SentenceTokens
    // returns them, and dropping them would run the sentence together.
    final List<InlineSpan> spans = <InlineSpan>[];
    int recognizerIndex = 0;
    for (final String token in _tokens) {
      if (token.trim().isEmpty) {
        spans.add(TextSpan(text: token));
        continue;
      }
      spans.add(TextSpan(
        text: token,
        recognizer: _recognizers[recognizerIndex++],
      ));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: t.ink,
          fontSize: NfFont.s17,
          fontWeight: NfTokens.bodyWeight,
          height: 1.6,
        ),
        children: spans,
      ),
    );
  }
}

/// What a tapped word shows: its meaning in this sentence, and a way to keep it.
///
/// Public, and its lookup injectable, so a test can drive the save. The bug
/// this guards against is silent: the word reaches the server, the sheet says
/// so, and the deck the learner then opens has never heard of it.
class ReaderWordSheet extends StatefulWidget {
  const ReaderWordSheet({
    super.key,
    this.lookUp,
    required this.word,
    required this.sentence,
    required this.sentenceTranslation,
    required this.api,
    required this.onSaved,
  });

  final String word;
  final String sentence;

  /// The book's translation of [sentence], or null when it has none.
  final String? sentenceTranslation;

  final ApiService api;

  /// Called with the word the server created, so the rest of the app learns
  /// about it without waiting for a restart.
  final void Function(Word word) onSaved;

  /// How to explain the word in its sentence. Defaults to the app's dictionary.
  final Future<String> Function(String word, String sentence)? lookUp;

  @override
  State<ReaderWordSheet> createState() => ReaderWordSheetState();
}

class ReaderWordSheetState extends State<ReaderWordSheet> {
  String? _definition;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _lookUp();
  }

  Future<void> _lookUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Future<String> Function(String, String) lookUp =
          widget.lookUp ?? GroqService.explainWordInSentence;
      final String definition = await lookUp(widget.word, widget.sentence);
      if (!mounted) return;
      setState(() {
        _definition = definition;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final String? meaning = _definition;
    if (meaning == null || meaning.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      final word = await widget.api.createWord(
        english: widget.word,
        turkish: meaning,
        addedDate: DateTime.now(),
      );
      // The sentence is the point of learning a word here: a word kept with the
      // line it came from has somewhere to be reviewed. It is attached whether
      // or not the book has a translation for it — five of the six books have
      // none, and a word saved from those would otherwise arrive in the deck
      // with no context at all, which is most of what makes reading worth
      // learning from.
      await widget.api.addSentenceToWord(
        wordId: word.id,
        sentence: widget.sentence,
        translation: widget.sentenceTranslation,
      );
      widget.onSaved(word);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NfSpace.s20),
        ),
      ),
      // viewInsets is the keyboard; viewPadding is the system navigation bar.
      // Only the first was accounted for, so on a device with on-screen
      // navigation the save button sat underneath it.
      padding: EdgeInsets.fromLTRB(
        NfSpace.s20,
        NfSpace.s16,
        NfSpace.s20,
        NfSpace.s20 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: NfSpace.s4,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(NfSpace.s4),
              ),
            ),
          ),
          const SizedBox(height: NfSpace.s16),
          Text(
            widget.word,
            style: TextStyle(
              color: t.ink,
              fontSize: NfFont.s22,
              fontWeight: NfTokens.displayWeight,
            ),
          ),
          const SizedBox(height: NfSpace.s12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: NfSpace.s16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(
              context.tr('books.word.failed'),
              style: TextStyle(
                color: t.wrong,
                fontSize: NfFont.s14,
                fontWeight: NfTokens.bodyWeight,
              ),
            )
          else
            Text(
              _definition ?? '',
              style: TextStyle(
                color: t.inkMuted,
                fontSize: NfFont.s15,
                fontWeight: NfTokens.bodyWeight,
                height: 1.5,
              ),
            ),
          const SizedBox(height: NfSpace.s20),
          NfPrimaryButton(
            label: _saved
                ? context.tr('books.word.saved')
                : context.tr('books.word.save'),
            busy: _saving,
            onPressed: (_loading || _saving || _saved || _definition == null)
                ? null
                : _save,
          ),
        ],
      ),
    );
  }
}
