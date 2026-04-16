import 'package:flutter/material.dart';
import '../constants/sentence_modal_colors.dart';

class SentenceItem {
  final int id;
  String english;
  String turkish;
  String difficulty;
  String selectedWord;
  String selectedWordTurkish;
  bool addToTodaysWords;
  
  // Controllers
  late final TextEditingController englishController;
  late final TextEditingController turkishController;
  late final TextEditingController selectedWordController;
  late final TextEditingController selectedWordTurkishController;

  SentenceItem({
    required this.id,
    this.english = '',
    this.turkish = '',
    this.difficulty = 'easy',
    this.selectedWord = '',
    this.selectedWordTurkish = '',
    this.addToTodaysWords = false,
  }) {
    englishController = TextEditingController(text: english);
    turkishController = TextEditingController(text: turkish);
    selectedWordController = TextEditingController(text: selectedWord);
    selectedWordTurkishController = TextEditingController(text: selectedWordTurkish);
  }
  
  void dispose() {
    englishController.dispose();
    turkishController.dispose();
    selectedWordController.dispose();
    selectedWordTurkishController.dispose();
  }
}

class AddSentenceFromSentencesModal extends StatefulWidget {
  final Function(List<SentenceItem>) onSave;

  const AddSentenceFromSentencesModal({super.key, required this.onSave});

  @override
  State<AddSentenceFromSentencesModal> createState() => 
      _AddSentenceFromSentencesModalState();
      
  static Future<void> show(BuildContext context, {required Function(List<SentenceItem>) onSave}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddSentenceFromSentencesModal(onSave: onSave),
    );
  }
}

