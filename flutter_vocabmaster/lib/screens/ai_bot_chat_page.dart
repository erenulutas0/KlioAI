import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/animated_background.dart';
import '../widgets/voice_selection_modal.dart';
import '../services/chatbot_service.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/piper_tts_service.dart';
import '../models/voice_model.dart';

class AIBotChatPage extends StatefulWidget {
  final String? initialScenario;
  final String? initialScenarioName;
  final String? scenarioContext; // Kullanıcının girdiği konu/bağlam
  
  const AIBotChatPage({
    Key? key,
    this.initialScenario,
    this.initialScenarioName,
    this.scenarioContext,
  }) : super(key: key);

  @override
  State<AIBotChatPage> createState() => _AIBotChatPageState();
}

class _AIBotChatPageState extends State<AIBotChatPage> with TickerProviderStateMixin {
  static const List<String> _disagreementTopics = [
    "Strict Office Attendance Policy vs Remote Work",
    "Budget Cuts for Team Building Events",
    "Switching to a New Project Management Tool",
    "Delaying the Product Launch for Polish",
    "Hiring a Junior vs Senior Developer",
    "Changing the Brand Color Scheme",
    "Mandatory Overtime to Meet Deadlines",
  ];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ChatbotService _chatbotService = ChatbotService();
  final PiperTtsService _ttsService = PiperTtsService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts(); // Fallback TTS
  
  bool _isTyping = false;
  bool _isSpeaking = false;
  bool _ttsEnabled = true;
  bool _ttsAvailable = false;
  
  // STT
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _continuousListening = false; // Persistent session state
  bool _autoSendMode = true; // true = auto send on silence, false = manual send
  bool _blurBotMessages = false; // Blur bot messages for listening practice
  
  // Seçili konuşmacı
  VoiceModel? _selectedVoice;
  bool _isFirstVisit = true;
  
  // Aktif senaryo (profesyonel konuşma pratiği için)
  String? _activeScenario;
  String? _activeScenarioName;
  String? _activeScenarioContext;
  
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
    
    // Keep screen on while in chat
    WakelockPlus.enable();
    
    _checkTtsAvailability();
    _initFlutterTts(); // Fallback TTS hazırla
    _loadSelectedVoice();
    
