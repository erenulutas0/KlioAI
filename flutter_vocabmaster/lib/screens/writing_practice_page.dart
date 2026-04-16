import 'package:flutter/material.dart';
import '../models/writing_practice_models.dart';
import '../services/groq_service.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/ai_paywall_handler.dart';
import '../services/daily_practice_progress_service.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../widgets/animated_background.dart';

class WritingPracticePage extends StatefulWidget {
  const WritingPracticePage({super.key});

  @override
  State<WritingPracticePage> createState() => _WritingPracticePageState();
}

class _WritingPracticePageState extends State<WritingPracticePage> {
  String _step = 'setup'; // 'setup', 'writing', 'evaluation'
  String _selectedLevel = 'B1';
  String _userText = '';
  int _wordCountActual = 0;
  bool _isLoading = false;
  late TextEditingController _textController; // Persistent controller

  TopicData? _topic;
  EvaluationData? _evaluation;
  final DailyPracticeProgressService _progressService =
      DailyPracticeProgressService();
  Map<String, bool> _completedLevels = {};

  final List<LevelOption> _levels = [
    LevelOption('A1', 'A1', [const Color(0xFF22C55E), const Color(0xFF10B981)]),
    LevelOption('A2', 'A2', [const Color(0xFF60A5FA), const Color(0xFF06B6D4)]),
    LevelOption('B1', 'B1', [const Color(0xFF22D3EE), const Color(0xFF3B82F6)]),
    LevelOption('B2', 'B2', [const Color(0xFFA78BFA), const Color(0xFFEC4899)]),
    LevelOption('C1', 'C1', [const Color(0xFFFB923C), const Color(0xFFEF4444)]),
    LevelOption('C2', 'C2', [const Color(0xFFEF4444), const Color(0xFFF43F5E)]),
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textController.addListener(_updateWordCount);
    _loadCompletionMap();
  }

