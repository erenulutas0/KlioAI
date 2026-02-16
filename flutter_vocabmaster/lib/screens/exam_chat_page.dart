import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/animated_background.dart';
import '../services/chatbot_service.dart';
import '../services/api_service.dart';
import '../services/piper_tts_service.dart';

class ExamChatPage extends StatefulWidget {
  final String examType; // 'IELTS' or 'TOEFL'

  const ExamChatPage({Key? key, required this.examType}) : super(key: key);

  @override
  State<ExamChatPage> createState() => _ExamChatPageState();
}

class _ExamChatPageState extends State<ExamChatPage> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatbotService _chatbotService = ChatbotService();
  final PiperTtsService _ttsService = PiperTtsService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isSpeaking = false;
  bool _ttsEnabled = true;
  bool _ttsAvailable = false;
  
  // STT
  late stt.SpeechToText _speech;
  bool _isListening = false;
  
  String _currentPart = 'part1'; // part1, part2, part3 for IELTS
  
  // Floating particles animation
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    // Keep screen on
    WakelockPlus.enable();
    
    _checkTtsAvailability();
    _initFlutterTts();
    _startExamSession();
  }

  Future<void> _initFlutterTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.45); // Slightly slower for exam clarity
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _checkTtsAvailability() async {
    final available = await _ttsService.isAvailable();
    if (mounted) {
      setState(() => _ttsAvailable = available);
    }
  }

  Future<void> _startExamSession() async {
    // Add welcome message
    String welcomeMessage = '';
    if (widget.examType == 'IELTS') {
      welcomeMessage = "Welcome to IELTS Speaking Practice!\n\n🎯 I'll help you prepare for your IELTS speaking exam. We'll go through all three parts:\n\n• Part 1: Introduction & Interview\n• Part 2: Long turn (Cue Card)\n• Part 3: Discussion\n\nLet's start with Part 1!";
    } else {
      welcomeMessage = "Welcome to TOEFL Speaking Practice!\n\n🎯 I'll help you prepare for your TOEFL speaking exam. We'll practice:\n\n• Task 1: Independent Speaking\n• Task 2: Campus Situation\n• Task 3: Academic Course\n• Task 4: Academic Lecture\n\nLet's start with Task 1!";
    }
    
    _addBotMessage(welcomeMessage, speak: true);
    
    // Load first question
    await Future.delayed(const Duration(milliseconds: 2000));
    await _loadQuestion();
  }

  Future<void> _loadQuestion() async {
    setState(() => _isTyping = true);
    
    try {
      final result = await _chatbotService.generateSpeakingTestQuestions(
        testType: widget.examType,
        part: _currentPart,
      );
      
      if (mounted) {
        setState(() => _isTyping = false);
        
        // Display question
        final question = result['question'] ?? result['questions']?[0] ?? 'Please tell me about yourself.';
        _addBotMessage('📝 $question', speak: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTyping = false);
        if (e is ApiQuotaExceededException) {
          _addBotMessage(e.message, speak: true);
        } else {
          _addBotMessage('Error loading question. Let\'s try a general question:\n\nTell me about your hometown. What do you like about living there?', speak: true);
        }
      }
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _messageController.dispose();
    _scrollController.dispose();
    _particleController.dispose();
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _addBotMessage(String text, {bool speak = false}) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isBot: true,
        time: _getCurrentTime(),
      ));
    });
    _scrollToBottom();
    
    if (speak && _ttsEnabled) {
      _speakText(text);
    }
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _audioPlayer.stop();
      await _flutterTts.stop();
    }
    
    // Stop listening while speaking
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }
    
    // Clean text for speech (remove emojis and special formatting)
    String cleanText = text.replaceAll(RegExp(r'[📝🎯💡•\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    
    setState(() => _isSpeaking = true);
    
    try {
      Uint8List? audioData;
      
      // Try Piper TTS first
      if (_ttsAvailable) {
        try {
          audioData = await _ttsService.synthesize(cleanText, voice: 'amy');
        } catch (e) {
          debugPrint('Piper TTS error: $e');
        }
      }
      
      if (audioData != null && mounted) {
        // Play Piper audio
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/exam_response.wav');
        await tempFile.writeAsBytes(audioData);
        
        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.play();
        
        await _audioPlayer.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed
        );
      } else {
        // Fallback to system TTS
        debugPrint('Using fallback TTS');
        await _flutterTts.speak(cleanText);
      }
    } catch (e) {
      debugPrint('TTS error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
    }
  }

  /// User's message'ı sesli dinle (göndermeden önce)
  Future<void> _playbackUserMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    setState(() => _isSpeaking = true);
    
    try {
      await _flutterTts.speak(_messageController.text.trim());
    } catch (e) {
      debugPrint('Playback error: $e');
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  /// Sesli giriş başlat
  Future<void> _startListening() async {
    // Stop any ongoing speech
    if (_isSpeaking) {
      await _audioPlayer.stop();
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    }
    
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon izni gerekli.')),
        );
      }
      return;
    }

    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (val) => debugPrint('STT Error: $val'),
      );
      
      if (available) {
        if (mounted) setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _messageController.text = val.recognizedWords;
            });
          },
          listenFor: const Duration(seconds: 120), // 2 minutes for full answer
          pauseFor: const Duration(seconds: 3),
          localeId: 'en_US',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ses algılama başlatılamadı.')),
          );
        }
      }
    }
  }

  /// Sesli girişi durdur (manuel olarak)
  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _sendMessage() async {
    // Stop listening first
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }
    
    if (_messageController.text.trim().isEmpty) return;
    
    final userMessage = _messageController.text.trim();
    setState(() {
      _messages.add(ChatMessage(
        text: userMessage,
        isBot: false,
        time: _getCurrentTime(),
      ));
      _isTyping = true;
    });
    _messageController.clear();
    _scrollToBottom();
    
    try {
      // Evaluate the response
      final lastBotMessage = _messages.lastWhere((m) => m.isBot).text;
      final question = lastBotMessage.replaceAll(RegExp(r'📝\s*'), '');
      
      final evaluation = await _chatbotService.evaluateSpeakingTest(
        testType: widget.examType,
        question: question,
        response: userMessage,
      );
      
      if (mounted) {
        setState(() => _isTyping = false);
        
        // Display feedback
        final score = evaluation['score'] ?? evaluation['band'] ?? '6.0';
        final feedback = evaluation['feedback'] ?? 'Good attempt! Keep practicing.';
        final suggestions = evaluation['suggestions'] ?? evaluation['improvements'] ?? '';
        
        String feedbackMessage = '🎯 **Score: $score**\n\n$feedback';
        if (suggestions.toString().isNotEmpty) {
          feedbackMessage += '\n\n💡 Suggestions:\n$suggestions';
        }
        
        _addBotMessage(feedbackMessage, speak: true);
        
        // Ask if they want to continue
        await Future.delayed(const Duration(seconds: 2));
        _addBotMessage('Would you like to try another question? Just type "next" or ask me anything!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTyping = false);
        if (e is ApiQuotaExceededException) {
          _addBotMessage(e.message, speak: true);
        } else {
          _addBotMessage('Good effort! Keep practicing. Your answer shows understanding of the topic.\n\nWould you like another question?');
        }
      }
    }
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
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

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF0ea5e9);
    
    return Scaffold(
      body: Stack(
        children: [
          // Animated Background
          const AnimatedBackground(isDark: true),
          
          // Floating particles
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                painter: ParticlesPainter(_particleController.value),
                size: Size.infinite,
              );
            },
          ),
          
          // Main content
          SafeArea(
            child: Column(
              children: [
                // App Bar
                _buildAppBar(primaryColor),
                
                // Messages List
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) {
                        return _buildTypingIndicator(primaryColor);
                      }
                      return _buildMessageBubble(_messages[index], primaryColor);
                    },
                  ),
                ),
                
                // Input Area
                _buildInputArea(primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          
          // Bot Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.examType == 'IELTS' 
                  ? const Color(0xFFdc2626) // Red for IELTS
                  : const Color(0xFF2563eb), // Blue for TOEFL
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.school_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          
          // Bot Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.examType} Coach',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22c55e),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Speaking - $_currentPart',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Next Part Button
          IconButton(
            onPressed: () {
              setState(() {
                if (_currentPart == 'part1') {
                  _currentPart = 'part2';
                } else if (_currentPart == 'part2') {
                  _currentPart = 'part3';
                } else {
                  _currentPart = 'part1';
                }
              });
              _addBotMessage('Moving to $_currentPart...');
              _loadQuestion();
            },
            icon: const Icon(Icons.skip_next, color: Colors.white70),
            tooltip: 'Next Part',
          ),
          
          // Sound Toggle
          IconButton(
            onPressed: () => setState(() => _ttsEnabled = !_ttsEnabled),
            icon: Icon(
              _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _ttsEnabled ? color : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: message.isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          if (message.isBot)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: widget.examType == 'IELTS' 
                          ? const Color(0xFFdc2626)
                          : const Color(0xFF2563eb),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.school,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.examType} Coach',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _speakText(message.text),
                    child: Icon(
                      _isSpeaking ? Icons.stop : Icons.volume_up,
                      color: color,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: message.isBot
                  ? const LinearGradient(
                      colors: [Color(0xFF1e3a5f), Color(0xFF1e3a8a)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [color, const Color(0xFF0284c7)],
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(message.isBot ? 4 : 20),
                bottomRight: Radius.circular(message.isBot ? 20 : 4),
              ),
              border: message.isBot
                  ? Border.all(color: color.withOpacity(0.2))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: (message.isBot ? const Color(0xFF1e3a8a) : color)
                      .withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message.time,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1e3a8a).withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0, color),
                const SizedBox(width: 4),
                _buildDot(1, color),
                const SizedBox(width: 4),
                _buildDot(2, color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index, Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (index * 200)),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6 + (value * 0.4)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildInputArea(Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a).withOpacity(0.8),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Mic Button
              GestureDetector(
                onTap: () {
                  if (_isListening) {
                    _stopListening();
                  } else {
                    _startListening();
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isListening ? const Color(0xFFef4444) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _isListening ? [
                      BoxShadow(
                        color: const Color(0xFFef4444).withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ] : [],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Playback Button (listen before sending)
              GestureDetector(
                onTap: _messageController.text.trim().isNotEmpty ? _playbackUserMessage : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isSpeaking ? Icons.pause : Icons.play_arrow,
                    color: _messageController.text.trim().isNotEmpty ? const Color(0xFF22c55e) : Colors.white24,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Text Input
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e293b).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Speak or type your answer...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}), // Rebuild for playback button
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Send Button
              GestureDetector(
                onTap: _isTyping ? null : _sendMessage,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Bottom Hint
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: color,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Manuel mod: Cevabını gönder butonuyla yolla',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isBot;
  final String time;

  ChatMessage({
    required this.text,
    required this.isBot,
    required this.time,
  });
}

// Custom audio source for just_audio
class MyCustomSource extends StreamAudioSource {
  final Uint8List _buffer;
  
  MyCustomSource(this._buffer);
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

// Particles Painter for floating animation
class ParticlesPainter extends CustomPainter {
  final double animationValue;
  
  ParticlesPainter(this.animationValue);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0ea5e9).withOpacity(0.2)
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < 20; i++) {
      final x = (size.width * (0.1 + (i * 0.05) + animationValue * 0.1)) % size.width;
      final y = (size.height * (0.1 + (i * 0.04) + animationValue * 0.2)) % size.height;
      final radius = 1.0 + (i % 3);
      
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant ParticlesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
