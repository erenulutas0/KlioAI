import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/book.dart';
import '../../services/api_service.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_card.dart';
import 'nf_reader_page.dart';

/// The reading shelf.
///
/// Books are public-domain texts, imported once on the server and served from
/// the database, so opening one costs nothing. The shelf is ordered easiest
/// first because that ordering is the teaching: a beginner should meet Peter
/// Rabbit before Conrad, and a list sorted by title would put Aesop first and
/// Conrad third.
class NfBooksPage extends StatefulWidget {
  const NfBooksPage({super.key, this.apiService});

  /// Injectable for tests. Defaults to the shared [ApiService].
  final ApiService? apiService;

  @override
  State<NfBooksPage> createState() => _NfBooksPageState();
}

class _NfBooksPageState extends State<NfBooksPage> {
  late final ApiService _api;

  List<BookShelfEntry> _books = const <BookShelfEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Assigned before the load, not after: an async body runs synchronously up
    // to its first await, and _load's first await reads _api.
    _api = widget.apiService ?? ApiService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<BookShelfEntry> books = await _api.getBookShelf();
      if (!mounted) return;
      setState(() {
        _books = books;
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

  Future<void> _open(BookShelfEntry book) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NfReaderPage(
          slug: book.slug,
          title: book.title,
          startAt: book.lastSentenceIndex,
          sentenceCount: book.sentenceCount,
          apiService: widget.apiService,
        ),
      ),
    );
    // The bookmark almost certainly moved while they were reading, and the
    // shelf is the screen that shows it.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(t),
            Expanded(child: _buildBody(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          NfSpace.s12, NfSpace.s8, NfSpace.s16, NfSpace.s4),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('books.title'),
                  style: TextStyle(
                    color: t.ink,
                    fontSize: NfFont.s20,
                    fontWeight: NfTokens.displayWeight,
                  ),
                ),
                Text(
                  context.tr('books.subtitle'),
                  style: TextStyle(
                    color: t.inkMuted,
                    fontSize: NfFont.s13,
                    fontWeight: NfTokens.bodyWeight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NfTokens t) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.primary));
    }
    if (_error != null) {
      return _buildMessage(
        t,
        icon: Icons.wifi_off_rounded,
        title: context.tr('books.error.shelf'),
        detail: context.tr('books.error.detail'),
        onRetry: _load,
      );
    }
    if (_books.isEmpty) {
      // Not an error: a shelf with nothing on it means the server has no books
      // imported yet, which is a normal state on a fresh deployment.
      return _buildMessage(
        t,
        icon: Icons.menu_book_rounded,
        title: context.tr('books.empty.title'),
        detail: context.tr('books.empty.detail'),
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            NfSpace.s16, NfSpace.s8, NfSpace.s16, NfSpace.s26),
        itemCount: _books.length,
        separatorBuilder: (_, __) => const SizedBox(height: NfSpace.s12),
        itemBuilder: (BuildContext context, int i) =>
            _buildBookCard(t, _books[i], i),
      ),
    );
  }

  Widget _buildBookCard(NfTokens t, BookShelfEntry book, int index) {
    return NfCard(
      onTap: () => _open(book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BookCover(book: book, shelfIndex: index),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      book.title,
                      style: TextStyle(
                        color: t.ink,
                        fontSize: NfFont.s16,
                        fontWeight: NfTokens.bodyEmphasisWeight,
                      ),
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      book.author,
                      style: TextStyle(
                        color: t.inkMuted,
                        fontSize: NfFont.s13,
                        fontWeight: NfTokens.bodyWeight,
                      ),
                    ),
                  ],
                ),
              ),
              if (book.level.isNotEmpty) _buildLevelBadge(t, book.level),
            ],
          ),
          const SizedBox(height: NfSpace.s12),
          Row(
            children: <Widget>[
              Icon(Icons.notes_rounded, size: NfFont.s14, color: t.inkFaint),
              const SizedBox(width: NfSpace.s6),
              Text(
                '${book.sentenceCount} ${context.tr('books.sentences')}',
                style: TextStyle(
                  color: t.inkFaint,
                  fontSize: NfFont.s12,
                  fontWeight: NfTokens.bodyWeight,
                ),
              ),
              const Spacer(),
              Text(
                book.started
                    ? '%${(book.fraction * 100).round()}'
                    : context.tr('books.start'),
                style: TextStyle(
                  color: book.started ? t.primaryText : t.inkMuted,
                  fontSize: NfFont.s12,
                  fontWeight: NfTokens.bodyEmphasisWeight,
                ),
              ),
            ],
          ),
          if (book.started) ...<Widget>[
            const SizedBox(height: NfSpace.s8),
            ClipRRect(
              borderRadius: BorderRadius.circular(NfSpace.s4),
              child: LinearProgressIndicator(
                value: book.fraction,
                minHeight: NfSpace.s6,
                backgroundColor: t.raised,
                valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelBadge(NfTokens t, String level) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: NfSpace.s8, vertical: NfSpace.s4),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: BorderRadius.circular(NfSpace.s8),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: t.primaryText,
          fontSize: NfFont.s12,
          fontWeight: NfTokens.bodyEmphasisWeight,
        ),
      ),
    );
  }

  Widget _buildMessage(
    NfTokens t, {
    required IconData icon,
    required String title,
    required String detail,
    required Future<void> Function() onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NfSpace.s26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: NfFont.s25 * 2, color: t.inkFaint),
            const SizedBox(height: NfSpace.s16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.ink,
                fontSize: NfFont.s16,
                fontWeight: NfTokens.bodyEmphasisWeight,
              ),
            ),
            const SizedBox(height: NfSpace.s6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.inkMuted,
                fontSize: NfFont.s13,
                fontWeight: NfTokens.bodyWeight,
              ),
            ),
            const SizedBox(height: NfSpace.s16),
            TextButton(
              onPressed: () => onRetry(),
              child: Text(context.tr('books.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A book's cover.
///
/// The shelf was six rows of title, author and a level badge, and it read as a
/// database table rather than as books. What it wanted was the covers, and for
/// five of the six they exist and are usable: every title here was published
/// before 1929 and its author died long ago, so the period binding art is
/// public domain along with the text. Those are real scans -- Warne's 1902
/// Peter Rabbit with Potter's own drawing, the Victorian Aesop, the 1892
/// Sherlock in blue cloth -- prepared by tool/make_covers.py and bundled, so
/// the shelf still needs no network.
///
/// The sixth is drawn here instead. What Project Gutenberg serves as a cover
/// for Heart of Darkness is a generated placeholder with their name printed
/// across it; it would be the one tile that looked broken, and it is not ours
/// to display. So a book with no artwork gets a typeset board in the style of
/// the bindings beside it, and any book added later gets the same rather than
/// a gap.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, required this.shelfIndex});

  final BookShelfEntry book;

  /// Where this book sits on the shelf, which is what colours a drawn cover.
  final int shelfIndex;

  // The covers are the point of this widget, so they get the room: at 72 the
  // card still leaves about 250dp for the title, author and level badge on a
  // 393dp screen, and a drawn board gets a 52dp column to set a title in
  // rather than 44.
  static const double _width = 72;
  static const double _height = 104;

  /// The slugs with a real cover in assets/covers/.
  ///
  /// A list rather than an errorBuilder on a missing asset: a missing asset
  /// throws during layout and the recovery path is a frame late, so the shelf
  /// flashes a broken tile before it settles. A test keeps this in step with
  /// what is actually on disk.
  static const Set<String> withArtwork = <String>{
    'peter-rabbit',
    'aesops-fables',
    'happy-prince',
    'sherlock-adventures',
    'jekyll-and-hyde',
  };

  static String assetFor(String slug) => 'assets/covers/$slug.jpg';

  /// Deep enough that white sits on all of them, and distinct enough at this
  /// size that two drawn covers are never mistaken for each other.
  static const List<Color> _palette = <Color>[
    Color(0xFF2A3D2E), // forest board
    Color(0xFF6B2B2B), // oxblood
    Color(0xFF1F3A5C), // navy cloth
    Color(0xFF4A3A26), // tan buckram
    Color(0xFF3B2A4A), // aubergine
    Color(0xFF14494A), // deep teal
    Color(0xFF5A2C46), // plum
    Color(0xFF33383D), // slate
  ];

  /// Distinct for every shelf shorter than the palette, by construction.
  ///
  /// Hashing the slug was the first attempt and is the more appealing idea,
  /// since the colour would then belong to the book and never move. It was
  /// wrong: six books drawn from eight colours came out as four colours, and
  /// widening the palette until these six separated would have been fitting
  /// the design to today's shelf and would break silently on the seventh.
  static Color colourOf(int shelfIndex) =>
      _palette[shelfIndex.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(NfSpace.s4),
        right: Radius.circular(NfSpace.s6),
      ),
      child: SizedBox(
        width: _width,
        height: _height,
        child: withArtwork.contains(book.slug)
            ? Image.asset(assetFor(book.slug), fit: BoxFit.cover)
            : _drawn(),
      ),
    );
  }

  /// A cover for a book that has none: a cloth board with the title stamped on
  /// it, which is what the five beside it are.
  Widget _drawn() {
    final Color board = colourOf(shelfIndex);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[board, Color.lerp(board, Colors.black, 0.32)!],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NfSpace.s6),
        child: Container(
          // The blind-stamped rule that runs round an old binding. It is what
          // stops the tile reading as a coloured rectangle.
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: .28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  book.title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                book.author,
                textAlign: TextAlign.center,
                // Two, because one gave "Joseph Conr..." on a phone. A 52dp
                // column is not wide enough for most names on one line, and an
                // old binding sets the author over two anyway.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .72),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
