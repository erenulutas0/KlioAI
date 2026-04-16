import 'package:flutter/material.dart';
import 'dart:math';
import '../widgets/animated_background.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../models/word.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/chatbot_service.dart';
import '../services/ai_paywall_handler.dart';

class TranslationPracticePage extends StatefulWidget {
  final Word? selectedWord;
  final List<String> selectedLevels;
  final List<String> selectedLengths;
  final String subMode; // 'select', 'manual', 'random'

  const TranslationPracticePage({
    super.key,
    this.selectedWord,
    this.selectedLevels = const ['B1'],
    this.selectedLengths = const ['medium'],
    this.subMode = 'select',
  });

  @override
  State<TranslationPracticePage> createState() =>
      _TranslationPracticePageState();
}

class _TranslationPracticePageState extends State<TranslationPracticePage> {
  final ChatbotService _chatbotService = ChatbotService();
  final ApiService _apiService = ApiService();
  final TextEditingController _wordController = TextEditingController();
  final Map<int, TextEditingController> _translationControllers = {};

  List<String> _generatedSentences = [];
  List<String> _aiTranslations = [];
  List<TranslationResult> _translationResults = [];
  bool _isGenerating = false;
  String _questionDirection = 'EN_TO_TR'; // EN_TO_TR, TR_TO_EN, MIXED

  Word? _selectedWord;

  @override
  void initState() {
    super.initState();
    _selectedWord = widget.selectedWord;
    if (_selectedWord != null) {
      _wordController.text = _selectedWord!.englishWord;
    }
  }

