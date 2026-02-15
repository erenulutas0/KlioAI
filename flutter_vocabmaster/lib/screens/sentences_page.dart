import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../widgets/animated_background.dart';
import '../models/word.dart';
import '../models/sentence_view_model.dart';
import '../services/offline_sync_service.dart';
import '../widgets/add_sentence_from_sentences_modal.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../providers/app_state_provider.dart';

class SentencesPage extends StatefulWidget {
  const SentencesPage({super.key});

  @override
  State<SentencesPage> createState() => _SentencesPageState();
}

class _SentencesPageState extends State<SentencesPage> {
  final OfflineSyncService _offlineSyncService = OfflineSyncService();
  String _activeFilter = 'Tümü'; // Tümü, Kolay, Orta, Zor
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppStateProvider>().refreshSentences();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {}); // Trigger rebuild for filtering
  }

  // Filtreleme metodu - artık AppState'ten gelen verileri filtreler
  List<SentenceViewModel> _getFilteredSentences(
      List<SentenceViewModel> allSentences) {
    final query = _searchController.text.toLowerCase();

    return allSentences.where((vm) {
      final matchesQuery = vm.sentence.toLowerCase().contains(query) ||
          vm.translation.toLowerCase().contains(query) ||
          (vm.word?.englishWord.toLowerCase().contains(query) ?? false);

      final matchesFilter = _activeFilter == 'Tümü' ||
          _mapDifficulty(vm.difficulty) == _activeFilter;

      return matchesQuery && matchesFilter;
    }).toList();
  }

  String _mapDifficulty(String diff) {
    if (diff == 'easy') return 'Kolay';
    if (diff == 'medium') return 'Orta';
    if (diff == 'hard') return 'Zor';
    return 'Orta';
  }

  void _setActiveFilter(String filter) {
    setState(() => _activeFilter = filter);
  }

  @override
  Widget build(BuildContext context) {
    // AppStateProvider'dan cümleleri al
    final appState = context.watch<AppStateProvider>();
    final allSentences = appState.allSentences;
    final isLoading = appState.isLoadingSentences;

    // Filtrelenmiş cümleler
    final filteredSentences = _getFilteredSentences(allSentences);

    // Calculate stats
    int total = allSentences.length;
    int easy = allSentences.where((s) => s.difficulty == 'easy').length;
    int medium = allSentences.where((s) => s.difficulty == 'medium').length;
    int hard = allSentences.where((s) => s.difficulty == 'hard').length;

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100.0),
        child: Container(
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00c6ff), Color(0xFF0072ff)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0072ff).withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: _showAddNewSentenceDialog,
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: const Icon(Icons.add, color: Colors.white, size: 32),
          ),
        ),
      ),
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: Column(
              children: [
                // Top Stats
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                          'Toplam', total.toString(), Colors.redAccent),
                      _buildStatItem(
                          'Kolay', easy.toString(), Colors.greenAccent),
                      _buildStatItem(
                          'Orta', medium.toString(), Colors.amberAccent),
                      _buildStatItem('Zor', hard.toString(), Colors.red),
                    ],
                  ),
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.6),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        icon: Icon(Icons.search, color: Colors.white54),
                        hintText: 'Cümlelerde ara...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildFilterChip('Tümü'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Kolay'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Orta'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Zor'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // List
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredSentences.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notes,
                                      size: 64,
                                      color: Colors.white.withOpacity(0.2)),
                                  const SizedBox(height: 16),
                                  Text(
                                    _activeFilter == 'Tümü'
                                        ? 'Henüz cümle eklenmedi.'
                                        : _activeFilter == 'Zor'
                                            ? 'Daha zor kelime eklenmedi.'
                                            : 'Henüz $_activeFilter seviyesinde cümle eklenmedi.',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filteredSentences.length,
                              itemBuilder: (context, index) {
                                final vm = filteredSentences[index];
                                return SentenceCard(
                                  vm: vm,
                                  mapDifficulty: _mapDifficulty,
                                  onDelete: () async {
                                    try {
                                      final appState =
                                          context.read<AppStateProvider>();

                                      // 🔧 ID'yi int'e çevir (dynamic olabilir)
                                      // ID'yi direkt kullan (String veya int olabilir)
                                      final dynamic sentenceId = vm.id;
                                      bool deleted = false;

                                      if (vm.isPractice) {
                                        // 🔥 AppStateProvider üzerinden sil (UI anında güncellenir)
                                        deleted = await appState
                                            .deletePracticeSentence(sentenceId);
                                      } else {
                                        if (vm.word != null) {
                                          final int? numericSentenceId =
                                              sentenceId is int
                                                  ? sentenceId
                                                  : int.tryParse(
                                                      sentenceId.toString());
                                          if (numericSentenceId == null) {
                                            throw Exception(
                                                'Geçersiz cümle ID: $sentenceId');
                                          }
                                          // 🔥 AppStateProvider üzerinden sil (UI anında güncellenir)
                                          deleted = await appState
                                              .deleteSentenceFromWord(
                                            wordId: vm.word!.id,
                                            sentenceId: numericSentenceId,
                                          );
                                        }
                                      }
                                      if (!deleted) {
                                        throw Exception(
                                            'Cümle silinemedi, lütfen tekrar deneyin.');
                                      }

                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text('Cümle silindi!'),
                                                backgroundColor: Colors.green));
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
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ... (Keep _buildStatItem and others same, delete _buildSentenceCard)

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      width: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e3a8a).withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _activeFilter == label;
    return GestureDetector(
      onTap: () => _setActiveFilter(label),
      child: ModernCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        borderRadius: BorderRadius.circular(20),
        variant:
            isSelected ? BackgroundVariant.accent : BackgroundVariant.secondary,
        showGlow: isSelected,
        showBorder: isSelected,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _showAddNewSentenceDialog() {
    final appState = context.read<AppStateProvider>();
    final allWords = appState.allWords;

    AddSentenceFromSentencesModal.show(context, onSave: (items) async {
      try {
        int addedCount = 0;

        for (var item in items) {
          String sentence = item.english.trim();
          String translation = item.turkish.trim();
          // Sadece İngilizce cümle zorunlu, Türkçe opsiyonel
          if (sentence.isEmpty) continue;

          String diff = item.difficulty;

          if (!item.addToTodaysWords) {
            // Bağımsız pratik cümlesi - AppStateProvider üzerinden ekle
            final success = await appState.addPracticeSentence(
              englishSentence: sentence,
              turkishTranslation: translation,
              difficulty: diff,
            );
            if (success) addedCount++;
          } else {
            String targetWord = item.selectedWord.trim();
            if (targetWord.isEmpty) targetWord = "Genel";

            int? wordId;
            final existingWord = allWords.firstWhere(
                (w) => w.englishWord.toLowerCase() == targetWord.toLowerCase(),
                orElse: () => Word(
                    id: -1,
                    englishWord: '',
                    turkishMeaning: '',
                    learnedDate: DateTime.now(),
                    difficulty: 'easy',
                    sentences: []));

            if (existingWord.id != -1) {
              wordId = existingWord.id;
            } else {
              final dialogMeaning = item.selectedWordTurkish.trim().isEmpty
                  ? 'Genel'
                  : item.selectedWordTurkish.trim();
              // Yeni kelime ekle - AppStateProvider üzerinden
              final newWord = await appState.addWord(
                english: targetWord,
                turkish: dialogMeaning,
                addedDate: DateTime.now(),
                difficulty: 'medium',
              );
              wordId = newWord?.id;
            }

            if (wordId != null && wordId != 0) {
              // Kelimeye cümle ekle - AppStateProvider üzerinden
              await appState.addSentenceToWord(
                wordId: wordId,
                sentence: sentence,
                translation: translation,
                difficulty: diff,
              );
              addedCount++;
            }
          }
        }

        if (mounted && addedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$addedCount cümle eklendi! +${addedCount * 5} XP'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
        }
      }
    });
  }
}

class SentenceCard extends StatefulWidget {
  final SentenceViewModel vm;
  final String Function(String) mapDifficulty;
  final VoidCallback? onDelete;

  const SentenceCard({
    Key? key,
    required this.vm,
    required this.mapDifficulty,
    this.onDelete,
  }) : super(key: key);

  @override
  State<SentenceCard> createState() => _SentenceCardState();
}

class _SentenceCardState extends State<SentenceCard> {
  bool _isMeaningVisible = false;

  @override
  Widget build(BuildContext context) {
    final wordText = widget.vm.word?.englishWord ?? '';
    final difficulty = widget.mapDifficulty(widget.vm.difficulty);

    final sentenceText = widget.vm.sentence;
    final lowerSentence = sentenceText.toLowerCase();
    final lowerWord = wordText.toLowerCase();
    final int index =
        (wordText.isNotEmpty) ? lowerSentence.indexOf(lowerWord) : -1;

    List<InlineSpan> spans = [];
    if (index != -1) {
      // Before the word
      if (index > 0) {
        spans.add(TextSpan(
          text: sentenceText.substring(0, index),
          style:
              const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
        ));
      }

      // The highlighted word
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0ea5e9).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0ea5e9).withOpacity(0.2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Text(
            sentenceText.substring(index, index + wordText.length),
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ));

      // After the word
      if (index + wordText.length < sentenceText.length) {
        spans.add(TextSpan(
          text: sentenceText.substring(index + wordText.length),
          style:
              const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
        ));
      }
    } else {
      spans.add(TextSpan(
        text: sentenceText,
        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
      ));
    }

    Color badgeColor;
    Color badgeBgColor;

    switch (difficulty) {
      case 'Kolay':
        badgeColor = Colors.greenAccent;
        badgeBgColor = Colors.green.withOpacity(0.2);
        break;
      case 'Zor':
        badgeColor = Colors.redAccent;
        badgeBgColor = Colors.red.withOpacity(0.2);
        break;
      default:
        badgeColor = Colors.amberAccent;
        badgeBgColor = Colors.amber.withOpacity(0.2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06b6d4).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a).withOpacity(0.6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF06b6d4).withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Label & Delete
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: badgeBgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        difficulty.toUpperCase(),
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white54, size: 20),
                      onPressed: widget.onDelete != null
                          ? () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF1e1b4b),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.delete_forever,
                                            color: Colors.red, size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text('Cümleyi Sil',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18)),
                                    ],
                                  ),
                                  content: const Text(
                                    'Bu cümleyi silmek istediğinize emin misiniz?',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('İptal',
                                          style:
                                              TextStyle(color: Colors.white54)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        widget.onDelete!();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Sil',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            }
                          : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Sentence with Highlight
                RichText(
                  text: TextSpan(
                    children: spans,
                    style: const TextStyle(height: 1.5),
                  ),
                ),

                // Meaning (Collapsible)
                AnimatedCrossFade(
                  firstChild: const SizedBox(height: 0),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 1, color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.translate,
                                color: Colors.white54, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                              widget.vm.translation, // Use VM translation
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                            )),
                          ],
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: _isMeaningVisible
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),

                const SizedBox(height: 12),

                // Toggle Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isMeaningVisible = !_isMeaningVisible;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: Colors.transparent, // Hit test için
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isMeaningVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF22d3ee),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isMeaningVisible ? "Anlamı Gizle" : "Anlamı Göster",
                          style: const TextStyle(
                              color: Color(0xFF22d3ee),
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
