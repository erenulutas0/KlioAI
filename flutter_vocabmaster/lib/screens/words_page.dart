import 'package:flutter/material.dart';
import 'dart:ui';
import '../widgets/animated_background.dart';
import '../models/word.dart';
import '../services/offline_sync_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../widgets/info_dialog.dart';
import '../widgets/neon_button.dart';
import '../widgets/word_sentences_modal.dart';
import '../widgets/add_sentence_modal.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../services/locale_text_service.dart';
import 'review_mode_selector_page.dart';
import 'word_galaxy_page.dart';

class WordsPage extends StatefulWidget {
  const WordsPage({super.key});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  final OfflineSyncService _offlineSyncService = OfflineSyncService();
  final FlutterTts _flutterTts = FlutterTts();
  DateTime _selectedDate = DateTime.now();
  List<Word> _wordsForSelectedDate = [];
  Set<String> _datesWithWords = {}; // Dates that have words (YYYY-MM-DD format)
  bool _isLoading = false;

  // Form Controllers
  final TextEditingController _englishWordController = TextEditingController();
  final TextEditingController _turkishMeaningController =
      TextEditingController();
  String _selectedDifficulty = 'easy';
  final bool _isAddingWord = false;

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

  bool get _isTurkish => LocaleTextService.isTurkish;

  String _text(String tr, String en) => _isTurkish ? tr : en;

  List<String> get _localizedWeekDays => _isTurkish
      ? const ['Pzt', 'Sal', 'Car', 'Per', 'Cum', 'Cmt', 'Paz']
      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return _text('Kolay', 'Easy');
      case 'hard':
        return _text('Zor', 'Hard');
      default:
        return _text('Orta', 'Medium');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDatesWithWords();
    _loadWordsForDate(_selectedDate);

