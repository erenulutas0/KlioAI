import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/bottom_nav.dart';
import '../services/groq_service.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/ai_paywall_handler.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../services/locale_text_service.dart';
import '../providers/app_state_provider.dart';

class QuickDictionaryPage extends StatefulWidget {
  const QuickDictionaryPage({super.key});

  @override
  State<QuickDictionaryPage> createState() => _QuickDictionaryPageState();
}

class _QuickDictionaryPageState extends State<QuickDictionaryPage> {
  bool get _isTurkish => LocaleTextService.isTurkish;
  String _text(String tr, String en) => _isTurkish ? tr : en;
  final TextEditingController _searchController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  // ApiService kaldırıldı - AppStateProvider kullanılıyor

  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;

  // Arama sonucu
  String _searchedWord = '';
  String _phonetic = '';
  List<WordMeaning> _meanings = [];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _searchWord() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _errorMessage = null;
      _meanings = [];
    });

    try {
      final result = await GroqService.lookupWordDetailed(query);

      if (mounted) {
        setState(() {
          _searchedWord = result['word'] ?? query;
          _phonetic = result['phonetic'] ?? '';

          final meaningsData = result['meanings'] as List? ?? [];
          _meanings = meaningsData
              .map((m) => WordMeaning(
                    type: m['type'] ?? 'n',
                    turkishMeaning: m['turkishMeaning'] ?? '',
                    englishDefinition: m['englishDefinition'] ?? '',
                    example: m['example'] ?? '',
                    exampleTranslation: m['exampleTranslation'] ?? '',
                  ))
              .toList();

          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
          setState(() {
            _errorMessage = AiErrorMessageFormatter.forError(e);
            _isSearching = false;
          });
          return;
        }
        final msg = e is ApiQuotaExceededException
            ? AiErrorMessageFormatter.forQuota(e)
            : 'Arama başarısız: $e';
        setState(() {
          _errorMessage = msg;
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  void _showWordInContextDialog(String word, String sentence) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF0f172a),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '"$word"',
              style: const TextStyle(
                color: Color(0xFF06b6d4),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _text('Ne yapmak istiyorsunuz?', 'What would you like to do?'),
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildOptionButton(
                    icon: Icons.search,
                    label: _text('Arat', 'Search'),
                    color: const Color(0xFF8b5cf6),
                    onTap: () {
                      Navigator.pop(context);
                      _searchController.text = word;
                      // Sadece arama kutusuna yaz, aramayı başlatma
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOptionButton(
                    icon: Icons.visibility,
                    label: _text('Direkt Gor', 'View Now'),
                    color: const Color(0xFF06b6d4),
                    onTap: () {
                      Navigator.pop(context);
                      _showWordMeaningInContext(word, sentence);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWordMeaningInContext(String word, String sentence) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF06b6d4)),
      ),
    );

    try {
      final meaning = await GroqService.explainWordInSentence(word, sentence);

      if (mounted) {
        Navigator.pop(context); // Loading dialog'u kapat

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1e293b),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06b6d4).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lightbulb,
                      color: Color(0xFF06b6d4), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  '"$word"',
                  style:
                      const TextStyle(color: Color(0xFF06b6d4), fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('Bu cumledeki anlami:', 'Meaning in this sentence:'),
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  meaning,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, height: 1.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_text('Tamam', 'OK'),
                    style: const TextStyle(color: Color(0xFF06b6d4))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : 'Hata: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddToTodayDialog(WordMeaning meaning) {
    String selectedDifficulty = 'medium';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Color(0xFF10b981)),
              SizedBox(width: 12),
              Text(_text('Kelimeyi Gune Ekle', 'Add Word to Today'),
                  style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF06b6d4).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _searchedWord,
                      style: const TextStyle(
                          color: Color(0xFF06b6d4),
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '(${meaning.type}) ${meaning.turkishMeaning}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _text('Zorluk Seviyesi:', 'Difficulty Level:'),
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildDifficultyChip(_text('Kolay', 'Easy'), 'easy', selectedDifficulty,
                      const Color(0xFF10b981), (val) {
                    setDialogState(() => selectedDifficulty = val);
                  }),
                  const SizedBox(width: 8),
                  _buildDifficultyChip(_text('Orta', 'Medium'), 'medium', selectedDifficulty,
                      const Color(0xFFf59e0b), (val) {
                    setDialogState(() => selectedDifficulty = val);
                  }),
                  const SizedBox(width: 8),
                  _buildDifficultyChip(_text('Zor', 'Hard'), 'hard', selectedDifficulty,
                      const Color(0xFFef4444), (val) {
                    setDialogState(() => selectedDifficulty = val);
                  }),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('İptal', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _addWordToToday(meaning, selectedDifficulty);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10b981),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyChip(String label, String value, String selected,
      Color color, Function(String) onSelect) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : Colors.transparent),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addWordToToday(WordMeaning meaning, String difficulty) async {
    try {
      final appState = context.read<AppStateProvider>();
      final addedDate = DateTime.now();

      // AppStateProvider üzerinden ekle - otomatik XP ve stats güncellenir
      // source: 'quick_dictionary' ile Hızlı Sözlük XP'si verilir (+10 XP)
      final word = await appState.addWord(
        english: _searchedWord,
        turkish: '(${meaning.type}) ${meaning.turkishMeaning}',
        addedDate: addedDate,
        difficulty: difficulty,
        source: 'quick_dictionary', // Hızlı Sözlük XP türü
      );

      // Eğer örnek cümle varsa onu da ekle (ve +5 XP daha kazan)
      if (word != null && meaning.example.isNotEmpty) {
        await appState.addSentenceToWord(
          wordId: word.id,
          sentence: meaning.example,
          translation: meaning.exampleTranslation,
          difficulty: difficulty,
        );
      }

      if (mounted) {
        String message = '✅ Kelime başarıyla eklendi! (+10 XP)';
        if (meaning.example.isNotEmpty) {
          message = '✅ Kelime ve cümle başarıyla eklendi! (+15 XP)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFF10b981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Hızlı Sözlük',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search Box
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (_) => _searchWord(),
                        decoration: InputDecoration(
                          hintText: _text(
                            'Ingilizce kelime yazin (orn: bring about)',
                            'Type an English word (e.g. bring about)',
                          ),
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.5)),
                          filled: true,
                          fillColor: const Color(0xFF1e3a8a).withOpacity(0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                                color: Color(0xFF06b6d4), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _isSearching ? null : _searchWord,
                        child: ModernCard(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          borderRadius: BorderRadius.circular(16),
                          variant: BackgroundVariant.secondary,
                          showBorder: false,
                          child: Center(
                            child: _isSearching
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Ara',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Content
                Expanded(
                  child:
                      _hasSearched ? _buildSearchResults() : _buildEmptyState(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // MVP: GlobalMatchmakingSheet disabled for v1.0
          // const GlobalMatchmakingSheet(),
          BottomNav(
            currentIndex: 2,
            onTap: (index) {
              if (index != 2) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.menu_book,
                size: 80,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _text('Kelime Ara', 'Search Word'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _text(
                'Ingilizce kelime veya deyim girebilirsiniz',
                'You can enter an English word or expression',
              ),
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF06b6d4)),
            SizedBox(height: 16),
            Text('AI sözlük aranıyor...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_meanings.isEmpty) {
      return Center(
        child: Text(
          _text('Sonuc bulunamadi', 'No result found'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Word Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1e3a8a).withOpacity(0.6),
                  const Color(0xFF0f172a).withOpacity(0.8)
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: const Color(0xFF06b6d4).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _searchedWord,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_phonetic.isNotEmpty)
                        Text(
                          _phonetic,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _speak(_searchedWord),
                  icon: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06b6d4).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.volume_up, color: Color(0xFF06b6d4)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Meanings Cards
          ..._meanings
              .asMap()
              .entries
              .map((entry) => _buildMeaningCard(entry.key, entry.value)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMeaningCard(int index, WordMeaning meaning) {
    final typeColors = {
      'n': const Color(0xFF8b5cf6), // Noun - Purple
      'v': const Color(0xFF10b981), // Verb - Green
      'adj': const Color(0xFFf59e0b), // Adjective - Orange
      'adv': const Color(0xFF0ea5e9), // Adverb - Blue
      'phr': const Color(0xFFec4899), // Phrasal - Pink
      'idiom': const Color(0xFF6366f1), // Idiom - Indigo
    };

    final color =
        typeColors[meaning.type.toLowerCase()] ?? const Color(0xFF06b6d4);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1e3a8a).withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type Tag & Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color),
                ),
                child: Text(
                  meaning.type.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showAddToTodayDialog(meaning),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10b981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Color(0xFF10b981), size: 16),
                      SizedBox(width: 4),
                      Text(
                        _text('Gune Ekle', 'Add to Today'),
                        style: TextStyle(
                            color: Color(0xFF10b981),
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Turkish Meaning
          Text(
            meaning.turkishMeaning,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (meaning.englishDefinition.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              meaning.englishDefinition,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          if (meaning.example.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _text('Ornek Cumle', 'Example Sentence'),
              style: TextStyle(
                color: Color(0xFF06b6d4),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Interactive sentence with highlighted word
                  _buildInteractiveSentence(meaning.example),
                  if (meaning.exampleTranslation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      meaning.exampleTranslation,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
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

  Widget _buildInteractiveSentence(String sentence) {
    final words = sentence.split(RegExp(r'(\s+)')); // Boşlukları koru
    final searchedWordLower = _searchedWord.toLowerCase();

    return Wrap(
      children: words.map((word) {
        // Kelimeyi ve noktalama işaretlerini ayır
        final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
        final isHighlighted = cleanWord == searchedWordLower ||
            searchedWordLower.contains(cleanWord) ||
            cleanWord.contains(searchedWordLower);

        // Sadece boşluk ise
        if (word.trim().isEmpty) {
          return Text(word, style: const TextStyle(color: Colors.white));
        }

        return GestureDetector(
          onTap: isHighlighted
              ? null
              : () => _showWordInContextDialog(cleanWord, sentence),
          child: Container(
            padding: isHighlighted
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                : null,
            decoration: isHighlighted
                ? BoxDecoration(
                    color: const Color(0xFF06b6d4).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF06b6d4).withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : null,
            child: Text(
              word,
              style: TextStyle(
                color: isHighlighted ? const Color(0xFF06b6d4) : Colors.white,
                fontSize: 15,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                decoration: isHighlighted ? null : TextDecoration.underline,
                decorationColor: Colors.white24,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}

class WordMeaning {
  final String type;
  final String turkishMeaning;
  final String englishDefinition;
  final String example;
  final String exampleTranslation;

  WordMeaning({
    required this.type,
    required this.turkishMeaning,
    this.englishDefinition = '',
    this.example = '',
    this.exampleTranslation = '',
  });
}