    // Eğer senaryo ile açıldıysa, senaryoyu başlat
    if (widget.initialScenario != null && widget.initialScenarioName != null) {
      _activeScenario = widget.initialScenario;
      _activeScenarioName = widget.initialScenarioName;
      _activeScenarioContext = widget.scenarioContext;
      
      // Eğer disagreement ise ve context yoksa, rastgele seç
      if (_activeScenario == 'disagreement_colleague' && (_activeScenarioContext == null || _activeScenarioContext!.isEmpty)) {
        _activeScenarioContext = _disagreementTopics[DateTime.now().millisecond % _disagreementTopics.length];
      }
      
      // Senaryo başlangıç mesajını biraz geciktir (TTS hazır olsun)
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _sendScenarioWelcomeMessage(widget.initialScenario!);
        }
      });
    }
  }

  /// Senaryo bazlı karşılama mesajı gönder
  void _sendScenarioWelcomeMessage(String scenarioId) {
    String welcomeMessage;
    final contextText = _activeScenarioContext;

    switch (scenarioId) {
      case 'job_interview_followup':
        if (contextText != null && contextText.isNotEmpty) {
           welcomeMessage = "Hi there! I see you're following up on your interview for the '$contextText' position. It's good to hear from you. How are you feeling about how it went?";
        } else {
           welcomeMessage = "Hi there! This is Sarah from HR. Thanks for reaching out. Could you remind me which position you applied for so I can pull up your file?";
        }
        break;
      case 'academic_presentation_qa':
        if (contextText != null && contextText.isNotEmpty) {
          welcomeMessage = "Thank you for that presentation on '$contextText'. I'm Dr. Johnson. I found your topic interesting, but I have a few questions about your methodology. Shall we dive in?";
        } else {
          welcomeMessage = "Thank you for that presentation. I'm Dr. Johnson. Before I ask my questions, could you briefly summarize the core thesis of your work again for the audience?";
        }
        break;
      case 'disagreement_colleague':
        // Disagreement is dynamic, so generic opening is better, prompt will handle the rest
        welcomeMessage = "Hey, I got your email about the project. Look, I respect your opinion, but there's a serious issue we need to discuss. Can we talk?";
        break;
      case 'explaining_to_manager':
        if (contextText != null && contextText.isNotEmpty) {
           welcomeMessage = "I have 10 minutes before my next meeting. You wanted to discuss '$contextText'? Go ahead, explain the situation clearly. I'm listening.";
        } else {
           welcomeMessage = "I have 10 minutes before my next meeting. You wanted to discuss an urgent matter with me? Go ahead, what is the specific issue?";
        }
        break;
      default:
        welcomeMessage = "Hello! Let's practice English together. What would you like to talk about?";
    }
    _addBotMessage(welcomeMessage, speak: true);
  }

  Future<void> _initFlutterTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true); // Konuşma bitmesini bekle
  }

  /// Kaydedilmiş konuşmacıyı yükle
  Future<void> _loadSelectedVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceJson = prefs.getString('selected_voice');
      final hasVisited = prefs.getBool('voice_modal_shown') ?? false;
      
      if (voiceJson != null) {
        setState(() {
          _selectedVoice = VoiceModel.fromJsonString(voiceJson);
          _isFirstVisit = false;
        });
      } else {
        _isFirstVisit = !hasVisited;
        
    // İlk ziyarette modal göster
        if (_isFirstVisit && mounted) {
          Future.delayed(const Duration(milliseconds: 800), _showVoiceSelectionModal);
        } else {
           // Zaten seçiliyse standart hoşgeldin mesajı
           if (_messages.isEmpty) {
             _addBotMessage(
              'Tekrar merhaba! Ben ${_selectedVoice?.name ?? 'AI Bot'}. İngilizce pratiğine kaldığımız yerden devam edelim mi? 👋',
             );
           }
        }
      }
    } catch (e) {
      debugPrint('Load voice error: $e');
    }
  }

  /// Konuşmacı seçim modalını göster
  Future<void> _showVoiceSelectionModal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_modal_shown', true);
    
    if (!mounted) return;
    
    final voice = await VoiceSelectionModal.show(
      context,
      currentVoice: _selectedVoice,
    );
    
    if (!mounted) return;

    if (voice != null) {
      // Ses değiştiyse sohbeti sıfırla
      if (_selectedVoice?.id != voice.id) {
         setState(() {
           _selectedVoice = voice;
           _messages.clear(); // Sohbeti temizle
         });
         
         // Yeni karakterin hoşgeldin mesajı
         _addBotMessage(
           'Selam! Ben ${voice.name}. Seninle ${voice.accent} aksanıyla konuşacağım için çok heyecanlıyım! Hadi başlayalım. 🚀',
           speak: true,
         );
      }
    } else {
      // Seçim yapmadan kapattıysa
      if (_selectedVoice == null) {
        // Eğer hiç ses seçili değilse sayfadan at (Zorunlu seçim)
        Navigator.pop(context); 
      }
    }
  }

  Future<void> _checkTtsAvailability() async {
    final available = await _ttsService.isAvailable();
    if (mounted) {
      setState(() => _ttsAvailable = available);
    }
  }

  @override
  void dispose() {
    // Disable wakelock when leaving
    WakelockPlus.disable();
    _messageController.dispose();
    _scrollController.dispose();
    _particleController.dispose();
    _audioPlayer.dispose();
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
    
    // TTS ile seslendir
    if (speak && _ttsEnabled) {
      _speakText(text);
    }
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
       // Önceki konuşmayı durdur
       await _audioPlayer.stop();
       await _flutterTts.stop();
    }
    
    // TTS başlamadan önce mikrofonu kesin olarak kapat
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
    
    setState(() => _isSpeaking = true);
    
    try {
      // Seçili konuşmacının sesini kullan
      final voiceName = _selectedVoice?.piperVoice ?? 'amy';
      
      // 1. Önce Piper TTS dene
      Uint8List? audioData;
      
      // Sadece Piper available ise API çağrısı yap, yoksa direkt fallback'e geç
      if (_ttsAvailable) {
        try {
           audioData = await _ttsService.synthesize(text, voice: voiceName);
        } catch (e) {
          debugPrint('Piper synthesize error: $e');
        }
      }

      if (audioData != null && mounted) {
        // Uint8List'i AudioSource'a çevir
        // File playback (Daha güvenli)
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/chat_response.wav');
        await tempFile.writeAsBytes(audioData);
        
        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.play();
        
        // Bitmesini bekle
        await _audioPlayer.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed
        );
        
      } else {
        // 2. Fallback: Flutter TTS (System)
        debugPrint('Main Chat: Piper başarısız, System TTS kullanılıyor.');
        if (_selectedVoice != null) {
           String locale = _selectedVoice!.locale.replaceAll('_', '-');
           await _flutterTts.setLanguage(locale);
           // Pitch ayarı
           if (_selectedVoice!.gender == 'female') {
              await _flutterTts.setPitch(1.1);
           } else {
              await _flutterTts.setPitch(0.9);
           }
        }
        await _flutterTts.speak(text);
        // awaitSpeakCompletion(true) olduğu için burada bekler
      }
      
    } catch (e) {
      debugPrint('TTS error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSpeaking = false);
        // Continue loop if session is active
        if (_continuousListening && !_isListening) {
          // Short delay to avoid clipping
          Future.delayed(const Duration(milliseconds: 500), _startListening);
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
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
      // Backend'den gerçek AI yanıtı al (senaryo varsa ilet)
      final response = await _chatbotService.chat(
        userMessage, 
        scenario: _activeScenario,
        scenarioContext: _activeScenarioContext,
      );
      
      if (mounted) {
        setState(() => _isTyping = false);
        _addBotMessage(response, speak: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTyping = false);
        if (e is ApiQuotaExceededException) {
          _addBotMessage(AiErrorMessageFormatter.forQuota(e));
          return;
        }

        final errorText = e.toString();
        // User-friendly connection error message
        String errorMsg =
            'Bağlantı hatası. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        if (errorText.contains('SocketException') ||
            errorText.contains('Failed host lookup')) {
          errorMsg = 'İnternet bağlantısı yok. WiFi veya mobil veriyi kontrol et!';
        } else if (errorText.contains('TimeoutException')) {
          errorMsg = 'Sunucu yanıt vermiyor. Biraz sonra tekrar dene!';
        }
        _addBotMessage(errorMsg);
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

  /// Mesajı göndermeden önce sesli dinle
  Future<void> _playbackUserMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (!_autoSendMode) {
      // Manuel modda playback özelliği aktif
      setState(() => _isSpeaking = true);
      try {
        await _flutterTts.speak(_messageController.text.trim());
      } catch (e) {
        debugPrint('Playback error: $e');
      } finally {
        if (mounted) setState(() => _isSpeaking = false);
      }
    }
  }

  /// Yeni sohbet başlat
  void _startNewChat() {
    if (_messages.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Yeni Sohbet', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Mevcut sohbeti temizleyip yeni bir konuşma başlamak istiyor musun?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.clear();
                _activeScenario = null;
                _activeScenarioName = null;
                _activeScenarioContext = null;
              });
              _addBotMessage('Yeni bir sohbete başladık! Seninle konuşmak güzel. 😊');
            },
            child: const Text('Evet', style: TextStyle(color: Color(0xFF0ea5e9))),
          ),
        ],
      ),
    );
  }

  /// Senaryo seçim modalı
  void _showScenarioModal() {
    final scenarios = [
      {
        'id': 'job_interview_followup',
        'name': 'Job Interview Follow-up',
        'subtitle': 'Mülakat Sonrası Takip',
        'icon': Icons.business_center,
        'color': const Color(0xFF8b5cf6),
        'welcomeMessage': "Hi there! This is Sarah from HR. Thanks for reaching out after your interview yesterday. How can I help you today?",
      },
      {
        'id': 'academic_presentation_qa',
        'name': 'Academic Presentation Q&A',
        'subtitle': 'Akademik Sunum Soru-Cevap',
        'icon': Icons.school,
        'color': const Color(0xFF0ea5e9),
        'welcomeMessage': "Thank you for that presentation. I'm Dr. Johnson. I have a few questions about your methodology. First, could you explain how you collected your data?",
      },
      {
        'id': 'disagreement_colleague',
        'name': 'Disagreement with Colleague',
        'subtitle': 'Meslektaşla Anlaşmazlık',
        'icon': Icons.people_outline,
        'color': const Color(0xFFf59e0b),
        'welcomeMessage': "Hey, I got your email about the project direction. Look, I respect your opinion, but I really think we should reconsider this approach. What's your rationale here?",
      },
      {
        'id': 'explaining_to_manager',
        'name': 'Explaining to Manager',
        'subtitle': 'Yöneticiye Açıklama',
        'icon': Icons.person_outline,
        'color': const Color(0xFF10b981),
        'welcomeMessage': "I have 10 minutes before my next meeting. You wanted to discuss something with me? Go ahead, what is it?",
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1e293b),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0ea5e9).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.theater_comedy, color: Color(0xFF0ea5e9), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Konuşma Senaryosu Seç',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Profesyonel durumları pratik edin',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Current scenario indicator
            if (_activeScenario != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF22c55e).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF22c55e), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Aktif: $_activeScenarioName',
                      style: const TextStyle(color: Color(0xFF22c55e), fontSize: 12),
                    ),
                  ],
                ),
              ),
            
            // Scenario cards
            ...scenarios.map((scenario) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _startScenario(
                      scenario['id'] as String,
                      scenario['name'] as String,
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (scenario['color'] as Color).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _activeScenario == scenario['id']
                            ? (scenario['color'] as Color)
                            : (scenario['color'] as Color).withOpacity(0.3),
                        width: _activeScenario == scenario['id'] ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (scenario['color'] as Color).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            scenario['icon'] as IconData,
                            color: scenario['color'] as Color,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scenario['name'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                scenario['subtitle'] as String,
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: (scenario['color'] as Color).withOpacity(0.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )),
            
            const Divider(color: Colors.white12, height: 24),
            
            // Free chat option
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _exitScenario();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _activeScenario == null
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white.withOpacity(0.1),
                      width: _activeScenario == null ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.chat_bubble_outline, color: Colors.white70, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Serbest Sohbet',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Normal konuşma pratiği',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (_activeScenario == null)
                        const Icon(Icons.check_circle, color: Color(0xFF22c55e), size: 20),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Senaryo başlat
  void _startScenario(String scenarioId, String scenarioName) {
    String? contextText;
    if (scenarioId == 'disagreement_colleague') {
      contextText = _disagreementTopics[DateTime.now().millisecond % _disagreementTopics.length];
    }

    setState(() {
      _messages.clear();
      _activeScenario = scenarioId;
      _activeScenarioName = scenarioName;
      _activeScenarioContext = contextText;
    });
    
    // Senaryo başlangıç mesajı (Context'e göre dinamik olabilir)
    _sendScenarioWelcomeMessage(scenarioId);
    
    // Bilgi mesajı
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.theater_comedy, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('$scenarioName senaryosu başladı!')),
          ],
        ),
        backgroundColor: const Color(0xFF8b5cf6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Senaryodan çık
  void _exitScenario() {
    if (_activeScenario == null) return;
    
    setState(() {
      _messages.clear();
      _activeScenario = null;
      _activeScenarioName = null;
      _activeScenarioContext = null;
    });
    
    _addBotMessage(
      'Serbest sohbete döndük! Ben ${_selectedVoice?.name ?? 'Amy'}. Ne hakkında konuşmak istersin? 😊',
      speak: true,
    );
  }

  /// Sohbeti kaydet
  Future<void> _saveConversation() async {
    if (_messages.isEmpty) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Existing conversations
      final existingJson = prefs.getString('saved_conversations') ?? '[]';
      final List<dynamic> conversations = jsonDecode(existingJson);
      
      // Create new conversation object
      final newConversation = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'date': DateTime.now().toIso8601String(),
        'voiceName': _selectedVoice?.name ?? 'AI Bot',
        'messageCount': _messages.length,
        'messages': _messages.map((m) => {
          'text': m.text,
          'isBot': m.isBot,
          'time': m.time,
        }).toList(),
      };
      
      conversations.insert(0, newConversation);
      
      // Keep only last 3 conversations
      if (conversations.length > 3) {
        conversations.removeRange(3, conversations.length);
      }
      
      await prefs.setString('saved_conversations', jsonEncode(conversations));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sohbet kaydedildi! ✓'),
            backgroundColor: Color(0xFF22c55e),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Sohbet geçmişini göster
  Future<void> _showConversationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final existingJson = prefs.getString('saved_conversations') ?? '[]';
    final List<dynamic> conversations = jsonDecode(existingJson);
    
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1e293b),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Color(0xFF0ea5e9)),
                  const SizedBox(width: 12),
                  const Text(
                    'Sohbet Geçmişi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${conversations.length} sohbet',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12),
            // List
            Expanded(
              child: conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'Henüz kayıtlı sohbet yok.\nBir sohbeti kaydetmek için 💾 butonuna bas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: conversations.length,
                      itemBuilder: (_, index) {
                        final conv = conversations[index];
                        final date = DateTime.tryParse(conv['date'] ?? '') ?? DateTime.now();
                        final messages = conv['messages'] as List<dynamic>? ?? [];
                        final firstUserMsg = messages.firstWhere(
                          (m) => m['isBot'] == false,
                          orElse: () => {'text': 'Sohbet'},
                        );
                        
                        return Dismissible(
                          key: Key(conv['id'].toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _deleteConversation(conv['id'].toString()),
                          child: Card(
                            color: const Color(0xFF0f172a),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0ea5e9),
                                child: Text(
                                  conv['voiceName']?[0] ?? 'A',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                (firstUserMsg['text'] as String).length > 40
                                    ? '${(firstUserMsg['text'] as String).substring(0, 40)}...'
                                    : firstUserMsg['text'],
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                '${conv['voiceName']} • ${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')} • ${conv['messageCount']} mesaj',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                              onTap: () {
                                Navigator.pop(ctx);
                                _loadConversation(conv);
                              },
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

  /// Sohbeti yükle
  void _loadConversation(Map<String, dynamic> conv) {
    final messages = conv['messages'] as List<dynamic>? ?? [];
    
    setState(() {
      _messages.clear();
      for (final m in messages) {
        _messages.add(ChatMessage(
          text: m['text'] ?? '',
          isBot: m['isBot'] ?? false,
          time: m['time'] ?? '',
        ));
      }
    });
    
    _scrollToBottom();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${conv['voiceName']} ile sohbet yüklendi'),
        backgroundColor: const Color(0xFF0ea5e9),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Sohbeti sil
  Future<void> _deleteConversation(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existingJson = prefs.getString('saved_conversations') ?? '[]';
    final List<dynamic> conversations = jsonDecode(existingJson);
    
    conversations.removeWhere((c) => c['id'].toString() == id);
    await prefs.setString('saved_conversations', jsonEncode(conversations));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sohbet silindi'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                _buildAppBar(),
                
                // Messages List
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) {
                        return _buildTypingIndicator();
                      }
                      return _buildMessageBubble(_messages[index], index);
                    },
                  ),
                ),
                
                // Input Area
                _buildInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _startListening() async {
    // Request permission first
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mikrofon izni gerekli.')));
      return;
    }

    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
             // If stopped automatically (silence or timeout)
             if (mounted && _isListening) {
               // Only auto-send if autoSendMode is on
               if (_autoSendMode) {
                 _stopAndSend(manual: false);
               } else {
                 // Manual mode: just stop listening, don't send
                 setState(() => _isListening = false);
               }
             }
          }
        },
        onError: (val) => debugPrint('STT Error: $val'),
      );
      if (available) {
        if(mounted) setState(() {
          _isListening = true;
          // Only set true, don't reset to false here unless manual stop?
          // Actually, if we start, we assume continuous unless told otherwise?
          // Let's set it true here to ensure loop starts/continues.
          _continuousListening = true; 
        });
        _speech.listen(
          onResult: (val) {
            setState(() {
              _messageController.text = val.recognizedWords;
            });
          },
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 5), // Wait 5 seconds of silence
          localeId: 'en_US',
        );
      } else {
        if(mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ses algılama başlatılamadı.')),
           );
        }
      }
    }
  }

  void _stopAndSend({bool manual = false}) {
    if (_isListening) {
      _speech.stop();
      if(mounted) {
        setState(() {
          _isListening = false;
          if (manual) _continuousListening = false;
        });
        // Delay slightly to ensure final result is captured
        Future.delayed(const Duration(milliseconds: 500), () {
           if (_messageController.text.trim().isNotEmpty) {
             _sendMessage();
           }
        });
      }
    }
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          
          // Bot Avatar - Eğer konuşmacı seçiliyse avatarını göster
          if (_selectedVoice != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: _selectedVoice!.avatarUrl,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0ea5e9), Color(0xFF06b6d4)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _selectedVoice!.name[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0ea5e9), Color(0xFF06b6d4)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _selectedVoice!.name[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0ea5e9), Color(0xFF06b6d4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0ea5e9).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
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
                  _selectedVoice?.name ?? 'AI Bot',
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
                    Expanded(
                      child: Text(
                        _activeScenario != null
                            ? '$_activeScenarioName'
                            : (_selectedVoice != null
                                ? '${_selectedVoice!.accent} • Sohbete hazır'
                                : (_ttsAvailable ? 'Online - Sesli cevap aktif' : 'Online - Ready to chat')),
                        style: TextStyle(
                          color: _activeScenario != null ? const Color(0xFF8b5cf6) : const Color(0xFF0ea5e9),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Popup Menu for extra actions
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            color: const Color(0xFF1e293b),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _startNewChat();
                  break;
                case 'save':
                  _saveConversation();
                  break;
                case 'history':
                  _showConversationHistory();
                  break;
                case 'voice':
                  _showVoiceSelectionModal();
                  break;
                case 'scenario':
                  _showScenarioModal();
                  break;
                case 'blur':
                  setState(() => _blurBotMessages = !_blurBotMessages);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: Colors.white54, size: 20),
                    SizedBox(width: 12),
                    Text('Yeni Sohbet', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'save',
                enabled: _messages.isNotEmpty,
                child: Row(
                  children: [
                    Icon(Icons.save_outlined, color: _messages.isNotEmpty ? Colors.white54 : Colors.white24, size: 20),
                    const SizedBox(width: 12),
                    Text('Sohbeti Kaydet', style: TextStyle(color: _messages.isNotEmpty ? Colors.white : Colors.white38)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history, color: Colors.white54, size: 20),
                    SizedBox(width: 12),
                    Text('Sohbet Geçmişi', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'voice',
                child: Row(
                  children: [
                    Icon(Icons.record_voice_over, color: Colors.white54, size: 20),
                    SizedBox(width: 12),
                    Text('Konuşmacı Değiştir', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'scenario',
                child: Row(
                  children: [
                    Icon(
                      Icons.theater_comedy,
                      color: _activeScenario != null ? const Color(0xFF8b5cf6) : Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _activeScenario != null ? 'Senaryo: $_activeScenarioName' : 'Senaryo Seç',
                      style: TextStyle(
                        color: _activeScenario != null ? const Color(0xFF8b5cf6) : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'blur',
                child: Row(
                  children: [
                    Icon(_blurBotMessages ? Icons.visibility : Icons.visibility_off, color: _blurBotMessages ? const Color(0xFF0ea5e9) : Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Text(_blurBotMessages ? 'Metni Göster' : 'Metni Gizle (Dinleme)', style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          
          // Sound Toggle
          IconButton(
            onPressed: () => setState(() => _ttsEnabled = !_ttsEnabled),
            icon: Icon(
              _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _ttsEnabled ? const Color(0xFF0ea5e9) : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, int index) {
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
                  if (_selectedVoice != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: _selectedVoice!.avatarUrl,
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0ea5e9), Color(0xFF06b6d4)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 14),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0ea5e9), Color(0xFF06b6d4)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.smart_toy_outlined,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedVoice?.name ?? 'AI Bot',
                    style: const TextStyle(
                      color: Color(0xFF0ea5e9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Speak button for bot messages
                  if (_ttsAvailable) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _speakText(message.text),
                      child: Icon(
                        _isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up,
                        color: const Color(0xFF0ea5e9),
                        size: 18,
                      ),
                    ),
                  ],
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
                  : const LinearGradient(
                      colors: [Color(0xFF0ea5e9), Color(0xFF0284c7)],
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(message.isBot ? 4 : 20),
                bottomRight: Radius.circular(message.isBot ? 20 : 4),
              ),
              border: message.isBot
                  ? Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.2))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: (message.isBot ? const Color(0xFF1e3a8a) : const Color(0xFF0ea5e9))
                      .withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Blur effect for bot messages when enabled
                if (message.isBot && _blurBotMessages)
                  GestureDetector(
                    onTap: () {
                      // Temporarily show text
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message.text),
                          duration: const Duration(seconds: 3),
                          backgroundColor: const Color(0xFF1e3a5f),
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        // Blurred text
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Text(
                            message.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ),
                        // Hint overlay
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.touch_app, color: Colors.white70, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Görmek için dokun',
                                    style: TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
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

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1e3a8a).withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (index * 200)),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF0ea5e9).withOpacity(0.6 + (value * 0.4)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
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
              // Mic Button (Voice Input)
              GestureDetector(
                  onTap: () {
                    if (_isListening) {
                      _stopAndSend(manual: true);
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
                    size: 22
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Playback Button (only in manual mode)
              if (!_autoSendMode)
                GestureDetector(
                  onTap: _messageController.text.trim().isNotEmpty ? _playbackUserMessage : null,
                  child: Container(
                    width: 40,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: _messageController.text.trim().isNotEmpty ? const Color(0xFF22c55e) : Colors.white24,
                      size: 22,
                    ),
                  ),
                ),
              if (!_autoSendMode) const SizedBox(width: 8),
              
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
                      hintText: 'Type your message in English...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}), // Rebuild for playback button visibility
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Send Button
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0ea5e9), Color(0xFF0284c7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0ea5e9).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _isTyping ? null : _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Voice Mode Toggle & Bottom Hint
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Auto/Manual Toggle
              GestureDetector(
                onTap: () => setState(() => _autoSendMode = !_autoSendMode),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _autoSendMode ? const Color(0xFF22c55e) : const Color(0xFFf59e0b),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _autoSendMode ? Icons.auto_mode : Icons.touch_app,
                        color: _autoSendMode ? const Color(0xFF22c55e) : const Color(0xFFf59e0b),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _autoSendMode ? 'Otomatik' : 'Manuel',
                        style: TextStyle(
                          color: _autoSendMode ? const Color(0xFF22c55e) : const Color(0xFFf59e0b),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _autoSendMode 
                    ? 'Sessizlikte otomatik gönderir' 
                    : 'Sen gönder butonuna bas',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
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
      ..color = const Color(0xFF0ea5e9).withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    // Draw floating particles
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