class _AddSentenceFromSentencesModalState 
    extends State<AddSentenceFromSentencesModal>
    with TickerProviderStateMixin {
  
  List<SentenceItem> sentences = [
    SentenceItem(id: 1),
  ];

  late AnimationController _modalController;
  late AnimationController _orb1Controller;
  late AnimationController _orb2Controller;
  late AnimationController _orb3Controller;
  
  late Animation<double> _modalAnimation;
  late Animation<double> _orb1Animation;
  late Animation<double> _orb2Animation;
  late Animation<double> _orb3Animation;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    
    // Modal Animation
    _modalController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _modalAnimation = CurvedAnimation(
      parent: _modalController,
      curve: Curves.easeOutCubic,
    );
    _modalController.forward();
    
    // Orb Animations
    _orb1Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    
    _orb2Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
    
    _orb3Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
    
    _orb1Animation = Tween<double>(begin: 0.3, end: 0.5).animate(
      CurvedAnimation(parent: _orb1Controller, curve: Curves.easeInOut),
    );
    
    _orb2Animation = Tween<double>(begin: 0.3, end: 0.5).animate(
      CurvedAnimation(parent: _orb2Controller, curve: Curves.easeInOut),
    );
    
    _orb3Animation = Tween<double>(begin: 0.3, end: 0.5).animate(
      CurvedAnimation(parent: _orb3Controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _modalController.dispose();
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    _orb3Controller.dispose();
    _scrollController.dispose();
    for (var sentence in sentences) {
      sentence.dispose();
    }
    super.dispose();
  }

  void _addSentence() {
    setState(() {
      final newId = sentences.isNotEmpty 
          ? sentences.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1 
          : 1;
      sentences.add(SentenceItem(id: newId));
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeSentence(int id) {
    if (sentences.length > 1) {
      setState(() {
        sentences.removeWhere((s) => s.id == id);
      });
    }
  }

  void _close() {
    _modalController.reverse().then((_) {
      Navigator.of(context).pop();
    });
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy': return SentenceModalColors.difficultyEasy;
      case 'medium': return SentenceModalColors.difficultyMedium;
      case 'hard': return SentenceModalColors.difficultyHard;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _modalAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.9 + (_modalAnimation.value * 0.1),
          child: Opacity(
            opacity: _modalAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(
          top: 48,
          left: 16, 
          right: 16, 
          bottom: 80,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: SentenceModalColors.gradientColors,
              ),
              border: Border.all(
                color: SentenceModalColors.borderMedium,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                // Animated Orbs Background
                _buildAnimatedOrbs(),
                
                // Sparkles
                _buildSparkles(),
                
                // Content
                Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _buildContent(),
                    ),
                    _buildAddSentenceButtonSticky(),
                    _buildFooter(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ... (Keep _buildAnimatedOrbs and _buildSparkles same)

  Widget _buildAnimatedOrbs() {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Orb 1
            Positioned(
              left: 0,
              top: 0,
              child: AnimatedBuilder(
                animation: _orb1Animation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _orb1Animation.value,
                    child: Container(
                      width: 256,
                      height: 256,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            SentenceModalColors.orb1Color,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Orb 2
            Positioned(
              right: 0,
              top: 100,
              child: AnimatedBuilder(
                animation: _orb2Animation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _orb2Animation.value,
                    child: Container(
                      width: 256,
                      height: 256,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            SentenceModalColors.orb2Color,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Orb 3
            Positioned(
              left: 100,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _orb3Animation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _orb3Animation.value,
                    child: Container(
                      width: 256,
                      height: 256,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            SentenceModalColors.orb1Color,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSparkles() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: List.generate(15, (index) {
            return _SparkleWidget(
              delay: index * 200,
              left: (index * 67) % 100,
              top: (index * 43) % 100,
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: SentenceModalColors.borderLight,
            width: 1,
          ),
        ),
        color: SentenceModalColors.bgOverlay5,
      ),
      child: Row(
        children: [
          // Icon Container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [
                  SentenceModalColors.gradientStart,
                  SentenceModalColors.gradientEnd,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: SentenceModalColors.gradientStart.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Title & Subtitle
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yeni Cümle Ekle',
                  style: TextStyle(
                    color: SentenceModalColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: SentenceModalColors.textCyan,
                      size: 14,
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Kelime seçerek veya seçmeden cümle ekleyin',
                        style: TextStyle(
                          color: SentenceModalColors.textCyan,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Close Button
          IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close, size: 20),
            color: SentenceModalColors.textWhite70,
            style: IconButton.styleFrom(
              backgroundColor: SentenceModalColors.bgOverlay10,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: sentences.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SentenceCard(
            sentence: sentences[index],
            index: index,
            onDelete: sentences.length > 1 
                ? () => _removeSentence(sentences[index].id)
                : null,
            onUpdate: (field, value) {
              setState(() {
                switch (field) {
                  case 'english':
                    sentences[index].english = value as String;
                    break;
                  case 'turkish':
                    sentences[index].turkish = value as String;
                    break;
                  case 'difficulty':
                    sentences[index].difficulty = value as String;
                    break;
                  case 'selectedWord':
                    sentences[index].selectedWord = value as String;
                    break;
                  case 'selectedWordTurkish':
                    sentences[index].selectedWordTurkish = value as String;
                    break;
                  case 'addToTodaysWords':
                    sentences[index].addToTodaysWords = value as bool;
                    break;
                }
              });
            },
            getDifficultyColor: _getDifficultyColor,
          ),
        );
      },
    );
  }

  Widget _buildAddSentenceButtonSticky() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: SentenceModalColors.borderLight,
            width: 1,
          ),
        ),
        color: SentenceModalColors.bgOverlay5,
      ),
      child: InkWell(
        onTap: _addSentence,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: SentenceModalColors.borderMedium,
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            borderRadius: BorderRadius.circular(12),
            color: SentenceModalColors.orb1Color.withOpacity(0.1),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                color: SentenceModalColors.textCyan,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Yeni Cümle Ekle',
                style: TextStyle(
                  color: SentenceModalColors.textCyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        border: const Border(
          top: BorderSide(
            color: SentenceModalColors.borderStrong,
            width: 2,
          ),
        ),
        gradient: LinearGradient(
          colors: [
            SentenceModalColors.gradientStart.withOpacity(0.1),
            SentenceModalColors.gradientEnd.withOpacity(0.1),
          ],
        ),
      ),
      child: Row(
        children: [
          // Cancel Button
          Expanded(
            child: OutlinedButton(
              onPressed: _close,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: SentenceModalColors.bgOverlay5,
                side: const BorderSide(
                  color: SentenceModalColors.borderMedium,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'İptal',
                style: TextStyle(
                  color: SentenceModalColors.textWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Save Button
          Expanded(
            child: _GradientButton(
              onPressed: () async {
                // Controller değerlerini model'e senkronize et
                for (var sentence in sentences) {
                  sentence.english = sentence.englishController.text;
                  sentence.turkish = sentence.turkishController.text;
                  sentence.selectedWord = sentence.selectedWordController.text;
                  sentence.selectedWordTurkish = sentence.selectedWordTurkishController.text;
                }
                
                // Async callback'i bekle
                await widget.onSave(sentences);
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text(
                'Cümle Ekle',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SentenceCard extends StatefulWidget {
  final SentenceItem sentence;
  final int index;
  final VoidCallback? onDelete;
  final Function(String field, dynamic value) onUpdate;
  final Color Function(String) getDifficultyColor;

  const _SentenceCard({
    required this.sentence,
    required this.index,
    this.onDelete,
    required this.onUpdate,
    required this.getDifficultyColor,
  });

  @override
  State<_SentenceCard> createState() => _SentenceCardState();
}

class _SentenceCardState extends State<_SentenceCard> {
  bool _isHovered = false;

  List<TextSpan> _highlightWord(String sentence, String word) {
    if (word.isEmpty) return [TextSpan(text: sentence)];
    
    final parts = sentence.split(RegExp(word, caseSensitive: false));
    final matches = RegExp(word, caseSensitive: false).allMatches(sentence);
    
    List<TextSpan> spans = [];
    int matchIndex = 0;
    
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(TextSpan(text: parts[i]));
      }
      
      if (matchIndex < matches.length) {
        spans.add(
          TextSpan(
            text: matches.elementAt(matchIndex).group(0),
            style: const TextStyle(
              backgroundColor: SentenceModalColors.highlightBg,
              color: Colors.white,
            ),
          ),
        );
        matchIndex++;
      }
    }
    
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: _isHovered 
                ? SentenceModalColors.borderStrong
                : SentenceModalColors.borderLight,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
          color: _isHovered 
              ? SentenceModalColors.bgOverlay10
              : SentenceModalColors.bgOverlay5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with number and delete
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [
                        SentenceModalColors.gradientStart,
                        SentenceModalColors.gradientEnd,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SentenceModalColors.gradientStart.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${widget.index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                const Text(
                  'Cümle',
                  style: TextStyle(
                    color: SentenceModalColors.textWhite,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                
                const Spacer(),
                
                if (widget.onDelete != null)
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 18,
                      color: SentenceModalColors.deleteColor,
                      style: IconButton.styleFrom(
                        backgroundColor: SentenceModalColors.deleteBg,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Word Selection (Optional)
            const Text(
              'Kelime Seçimi (Opsiyonel)',
              style: TextStyle(
                color: SentenceModalColors.textCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            const SizedBox(height: 6),
            
            Row(
              children: [
                Expanded(
                  child: _CustomTextField(
                    placeholder: 'İngilizce kelime',
                    controller: widget.sentence.selectedWordController,
                    onChanged: (value) => widget.onUpdate('selectedWord', value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CustomTextField(
                    placeholder: 'Türkçe anlamı',
                    controller: widget.sentence.selectedWordTurkishController,
                    onChanged: (value) => widget.onUpdate('selectedWordTurkish', value),
                  ),
                ),
              ],
            ),
            
            // Add to Today's Words Checkbox
            if (widget.sentence.selectedWord.isNotEmpty && 
                widget.sentence.selectedWordTurkish.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: SentenceModalColors.borderLight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: SentenceModalColors.bgOverlay5,
                  ),
                  child: InkWell(
                    onTap: () => widget.onUpdate(
                      'addToTodaysWords', 
                      !widget.sentence.addToTodaysWords
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: widget.sentence.addToTodaysWords,
                            onChanged: (value) => widget.onUpdate(
                              'addToTodaysWords', 
                              value ?? false
                            ),
                            activeColor: SentenceModalColors.checkboxFill,
                            side: const BorderSide(
                              color: SentenceModalColors.checkboxBorder,
                              width: 2,
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bugünün Kelimelerine Ekle',
                                style: TextStyle(
                                  color: SentenceModalColors.textWhite,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '"${widget.sentence.selectedWord}" kelimesini bugünün öğrenilen kelimelerine ekler',
                                style: const TextStyle(
                                  color: SentenceModalColors.textWhite60,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            const SizedBox(height: 8),
            
            // English Sentence
            const Text(
              'İngilizce Cümle',
              style: TextStyle(
                color: SentenceModalColors.textCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            const SizedBox(height: 6),
            
            _CustomTextField(
              placeholder: 'Enter an example sentence...',
              controller: widget.sentence.englishController,
              onChanged: (value) => widget.onUpdate('english', value),
            ),
            
            // Preview
            if (widget.sentence.english.isNotEmpty && 
                widget.sentence.selectedWord.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: SentenceModalColors.borderLight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: SentenceModalColors.bgOverlay5,
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: SentenceModalColors.textWhite80,
                        fontSize: 12,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Önizleme: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ..._highlightWord(
                          widget.sentence.english, 
                          widget.sentence.selectedWord
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            const SizedBox(height: 8),
            
            // Turkish Translation
            const Text(
              'Türkçe Anlamı',
              style: TextStyle(
                color: SentenceModalColors.textCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            const SizedBox(height: 6),
            
            _CustomTextField(
              placeholder: 'Cümlenin Türkçe çevirisi...',
              controller: widget.sentence.turkishController,
              onChanged: (value) => widget.onUpdate('turkish', value),
            ),
            
            const SizedBox(height: 8),
            
            // Difficulty
            const Text(
              'Zorluk Seviyesi',
              style: TextStyle(
                color: SentenceModalColors.textCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            const SizedBox(height: 6),
            
            _DifficultyDropdown(
              value: widget.sentence.difficulty,
              onChanged: (value) => widget.onUpdate('difficulty', value),
              getColor: widget.getDifficultyColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final String placeholder;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _CustomTextField({
    required this.placeholder,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(
        color: SentenceModalColors.textWhite,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(
          color: SentenceModalColors.textWhite.withOpacity(0.4),
          fontSize: 13,
        ),
        filled: true,
        fillColor: SentenceModalColors.bgOverlay10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SentenceModalColors.borderMedium,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SentenceModalColors.borderMedium,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SentenceModalColors.checkboxBorder,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

class _DifficultyDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final Color Function(String) getColor;

  const _DifficultyDropdown({
    required this.value,
    required this.onChanged,
    required this.getColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: SentenceModalColors.borderMedium,
        ),
        borderRadius: BorderRadius.circular(12),
        color: SentenceModalColors.bgOverlay10,
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                onChanged: (newValue) => onChanged(newValue!),
                dropdownColor: const Color(0xFF1E293B), // slate-800
                style: const TextStyle(
                  color: SentenceModalColors.textWhite,
                  fontSize: 14,
                ),
                icon: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: 'easy',
                    child: Text('🟢 Kolay'),
                  ),
                  DropdownMenuItem(
                    value: 'medium',
                    child: Text('🟡 Orta'),
                  ),
                  DropdownMenuItem(
                    value: 'hard',
                    child: Text('🔴 Zor'),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: getColor(value),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: getColor(value).withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;

  const _GradientButton({
    required this.onPressed,
    required this.child,
  });

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> 
    with SingleTickerProviderStateMixin {
  
  late AnimationController _shineController;
  late Animation<double> _shineAnimation;

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shineAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shineController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _shineController.forward(from: 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  SentenceModalColors.gradientStart,
                  SentenceModalColors.gradientEnd,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: SentenceModalColors.gradientStart.withOpacity(0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Shine Effect
                AnimatedBuilder(
                  animation: _shineAnimation,
                  builder: (context, child) {
                    return Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Transform.translate(
                          offset: Offset(_shineAnimation.value * 300, 0),
                          child: Container(
                            width: 50,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withOpacity(0.2),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                
                // Button Content
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkleWidget extends StatefulWidget {
  final int delay;
  final double left;
  final double top;

  const _SparkleWidget({
    required this.delay,
    required this.left,
    required this.top,
  });

  @override
  State<_SparkleWidget> createState() => _SparkleWidgetState();
}

class _SparkleWidgetState extends State<_SparkleWidget>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2000 + (widget.delay % 1000)),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(_controller);
    
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: SentenceModalColors.sparkleColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SentenceModalColors.sparkleColor.withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

