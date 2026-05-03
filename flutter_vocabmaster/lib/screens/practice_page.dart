import 'package:flutter/material.dart';
import '../widgets/animated_background.dart';
import '../widgets/info_dialog.dart';
import '../models/word.dart';
import '../services/global_state.dart';
import 'exam_selection_page.dart';
import 'translation_practice_page.dart';
import 'reading_practice_page.dart';
import 'writing_practice_page.dart';
import 'video_call_page.dart';
import '../services/matchmaking_service.dart';
import 'package:provider/provider.dart';
import '../widgets/animated_ai_chat_card.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../widgets/level_and_length_section.dart';
import '../providers/app_state_provider.dart';
import 'grammar_tab.dart';
import 'neural_game_page.dart';
import 'word_galaxy_page.dart';
import '../services/daily_practice_progress_service.dart';
import '../services/app_market_config.dart';
import '../services/ai_access_policy.dart';
import '../services/analytics_service.dart';
import '../services/first_session_activation_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../l10n/app_localizations.dart';

class PracticePage extends StatefulWidget {
  final String? initialMode;
  const PracticePage({super.key, this.initialMode});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with TickerProviderStateMixin {
  static const String _modeTranslate = 'translate';
  static const String _modeReading = 'reading';
  static const String _modeWriting = 'writing';
  static const String _modeGrammar = 'grammar';
  static const String _modeSpeaking = 'speaking';
  static const String _modeExams = 'exams';
  static const String _modeNeural = 'neural';
  static const String _modeWordGalaxy = 'word_galaxy';

  static const String _subModeSelect = 'select';
  static const String _subModeManual = 'manual';
  static const String _subModeMixed = 'random';

  static const String _lengthMedium = 'medium';

  String _selectedMode = _modeTranslate;
  String _selectedSubMode = _subModeSelect;
  String _selectedLevel = 'B1';
  String _selectedLength = _lengthMedium;

  // Word Selection State
  List<Word> _allWords = [];
  List<Word> _filteredWords = [];
  final Set<int> _selectedWordIds = {};
  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingWords = true;
  bool _requestedEntitlementRefresh = false;
  final DailyPracticeProgressService _dailyProgressService =
      DailyPracticeProgressService();
  Map<String, bool> _readingCompletedLevels = {};
  final FirstSessionActivationService _activationService =
      FirstSessionActivationService();
  bool _firstSessionPracticeCompleted = false;

  AppThemeConfig _currentTheme({bool listen = true}) {
    try {
      final provider = Provider.of<ThemeProvider?>(context, listen: listen);
      return provider?.currentTheme ?? VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  Color _mix(Color from, Color to, double amount) {
    return Color.lerp(from, to, amount) ?? from;
  }

  static const List<String> _basePracticeModes = [
    _modeTranslate,
    _modeReading,
    _modeWriting,
    _modeGrammar,
    _modeSpeaking,
  ];

  List<String> _availableModesForLocale(Locale? locale,
      {bool compact = false}) {
    if (compact) {
      return const [_modeTranslate, _modeWriting, _modeSpeaking];
    }
    final modes = <String>[..._basePracticeModes];
    if (AppMarketConfig.isExamModuleEnabled(locale)) {
      modes.add(_modeExams);
    }
    modes.add(_modeWordGalaxy);
    modes.add(_modeNeural);
    return modes;
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case _modeReading:
        return context.tr('practice.mode.reading');
      case _modeWriting:
        return context.tr('practice.mode.writing');
      case _modeGrammar:
        return context.tr('practice.mode.grammar');
      case _modeSpeaking:
        return context.tr('practice.mode.speaking');
      case _modeExams:
        return context.tr('practice.mode.exams');
      case _modeWordGalaxy:
        return Localizations.localeOf(context).languageCode == 'tr'
            ? 'Kelime Evreni'
            : 'Word Galaxy';
      case _modeNeural:
        return context.tr('practice.mode.neural');
      default:
        return context.tr('practice.mode.translate');
    }
  }

  String _subModeLabel(String mode) {
    switch (mode) {
      case _subModeManual:
        return context.tr('practice.submode.manual');
      case _subModeMixed:
        return context.tr('practice.submode.mixed');
      default:
        return context.tr('practice.submode.select');
    }
  }

  String _normalizeModeId(String rawMode) {
    switch (rawMode.trim().toLowerCase()) {
      case 'okuma':
      case 'reading':
        return _modeReading;
      case 'yazma':
      case 'writing':
        return _modeWriting;
      case 'gramer':
      case 'grammar':
        return _modeGrammar;
      case 'konuşma':
      case 'konusma':
      case 'speaking':
        return _modeSpeaking;
      case 'sınavlar':
      case 'sinavlar':
      case 'exams':
        return _modeExams;
      case 'kelime evreni':
      case 'word galaxy':
      case 'word_galaxy':
        return _modeWordGalaxy;
      case 'neural oyun':
      case 'neural':
        return _modeNeural;
      default:
        return _modeTranslate;
    }
  }

  void _ensureSelectedModeVisible({bool compact = false}) {
    final locale = Localizations.maybeLocaleOf(context);
    final availableModes = _availableModesForLocale(locale, compact: compact);
    if (!availableModes.contains(_selectedMode)) {
      _selectedMode = availableModes.first;
    }
  }

  void _updateMatchingState() {
    if (mounted) setState(() {});
  }

  // Animation State
  late AnimationController _avatarAnimationController;

  @override
  void initState() {
    super.initState();
    _loadWords();
    _loadDailyCompletionBadges();
    _loadFirstSessionPracticeState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPracticeAccessIfNeeded();
      _logPracticeStarted();
    });
    _searchController.addListener(_onSearchChanged);
    GlobalState.isMatching.addListener(_updateMatchingState);
    GlobalState.matchmakingService.addListener(_onMatchmakingUpdate);
    if (widget.initialMode != null) {
      _selectedMode = _normalizeModeId(widget.initialMode!);
    }

    _avatarAnimationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
  }