  @override
  void dispose() {
    _wordController.dispose();
    for (var controller in _translationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generateSentences() async {
    String wordToUse = '';

    if (widget.subMode == 'random') {
      final words = await _apiService.getAllWords();
      if (!mounted) return;
      if (words.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Henüz kelime listeniz boş.'),
              backgroundColor: Colors.red),
        );
        return;
      }
      words.shuffle();
      final selectedWords = words.take(5).map((w) => w.englishWord).toList();
      wordToUse = selectedWords.join(', ');
    } else {
      wordToUse = _selectedWord?.englishWord ?? _wordController.text.trim();
      if (wordToUse.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Lütfen bir kelime seçin veya yazın'),
              backgroundColor: Colors.red),
        );
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _generatedSentences = [];
      _aiTranslations = [];
      _translationResults = [];
    });

    try {
      final result = await _chatbotService.generateSentences(
        word: wordToUse,
        levels: widget.selectedLevels,
        lengths: widget.selectedLengths,
        fresh: true,
      );

      if (!mounted) return;

      final sentences = List<String>.from(result['sentences'] ?? []);
      final translations = List<String>.from(result['translations'] ?? []);

      // Dispose old controllers
      for (var controller in _translationControllers.values) {
        controller.dispose();
      }
      _translationControllers.clear();

      setState(() {
        _generatedSentences = sentences;
        _aiTranslations = translations;
        _translationResults = List.generate(
          sentences.length,
          (index) {
            final controller = TextEditingController();
            _translationControllers[index] = controller;

            // Determine direction for this sentence
            bool isReverse = false;
            if (_questionDirection == 'TR_TO_EN') {
              isReverse = true;
            } else if (_questionDirection == 'MIXED') {
              isReverse = Random().nextBool();
            }

            return TranslationResult(
              sentence: sentences[index],
              aiTranslation:
                  index < translations.length ? translations[index] : '',
              userTranslation: '',
              isCorrect: null,
              feedback: '',
              correctTranslation: '',
              isChecking: false,
              isReverse: isReverse,
            );
          },
        );
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
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

  Future<void> _checkTranslation(int index) async {
    final userTranslation = _translationControllers[index]?.text.trim() ?? '';
    if (userTranslation.isEmpty) return;

    setState(() {
      _translationResults[index].isChecking = true;
      _translationResults[index].userTranslation = userTranslation;
    });

    try {
      final result = _translationResults[index];
      final isReverse = result.isReverse;

      final resultData = await _chatbotService.checkTranslation(
        originalSentence:
            isReverse ? _aiTranslations[index] : _generatedSentences[index],
        userTranslation: userTranslation,
        direction: isReverse ? 'TR_TO_EN' : 'EN_TO_TR',
        referenceSentence: isReverse ? _generatedSentences[index] : null,
      );

      if (mounted) {
        setState(() {
          _translationResults[index].isCorrect =
              resultData['isCorrect'] as bool?;
          _translationResults[index].feedback = resultData['feedback'] ?? '';
          _translationResults[index].correctTranslation =
              resultData['correctTranslation'] ?? '';
          _translationResults[index].isChecking = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _translationResults[index].isChecking = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : 'Kontrol hatası: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
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
                _buildHeader(),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Word Input or Display
                        _buildWordSection(),

                        const SizedBox(height: 20),

                        // Direction Selection
                        _buildDirectionSelector(),

                        const SizedBox(height: 20),

                        // Generate Button
                        _buildGenerateButton(),

                        const SizedBox(height: 24),

                        // Generated Sentences
                        if (_generatedSentences.isNotEmpty) ...[
                          _buildSentencesHeader(),
                          const SizedBox(height: 16),
                          ..._translationResults.asMap().entries.map(
                                (entry) =>
                                    _buildSentenceCard(entry.key, entry.value),
                              ),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text(
            'Çevirme Pratiği',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordSection() {
    if (widget.subMode == 'random') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF8b5cf6).withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF8b5cf6).withOpacity(0.3)),
        ),
        child: const Column(
          children: [
            Icon(Icons.shuffle, color: Color(0xFF8b5cf6), size: 32),
            SizedBox(height: 12),
            Text(
              'Karışık Mod',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Rastgele 5 kelime seçilecek',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kelime',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_selectedWord != null)
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0ea5e9).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0ea5e9)),
                  ),
                  child: Text(
                    _selectedWord!.englishWord,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '→ ${_selectedWord!.turkishMeaning}',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            )
          else
            TextField(
              controller: _wordController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Kelime yazın...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectionSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Çeviri Yönü',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildDirectionChip('EN_TO_TR', 'EN → TR', Icons.arrow_forward),
              const SizedBox(width: 8),
              _buildDirectionChip('TR_TO_EN', 'TR → EN', Icons.arrow_back),
              const SizedBox(width: 8),
              _buildDirectionChip('MIXED', 'Karışık', Icons.shuffle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionChip(String value, String label, IconData icon) {
    final isSelected = _questionDirection == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _questionDirection = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0ea5e9).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF0ea5e9) : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? const Color(0xFF0ea5e9) : Colors.white54,
                  size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return GestureDetector(
      onTap: _isGenerating ? null : _generateSentences,
      child: ModernCard(
        variant: BackgroundVariant.accent,
        borderRadius: BorderRadius.circular(16),
        showGlow: true,
        showBorder: false,
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: _isGenerating
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Text('Owen cümle üretiyor...',
                      style: TextStyle(color: Colors.white)),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Cümle Üret',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSentencesHeader() {
    return Row(
      children: [
        const Icon(Icons.format_list_numbered, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Text(
          'Cümleler (${_generatedSentences.length})',
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSentenceCard(int index, TranslationResult result) {
    final isReverse = result.isReverse;
    final displaySentence = isReverse ? result.aiTranslation : result.sentence;
    final direction = isReverse ? 'TR → EN' : 'EN → TR';

    Color? resultColor;
    if (result.isCorrect == true) {
      resultColor = const Color(0xFF10b981);
    } else if (result.isCorrect == false) {
      resultColor = const Color(0xFFef4444);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: resultColor?.withOpacity(0.5) ?? Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF8b5cf6).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      color: Color(0xFF8b5cf6), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0ea5e9).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  direction,
                  style:
                      const TextStyle(color: Color(0xFF0ea5e9), fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sentence
          Text(
            displaySentence,
            style:
                const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Translation Input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _translationControllers[index],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: isReverse
                        ? 'İngilizce çevirinizi yazın...'
                        : 'Türkçe çevirinizi yazın...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onSubmitted: (_) => _checkTranslation(index),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0ea5e9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed:
                      result.isChecking ? null : () => _checkTranslation(index),
                  icon: result.isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, color: Colors.white),
                ),
              ),
            ],
          ),

          // Result
          if (result.isCorrect != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: resultColor!.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: resultColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        result.isCorrect! ? Icons.check_circle : Icons.cancel,
                        color: resultColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        result.isCorrect! ? 'Doğru!' : 'Yanlış',
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (result.feedback.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      result.feedback,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                  if (result.correctTranslation.isNotEmpty &&
                      !result.isCorrect!) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Doğru çeviri: ${result.correctTranslation}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8), fontSize: 13),
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
}

class TranslationResult {
  String sentence;
  String aiTranslation;
  String userTranslation;
  bool? isCorrect;
  String feedback;
  String correctTranslation;
  bool isChecking;
  bool isReverse;

  TranslationResult({
    required this.sentence,
    this.aiTranslation = '',
    required this.userTranslation,
    this.isCorrect,
    required this.feedback,
    required this.correctTranslation,
    required this.isChecking,
    this.isReverse = false,
  });
}

