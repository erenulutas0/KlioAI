import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../widgets/animated_background.dart';
import '../models/word.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/groq_service.dart';
import '../services/chatbot_service.dart';
import '../widgets/global_matchmaking_sheet.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({Key? key}) : super(key: key);

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  final ChatbotService _chatbotService = ChatbotService();
  final FlutterTts _flutterTts = FlutterTts();
  
  Word? searchResultWord; // Kayıtlı kelimelerden bulunan sonuç
  Map<String, dynamic>? groqResult; // Groq API'den gelen zengin anlam sonucu
  List<Word> allWords = [];
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  
  // Seçilen cümleler (Bugüne Kaydet için)
  Set<int> selectedMeaningIndices = {};

  @override
  void initState() {
    super.initState();
    _loadWords();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _loadWords() async {
    try {
      final words = await _apiService.getAllWords();
      if (mounted) {
        setState(() => allWords = words);
      }
    } catch (e) {
      print('Error loading words: $e');
    }
  }

  Future<void> handleSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        searchResultWord = null;
        groqResult = null;
        errorMessage = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
      searchResultWord = null;
      groqResult = null;
      selectedMeaningIndices.clear();
    });

    // 1. Önce yerel koleksiyonda ara
    try {
      final localResult = allWords.firstWhere(
        (item) => item.englishWord.toLowerCase() == query.toLowerCase(),
      );
      setState(() {
        searchResultWord = localResult;
        isLoading = false;
      });
      return;
    } catch (_) {
      // Yerel koleksiyonda bulunamadı, Groq'a danış
    }

    // 2. Groq API ile ara
    try {
      final result = await GroqService.lookupWord(query);
      if (mounted) {
        setState(() {
          groqResult = result;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiQuotaExceededException
            ? AiErrorMessageFormatter.forQuota(e)
            : 'Kelime aranamadı: $e';
        setState(() {
          errorMessage = msg;
          isLoading = false;
        });
      }
    }
  }

  Future<void> _speakWord(String word) async {
    await _flutterTts.speak(word);
  }

  Future<void> _saveToToday() async {
    if (groqResult == null) return;
    
    setState(() => isSaving = true);
    
    try {
      final word = groqResult!['word'] as String;
      final meanings = groqResult!['meanings'] as List;
      
      // Seçilen anlamları topla
      List<String> selectedMeanings = [];
      List<String> selectedSentences = [];
      
      for (int i = 0; i < meanings.length; i++) {
        if (selectedMeaningIndices.isEmpty || selectedMeaningIndices.contains(i)) {
          selectedMeanings.add(meanings[i]['translation'] ?? '');
          if (meanings[i]['example'] != null) {
            selectedSentences.add(meanings[i]['example']);
          }
        }
      }
      
      await _chatbotService.saveWordToToday(
        englishWord: word,
        meanings: selectedMeanings,
        sentences: selectedSentences,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Kelime bugüne kaydedildi!'),
            backgroundColor: Colors.green,
          ),
        );
        // Listeyi yenile
        _loadWords();
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiQuotaExceededException
            ? AiErrorMessageFormatter.forQuota(e)
            : 'Hata: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // MVP: GlobalMatchmakingSheet disabled for v1.0
      // bottomNavigationBar: const GlobalMatchmakingSheet(),
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          const Expanded(
                            child: Text(
                              'Hızlı Sözlük',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Search Bar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'İngilizce kelime yazın (örn: apple)',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          ),
                          onSubmitted: (_) => handleSearch(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Search Button
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF06b6d4), Color(0xFF3b82f6)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ElevatedButton(
                          onPressed: isLoading ? null : handleSearch,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isLoading 
                              ? const SizedBox(
                                  height: 20, 
                                  width: 20, 
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                                )
                              : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Ara',
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
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Error State
    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Empty State
    if (searchResultWord == null && groqResult == null && _searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book,
                size: 48,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Herhangi bir İngilizce kelime arayın',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'AI ile detaylı anlamları getirin',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Yerel Koleksiyonda Bulundu
    if (searchResultWord != null) {
      return _buildLocalWordResult(searchResultWord!);
    }

    // Groq API Sonucu
    if (groqResult != null) {
      return _buildGroqResult(groqResult!);
    }

    // No Results (arama yapıldı ama sonuç yok)
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'Sonuç bulunamadı',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalWordResult(Word word) {
    final example = word.sentences.isNotEmpty ? word.sentences.first.sentence : 'Örnek cümle yok';
    final exampleTr = word.sentences.isNotEmpty ? word.sentences.first.translation : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Word Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    word.englishWord,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => _speakWord(word.englishWord),
                  icon: const Icon(Icons.volume_up, color: Colors.white),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('Kayıtlı', style: TextStyle(color: Colors.green, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Meaning
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                word.turkishMeaning,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            
            // Example
            if (example != 'Örnek cümle yok') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0ea5e9).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Example:', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('"$example"', style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic)),
                    if (exampleTr.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('"$exampleTr"', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroqResult(Map<String, dynamic> result) {
    final word = result['word'] as String? ?? '';
    final type = result['type'] as String? ?? '';
    final meanings = result['meanings'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Word Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF0ea5e9).withOpacity(0.2), const Color(0xFF3b82f6).withOpacity(0.2)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        word,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      if (type.isNotEmpty)
                        Text(type, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _speakWord(word),
                  icon: const Icon(Icons.volume_up, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Meanings
          Text(
            'Anlamlar (${meanings.length})',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          ...meanings.asMap().entries.map((entry) {
            final index = entry.key;
            final meaning = entry.value as Map<String, dynamic>;
            final translation = meaning['translation'] ?? '';
            final context = meaning['context'] ?? '';
            final example = meaning['example'] ?? '';
            final isSelected = selectedMeaningIndices.contains(index);
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    selectedMeaningIndices.remove(index);
                  } else {
                    selectedMeaningIndices.add(index);
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? const Color(0xFF0ea5e9).withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected 
                        ? const Color(0xFF0ea5e9)
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFF0ea5e9)
                                : Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: isSelected 
                              ? const Icon(Icons.check, color: Colors.white, size: 16)
                              : Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            translation,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (context.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8b5cf6).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context,
                          style: const TextStyle(color: Color(0xFFa78bfa), fontSize: 12),
                        ),
                      ),
                    ],
                    if (example.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.format_quote, color: Color(0xFF0ea5e9), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                example,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          
          const SizedBox(height: 24),
          
          // Save to Today Button
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10b981), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ElevatedButton(
              onPressed: isSaving ? null : _saveToToday,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_circle_outline, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          selectedMeaningIndices.isEmpty
                              ? 'Tümünü Bugüne Kaydet'
                              : '${selectedMeaningIndices.length} Anlamı Kaydet',
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
          
          const SizedBox(height: 16),
          Text(
            'Kaydetmek istediğiniz anlamları seçebilirsiniz',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
