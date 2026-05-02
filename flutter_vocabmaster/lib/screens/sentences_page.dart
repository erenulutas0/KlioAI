import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sentence_view_model.dart';
import '../models/word.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/add_sentence_from_sentences_modal.dart';
import '../widgets/animated_background.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';

class SentencesPage extends StatefulWidget {
  const SentencesPage({super.key});

  @override
  State<SentencesPage> createState() => _SentencesPageState();
}

class _SentencesPageState extends State<SentencesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _activeFilter = 'all';

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';
  String _text(String tr, String en) => _isTurkish ? tr : en;

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
    setState(() {});
  }

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return _text('Kolay', 'Easy');
      case 'medium':
        return _text('Orta', 'Medium');
      case 'hard':
        return _text('Zor', 'Hard');
      default:
        return _text('Orta', 'Medium');
    }
  }

  String _filterLabel(String filter) {
    switch (filter) {
      case 'easy':
        return _text('Kolay', 'Easy');
      case 'medium':
        return _text('Orta', 'Medium');
      case 'hard':
        return _text('Zor', 'Hard');
      default:
        return _text('Tumu', 'All');
    }
  }

  List<SentenceViewModel> _getFilteredSentences(
    List<SentenceViewModel> allSentences,
  ) {
    final query = _searchController.text.trim().toLowerCase();

    return allSentences.where((vm) {
      final matchesQuery = query.isEmpty ||
          vm.sentence.toLowerCase().contains(query) ||
          vm.translation.toLowerCase().contains(query) ||
          (vm.word?.englishWord.toLowerCase().contains(query) ?? false);
      final matchesFilter =
          _activeFilter == 'all' || vm.difficulty == _activeFilter;
      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _showAddNewSentenceDialog() async {
    final appState = context.read<AppStateProvider>();
    final allWords = appState.allWords;

    AddSentenceFromSentencesModal.show(context, onSave: (items) async {
      try {
        var addedCount = 0;

        for (final item in items) {
          final sentence = item.english.trim();
          final translation = item.turkish.trim();
          if (sentence.isEmpty) continue;

          final difficulty = item.difficulty;

          if (!item.addToTodaysWords) {
            final success = await appState.addPracticeSentence(
              englishSentence: sentence,
              turkishTranslation: translation,
              difficulty: difficulty,
            );
            if (success) {
              addedCount++;
            }
            continue;
          }

          var targetWord = item.selectedWord.trim();
          if (targetWord.isEmpty) {
            targetWord = _text('Genel', 'General');
          }

          int? wordId;
          final existingWord = allWords.cast<Word?>().firstWhere(
                (word) =>
                    word != null &&
                    word.englishWord.toLowerCase() == targetWord.toLowerCase(),
                orElse: () => null,
              );

          if (existingWord != null) {
            wordId = existingWord.id;
          } else {
            final wordMeaning = item.selectedWordTurkish.trim().isEmpty
                ? _text('Genel', 'General')
                : item.selectedWordTurkish.trim();
            final newWord = await appState.addWord(
              english: targetWord,
              turkish: wordMeaning,
              addedDate: DateTime.now(),
              difficulty: 'medium',
            );
            wordId = newWord?.id;
          }

          if (wordId != null && wordId != 0) {
            await appState.addSentenceToWord(
              wordId: wordId,
              sentence: sentence,
              translation: translation,
              difficulty: difficulty,
            );
            addedCount++;
          }
        }

        if (!mounted || addedCount == 0) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                '$addedCount cumle eklendi! +${addedCount * 5} XP',
                '$addedCount sentences added! +${addedCount * 5} XP',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text('Hata: $e', 'Error: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);
    final appState = context.watch<AppStateProvider>();
    final allSentences = appState.allSentences;
    final filteredSentences = _getFilteredSentences(allSentences);
    final isLoading = appState.isLoadingSentences;

    final total = allSentences.length;
    final easy = allSentences.where((s) => s.difficulty == 'easy').length;
    final medium = allSentences.where((s) => s.difficulty == 'medium').length;
    final hard = allSentences.where((s) => s.difficulty == 'hard').length;

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100),
        child: Container(
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                selectedTheme.colors.accent,
                selectedTheme.colors.primary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: selectedTheme.colors.accentGlow.withOpacity(0.42),
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        _text('Toplam', 'Total'),
                        total.toString(),
                        Colors.redAccent,
                      ),
                      _buildStatItem(
                        _text('Kolay', 'Easy'),
                        easy.toString(),
                        Colors.greenAccent,
                      ),
                      _buildStatItem(
                        _text('Orta', 'Medium'),
                        medium.toString(),
                        Colors.amberAccent,
                      ),
                      _buildStatItem(
                        _text('Zor', 'Hard'),
                        hard.toString(),
                        Colors.red,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: _mix(selectedTheme.colors.background, Colors.black,
                              0.12)
                          .withOpacity(0.72),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        icon: const Icon(Icons.search, color: Colors.white54),
                        hintText:
                            _text('Cumlelerde ara...', 'Search sentences...'),
                        hintStyle: const TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildFilterChip('all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('easy'),
                      const SizedBox(width: 8),
                      _buildFilterChip('medium'),
                      const SizedBox(width: 8),
                      _buildFilterChip('hard'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredSentences.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filteredSentences.length,
                              itemBuilder: (context, index) {
                                final vm = filteredSentences[index];
                                return SentenceCard(
                                  vm: vm,
                                  difficultyLabel:
                                      _difficultyLabel(vm.difficulty),
                                  onDelete: () => _deleteSentence(vm),
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

  Widget _buildEmptyState() {
    String message;
    if (_activeFilter == 'all') {
      message = _text(
        'Henuz cumle eklenmedi.',
        'No sentences have been added yet.',
      );
    } else if (_activeFilter == 'hard') {
      message = _text(
        'Daha zor cumle eklenmedi.',
        'No hard sentences are available yet.',
      );
    } else {
      final label = _filterLabel(_activeFilter).toLowerCase();
      message = _text(
        'Henuz $label seviyesinde cumle eklenmedi.',
        'No $label sentences are available yet.',
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notes, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            message,
            style:
                TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSentence(SentenceViewModel vm) async {
    try {
      final appState = context.read<AppStateProvider>();
      final sentenceId = vm.id;
      var deleted = false;

      if (vm.isPractice) {
        deleted = await appState.deletePracticeSentence(sentenceId);
      } else if (vm.word != null) {
        final numericSentenceId = sentenceId is int
            ? sentenceId
            : int.tryParse(sentenceId.toString());
        if (numericSentenceId == null) {
          throw Exception(
            _text(
              'Gecersiz cumle ID: $sentenceId',
              'Invalid sentence ID: $sentenceId',
            ),
          );
        }
        deleted = await appState.deleteSentenceFromWord(
          wordId: vm.word!.id,
          sentenceId: numericSentenceId,
        );
      }

      if (!deleted) {
        throw Exception(
          _text(
            'Cumle silinemedi, lutfen tekrar deneyin.',
            'The sentence could not be deleted. Please try again.',
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Cumle silindi!', 'Sentence deleted!')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Hata: $e', 'Error: $e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    final selectedTheme = _currentTheme();
    return Container(
      width: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selectedTheme.colors.cardBackground.withOpacity(0.66),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedTheme.colors.glassBorder.withOpacity(0.52),
        ),
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

  Widget _buildFilterChip(String value) {
    final isSelected = _activeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = value),
      child: ModernCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        borderRadius: BorderRadius.circular(20),
        variant:
            isSelected ? BackgroundVariant.accent : BackgroundVariant.secondary,
        showGlow: isSelected,
        showBorder: isSelected,
        child: Text(
          _filterLabel(value),
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class SentenceCard extends StatefulWidget {
  final SentenceViewModel vm;
  final String difficultyLabel;
  final VoidCallback? onDelete;

  const SentenceCard({
    super.key,
    required this.vm,
    required this.difficultyLabel,
    this.onDelete,
  });

  @override
  State<SentenceCard> createState() => _SentenceCardState();
}

class _SentenceCardState extends State<SentenceCard> {
  bool _isMeaningVisible = false;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';
  String _text(String tr, String en) => _isTurkish ? tr : en;

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

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);
    final wordText = widget.vm.word?.englishWord ?? '';
    final sentenceText = widget.vm.sentence;
    final lowerSentence = sentenceText.toLowerCase();
    final lowerWord = wordText.toLowerCase();
    final highlightIndex =
        wordText.isNotEmpty ? lowerSentence.indexOf(lowerWord) : -1;

    final spans = <InlineSpan>[];
    if (highlightIndex != -1) {
      if (highlightIndex > 0) {
        spans.add(
          TextSpan(
            text: sentenceText.substring(0, highlightIndex),
            style:
                const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
          ),
        );
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selectedTheme.colors.accent.withOpacity(0.30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selectedTheme.colors.accent.withOpacity(0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: selectedTheme.colors.accentGlow.withOpacity(0.26),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Text(
              sentenceText.substring(
                highlightIndex,
                highlightIndex + wordText.length,
              ),
              style: TextStyle(
                color:
                    Color.lerp(selectedTheme.colors.accent, Colors.white, 0.2),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );

      if (highlightIndex + wordText.length < sentenceText.length) {
        spans.add(
          TextSpan(
            text: sentenceText.substring(highlightIndex + wordText.length),
            style:
                const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
          ),
        );
      }
    } else {
      spans.add(
        TextSpan(
          text: sentenceText,
          style:
              const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
        ),
      );
    }

    Color badgeColor;
    Color badgeBackground;
    switch (widget.vm.difficulty) {
      case 'easy':
        badgeColor = Colors.greenAccent;
        badgeBackground = Colors.green.withOpacity(0.2);
        break;
      case 'hard':
        badgeColor = Colors.redAccent;
        badgeBackground = Colors.red.withOpacity(0.2);
        break;
      default:
        badgeColor = Colors.amberAccent;
        badgeBackground = Colors.amber.withOpacity(0.2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: selectedTheme.colors.accentGlow.withOpacity(0.12),
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
              color: _mix(selectedTheme.colors.background, Colors.black, 0.08)
                  .withOpacity(0.68),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selectedTheme.colors.glassBorder.withOpacity(0.72),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        widget.difficultyLabel.toUpperCase(),
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: widget.onDelete == null
                          ? null
                          : () => _confirmDelete(selectedTheme),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    children: spans,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(height: 0),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.translate,
                                color: Colors.white54, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.vm.translation,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
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
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isMeaningVisible = !_isMeaningVisible;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: Colors.transparent,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isMeaningVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: selectedTheme.colors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isMeaningVisible
                              ? _text('Anlami Gizle', 'Hide Meaning')
                              : _text('Anlami Goster', 'Show Meaning'),
                          style: TextStyle(
                            color: selectedTheme.colors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
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

  Future<void> _confirmDelete(AppThemeConfig selectedTheme) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            _mix(selectedTheme.colors.background, Colors.black, 0.22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.delete_forever, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              _text('Cumleyi Sil', 'Delete Sentence'),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          _text(
            'Bu cumleyi silmek istediginize emin misiniz?',
            'Are you sure you want to delete this sentence?',
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _text('Iptal', 'Cancel'),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _text('Sil', 'Delete'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
