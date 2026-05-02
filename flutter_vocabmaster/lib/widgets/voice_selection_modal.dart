import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/voice_model.dart';
import '../services/piper_tts_service.dart';

/// Konuşmacı Seçim Modal Widget'ı
/// Carousel ile 6 konuşmacı gösterir, ses dinleme ve kaydetme sağlar
class VoiceSelectionModal extends StatefulWidget {
  final VoiceModel? currentVoice;
  final Function(VoiceModel) onVoiceSelected;

  const VoiceSelectionModal({
    super.key,
    this.currentVoice,
    required this.onVoiceSelected,
  });

  @override
  State<VoiceSelectionModal> createState() => _VoiceSelectionModalState();

  /// Modal'ı göster
  static Future<VoiceModel?> show(BuildContext context,
      {VoiceModel? currentVoice}) async {
    return showGeneralDialog<VoiceModel>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Voice Selection',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return VoiceSelectionModal(
          currentVoice: currentVoice,
          onVoiceSelected: (voice) {
            Navigator.of(context).pop(voice);
          },
        );
      },
    );
  }
}

class _VoiceSelectionModalState extends State<VoiceSelectionModal>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _pulseController;

  final PiperTtsService _ttsService = PiperTtsService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts(); // Fallback TTS

  int _currentPage = 0;
  VoiceModel? _selectedVoice;
  bool _isPlaying = false;

  final List<VoiceModel> _voices = VoiceModel.availableVoices;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();

    // Mevcut seçimi bul
    if (widget.currentVoice != null) {
      _selectedVoice = widget.currentVoice;
      _currentPage = _voices.indexWhere((v) => v.id == widget.currentVoice!.id);
      if (_currentPage < 0) _currentPage = 0;
    }

    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.85,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _initFlutterTts(); // Fallback TTS hazırla
  }

  Future<void> _initFlutterTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        _pulseController.stop();
        _pulseController.reset();
        setState(() => _isPlaying = false);
      }
    });

    _flutterTts.setErrorHandler((msg) {
      if (mounted) {
        _pulseController.stop();
        _pulseController.reset();
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  /// Sesi dinle
  Future<void> _playVoiceSample(VoiceModel voice) async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      await _flutterTts.stop();
      _pulseController.stop();
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _isPlaying = true);
    _pulseController.repeat(reverse: true);

    try {
      debugPrint('Sentezleniyor: ${voice.name} (${voice.piperVoice})');

      // 1. Önce Piper TTS dene
      Uint8List? audioData;
      try {
        audioData = await _ttsService.synthesize(
          voice.sampleText,
          voice: voice.piperVoice,
        );
      } catch (e) {
        debugPrint('Piper TTS Synth Error: $e');
      }

      if (audioData != null && mounted) {
        // Geçici dosya oluştur ve oynat (Daha güvenilir)
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/voice_sample.wav');
        await tempFile.writeAsBytes(audioData);

        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.play();

        // Oynatma bitince butonu resetle
        _audioPlayer.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) {
              _pulseController.stop();
              _pulseController.reset();
              setState(() => _isPlaying = false);
            }
          }
        });
      } else {
        // 2. Piper başarısızsa Fallback: Flutter TTS (System)
        if (!mounted) return;
        debugPrint('Piper başarısız veya veri yok, System TTS kullanılıyor...');

        // Locale ayarla (örn: en-US, en-GB)
        // FlutterTts genelde '-' kullanır (en-US), bizim model '_' kullanıyorsa replace yapalım
        String locale = voice.locale.replaceAll('_', '-');
        await _flutterTts.setLanguage(locale);

        // Cinsiyete göre pitch ayarı
        if (voice.gender == 'female') {
          await _flutterTts.setPitch(1.1);
        } else {
          await _flutterTts.setPitch(0.9);
        }

        await _flutterTts.speak(voice.sampleText);
      }
    } catch (e) {
      debugPrint('Voice sample error: $e');
      if (mounted) {
        _pulseController.stop();
        _pulseController.reset();
        setState(() => _isPlaying = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text('Ses calinamadi: ${e.toString()}',
                'Voice sample could not be played: ${e.toString()}')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Sesi kaydet
  Future<void> _saveVoice() async {
    if (_selectedVoice == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_voice', _selectedVoice!.toJsonString());
      widget.onVoiceSelected(_selectedVoice!);
    } catch (e) {
      debugPrint('Save voice error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Kaydetme basarisiz', 'Saving failed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final modalWidth = (size.width * 0.92).clamp(300.0, 400.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: modalWidth,
          constraints: BoxConstraints(
            maxHeight: size.height * 0.85, // Biraz arttırıldı
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E293B),
                Color(0xFF0F172A),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06B6D4).withOpacity(0.2),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: SingleChildScrollView(
                // Overflow fix
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    _buildHeader(),

                    // Carousel
                    SizedBox(
                      height: 320, // 360 -> 320 (Reduced height)
                      child: Stack(
                        children: [
                          // PageView
                          PageView.builder(
                            controller: _pageController,
                            itemCount: _voices.length,
                            onPageChanged: (index) {
                              setState(() => _currentPage = index);
                            },
                            itemBuilder: (context, index) {
                              return _buildVoiceCard(_voices[index], index);
                            },
                          ),

                          // Left Arrow
                          if (_currentPage > 0)
                            Positioned(
                              left: 4,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _buildArrowButton(
                                  icon: Icons.chevron_left,
                                  onTap: () => _pageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  ),
                                ),
                              ),
                            ),

                          // Right Arrow
                          if (_currentPage < _voices.length - 1)
                            Positioned(
                              right: 4,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _buildArrowButton(
                                  icon: Icons.chevron_right,
                                  onTap: () => _pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Pagination Dots
                    _buildPaginationDots(),

                    const SizedBox(height: 16),

                    // Footer
                    _buildFooter(),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('Konusmaci Sec', 'Choose Speaker'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _text('En sevdigin ses tonunu sec',
                      'Choose your preferred voice'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceCard(VoiceModel voice, int index) {
    final isSelected = _selectedVoice?.id == voice.id;
    final isCurrent = _currentPage == index;

    return AnimatedScale(
      scale: isCurrent ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedVoice = voice);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFF22D3EE) : Colors.transparent,
              width: isSelected ? 4 : 0,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: const Color(0xFF06B6D4).withOpacity(0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Avatar Image
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: voice.avatarUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: const Color(0xFF1E3A8A),
                      child: Center(
                        child: Text(
                          voice.name[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          voice.name[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Gradient Overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.9),
                        ],
                        stops: const [0.3, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),

                // Selected Checkmark
                if (isSelected)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF22D3EE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),

                // Info Section
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        voice.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Badges
                      Row(
                        children: [
                          // Gender Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF06B6D4).withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF22D3EE).withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  voice.genderEmoji,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  voice.genderText,
                                  style: const TextStyle(
                                    color: Color(0xFFA5F3FC),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Accent Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF3B82F6).withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              voice.accent,
                              style: const TextStyle(
                                color: Color(0xFFBFDBFE),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Play Button
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = _isPlaying && _currentPage == index
                              ? 1.0 + (_pulseController.value * 0.05)
                              : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: child,
                          );
                        },
                        child: GestureDetector(
                          onTap: () => _playVoiceSample(voice),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _isPlaying && _currentPage == index
                                    ? [
                                        const Color(0xFFEF4444),
                                        const Color(0xFFDC2626)
                                      ]
                                    : [
                                        const Color(0xFF06B6D4),
                                        const Color(0xFF0284C7)
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isPlaying && _currentPage == index
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF06B6D4))
                                      .withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isPlaying && _currentPage == index
                                      ? Icons.stop
                                      : Icons.volume_up,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isPlaying && _currentPage == index
                                      ? _text('Durdur', 'Stop')
                                      : _text('Sesi Dinle', 'Play Voice'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF06B6D4).withOpacity(0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildPaginationDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_voices.length, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF22D3EE)
                : Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Confirmation Text
          if (_selectedVoice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _text('${_selectedVoice!.name} ile devam etmek istiyor musun?',
                    'Do you want to continue with ${_selectedVoice!.name}?'),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Buttons
          Row(
            children: [
              // Cancel Button
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _text('Iptal', 'Cancel'),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Save Button
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _selectedVoice != null ? _saveVoice : null,
                  child: AnimatedOpacity(
                    opacity: _selectedVoice != null ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _text('Kaydet', 'Save'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
}