  @override
  void dispose() {
    _textController.removeListener(_updateWordCount);
    _textController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    final text = _textController.text;
    setState(() {
      _userText = text;
      _wordCountActual =
          text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Transparent for AnimatedBackground
      extendBodyBehindAppBar: true, // Allow background to show through AppBar
      appBar: AppBar(
        title: const Text('Yazma Pratiği',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case 'setup':
        return _buildSetupStep();
      case 'writing':
        return _buildWritingStep();
      case 'evaluation':
        return _buildEvaluationStep();
      default:
        return _buildSetupStep();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // STEP 1: SETUP
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSetupStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Card
        _buildHeaderCard(),
        const SizedBox(height: 16),

        // Zorluk Seç Card
        _buildDifficultyCard(),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      variant: BackgroundVariant.primary,
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.edit,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // Text
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI ile Yazma Pratiği',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Seviyene uygun konularda yaz, yapay zeka değerlendirsin',
                  style: TextStyle(
                    color: Color(0xFFBAE6FD), // cyan-200
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyCard() {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Row(
            children: [
              Icon(
                Icons.gps_fixed,
                color: Color(0xFF22D3EE),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Zorluk Seç',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Level Grid (3x2)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.5,
            ),
            itemCount: _levels.length,
            itemBuilder: (context, index) {
              final level = _levels[index];
              final isSelected = _selectedLevel == level.id;
              final isCompleted = _completedLevels[level.id] == true;

              return GestureDetector(
                onTap: () => setState(() => _selectedLevel = level.id),
                child: Stack(
                  children: [
                    ModernCard(
                      padding: const EdgeInsets.all(0),
                      borderRadius: BorderRadius.circular(12),
                      variant: isSelected
                          ? BackgroundVariant.accent
                          : BackgroundVariant.secondary,
                      showGlow: isSelected,
                      child: Center(
                        child: Text(
                          level.label,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xB3FFFFFF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (isCompleted)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          Icons.check_circle,
                          color: Color(0xFF22C55E),
                          size: 16,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          if (_completedLevels[_selectedLevel] == true)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: const Color(0xFF22C55E).withOpacity(0.35)),
              ),
              child: const Text(
                'Bu seviyedeki gunluk yazma alistirmasi tamamlandi. Ayni konuyu tekrar coze bilirsin.',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),

          // Divider
          Container(
            height: 1,
            color: const Color(0x1AFFFFFF),
          ),
          const SizedBox(height: 16),

          // Konu Oluştur Button
          GestureDetector(
            onTap: _isLoading ? null : _handleGenerateTopic,
            child: ModernCard(
              padding: const EdgeInsets.symmetric(vertical: 16),
              borderRadius: BorderRadius.circular(12),
              variant: BackgroundVariant.accent,
              showGlow: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isLoading ? Icons.refresh : Icons.auto_awesome,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isLoading ? 'Konu Hazırlanıyor...' : 'Günün Konusunu Getir',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Her seviye icin gunluk tek konu verilir. Ayni seviyede tekrar ayni konu acilir.',
            style: TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCompletionMap() async {
    final completed = await _progressService.getCompletedLevels('writing');
    if (!mounted) {
      return;
    }
    setState(() {
      _completedLevels = completed;
    });
  }

  void _handleGenerateTopic() async {
    setState(() => _isLoading = true);

    try {
      final topic = await GroqService.generateDailyWritingTopic(_selectedLevel);
      if (mounted) {
        setState(() {
          _topic = topic;
          _step = 'writing';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : 'Hata: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // STEP 2: WRITING
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWritingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Topic Card
        _buildTopicCard(),
        const SizedBox(height: 24),

        // Writing Area
        _buildWritingArea(),
        const SizedBox(height: 24),

        // Action Buttons
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildTopicCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x4D06B6D4), // cyan-500/30
            Color(0x4D3B82F6), // blue-500/30
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x4D22D3EE), // cyan-400/30
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lightbulb_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badges
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x4D06B6D4),
                        border: Border.all(
                          color: const Color(0x8022D3EE),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _topic!.level,
                        style: const TextStyle(
                          color: Color(0xFFBAE6FD),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Topic Title
                Text(
                  _topic!.topic,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  _topic!.description,
                  style: const TextStyle(
                    color: Color(0xFFE0F2FE),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWritingArea() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x1AFFFFFF),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 10,
            spacing: 10,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit,
                    color: Color(0xFF22D3EE),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Yazınızı Buraya Yazın',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Color(0xFF22D3EE),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Kelime: ',
                    style: TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '$_wordCountActual',
                    style: const TextStyle(
                      color: Color(0xFF22D3EE),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Textarea
          Container(
            height: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              border: Border.all(
                color: const Color(0x3322D3EE),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _textController, // Use persistent controller
              maxLines: null,
              expands: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.8,
                fontFamily: 'serif',
              ),
              decoration: const InputDecoration(
                hintText:
                    'Yazınızı buraya yazın... Duygularınızı, düşüncelerinizi özgürce ifade edin. Her kelime öğrenme yolculuğunuzda bir adımdır.',
                hintStyle: TextStyle(
                  color: Color(0x66FFFFFF),
                  fontSize: 16,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tip Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x1A06B6D4),
              border: Border.all(
                color: const Color(0x3322D3EE),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF22D3EE),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        color: Color(0xFFE0F2FE),
                        fontSize: 14,
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Yazı İpuçları: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text:
                              'Cümlelerinizi net ve anlaşılır tutun. Geçiş kelimelerini kullanarak fikirlerinizi birbirine bağlayın. Yaratıcı olun ve kendi sesinizi buldurma çekinmeyin!',
                        ),
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

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Ayni konu
        Expanded(
          child: GestureDetector(
            onTap: _resetCurrentWritingAttempt,
            child: ModernCard(
              padding: const EdgeInsets.symmetric(vertical: 24),
              borderRadius: BorderRadius.circular(12),
              variant: BackgroundVariant.secondary,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Aynı Konuyu Tekrar Çöz',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Değerlendir
        Expanded(
          child: GestureDetector(
            onTap: _userText.trim().length < 10 ? null : _handleSubmitWriting,
            child: ModernCard(
              padding: const EdgeInsets.symmetric(vertical: 24),
              borderRadius: BorderRadius.circular(12),
              variant: BackgroundVariant.accent,
              showGlow: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _isLoading ? 'Değerlendiriliyor...' : 'Değerlendir',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleSubmitWriting() async {
    setState(() => _isLoading = true);
    try {
      final evaluation =
          await GroqService.evaluateWriting(_userText, _selectedLevel, _topic!);
      await _progressService.saveWritingResult(
        level: _selectedLevel,
        topic: _topic?.topic ?? '',
        score: evaluation.score,
      );
      await _loadCompletionMap();
      if (mounted) {
        setState(() {
          _evaluation = evaluation;
          _step = 'evaluation';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : 'Hata: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _handleReset() {
    setState(() {
      _step = 'setup';
      _topic = null;
      _userText = '';
      _textController.clear(); // Clear text field properly
      _evaluation = null;
      _wordCountActual = 0;
    });
  }

  void _resetCurrentWritingAttempt() {
    setState(() {
      _step = 'writing';
      _evaluation = null;
      _userText = '';
      _wordCountActual = 0;
      _textController.clear();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // STEP 3: EVALUATION
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEvaluationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Score Card
        _buildScoreCard(),
        const SizedBox(height: 24),

        // Strengths
        _buildStrengthsCard(),
        const SizedBox(height: 24),

        // Improvements
        _buildImprovementsCard(),
        const SizedBox(height: 24),

        // Detailed Feedback
        _buildDetailedFeedback(),
        const SizedBox(height: 24),

        // Reset Button
        _buildResetButton(),
      ],
    );
  }

  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x4DA78BFA), // purple-400/30
            Color(0x4DEC4899), // pink-500/30
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x4DC084FC), // purple-400/30
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Award Icon
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFA78BFA), Color(0xFFEC4899)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Harika İş Çıkardınız! 🎉',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Score
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFC084FC), Color(0xFFF472B6)],
            ).createShader(bounds),
            child: Text(
              '${_evaluation!.score}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle
          const Text(
            '100 üzerinden puanınız',
            style: TextStyle(
              color: Color(0xFFF5D0FE), // purple-200
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrengthsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x1A22C55E), // green-500/10
            Color(0x1A10B981), // emerald-500/10
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x4D4ADE80), // green-400/30
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Color(0xFF4ADE80),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Güçlü Yönler',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._evaluation!.strengths.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: const BoxDecoration(
                      color: Color(0x4D22C55E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Color(0xFF4ADE80),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry,
                      style: const TextStyle(
                        color: Color(0xFFBBF7D0),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildImprovementsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x1AF97316), // orange-500/10
            Color(0x1A22D3EE), // cyan-400/10 mixed
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x4DF97316), // orange/30
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: Color(0xFFFDBA74),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Geliştirilebilir Alanlar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._evaluation!.improvements.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: const BoxDecoration(
                      color: Color(0x33F97316),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.priority_high,
                      color: Color(0xFFFDBA74),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry,
                      style: const TextStyle(
                        color: Color(0xFFFED7AA),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDetailedFeedback() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x1AFFFFFF),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: Color(0xFF22D3EE),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Detaylı Geri Bildirim',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grammar
          _buildFeedbackSection(
            title: '📝 Gramer',
            content: _evaluation!.grammar,
            color: const Color(0xFF06B6D4),
          ),
          const SizedBox(height: 16),

          // Vocabulary
          _buildFeedbackSection(
            title: '📚 Kelime Dağarcığı',
            content: _evaluation!.vocabulary,
            color: const Color(0xFFA78BFA),
          ),
          const SizedBox(height: 16),

          // Coherence
          _buildFeedbackSection(
            title: '🔗 Tutarlılık',
            content: _evaluation!.coherence,
            color: const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 16),

          // Context Relevance
          if (_evaluation!.contextRelevance.isNotEmpty) ...[
            _buildFeedbackSection(
              title: '🎯 Konu Uyumu',
              content: _evaluation!.contextRelevance,
              color:
                  const Color(0xFFF43F5E), // Red/Pink to highlight importance
            ),
            const SizedBox(height: 16),
          ],

          // Overall
          _buildFeedbackSection(
            title: '⭐ Genel Değerlendirme',
            content: _evaluation!.overall,
            color: const Color(0xFFEC4899),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackSection({
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: _handleReset,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D06B6D4),
              blurRadius: 16,
              spreadRadius: 0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.refresh,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Başka Seviye Seç',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// DATA MODELS (Only UI helpers here, main data models in separate file)
// ═══════════════════════════════════════════════════════════════

class LevelOption {
  final String id;
  final String label;
  final List<Color> colors;

  LevelOption(this.id, this.label, this.colors);
}
