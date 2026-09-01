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
              BookSpine(book: book, shelfIndex: index),
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

/// A book's spine, drawn rather than downloaded.
///
/// The shelf was six rows of title, author and a level badge, and it read as a
/// database table rather than as books. What it wanted was a picture, and the
/// obvious picture -- the real cover -- is the wrong one to reach for. These
/// texts are public domain but their modern jacket art is not, the scans that
/// are free are inconsistent in size, tone and quality, and every one of them
/// would be a network image on a screen that currently needs no network at all.
///
/// So the spine is generated, and its colour comes from the book's position on
/// the shelf rather than from anything about the book.
///
/// Hashing the slug was the first attempt, and it is the more appealing idea:
/// the colour would belong to the book itself and never move. It was wrong.
/// Six books drawn from eight colours collide about ninety per cent of the
/// time -- the test found four colours across the six, which is most of the
/// point of having them gone. Widening the palette until these particular six
/// happened to separate would be fitting the design to today's shelf and
/// would break on the seventh book, silently.
///
/// By position it cannot collide while the shelf is shorter than the palette,
/// and the failure when it is longer is a wrap-around between rows far apart
/// on screen. The cost is real and accepted: inserting a book renumbers the
/// ones after it, so their colours move once. The shelf is a server-side
/// constant that changes about never, and six spines that look the same is a
/// worse thing every day than six that shift on the day a book is added.
class BookSpine extends StatelessWidget {
  const BookSpine({super.key, required this.book, required this.shelfIndex});

  final BookShelfEntry book;

  /// Where this book sits on the shelf, which is what picks its colour.
  final int shelfIndex;

  static const double _width = 52;
  static const double _height = 74;

  /// Deep enough that white sits on all of them, and distinct enough at
  /// thumbnail size that two spines are never mistaken for each other.
  static const List<Color> _palette = <Color>[
    Color(0xFF6C4EF5), // the app's violet
    Color(0xFF1F7A5A), // pine
    Color(0xFF9C3B4E), // claret
    Color(0xFF2A5C8A), // slate blue
    Color(0xFF8A5A1F), // tan
    Color(0xFF4A3A7A), // aubergine
    Color(0xFF1F6A6A), // teal
    Color(0xFF6A2F5C), // plum
  ];

  /// Distinct for every shelf shorter than the palette, by construction.
  static Color colourOf(int shelfIndex) =>
      _palette[shelfIndex.abs() % _palette.length];

  /// The first letter that carries meaning. "The Tale of Peter Rabbit" is a T
  /// for Tale, not for The -- four of these six titles open with "The", and
  /// four identical letters is no picture at all.
  static String initialOf(String title) {
    const Set<String> skip = <String>{'the', 'a', 'an'};
    for (final String word in title.trim().split(RegExp(r'\s+'))) {
      final String bare = word.replaceAll(RegExp(r"[^A-Za-z']"), '');
      if (bare.isEmpty || skip.contains(bare.toLowerCase())) {
        continue;
      }
      return bare[0].toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final Color colour = colourOf(shelfIndex);
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        // Rounded on the fore-edge, square at the spine, which is the shape of
        // a closed book seen face-on and the cheapest way to say "book".
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(NfSpace.s4),
          right: Radius.circular(NfSpace.s6),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colour, Color.lerp(colour, Colors.black, 0.34)!],
        ),
      ),
      child: Stack(
        children: <Widget>[
          // The binding: one lighter hairline a few pixels in from the left.
          Positioned(
            left: NfSpace.s6,
            top: NfSpace.s6,
            bottom: NfSpace.s6,
            child: Container(width: 1, color: Colors.white.withValues(alpha: .22)),
          ),
          Center(
            child: Text(
              initialOf(book.title),
              style: NfTokens.display(size: NfFont.s25, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
