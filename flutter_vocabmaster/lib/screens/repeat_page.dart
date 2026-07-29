import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../widgets/animated_background.dart';
import '../models/word.dart';
import '../services/api_service.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../providers/app_state_provider.dart';
import '../services/analytics_service.dart';
import '../services/in_app_review_service.dart';
import '../services/locale_text_service.dart';
import '../services/xp_manager.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/session_summary_sheet.dart';

class RepeatPage extends StatefulWidget {
  const RepeatPage({
    super.key,
    this.initialWordId,
    this.apiService,
    this.dueOnly = false,
  });

  final int? initialWordId;

  /// When true, only words whose SRS `nextReviewDate` has arrived are loaded,
  /// so a session opened from the home "N words due" card really holds N cards.
  final bool dueOnly;

  /// Test seam; production always uses the real [ApiService].
  final ApiService? apiService;

  @override
  State<RepeatPage> createState() => _RepeatPageState();
}

class _RepeatPageState extends State<RepeatPage> with TickerProviderStateMixin {
  // State
  int _currentIndex = 0;
  bool _showTranslation = false;
  List<Word> words = [];
  bool isLoading = true;
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final FlutterTts flutterTts = FlutterTts();
  bool _isSubmittingSrsGrade = false;

  // Oturum özeti: bu oturumda tamamlanan aksiyon sayısı ve kazanılan XP.
  // Tam bir tur (words.length aksiyon) tamamlanınca özet gösterilir.
  int _sessionActions = 0;
  int _sessionXp = 0;