  Future<void> _loadDailyCompletionBadges() async {
    final reading = await _dailyProgressService.getCompletedLevels('reading');
    if (!mounted) {
      return;
    }
    setState(() {
      _readingCompletedLevels = reading;
    });
  }

  @override
  void didUpdateWidget(PracticePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != null &&
        widget.initialMode != oldWidget.initialMode) {
      setState(() {
        _selectedMode = _normalizeModeId(widget.initialMode!);
        _ensureSelectedModeVisible(compact: !_firstSessionPracticeCompleted);
      });
      _logPracticeStarted();
    }
  }

  Future<void> _loadFirstSessionPracticeState() async {
    final completed = await _activationService.isPracticeCompleted();
    if (!mounted) return;
    setState(() => _firstSessionPracticeCompleted = completed);
  }

  Future<void> _refreshFirstSessionPracticeState() async {
    if (_firstSessionPracticeCompleted) return;
    final completed = await _activationService.isPracticeCompleted();
    if (!mounted || !completed) return;
    setState(() {
      _firstSessionPracticeCompleted = true;
      _ensureSelectedModeVisible();
    });
  }

  void _selectPracticeMode(String mode) {
    if (_selectedMode == mode) {
      return;
    }
    setState(() => _selectedMode = mode);
    _logPracticeStarted(type: mode);
  }

  void _logPracticeStarted({String? type}) {
    AnalyticsService.logPracticeStarted(
      type: type ?? _selectedMode,
      level: _selectedLevel,
      subMode: _selectedSubMode,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 🔥 AppStateProvider değiştiğinde kelime listesini güncelle
    _syncWordsFromProvider();
    _ensureSelectedModeVisible(compact: !_firstSessionPracticeCompleted);
    _refreshPracticeAccessIfNeeded();
  }

  Future<void> _refreshPracticeAccessIfNeeded() async {
    if (!mounted || _requestedEntitlementRefresh) {
      return;
    }
    final appState = context.read<AppStateProvider>();
    final hasSnapshot = hasAiEntitlementSnapshot(appState.userInfo);
    final hasAccess = hasPracticeAccess(appState.userInfo);
    if (hasSnapshot || hasAccess || appState.isLoadingAiEntitlement) {
      return;
    }
    _requestedEntitlementRefresh = true;
    try {
      await appState.refreshUserData();
    } finally {
      _requestedEntitlementRefresh = false;
    }
  }

  /// Provider'dan güncel kelimeleri al ve local state'i güncelle
  void _syncWordsFromProvider() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final providerWords = appState.allWords;

    // Eğer provider'daki kelimeler local state'ten farklıysa güncelle
    if (providerWords.length != _allWords.length ||
        (providerWords.isNotEmpty &&
            _allWords.isNotEmpty &&
            providerWords.first.id != _allWords.first.id)) {
      final sortedWords = List<Word>.from(providerWords);
      sortedWords.sort((a, b) => b.learnedDate.compareTo(a.learnedDate));

      // Arama filtresiyle birlikte güncelle
      final query = _searchController.text.toLowerCase();
      final filtered = query.isEmpty
          ? sortedWords
          : sortedWords.where((w) {
              return w.englishWord.toLowerCase().contains(query) ||
                  w.turkishMeaning.toLowerCase().contains(query);
            }).toList();

      // Silinmiş kelimeleri seçim listesinden çıkar
      final validWordIds = providerWords.map((w) => w.id).toSet();
      _selectedWordIds.removeWhere((id) => !validWordIds.contains(id));

      if (mounted) {
        setState(() {
          _allWords = sortedWords;
          _filteredWords = filtered;
          _isLoadingWords = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _avatarAnimationController.dispose();
    GlobalState.isMatching.removeListener(_updateMatchingState);
    GlobalState.matchmakingService.removeListener(_onMatchmakingUpdate);
    super.dispose();
  }

  // ... (Existing helper methods)
  // Re-declare _loadWords, _onMatchmakingUpdate... to keep context, but use ... range to skip unmodified methods if possible or include them
  // For safety, I will include _loadWords and others since they are in the range.

  Future<void> _loadWords() async {
    try {
      // Local-first: AppStateProvider'dan kelimeleri al (anında yüklenir)
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      final words = appState.allWords;

      // Eğer kelimeler henüz yüklenmediyse, yenilemeyi tetikle
      if (words.isEmpty) {
        await appState.refreshWords();
      }

      final sortedWords = List<Word>.from(appState.allWords);
      sortedWords.sort((a, b) => b.learnedDate.compareTo(a.learnedDate));

      if (mounted) {
        setState(() {
          _allWords = sortedWords;
          _filteredWords = sortedWords;
          _isLoadingWords = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading words: $e');
      if (mounted) setState(() => _isLoadingWords = false);
    }
  }

  void _onMatchmakingUpdate() {
    final service = GlobalState.matchmakingService;
    if (service.status == MatchStatus.matched && service.matchInfo != null) {
      GlobalState.isMatching.value = false;
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoCallPage(
              socket: service.socket!,
              roomId: service.matchInfo!.roomId,
              matchedUserId: service.matchInfo!.matchedUserId,
              currentUserId: service.userId!,
              role: service.matchInfo!.role,
            ),
          ),
        ).then((_) {
          service.leftCall();
        });
        service.setInCall();
      }
    } else if (service.status == MatchStatus.error) {
      GlobalState.isMatching.value = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(service.errorMessage ?? context.tr('common.error'))),
        );
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredWords = _allWords.where((w) {
        return w.englishWord.toLowerCase().contains(query) ||
            w.turkishMeaning.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _toggleWordSelection(int id) {
    setState(() {
      if (_selectedWordIds.contains(id)) {
        _selectedWordIds.remove(id);
      } else {
        _selectedWordIds.add(id);
      }
    });
  }

  Future<void> _showWordDetailsDialog(Word word) async {
    final selectedTheme = _currentTheme(listen: false);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ModernCard(
              variant: BackgroundVariant.primary,
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          word.englishWord,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    word.turkishMeaning,
                    style: TextStyle(
                        color: selectedTheme.colors.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(context.tr('practice.wordDetail.level'),
                            word.difficulty.toUpperCase()),
                        const Divider(color: Colors.white10, height: 16),
                        _buildDetailRow(
                            context.tr('practice.wordDetail.addedDate'),
                            word.learnedDate.toIso8601String().split('T')[0]),
                        if (word.notes != null && word.notes!.isNotEmpty) ...[
                          const Divider(color: Colors.white10, height: 16),
                          _buildDetailRow(
                              context.tr('practice.wordDetail.notes'),
                              word.notes!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: ModernCard(
                      variant: BackgroundVariant.accent,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      showGlow: true,
                      child: Center(
                        child: Text(context.tr('common.close'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);
    final appState = context.watch<AppStateProvider>();
    final isLoading = !appState.isInitialized;
    final isEntitlementLoading = appState.isLoadingAiEntitlement &&
        !hasAiEntitlementSnapshot(appState.userInfo);
    final locale = Localizations.maybeLocaleOf(context);
    if (!_firstSessionPracticeCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshFirstSessionPracticeState();
      });
    }
    final availableModes = _availableModesForLocale(
      locale,
      compact: !_firstSessionPracticeCompleted,
    );
    if (!availableModes.contains(_selectedMode)) {
      _selectedMode = availableModes.first;
    }

    if (isLoading || isEntitlementLoading) {
      return Scaffold(
        backgroundColor: selectedTheme.colors.background,
        body: Center(
          child: CircularProgressIndicator(color: selectedTheme.colors.accent),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  // Header with Info button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _mix(selectedTheme.colors.background,
                                    selectedTheme.colors.accent, 0.48)
                                .withOpacity(0.92),
                            _mix(selectedTheme.colors.background,
                                    selectedTheme.colors.primary, 0.48)
                                .withOpacity(0.92),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: selectedTheme.colors.accentGlow
                                .withOpacity(0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.school,
                                  color: Colors.white, size: 28),
                              const SizedBox(width: 12),
                              Text(
                                context.tr('practice.start'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () {
                              InfoDialog.show(
                                context,
                                title: context.tr('practice.modes.title'),
                                steps: [
                                  context.tr('practice.modes.desc'),
                                  context.tr('practice.modes.point.read'),
                                  context.tr('practice.modes.point.speaking'),
                                  context.tr('practice.modes.point.writing'),
                                  context
                                      .tr('practice.modes.point.consistency'),
                                ],
                              );
                            },
                            icon: const Icon(Icons.info_outline,
                                color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: _mix(
                                selectedTheme.colors.background,
                                Colors.white,
                                0.12,
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Top Tabs
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ModernCard(
                      borderRadius: BorderRadius.circular(16),
                      padding: const EdgeInsets.all(4),
                      variant: BackgroundVariant.secondary,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: availableModes
                              .map((mode) => _buildTopTab(mode))
                              .toList(),
                        ),
                      ),
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildContent(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedMode == _modeReading) {
      return _buildReadingTab();
    } else if (_selectedMode == _modeSpeaking) {
      return _buildSpeakingTab();
    } else if (_selectedMode == _modeWriting) {
      return _buildWritingTab();
    } else if (_selectedMode == _modeExams &&
        AppMarketConfig.isExamModuleEnabled(
            Localizations.maybeLocaleOf(context))) {
      return _buildExamsTab();
    } else if (_selectedMode == _modeWordGalaxy) {
      return _buildWordGalaxyTab();
    } else if (_selectedMode == _modeNeural) {
      return _buildNeuralGameTab();
    } else if (_selectedMode == _modeGrammar) {
      return const GrammarTab();
    } else {
      return _buildTranslationTab();
    }
  }

  Widget _buildReadingTab() {
    final selectedTheme = _currentTheme();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selectedTheme.colors.accent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.menu_book, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('practice.reading.title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  context.tr('practice.reading.subtitle'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 24),

        // Level Card
        ModernCard(
          showGlow: true,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('common.level'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('practice.reading.levelLabel'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
                    .map((l) => _buildReadingLevelChip(l))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('practice.reading.dailyInfo1'),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('practice.reading.dailyInfo2'),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Start Button
        ModernCard(
          width: double.infinity,
          variant: BackgroundVariant.accent,
          showGlow: true,
          borderRadius: BorderRadius.circular(16),
          padding: EdgeInsets.zero,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ReadingPracticePage(
                    level: _selectedLevel,
                  ),
                ),
              ).then((_) => _loadDailyCompletionBadges());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  context.tr('practice.reading.start'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildWritingTab() {
    final selectedTheme = _currentTheme();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selectedTheme.colors.accent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('practice.writing.title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  context.tr('practice.writing.subtitle'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 24),

        // Info Card - Glassmorphism
        ModernCard(
          showGlow: true,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selectedTheme.colors.accent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectedTheme.colors.accent.withOpacity(0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selectedTheme.colors.accentGlow.withOpacity(0.2),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(Icons.auto_awesome,
                    color: selectedTheme.colors.accent, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('practice.writing.card.title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('practice.writing.card.desc'),
                style: const TextStyle(
                  color: Colors.white70, // Slightly improved readability
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ModernCard(
                  variant: BackgroundVariant.accent,
                  showGlow: true,
                  borderRadius: BorderRadius.circular(16),
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WritingPracticePage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(context.tr('common.start'),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSpeakingTab() {
    final examModuleEnabled = AppMarketConfig.isExamModuleEnabled(
        Localizations.maybeLocaleOf(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: ModernCard(
            showGlow: true,
            borderRadius: BorderRadius.circular(20),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              context.tr('practice.speaking.title'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentTheme().colors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('practice.speaking.subtitle'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // MVP: Sohbet/Chat Card with matching disabled for v1.0
        // This section contains video matching and chat features
        // Will be enabled in future social features release
        /* 
          // 2. Sohbet (Chat) Card - DISABLED FOR MVP
          ModernCard(showGlow: true, borderRadius: BorderRadius.circular(20),
            child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               ...matching and chat code...
             ],
           ),
          ),
         */

        // const SizedBox(height: 20);

        // 3. AI Asistanları Animasyonlu Kart - PRO LOCKED
        _buildProLockedWidget(
          child: const AnimatedAIChatCard(),
          featureName: context.tr('practice.aiAssistants'),
        ),

        if (examModuleEnabled) ...[
          const SizedBox(height: 20),
          // 4. Kendini Sınavlara Hazırla Card - PRO LOCKED
          _buildProLockedWidget(
            featureName: 'IELTS & TOEFL',
            child: ModernCard(
              showGlow: true,
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mic_none_outlined,
                            color: Colors.white70, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('practice.examPrep.title'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17),
                          ),
                          Text(
                            context.tr('practice.examPrep.subtitle'),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ModernCard(
                      variant: BackgroundVariant.accent,
                      showGlow: true,
                      borderRadius: BorderRadius.circular(16),
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const ExamSelectionPage()),
                            );
                          },
                          icon: const Icon(Icons.menu_book_rounded,
                              size: 18, color: Colors.white),
                          label: Text(context.tr('practice.examPrep.button'),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildExamsTab() {
    final selectedTheme = _currentTheme();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selectedTheme.colors.accent.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selectedTheme.colors.accent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.school, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('practice.exams.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    context.tr('practice.exams.subtitle'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 24),
        ModernCard(
          showGlow: true,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('practice.exams.turkiye'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('practice.exams.desc'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ModernCard(
                width: double.infinity,
                variant: BackgroundVariant.accent,
                showGlow: true,
                borderRadius: BorderRadius.circular(16),
                padding: EdgeInsets.zero,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ExamSelectionPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    context.tr('practice.exams.go'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildTranslationTab() {
    final selectedTheme = _currentTheme();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header (Logo + Title)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selectedTheme.colors.accent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.translate, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('practice.translation.title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  context.tr('practice.translation.subtitle'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(child: _buildModeButton(_subModeSelect)),
            const SizedBox(width: 8),
            Expanded(child: _buildModeButton(_subModeManual)),
            const SizedBox(width: 8),
            Expanded(child: _buildModeButton(_subModeMixed)),
          ],
        ),

        const SizedBox(height: 24),

        // Banner (Owen)
        // Owen Banner Removed

        const SizedBox(height: 24),

        if (_selectedSubMode == _subModeManual) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: context.tr('practice.translation.manualHint'),
                hintStyle: const TextStyle(color: Colors.white54),
                border: InputBorder.none,
                prefixIcon:
                    const Icon(Icons.edit_outlined, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Level and Length
        LevelAndLengthSection(
          selectedLevel: _selectedLevel,
          selectedLength: _selectedLength,
          onLevelChanged: (val) => setState(() => _selectedLevel = val),
          onLengthChanged: (val) => setState(() => _selectedLength = val),
        ),

        // Word Selection Section (Only in 'Seç' mode)
        // Word Selection Section (Only in 'Seç' mode)
        if (_selectedSubMode == _subModeSelect) ...[
          const SizedBox(height: 24),
          ModernCard(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(20),
            variant: BackgroundVariant.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('practice.wordSelection'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('practice.wordSearch'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),

                // Search Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      icon: const Icon(Icons.search, color: Colors.white54),
                      hintText: context.tr('practice.wordSearchHint'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.tr('practice.wordList'),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                        '${_selectedWordIds.length} ${context.tr('practice.selected')}',
                        style: TextStyle(
                            color: selectedTheme.colors.accent,
                            fontWeight: FontWeight.bold)),
                  ],
                ),

                const SizedBox(height: 12),

                // Word List
                SizedBox(
                  height:
                      300, // Fixed height for scrollable list within the page
                  child: _isLoadingWords
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _filteredWords.length,
                          itemBuilder: (context, index) {
                            final word = _filteredWords[index];
                            final isSelected =
                                _selectedWordIds.contains(word.id);
                            final bool hasStar =
                                word.turkishMeaning.contains('★') ||
                                    word.turkishMeaning.contains('⭐');
                            final String displayMeaning = word.turkishMeaning
                                .replaceAll('★', '')
                                .replaceAll('⭐', '')
                                .trim();

                            return GestureDetector(
                              onTap: () => _toggleWordSelection(word.id),
                              child: ModernCard(
                                padding: const EdgeInsets.all(12),
                                borderRadius: BorderRadius.circular(16),
                                variant: isSelected
                                    ? BackgroundVariant.accent
                                    : BackgroundVariant.secondary,
                                showGlow: isSelected,
                                showBorder: isSelected,
                                child: Row(
                                  children: [
                                    // Checkbox circle
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? selectedTheme.colors.accent
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? selectedTheme.colors.accent
                                              : Colors.white54,
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check,
                                              size: 16, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (hasStar) ...[
                                                const Icon(Icons.star,
                                                    color: Color(0xFFFACC15),
                                                    size: 16), // Yellow
                                                const SizedBox(width: 4),
                                              ],
                                              Flexible(
                                                child: Text(
                                                  word.englishWord,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // Type Tag
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: selectedTheme
                                                      .colors.accent
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  context
                                                      .tr('practice.wordTag'),
                                                  style: TextStyle(
                                                    color: selectedTheme
                                                        .colors.accent,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            displayMeaning,
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    // Right side actions
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // Difficulty Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            word.difficulty.toUpperCase(),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Info Button
                                        GestureDetector(
                                          onTap: () =>
                                              _showWordDetailsDialog(word),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: selectedTheme.colors.accent
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: selectedTheme
                                                    .colors.accent
                                                    .withOpacity(0.3),
                                                width: 1,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.info_outline,
                                              color:
                                                  selectedTheme.colors.accent,
                                              size: 18,
                                            ),
                                          ),
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
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Start Button
        ModernCard(
          width: double.infinity,
          variant: BackgroundVariant.accent,
          showGlow: true,
          borderRadius: BorderRadius.circular(16),
          padding: EdgeInsets.zero,
          child: ElevatedButton(
            onPressed: () {
              // Seçili kelimeleri al
              final selectedWords = _allWords
                  .where((w) => _selectedWordIds.contains(w.id))
                  .toList();
              final firstWord =
                  selectedWords.isNotEmpty ? selectedWords.first : null;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TranslationPracticePage(
                    selectedWord: firstWord,
                    selectedLevels: [_selectedLevel],
                    selectedLengths: [_selectedLength],
                    subMode: _selectedSubMode,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  context.tr('common.start'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildTopTab(String text) {
    final isSelected = _selectedMode == text;
    return GestureDetector(
      onTap: () => _selectPracticeMode(text),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: ModernCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          borderRadius: BorderRadius.circular(12),
          variant: isSelected
              ? BackgroundVariant.accent
              : BackgroundVariant.secondary,
          showGlow: isSelected,
          child: Center(
            child: Text(
              _modeLabel(text),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(String text) {
    final isSelected = _selectedSubMode == text;
    return GestureDetector(
      onTap: () => setState(() => _selectedSubMode = text),
      child: ModernCard(
        padding: const EdgeInsets.symmetric(vertical: 16),
        borderRadius: BorderRadius.circular(16),
        variant:
            isSelected ? BackgroundVariant.accent : BackgroundVariant.secondary,
        showGlow: isSelected,
        child: Center(
          child: Text(
            _subModeLabel(text),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingLevelChip(String level) {
    final isCompleted = _readingCompletedLevels[level] == true;
    return Stack(
      children: [
        _buildLevelChip(level),
        if (isCompleted)
          Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.check_circle,
              color: _currentTheme().colors.accent,
              size: 14,
            ),
          ),
      ],
    );
  }

  Widget _buildLevelChip(String level) {
    final isSelected = _selectedLevel == level;
    return GestureDetector(
      onTap: () => setState(() => _selectedLevel = level),
      child: ModernCard(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12),
        borderRadius: BorderRadius.circular(12),
        variant:
            isSelected ? BackgroundVariant.accent : BackgroundVariant.secondary,
        showGlow: isSelected,
        child: Center(
          child: Text(
            level,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildWordGalaxyTab() {
    final selectedTheme = _currentTheme();
    final isTurkish = Localizations.localeOf(context).languageCode == 'tr';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModernCard(
          variant: BackgroundVariant.primary,
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      selectedTheme.colors.primary,
                      selectedTheme.colors.accent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_mosaic_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTurkish ? 'Kelime Evreni' : 'Word Galaxy',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTurkish
                          ? 'Kelimeleri ag seklinde gor, cumlelerini incele ve yeni cumleler ekle.'
                          : 'Explore your words as a network, review their sentences, and add new ones.',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ModernCard(
          variant: BackgroundVariant.secondary,
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WordGalaxyInfoRow(
                icon: Icons.hub_outlined,
                value: isTurkish
                    ? 'Kelimeler odak node etrafinda katmanli dizilir.'
                    : 'Words are arranged in layered rings around the focus node.',
              ),
              const SizedBox(height: 8),
              _WordGalaxyInfoRow(
                icon: Icons.notes_rounded,
                value: isTurkish
                    ? 'Kartlara dokunup mevcut cumleleri gor ve yeni cumle ekle.'
                    : 'Tap cards to review existing sentences and add new ones.',
              ),
              const SizedBox(height: 8),
              _WordGalaxyInfoRow(
                icon: Icons.wallpaper_rounded,
                value: isTurkish
                    ? 'Galaksi, kara delik ve samanyolu arkaplanlari arasindan sec.'
                    : 'Pick between galaxy, black hole, and milky way backgrounds.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ModernCard(
          width: double.infinity,
          variant: BackgroundVariant.accent,
          showGlow: true,
          borderRadius: BorderRadius.circular(16),
          padding: EdgeInsets.zero,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WordGalaxyPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isTurkish ? 'Kelime Evrenini Ac' : 'Open Word Galaxy',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildNeuralGameTab() {
    final selectedTheme = _currentTheme();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).height < 720;
        final iconSize = compact ? 42.0 : 48.0;
        final titleSize = compact ? 17.0 : 19.0;
        final bodySize = compact ? 11.0 : 12.0;

        return ModernCard(
          variant: BackgroundVariant.primary,
          borderRadius: BorderRadius.circular(18),
          padding: EdgeInsets.all(compact ? 14 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          selectedTheme.colors.primary,
                          selectedTheme.colors.accent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              selectedTheme.colors.accentGlow.withOpacity(0.22),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(Icons.hub_rounded,
                        color: Colors.white, size: compact ? 21 : 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('practice.neural.title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: titleSize,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr('practice.neural.desc'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: bodySize,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 12),
              Row(
                children: [
                  Expanded(
                    child: _NeuralCompactInfoTile(
                      icon: Icons.timer_outlined,
                      title: context.tr('practice.neural.info.time'),
                      value: context.tr('practice.neural.info.timeValue'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeuralCompactInfoTile(
                      icon: Icons.bolt_outlined,
                      title: context.tr('practice.neural.info.score'),
                      value: context.tr('practice.neural.info.scoreValue'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeuralCompactInfoTile(
                      icon: Icons.auto_awesome_outlined,
                      title: context.tr('practice.neural.info.goal'),
                      value: context.tr('practice.neural.info.goalValue'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 12),
              Container(
                decoration: BoxDecoration(
                  gradient: selectedTheme.colors.buttonGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  height: compact ? 42 : 46,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NeuralGamePage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          context.tr('practice.neural.start'),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: compact ? 14 : 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: compact ? 18 : 20),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
            ],
          ),
        );
      },
    );
  }

  /// Widget that shows PRO lock overlay for non-subscribers
  Widget _buildProLockedWidget(
      {required Widget child, required String featureName}) {
    return child;
  }
}

class _WordGalaxyInfoRow extends StatelessWidget {
  final IconData icon;
  final String value;

  const _WordGalaxyInfoRow({
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider?>(context, listen: true);
    } catch (_) {
      themeProvider = null;
    }
    final selectedTheme =
        themeProvider?.currentTheme ?? VocabThemes.defaultTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: selectedTheme.colors.accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _NeuralCompactInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _NeuralCompactInfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider?>(context, listen: true);
    } catch (_) {
      themeProvider = null;
    }
    final selectedTheme =
        themeProvider?.currentTheme ?? VocabThemes.defaultTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedTheme.colors.accent.withOpacity(0.18),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: selectedTheme.colors.accent, size: 15),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
