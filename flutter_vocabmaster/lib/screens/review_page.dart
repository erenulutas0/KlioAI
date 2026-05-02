import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../widgets/navigation_menu_panel.dart';
import '../widgets/animated_background.dart';
import '../widgets/bottom_nav.dart';
import '../services/global_state.dart';
import '../services/offline_sync_service.dart';
import '../models/word.dart';
import '../providers/app_state_provider.dart';
import '../main.dart'; // Import MainScreen
import '../screens/stats_page.dart';
import '../screens/profile_page.dart';
import '../screens/chat_list_page.dart';
import '../screens/quick_dictionary_page.dart';
import '../screens/social_feed_page.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // ... state variables ...
  int _currentIndex = 0;
  List<Word> _words = [];
  bool _isLoading = true;
  bool _showTranslation = false;
  final OfflineSyncService _offlineSyncService = OfflineSyncService();
  final FlutterTts _flutterTts = FlutterTts();

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';
  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();
    _loadWords();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppStateProvider>().refreshWords();
    });
  }

  Future<void> _loadWords() async {
    try {
      final words = await _offlineSyncService.getAllWords();
      if (mounted) {
        setState(() {
          _words = words;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.speak(text);
  }

  void _nextCard() {
    if (_currentIndex < _words.length - 1) {
      setState(() {
        _currentIndex++;
        _showTranslation = false;
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showTranslation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appStateWords = context.watch<AppStateProvider>().allWords;
    if (appStateWords.isNotEmpty) {
      _words = appStateWords;
      if (_isLoading) _isLoading = false;
      if (_currentIndex >= _words.length) {
        _currentIndex = _words.isEmpty ? 0 : _words.length - 1;
      }
    }
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.isMatching,
      builder: (context, isMatching, _) {
        final double cardPadding = isMatching ? 12.0 : 20.0;
        final double spacerHeight = isMatching ? 10.0 : 20.0;
        final double smallSpacerHeight = isMatching ? 4.0 : 8.0;
        final double wordFontSize = isMatching ? 32.0 : 42.0;
        final double meaningFontSize = isMatching ? 14.0 : 16.0;
        final double sentencePadding = isMatching ? 10.0 : 16.0;
        final double sentenceFontSize = isMatching ? 13.0 : 14.0;

        return Scaffold(
          key: _scaffoldKey,
          drawer: NavigationMenuPanel(
            activeTab: '',
            currentPage: 'repeat',
            onTabChange: (id) {
              Navigator.pop(context);

              if (['home', 'words', 'sentences', 'practice'].contains(id)) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => MainScreen(
                          initialIndex: id == 'home'
                              ? 0
                              : id == 'words'
                                  ? 1
                                  : id == 'sentences'
                                      ? 3
                                      : 4)),
                  (route) => false,
                );
              }
            },
            onNavigate: (id) {
              Navigator.pop(context);

              if (id == 'repeat') return;

              if (id == 'chat') {
                // For now simply open chat list or reuse the dialog logic if possible (need to duplicate logic or make it shared)
                // Simplest: push ChatListPage
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatListPage()));
              } else if (id == 'feed') {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SocialFeedPage()));
              } else if (id == 'speaking') {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const MainScreen(initialIndex: 4)),
                  (route) => false,
                );
              } else if (id == 'dictionary') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const QuickDictionaryPage()));
              } else if (id == 'stats') {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const StatsPage()));
              } else if (id == 'profile-settings') {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfilePage()));
              }
            },
          ),
          body: Builder(
            builder: (context) => Stack(
              children: [
                const AnimatedBackground(isDark: true),
                SafeArea(
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Text(
                              _words.isEmpty
                                  ? _text('Tekrar', 'Review')
                                  : '${_text('Tekrar', 'Review')} (${_currentIndex + 1}/${_words.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  _currentIndex = 0;
                                  _showTranslation = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      // Progress Bar
                      if (_words.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: (_currentIndex + 1) / _words.length,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF06b6d4)),
                              minHeight: 8,
                            ),
                          ),
                        ),

                      SizedBox(height: spacerHeight),

                      // Content
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _words.isEmpty
                                ? Center(
                                    child: Text(
                                      _text('Henuz ogrenilen kelime yok.',
                                          'No words available for review yet.'),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 18),
                                    ),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: Dismissible(
                                      key: ValueKey(_words[_currentIndex].id),
                                      direction: DismissDirection.horizontal,
                                      onDismissed: (direction) {
                                        if (direction ==
                                            DismissDirection.endToStart) {
                                          // Swipe Left -> Next
                                          if (_currentIndex <
                                              _words.length - 1) {
                                            setState(() {
                                              _currentIndex++;
                                              _showTranslation = false;
                                            });
                                          } else {
                                            // End of list, reset or show message?
                                            setState(() {
                                              // Just rebuild to bring back the card if dismissed (but Dismissible removes it from tree...)
                                              // We need to handle index carefully.
                                              // Simple way: prevent dismiss if last item using confirmDismiss?
                                              // But logic here handles logic after dismiss.
                                              // If last item, maybe cycle? For now, handled by index check.
                                              if (_currentIndex <
                                                  _words.length - 1)
                                                _currentIndex++;
                                            });
                                          }
                                        } else {
                                          // Swipe Right -> Prev
                                          if (_currentIndex > 0) {
                                            setState(() {
                                              _currentIndex--;
                                              _showTranslation = false;
                                            });
                                          }
                                        }
                                      },
                                      confirmDismiss: (direction) async {
                                        // Only confirm if we can move
                                        if (direction ==
                                            DismissDirection.endToStart) {
                                          return _currentIndex <
                                              _words.length - 1;
                                        } else {
                                          return _currentIndex > 0;
                                        }
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1e3a8a)
                                              .withOpacity(0.5),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          border: Border.all(
                                              color:
                                                  Colors.white.withOpacity(0.2),
                                              width: 2),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final word =
                                                  _words[_currentIndex];
                                              return SingleChildScrollView(
                                                padding:
                                                    EdgeInsets.all(cardPadding),
                                                child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    minHeight:
                                                        constraints.maxHeight -
                                                            (cardPadding * 2),
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      // Top Row: Badge & Speaker
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        12,
                                                                    vertical:
                                                                        6),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: _getDifficultyColor(
                                                                  word.difficulty),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          20),
                                                            ),
                                                            child: Text(
                                                              word.difficulty
                                                                  .toUpperCase(),
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons.volume_up,
                                                                color: Colors
                                                                    .white70),
                                                            onPressed: () =>
                                                                _speak(word
                                                                    .englishWord),
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                          ),
                                                        ],
                                                      ),

                                                      SizedBox(
                                                          height: spacerHeight),

                                                      // Word & Meaning
                                                      Column(
                                                        children: [
                                                          Text(
                                                            word.englishWord,
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize:
                                                                  wordFontSize,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              height: 1.1,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                          ),
                                                          SizedBox(
                                                              height:
                                                                  smallSpacerHeight),
                                                          Text(
                                                            word.turkishMeaning,
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.7),
                                                              fontSize:
                                                                  meaningFontSize,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                          ),
                                                        ],
                                                      ),

                                                      SizedBox(
                                                          height: spacerHeight),

                                                      // Bottom Section
                                                      Column(
                                                        children: [
                                                          // Sentence Box
                                                          if (word.sentences
                                                              .isNotEmpty)
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  setState(() =>
                                                                      _showTranslation =
                                                                          !_showTranslation),
                                                              child: Container(
                                                                width: double
                                                                    .infinity,
                                                                padding:
                                                                    EdgeInsets.all(
                                                                        sentencePadding),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: const Color(
                                                                          0xFF0ea5e9)
                                                                      .withOpacity(
                                                                          0.2),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              16),
                                                                  border: Border
                                                                      .all(
                                                                    color: const Color(
                                                                            0xFF0ea5e9)
                                                                        .withOpacity(
                                                                            0.3),
                                                                  ),
                                                                ),
                                                                child: Column(
                                                                  children: [
                                                                    Text(
                                                                      '"${word.sentences.first.sentence}"',
                                                                      style:
                                                                          TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontSize:
                                                                            sentenceFontSize,
                                                                        fontStyle:
                                                                            FontStyle.italic,
                                                                        height:
                                                                            1.4,
                                                                      ),
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                    ),
                                                                    SizedBox(
                                                                        height:
                                                                            smallSpacerHeight +
                                                                                4),
                                                                    Text(
                                                                      _showTranslation
                                                                          ? word
                                                                              .sentences
                                                                              .first
                                                                              .translation
                                                                          : _text(
                                                                              'Ceviriyi gormek icin dokunun',
                                                                              'Tap to reveal the translation'),
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Color(
                                                                            0xFF06b6d4),
                                                                        fontSize:
                                                                            12,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            )
                                                          else
                                                            Text(
                                                              _text(
                                                                  'Ornek cumle yok',
                                                                  'No example sentence'),
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white
                                                                      .withOpacity(
                                                                          0.5),
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic),
                                                            ),

                                                          SizedBox(
                                                              height:
                                                                  spacerHeight),

                                                          // Action Buttons
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child:
                                                                    _buildActionButton(
                                                                  icon: Icons
                                                                      .favorite_border,
                                                                  label: _text(
                                                                      'Favorilere Ekle',
                                                                      'Add to Favorites'),
                                                                  onTap: () {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                          content: Text(_text(
                                                                              'Favorilere eklendi!',
                                                                              'Added to favorites!')),
                                                                          duration:
                                                                              const Duration(seconds: 1)),
                                                                    );
                                                                  },
                                                                  isCompact:
                                                                      isMatching,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 12),
                                                              Expanded(
                                                                child:
                                                                    _buildActionButton(
                                                                  icon: Icons
                                                                      .check_circle_outline,
                                                                  label: _text(
                                                                      'Ogrendim',
                                                                      'Learned'),
                                                                  onTap: () {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Container(
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              vertical: 4),
                                                                          child:
                                                                              Row(
                                                                            children: [
                                                                              Icon(Icons.check_circle, color: Colors.white, size: 28),
                                                                              SizedBox(width: 12),
                                                                              Text(
                                                                                _text('Ogrenildi!', 'Marked as learned!'),
                                                                                style: TextStyle(
                                                                                  color: Colors.white,
                                                                                  fontSize: 16,
                                                                                  fontWeight: FontWeight.bold,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        backgroundColor:
                                                                            const Color(0xFF0ea5e9), // Neon Blue (Sky 500)
                                                                        behavior:
                                                                            SnackBarBehavior.floating,
                                                                        shape:
                                                                            RoundedRectangleBorder(
                                                                          borderRadius:
                                                                              BorderRadius.circular(16),
                                                                          side: BorderSide(
                                                                              color: Colors.white.withOpacity(0.2),
                                                                              width: 1),
                                                                        ),
                                                                        margin: const EdgeInsets
                                                                            .all(
                                                                            20),
                                                                        duration:
                                                                            const Duration(milliseconds: 1500),
                                                                        elevation:
                                                                            10,
                                                                      ),
                                                                    );
                                                                    _nextCard();
                                                                  },
                                                                  isCompact:
                                                                      isMatching,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                      ),

                      SizedBox(height: spacerHeight),

                      // Navigation Buttons (Outside Card)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            20, 0, 20, isMatching ? 10 : 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    _words.isNotEmpty && _currentIndex > 0
                                        ? _prevCard
                                        : null,
                                icon: const Icon(Icons.chevron_left),
                                label: Text(_text('Onceki', 'Previous')),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                      color: Colors.white.withOpacity(0.3)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor:
                                      const Color(0xFF1e3a8a).withOpacity(0.3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _words.isNotEmpty &&
                                        _currentIndex < _words.length - 1
                                    ? _nextCard
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                                label: Text(_text('Sonraki', 'Next')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF06b6d4),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 4,
                                  shadowColor:
                                      const Color(0xFF06b6d4).withOpacity(0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ), // Closing Builder for body
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // MVP: GlobalMatchmakingSheet disabled for v1.0
              // const GlobalMatchmakingSheet(),
              BottomNav(
                currentIndex: -1,
                onTap: (index) {
                  if (index == 2) {
                    _scaffoldKey.currentState?.openDrawer();
                  } else {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => MainScreen(initialIndex: index)),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
      case 'kolay':
        return Colors.green;
      case 'medium':
      case 'orta':
        return Colors.amber;
      case 'hard':
      case 'zor':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isCompact ? 8 : 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: isCompact ? 20 : 24),
          ),
          SizedBox(height: isCompact ? 4 : 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