  void _registerSessionAction({required int xpEarned}) {
    _sessionActions++;
    _sessionXp += xpEarned;
    if (words.isNotEmpty && _sessionActions >= words.length) {
      final xpForSheet = _sessionXp;
      final itemsForSheet = _sessionActions;
      _sessionActions = 0;
      _sessionXp = 0;
      // Kart geçiş animasyonuyla çakışmaması için bir frame sonra göster.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SessionSummarySheet.show(
          context,
          xpEarned: xpForSheet,
          itemsCompleted: itemsForSheet,
        );
      });
    }
  }

  // Button states
  bool _previousPressed = false;
  bool _nextPressed = false;
  bool _favoritePressed = false;
  bool _learnPressed = false;
  bool _isCardPressed = false;

  // Animation Controllers
  late AnimationController _iconController;
  late AnimationController _rotationController;
  late AnimationController _orb1Controller;
  late AnimationController _orb2Controller;
  late AnimationController _orb3Controller;
  late AnimationController _shimmerController;
  late List<AnimationController> _statsAnimations;
  late List<AnimationController> _particleControllers;

  AppThemeConfig _theme({bool listen = false}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)
              ?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  Color _mix(Color a, Color b, double t) {
    return Color.lerp(a, b, t) ?? a;
  }

  @override
  void initState() {
    super.initState();
    _loadWords();
    _initTts();

    // Initialize controllers
    _iconController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _rotationController = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
    _orb1Controller =
        AnimationController(duration: const Duration(seconds: 6), vsync: this)
          ..repeat(reverse: true);
    _orb2Controller =
        AnimationController(duration: const Duration(seconds: 8), vsync: this)
          ..repeat(reverse: true);
    _orb3Controller =
        AnimationController(duration: const Duration(seconds: 10), vsync: this)
          ..repeat(reverse: true);
    _shimmerController =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat();

    _statsAnimations = List.generate(
        2,
        (i) => AnimationController(
            duration: const Duration(milliseconds: 500), vsync: this));
    _particleControllers = List.generate(
        5,
        (i) => AnimationController(
            duration: const Duration(seconds: 3), vsync: this)
          ..repeat());

    // Start animations
    _iconController.forward();
    _startStaggeredAnimations();
  }

  /// Words the SM-2 scheduler has brought up for today. Falls back to the full
  /// deck when nothing is due (or the backend omits `nextReviewDate`), so the
  /// screen is never mysteriously empty.
  List<Word> _selectDueWords(List<Word> all) {
    final endOfToday = DateTime.now().copyWith(
      hour: 23,
      minute: 59,
      second: 59,
      millisecond: 999,
      microsecond: 999,
    );
    final due = all
        .where((word) =>
            word.nextReviewDate != null &&
            !word.nextReviewDate!.isAfter(endOfToday))
        .toList();
    return due.isEmpty ? all : due;
  }

  Future<void> _loadWords() async {
    try {
      final allWords = await _apiService.getAllWords();
      final loadedWords =
          widget.dueOnly ? _selectDueWords(allWords) : allWords;
      if (mounted) {
        final initialIndex = widget.initialWordId == null
            ? 0
            : loadedWords.indexWhere((word) => word.id == widget.initialWordId);
        setState(() {
          words = loadedWords;
          _currentIndex = initialIndex >= 0 ? initialIndex : 0;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleTextService.pick('Hata: $e', 'Error: $e')),
          ),
        );
      }
    }
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  void _startStaggeredAnimations() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _statsAnimations[0].forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _statsAnimations[1].forward();
    });
  }

  void _handleNext() {
    if (words.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % words.length;
      _showTranslation = false;
    });
  }

  void _handlePrevious() {
    if (words.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex - 1 + words.length) % words.length;
      _showTranslation = false;
    });
  }

  Future<void> _playAudio() async {
    if (words.isEmpty) return;
    final word = words[_currentIndex].englishWord;
    await flutterTts.speak(word);
  }

  /// Classic Review previously never fed the backend SM-2 engine — grades
  /// went nowhere and due dates never advanced. Submitting here reuses the
  /// same `/api/srs/submit-review` path as Neural review. Offline/temp-id
  /// failures are tolerated: the session keeps flowing either way.
  Future<void> _submitSrsGrade(int quality) async {
    if (words.isEmpty || _isSubmittingSrsGrade) return;
    final word = words[_currentIndex];
    setState(() => _isSubmittingSrsGrade = true);
    try {
      await context
          .read<AppStateProvider>()
          .submitWordReview(wordId: word.id, quality: quality);
    } catch (e) {
      debugPrint('Classic review SRS submit failed (offline?): $e');
    }
    if (!mounted) return;
    // SRS notlama bugüne kadar hiç XP/streak vermiyordu - yalnızca manuel
    // "öğrenildi" butonu veriyordu. Not vermek de bir tekrar tamamlamadır;
    // addXPForAction ayrıca streak'i işler (creditLearningActivity).
    // Bilinçli olarak await edilmiyor: kart akışı XP alt sistemine (prefs/DB)
    // takılmamalı - kazanç toast'u zaten global dinleyiciden gelir.
    unawaited(context.read<AppStateProvider>().addXPForAction(
          XPActionTypes.reviewComplete,
          source: 'SRS Tekrar',
        ));
    _registerSessionAction(xpEarned: XPActionTypes.reviewComplete.xpAmount);
    setState(() => _isSubmittingSrsGrade = false);
    _handleNext();
  }

  Future<void> _markAsLearned() async {
    // XP ekle
    if (!mounted) return;
    final appState = context.read<AppStateProvider>();
    await appState.addXPForAction(XPActionTypes.reviewComplete,
        source: 'Tekrar');
    await AnalyticsService.logPracticeCompleted(type: 'classic_review');
    await InAppReviewService().recordPracticeCompletion();
    if (!mounted) return;
    _registerSessionAction(xpEarned: XPActionTypes.reviewComplete.xpAmount);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(LocaleTextService.pick(
            'Öğrenildi olarak işaretlendi! (+5 XP)',
            'Marked as learned! (+5 XP)',
          )),
          duration: const Duration(milliseconds: 800)),
    );
    _handleNext();
  }

  double _getWordFontSize(String word) {
    // Kelime uzunluğuna göre font boyutu
    final length = word.length;
    if (length <= 6) return 56.0;
    if (length <= 8) return 48.0;
    if (length <= 10) return 40.0;
    if (length <= 12) return 34.0;
    if (length <= 15) return 28.0;
    if (length <= 18) return 24.0;
    return 20.0;
  }

  @override
  void dispose() {
    _iconController.dispose();
    _rotationController.dispose();
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    _orb3Controller.dispose();
    _shimmerController.dispose();
    for (var c in _statsAnimations) {
      c.dispose();
    }
    for (var c in _particleControllers) {
      c.dispose();
    }
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme(listen: true);

    if (isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colors.accent),
        ),
      );
    }

    if (words.isEmpty) {
      return Scaffold(
        backgroundColor: theme.colors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                LocaleTextService.pick(
                  'Henüz hiç kelime yok.\nSözlükten kelime ekleyin!',
                  'No words yet.\nAdd some from the dictionary!',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(LocaleTextService.pick('Geri Dön', 'Go Back')),
              ),
            ],
          ),
        ),
      );
    }

    final currentCard = words[_currentIndex % words.length];
    final progress = (_currentIndex + 1) / words.length;
    // Calculate progress for stats
    final remaining = words.length - (_currentIndex + 1);

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colors.background,
                  _mix(theme.colors.background, theme.colors.primaryDark, 0.52),
                  theme.colors.background,
                ],
              ),
            ),
          ),

          // Animated background
          const AnimatedBackground(isDark: true),

          // Orbs
          _buildAnimatedOrb(_orb1Controller, top: 80, left: 40),
          _buildAnimatedOrb(_orb2Controller,
              top: MediaQuery.of(context).size.height / 3, right: 40),
          _buildAnimatedOrb(_orb3Controller, bottom: 160),

          // Main View Column (No Scroll)
          SafeArea(
            child: Column(
              children: [
                _buildHeader(progress, remaining),
                // Flashcard Area - Expands to fill available space
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: _buildFlashcard(currentCard),
                  ),
                ),
                // Navigation Buttons (Fixed at bottom)
                _buildNavigationButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedOrb(AnimationController controller,
      {double? top, double? bottom, double? left, double? right}) {
    final theme = _theme(listen: true);
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final scale = 1.0 + (0.3 * controller.value);
          final opacity = 0.3 + (0.3 * controller.value);
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  color: theme.colors.orbColor1.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(double progress, int remaining) {
    final theme = _theme(listen: true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),

              // Title
              Column(
                children: [
                  Text(
                    LocaleTextService.pick('Tekrar', 'Review'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_currentIndex + 1} / ${words.length}',
                    style: TextStyle(
                      color: theme.colors.accent.withValues(alpha: 0.75),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),

              // Refresh Button
              AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationController.value * math.pi,
                    child: IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        _rotationController.forward(from: 0);
                        _loadWords();
                      },
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats Pills
          Row(
            children: [
              _buildStatsPill(
                0,
                icon: Icons.auto_awesome,
                label: LocaleTextService.pick(
                  'İlerleme: ${(progress * 100).toInt()}%',
                  'Progress: ${(progress * 100).toInt()}%',
                ),
                gradient: [
                  theme.colors.accent,
                  theme.colors.primary,
                ],
              ),
              const SizedBox(width: 12),
              _buildStatsPill(
                1,
                icon: Icons.bolt,
                label: LocaleTextService.pick(
                  '$remaining kaldı',
                  '$remaining left',
                ),
                gradient: [
                  _mix(theme.colors.primary, theme.colors.accent, 0.45),
                  _mix(theme.colors.accent, Colors.white, 0.15),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPill(int index,
      {required IconData icon,
      required String label,
      required List<Color> gradient}) {
    return Expanded(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.5, 0),
          end: Offset.zero,
        ).animate(_statsAnimations[index]),
        child: FadeTransition(
          opacity: _statsAnimations[index],
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gradient[0].withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: gradient[0], size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: gradient[1].withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlashcard(Word card) {
    final theme = _theme(listen: true);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: SizedBox(
        key: ValueKey(_currentIndex),
        width: double.infinity,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isCardPressed = true),
          onTapUp: (_) => setState(() => _isCardPressed = false),
          onTapCancel: () => setState(() => _isCardPressed = false),
          child: Stack(
            fit: StackFit.loose,
            children: [
              // Glow background
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _isCardPressed ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colors.accent.withValues(alpha: 0.26),
                          theme.colors.primary.withValues(alpha: 0.26),
                          _mix(theme.colors.primary, theme.colors.accent, 0.5)
                              .withValues(alpha: 0.26),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ),

              // Actual Card Content
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.1),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Accent Line
                          Container(
                            height: 4,
                            width: 120,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colors.accent,
                                  theme.colors.primary,
                                  _mix(theme.colors.primary,
                                      theme.colors.accent, 0.5),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),

                          // Top Section: Badge & Speaker
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        theme.colors.accent,
                                        theme.colors.primary,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colors.accentGlow
                                            .withValues(alpha: 0.5),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    card.difficulty.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.volume_up,
                                      color: Colors.white),
                                  style: IconButton.styleFrom(
                                    backgroundColor: theme.colors.primary
                                        .withValues(alpha: 0.45),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  onPressed: _playAudio,
                                ),
                              ],
                            ),
                          ),

                          // Word, meaning and example share one scroll area.
                          // They used to sit in separate Expanded(flex:) slots,
                          // which clipped a wrapped meaning mid-line and hid the
                          // revealed translation below the example box's fold.
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 8),
                                  Text(
                                    card.englishWord,
                                    style: TextStyle(
                                      fontSize:
                                          _getWordFontSize(card.englishWord),
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                      foreground: Paint()
                                        ..shader = LinearGradient(
                                          colors: [
                                            _mix(theme.colors.accent,
                                                Colors.white, 0.2),
                                            theme.colors.primaryLight,
                                            _mix(theme.colors.primary,
                                                theme.colors.accent, 0.45),
                                          ],
                                        ).createShader(const Rect.fromLTWH(
                                            0, 0, 300, 70)),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    card.turkishMeaning,
                                    style: TextStyle(
                                      color: const Color(0xFFE0F2FE)
                                          .withValues(alpha: 0.8),
                                      fontSize: _getMeaningFontSize(
                                          card.turkishMeaning),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (card.sentences.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _buildExampleBox(card),
                                  ],
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // SRS grade buttons (feed the SM-2 scheduler)
                          _buildSrsGradeButtons(),

                          const SizedBox(height: 12),

                          // Action Buttons
                          _buildActionButtons(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Particles
              ...List.generate(5, (i) {
                return Positioned(
                  bottom: 40,
                  left: 20.0 + (i * 40),
                  child: AnimatedBuilder(
                    animation: _particleControllers[i],
                    builder: (context, child) {
                      final progress = _particleControllers[i].value;
                      return Transform.translate(
                        offset: Offset(0, -progress * 150),
                        child: Opacity(
                          opacity: (1 - progress) * 0.5,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  double _getMeaningFontSize(String text) {
    if (text.length > 150) return 12.0;
    if (text.length > 100) return 13.0;
    if (text.length > 60) return 15.0;
    if (text.length > 30) return 18.0;
    return 22.0;
  }

  Widget _buildExampleBox(Word card) {
    final theme = _theme(listen: true);
    final example = card.sentences.isNotEmpty
        ? card.sentences.first.sentence
        : LocaleTextService.pick('Örnek cümle yok', 'No example sentence');
    final exampleTr = card.sentences.isNotEmpty
        ? card.sentences.first.translation
        : LocaleTextService.pick('Çeviri yok', 'No translation');

    return ModernCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      variant: BackgroundVariant.primary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"$example"',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: example.length > 80 ? 12 : 14,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          if (_showTranslation) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 8),
            Text(
              exampleTr,
              style: TextStyle(
                color: theme.colors.accent.withValues(alpha: 0.85),
                fontSize: exampleTr.length > 80 ? 12 : 13,
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showTranslation = true),
              child: Text(
                LocaleTextService.pick(
                  'Çeviri görmek için dokunun',
                  'Tap to see the translation',
                ),
                style: TextStyle(
                  color: theme.colors.accent,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSrsGradeButtons() {
    final theme = _theme(listen: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleTextService.pick(
            'Bu kelime ne kadar kolaydı?',
            'How easy was this word?',
          ),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildSrsGradeButton(
              key: const ValueKey('srs-grade-hard'),
              label: LocaleTextService.pick('Zor', 'Hard'),
              icon: Icons.replay_rounded,
              color: const Color(0xFFF87171),
              quality: 2,
            ),
            const SizedBox(width: 10),
            _buildSrsGradeButton(
              key: const ValueKey('srs-grade-good'),
              label: LocaleTextService.pick('İyi', 'Good'),
              icon: Icons.check_rounded,
              color: theme.colors.accent,
              quality: 4,
            ),
            const SizedBox(width: 10),
            _buildSrsGradeButton(
              key: const ValueKey('srs-grade-easy'),
              label: LocaleTextService.pick('Kolay', 'Easy'),
              icon: Icons.done_all_rounded,
              color: const Color(0xFF34D399),
              quality: 5,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSrsGradeButton({
    required Key key,
    required String label,
    required IconData icon,
    required Color color,
    required int quality,
  }) {
    return Expanded(
      child: InkWell(
        key: key,
        onTap: _isSubmittingSrsGrade ? null : () => _submitSrsGrade(quality),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final theme = _theme(listen: true);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTapDown: (_) => setState(() => _favoritePressed = true),
            onTapUp: (_) => setState(() => _favoritePressed = false),
            onTapCancel: () => setState(() => _favoritePressed = false),
            child: AnimatedScale(
              scale: _favoritePressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _favoritePressed ? Icons.favorite : Icons.favorite_border,
                      color: const Color(0xFFEC4899),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        LocaleTextService.pick(
                          'Favorilere Ekle',
                          'Add to Favorites',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTapDown: (_) => setState(() => _learnPressed = true),
            onTapUp: (_) {
              setState(() => _learnPressed = false);
              _markAsLearned();
            },
            onTapCancel: () => setState(() => _learnPressed = false),
            child: AnimatedScale(
              scale: _learnPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colors.accent, theme.colors.primary],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _learnPressed ? Icons.star : Icons.star_border,
                      color: _learnPressed
                          ? const Color(0xFFFDE047)
                          : Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        LocaleTextService.pick('Öğrendim', 'I Learned It'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final theme = _theme(listen: true);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => setState(() => _previousPressed = true),
              onTapUp: (_) {
                setState(() => _previousPressed = false);
                _handlePrevious();
              },
              onTapCancel: () => setState(() => _previousPressed = false),
              child: AnimatedScale(
                scale: _previousPressed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Center(
                    child: Text(
                      LocaleTextService.pick('Önceki', 'Previous'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => setState(() => _nextPressed = true),
              onTapUp: (_) {
                setState(() => _nextPressed = false);
                _handleNext();
              },
              onTapCancel: () => setState(() => _nextPressed = false),
              child: AnimatedScale(
                scale: _nextPressed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colors.accent, theme.colors.primary],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colors.accentGlow.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      LocaleTextService.pick('Sonraki', 'Next'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