    // Online durumu dinle
    _offlineSyncService.onlineStatus.listen((isOnline) {
      if (mounted) {
        if (isOnline) {
          // Online olunca yenile
          _loadDatesWithWords();
          _loadWordsForDate(_selectedDate);
        }
      }
    });
  }

  Future<void> _loadDatesWithWords() async {
    // AppStateProvider otomatik yönetiyor
  }

  Future<void> _loadWordsForDate(DateTime date) async {
    // AppStateProvider otomatik yönetiyor
  }

  void _onDaySelected(int day) {
    if (day < 1) return;
    // Use the currently displayed month/year from _selectedDate
    final newDate = DateTime(_selectedDate.year, _selectedDate.month, day);

    setState(() => _selectedDate = newDate);
    _loadWordsForDate(newDate);
  }

  Future<void> _speak(String text, String languageCode) async {
    await _flutterTts.setLanguage(languageCode);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(text);
  }

  Future<void> _addNewWord() async {
    final english = _englishWordController.text.trim();
    final turkish = _turkishMeaningController.text.trim();

    if (english.isEmpty || turkish.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('Lütfen tüm alanları doldurun', 'Please fill in all fields.'),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final appState = context.read<AppStateProvider>();
      await appState.addWord(
        english: english,
        turkish: turkish,
        addedDate: _selectedDate,
        difficulty: _selectedDifficulty,
        source: 'manual',
      );

      _englishWordController.clear();
      _turkishMeaningController.clear();
      setState(() => _selectedDifficulty = 'easy');

      await _loadWordsForDate(_selectedDate);
      await _loadDatesWithWords();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                'Kelime başarıyla eklendi! (+10 XP)',
                'Word added successfully! (+10 XP)',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('Hata oluştu: $e', 'Something went wrong: $e'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedDate =
          DateTime(_selectedDate.year, _selectedDate.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);
    // AppStateProvider entegrasyonu (Anlık güncelleme)
    final appState = context.watch<AppStateProvider>();
    final allWords = appState.allWords;

    // Tarihleri güncelle
    _datesWithWords = allWords
        .map((w) => w.learnedDate.toIso8601String().split('T')[0])
        .toSet();

    // Seçili tarihe göre kelimeleri filtrele
    final selectedDateStr = _selectedDate.toIso8601String().split('T')[0];
    _wordsForSelectedDate = allWords.where((w) {
      final wDate = w.learnedDate.toIso8601String().split('T')[0];
      return wDate == selectedDateStr;
    }).toList();

    // Sıralama (Tarihe göre - en yeni en üstte)
    // Not: ID'ye göre sıralama offline kelimelerde (negatif ID) sorun çıkarıyordu
    _wordsForSelectedDate
        .sort((a, b) => b.learnedDate.compareTo(a.learnedDate));

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _text('Kelime Takviminiz', 'Your Word Calendar'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          InfoDialog.show(
                            context,
                            title: _text('Kelimeler Sayfası', 'Words Page'),
                            steps: [
                              _text(
                                'Takvimden gun secip o tarihte ogrendiginiz kelimeleri inceleyin.',
                                'Pick a day on the calendar to review the words learned on that date.',
                              ),
                              _text(
                                'Isaretli gunler, kelime calismasi yaptiginiz aktif gunleri gosterir.',
                                'Marked days show when you practiced vocabulary.',
                              ),
                              _text(
                                'Gecmis veya gelecek tarihleri secerek yeni kelimeler ekleyebilirsiniz.',
                                'You can select past or future dates and add new words.',
                              ),
                              _text(
                                'Her kelime icin zorluk seviyesi belirleyerek sureci yonetin.',
                                'Set a difficulty level for each word to manage review flow.',
                              ),
                              _text(
                                'Eklediginiz kelimelere ornek cumleler ekleyerek kaliciligi artirin.',
                                'Add example sentences to make each word easier to retain.',
                              ),
                            ],
                          );
                        },
                        icon: Icon(Icons.info_outline,
                            color: Colors.white.withOpacity(0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildWordPracticeActions(allWords.length),
                  const SizedBox(height: 20),

                  // Calendar Card
                  ModernCard(
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(24),
                    variant: BackgroundVariant.primary,
                    child: Column(
                      children: [
                        // Month Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left,
                                    color: Colors.white.withOpacity(0.7)),
                                onPressed: () => _changeMonth(-1),
                              ),
                              Text(
                                '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right,
                                    color: Colors.white.withOpacity(0.7)),
                                onPressed: () => _changeMonth(1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Days Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: _localizedWeekDays
                              .map((day) => Text(
                                    day,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 14,
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),

                        // Days Grid
                        // A simple grid for specific month structure (e.g. Jan 2026 starts on Thursday)
                        // For dynamic: calculate start offset.
                        _buildCalendarGrid(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Add New Word Form Header
                  Text(
                    _text('Yeni Kelime Ekle', 'Add New Word'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Add New Word Form
                  _buildAddNewWordForm(),

                  const SizedBox(height: 32),

                  // Learned Words List Header
                  Text(
                    _text(
                      '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} - Ogrenilen Kelimeler',
                      '${_getMonthName(_selectedDate.month)} ${_selectedDate.day} - Learned Words',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // List
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_wordsForSelectedDate.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: selectedTheme.colors.cardBackground
                            .withOpacity(0.62),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: selectedTheme.colors.glassBorder
                              .withOpacity(0.72),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color:
                                  selectedTheme.colors.accent.withOpacity(0.20),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.history_edu,
                              color: selectedTheme.colors.accent,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _text('Henuz kelime yok', 'No words yet'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _text(
                                'Yukaridaki formu kullanarak bu gune yeni bir kelime ekleyin.',
                                'Use the form above to add a new word to this day.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: _wordsForSelectedDate
                          .map((word) => _buildWordCard(word))
                          .toList(),
                    ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordPracticeActions(int wordCount) {
    final selectedTheme = _currentTheme(listen: true);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _mix(selectedTheme.colors.background, selectedTheme.colors.accent,
                    0.16)
                .withOpacity(0.78),
            _mix(selectedTheme.colors.background, selectedTheme.colors.primary,
                    0.14)
                .withOpacity(0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.68),
        ),
        boxShadow: [
          BoxShadow(
            color: selectedTheme.colors.accentGlow.withOpacity(0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selectedTheme.colors.accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selectedTheme.colors.accent.withOpacity(0.34),
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: selectedTheme.colors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('Tekrar', 'Review'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _text(
                        '$wordCount kelimeyi toplu olarak klasik veya neural modda tekrar et.',
                        'Review $wordCount words in classic or neural mode.',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selectedTheme.colors.textSecondary
                            .withOpacity(0.92),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildPracticeActionButton(
                  selectedTheme: selectedTheme,
                  label: _text('Klasik Tekrar', 'Classic Review'),
                  icon: Icons.replay_rounded,
                  filled: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReviewModeSelectorPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPracticeActionButton(
                  selectedTheme: selectedTheme,
                  label: _text('Neural Tekrar', 'Neural Review'),
                  icon: Icons.hub_rounded,
                  filled: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WordGalaxyPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeActionButton({
    required AppThemeConfig selectedTheme,
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: filled ? selectedTheme.colors.buttonGradient : null,
          color: filled ? null : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled
                ? Colors.white.withOpacity(0.18)
                : selectedTheme.colors.accent.withOpacity(0.36),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final selectedTheme = _currentTheme();
    final daysInMonth =
        DateUtils.getDaysInMonth(_selectedDate.year, _selectedDate.month);
    final firstDayOfMonth =
        DateTime(_selectedDate.year, _selectedDate.month, 1);
    final weekdayOffset = firstDayOfMonth.weekday - 1; // 0 for Mon

    List<Widget> dayWidgets = [];

    // Empty slots
    for (int i = 0; i < weekdayOffset; i++) {
      dayWidgets.add(const SizedBox());
    }

    for (int i = 1; i <= daysInMonth; i++) {
      final isSelected = i == _selectedDate.day &&
          _selectedDate.month == DateTime.now().month &&
          _selectedDate.year == DateTime.now().year;

      // Check if this date has words learned
      final dateStr = DateTime(_selectedDate.year, _selectedDate.month, i)
          .toIso8601String()
          .split('T')[0];
      final hasWords = _datesWithWords.contains(dateStr);

      dayWidgets.add(
        GestureDetector(
          onTap: () => _onDaySelected(i),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? selectedTheme.colors.accent
                  : (hasWords
                      ? selectedTheme.colors.primary.withOpacity(0.55)
                      : Colors.white.withOpacity(0.1)),
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: selectedTheme.colors.accent, width: 2)
                  : null,
            ),
            child: Center(
              child: Text(
                '$i',
                style: TextStyle(
                  color: Colors.white
                      .withOpacity(isSelected || hasWords ? 1.0 : 0.6),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Fill remaining
    while (dayWidgets.length < 35) {
      dayWidgets.add(const SizedBox());
    }

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 7,
      physics: const NeverScrollableScrollPhysics(),
      children: dayWidgets,
    );
  }

  void _showDeleteWordConfirmDialog(Word word) {
    final selectedTheme = _currentTheme(listen: false);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) => const SizedBox(),
      transitionBuilder: (context, anim, __, child) {
        return Transform.scale(
          scale: anim.value,
          child: Opacity(
            opacity: anim.value,
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: selectedTheme.colors.background.withOpacity(0.90),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color:
                            selectedTheme.colors.glassBorder.withOpacity(0.70),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              selectedTheme.colors.accentGlow.withOpacity(0.30),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.delete_forever,
                              color: Colors.redAccent, size: 32),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _text('Kelimeyi Sil', 'Delete Word'),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _text(
                              'Bu kelimeyi silmek istediğinize emin misiniz? Buna bağlı tüm cümleler de kalıcı olarak silinecektir.',
                              'Are you sure you want to delete this word? All related sentences will also be deleted permanently.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(_text('İptal', 'Cancel'),
                                    style: TextStyle(color: Colors.white60)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  try {
                                    // 🔥 AppStateProvider üzerinden sil (UI anında güncellenir)
                                    final appState =
                                        this.context.read<AppStateProvider>();
                                    final deleted =
                                        await appState.deleteWord(word.id);

                                    if (mounted) {
                                      if (deleted) {
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(_text(
                                                'Kelime ve cumleleri silindi!',
                                                'Word and related sentences were deleted.')),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(_text(
                                                'Kelime silinemedi, lutfen tekrar deneyin.',
                                                'Word could not be deleted. Please try again.')),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(SnackBar(
                                              content: Text('Hata: $e'),
                                              backgroundColor: Colors.red));
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(_text('Sil', 'Delete')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWordCard(Word word) {
    Color difficultyColor = Colors.amber;
    String difficultyText = _difficultyLabel('medium');
    if (word.difficulty == 'easy') {
      difficultyColor = Colors.green;
      difficultyText = _difficultyLabel('easy');
    } else if (word.difficulty == 'hard') {
      difficultyColor = Colors.red;
      difficultyText = _difficultyLabel('hard');
    }

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white60),
                onPressed: () => _showDeleteWordConfirmDialog(word),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: difficultyColor,
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Text(
                  difficultyText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (word.turkishMeaning.startsWith('⭐'))
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child:
                              Icon(Icons.star, color: Colors.amber, size: 24),
                        ),
                      Expanded(
                        child: Text(
                          word.englishWord,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Wrap buttons in a Row to keep them together
                      Row(
                        children: [
                          _buildSmallSpeakButton(
                              'US', () => _speak(word.englishWord, 'en-US')),
                          const SizedBox(width: 8),
                          _buildSmallSpeakButton(
                              'UK', () => _speak(word.englishWord, 'en-GB')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    word.turkishMeaning.replaceAll('?', '').trim(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: NeonButton(
                          label: _text('Cumleler', 'Sentences'),
                          icon: Icons.article_outlined,
                          isCyan: true,
                          onTap: () => _showSentencesDialog(word),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NeonButton(
                          label: _text('Cumle Ekle', 'Add Sentence'),
                          icon: Icons.add,
                          isCyan: false,
                          onTap: () => _showAddSentenceDialog(word),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallSpeakButton(String label, VoidCallback onTap) {
    final selectedTheme = _currentTheme();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selectedTheme.colors.accent.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selectedTheme.colors.accent.withOpacity(0.36),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_up, size: 14, color: selectedTheme.colors.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selectedTheme.colors.accent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    final months = _isTurkish
        ? const [
            '',
            'Ocak',
            'Subat',
            'Mart',
            'Nisan',
            'Mayis',
            'Haziran',
            'Temmuz',
            'Agustos',
            'Eylul',
            'Ekim',
            'Kasim',
            'Aralik'
          ]
        : const [
            '',
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December'
          ];
    if (month < 1 || month > 12) return '';
    return months[month];
  }

  void _showSentencesDialog(Word word) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WordSentencesModal(word: word),
    );
  }

  void _showAddSentenceDialog(Word word) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddSentenceModal(
        word: word,
        onSentencesAdded: () async {
          await _loadWordsForDate(_selectedDate);
          // Global listeyi de yenile
          if (mounted) {
            this.context.read<AppStateProvider>().refreshWords();
          }
        },
      ),
    );
  }

  Widget _buildAddNewWordForm() {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            _englishWordController,
            _text('Ingilizce Kelime', 'English Word'),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _turkishMeaningController,
            _text('Ceviri / Anlam', 'Translation / Meaning'),
          ),
          const SizedBox(height: 12),
          _buildFormDifficultyDropdown(),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _isAddingWord ? null : _addNewWord,
            child: ModernCard(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              borderRadius: BorderRadius.circular(16),
              variant: BackgroundVariant.secondary,
              showBorder: false,
              child: Center(
                child: _isAddingWord
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            _text('Kelime Ekle', 'Add Word'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    final selectedTheme = _currentTheme();
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: selectedTheme.colors.accent),
        ),
      ),
    );
  }

  Widget _buildFormDifficultyDropdown() {
    final selectedTheme = _currentTheme();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedDifficulty,
          isExpanded: true,
          dropdownColor:
              _mix(selectedTheme.colors.background, Colors.black, 0.20),
          style: const TextStyle(color: Colors.white),
          items: ['easy', 'medium', 'hard'].map((String value) {
            Color itemColor = Colors.white;
            if (value == 'easy') itemColor = Colors.green;
            if (value == 'medium') itemColor = Colors.amber;
            if (value == 'hard') itemColor = Colors.red;

            return DropdownMenuItem<String>(
              value: value,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: itemColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(_difficultyLabel(value)),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedDifficulty = value);
            }
          },
        ),
      ),
    );
  }
}
