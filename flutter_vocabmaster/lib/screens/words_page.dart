import 'package:flutter/material.dart';
import 'dart:ui';
import '../widgets/animated_background.dart';
import '../models/word.dart';
import '../services/offline_sync_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../widgets/info_dialog.dart';
import '../services/global_state.dart';
import '../widgets/neon_button.dart';
import '../widgets/word_sentences_modal.dart';
import '../widgets/add_sentence_modal.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';

class WordsPage extends StatefulWidget {
  const WordsPage({Key? key}) : super(key: key);

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
  bool _isOnline = true;

  final List<String> _weekDays = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz'
  ];

  // Form Controllers
  final TextEditingController _englishWordController = TextEditingController();
  final TextEditingController _turkishMeaningController =
      TextEditingController();
  String _selectedDifficulty = 'Kolay';
  bool _isAddingWord = false;

  @override
  void initState() {
    super.initState();
    _isOnline = _offlineSyncService.isOnline;
    _loadDatesWithWords();
    _loadWordsForDate(_selectedDate);

    // Online durumu dinle
    _offlineSyncService.onlineStatus.listen((isOnline) {
      if (mounted) {
        setState(() => _isOnline = isOnline);
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
        const SnackBar(content: Text('Lütfen tüm alanları doldurun')),
      );
      return;
    }

    setState(() => _isLoading =
        true); // _isAddingWord yerine _isLoading kullanalım veya _isAddingWord

    try {
      String difficulty = 'easy';
      if (_selectedDifficulty == 'Orta') difficulty = 'medium';
      if (_selectedDifficulty == 'Zor') difficulty = 'hard';

      final appState = context.read<AppStateProvider>();

      // AppStateProvider ile kelime ekle - XP ve Stats otomatik güncellenir
      await appState.addWord(
        english: english,
        turkish: turkish,
        addedDate: _selectedDate,
        difficulty: difficulty,
        source: 'manual', // Manuel ekleme XP türü
      );

      // Formu temizle
      _englishWordController.clear();
      _turkishMeaningController.clear();
      setState(() => _selectedDifficulty = 'Kolay');

      // Yerel listeyi yenile (AppStateProvider global listeyi güncelledi ama bu sayfa tarihe göre filtreliyor)
      await _loadWordsForDate(_selectedDate);
      await _loadDatesWithWords();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kelime başarıyla eklendi! (+10 XP)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
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
                      const Text(
                        'Kelime Takviminiz',
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
                            title: 'Kelimeler Sayfası',
                            steps: [
                              'Takvimden gün seçip o tarihte öğrendiğiniz kelimeleri inceleyin.',
                              'Mor işaretli günler, kelime çalışması yaptığınız aktif günleri gösterir.',
                              'Geçmiş veya gelecek tarihleri seçerek yeni kelimeler ekleyebilirsiniz.',
                              'Her kelime için zorluk seviyesi (Kolay, Orta, Zor) belirleyerek süreci yönetin.',
                              'Eklediğiniz kelimelere örnek cümleler ekleyerek kalıcılığı artırın.',
                            ],
                          );
                        },
                        icon: Icon(Icons.info_outline,
                            color: Colors.white.withOpacity(0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

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
                          children: _weekDays
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
                  const Text(
                    'Yeni Kelime Ekle',
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
                    '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} - Öğrenilen Kelimeler',
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
                        color: const Color(0xFF1e3a8a).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.history_edu,
                                color: Colors.blue, size: 32),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Henüz kelime yok',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Yukarıdaki formu kullanarak bu güne yeni bir kelime ekleyin.',
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

  Widget _buildCalendarGrid() {
    final daysInMonth =
        DateUtils.getDaysInMonth(_selectedDate.year, _selectedDate.month);
    final firstDayOfMonth =
        DateTime(_selectedDate.year, _selectedDate.month, 1);
    final weekdayOffset = firstDayOfMonth.weekday - 1; // 0 for Mon

    // Total cells = offset + days.
    final totalCells = 35; // Fixed 5 rows for aesthetics or 42 for 6 rows

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
                  ? const Color(0xFF06b6d4) // Cyan for selected
                  : (hasWords
                      ? const Color(0xFF3b82f6).withOpacity(0.6)
                      : Colors.white.withOpacity(0.1)),
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: const Color(0xFF06b6d4), width: 2)
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
                      color: const Color(0xFF0f172a).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: const Color(0xFF06b6d4).withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF06b6d4).withOpacity(0.1),
                            blurRadius: 20),
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
                        const Text(
                          'Kelimeyi Sil',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bu kelimeyi silmek istediğinize emin misiniz? Buna bağlı tüm cümleler de kalıcı olarak silinecektir.',
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
                                child: const Text('İptal',
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
                                        context.read<AppStateProvider>();
                                    final deleted =
                                        await appState.deleteWord(word.id);

                                    if (mounted) {
                                      if (deleted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Kelime ve cümleleri silindi!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Kelime silinemedi, lütfen tekrar deneyin.'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
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
                                child: const Text('Sil'),
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
    String difficultyText = 'Orta';
    if (word.difficulty == 'easy') {
      difficultyColor = Colors.green;
      difficultyText = 'Kolay';
    } else if (word.difficulty == 'hard') {
      difficultyColor = Colors.red;
      difficultyText = 'Zor';
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
                    word.turkishMeaning.replaceAll('⭐', '').trim(),
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
                          label: 'Cümleler',
                          icon: Icons.article_outlined,
                          isCyan: true,
                          onTap: () => _showSentencesDialog(word),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NeonButton(
                          label: 'Cümle Ekle',
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF06b6d4).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF06b6d4).withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.volume_up, size: 14, color: Color(0xFF06b6d4)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF06b6d4),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)], // Cyan to Blue
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildDifficultyDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: 'Kolay',
          isExpanded: true,
          dropdownColor: const Color(0xFF1e1b4b),
          style: const TextStyle(color: Colors.white),
          items: ['Kolay', 'Orta', 'Zor'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (_) {},
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      '',
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
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

  Widget _buildUnilabeledDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
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
            context.read<AppStateProvider>().refreshWords();
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
          _buildTextField(_englishWordController, 'İngilizce Kelime'),
          const SizedBox(height: 12),
          _buildTextField(_turkishMeaningController, 'Türkçe Anlamı'),
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Kelime Ekle',
                            style: TextStyle(
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
          borderSide: const BorderSide(color: Color(0xFF06b6d4)),
        ),
      ),
    );
  }

  Widget _buildFormDifficultyDropdown() {
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
          dropdownColor: const Color(0xFF1e1b4b),
          style: const TextStyle(color: Colors.white),
          items: ['Kolay', 'Orta', 'Zor'].map((String value) {
            Color itemColor = Colors.white;
            if (value == 'Kolay') itemColor = Colors.green;
            if (value == 'Orta') itemColor = Colors.amber;
            if (value == 'Zor') itemColor = Colors.red;

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
                  Text(value),
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
