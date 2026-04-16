
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// Helper class for audio output selection
class Helper {
  static Future<List<MediaDeviceInfo>> get audiooutputs =>
      navigator.mediaDevices.enumerateDevices().then((devices) => devices
          .where((d) => d.kind == 'audiooutput')
          .toList());

  static Future<void> selectAudioOutput(String deviceId) async {
    // Note: selectAudioOutput functionality might vary by platform/plugin version
    // This is a placeholder for the actual implementation if supported by flutter_webrtc
    if (!kIsWeb) {
      // Android/iOS specific helper might be needed here, or use the plugin's method if available
      Helper.setSpeakerphoneOn(true); 
    }
  }

  static Future<void> setSpeakerphoneOn(bool enable) async {
     // Basic implementation using the stream's audio tracks or a platform channel
     // For flutter_webrtc, often we rely on the OS default or simple toggle
     // But let's assume standard behavior helper if available or we just use tracks.
     // In many flutter_webrtc examples, this is handled by a specific plugin or channel.
     // For this code, we'll assume the intention is to toggle audio routing.
  }
}

class VideoCallPage extends StatefulWidget {
  final io.Socket socket;
  final String roomId;
  final String matchedUserId;
  final String? role; // 'caller' or 'callee'
  final String currentUserId;

  const VideoCallPage({
    super.key,
    required this.socket,
    required this.roomId,
    required this.matchedUserId,
    required this.currentUserId,
    this.role,
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> with TickerProviderStateMixin {
  // --- Animation Controllers ---
  late AnimationController _pulseController; // Connecting radar efekti için

  // --- State Variables ---
  bool _isVideoEnabled = true;
  bool _isAudioEnabled = true;
  bool _isSpeakerOn = true;
  bool _isRemoteVideoReady = false;
  
  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isLocalRendererInitialized = false;
  
  Timer? _statsTimer;
  
  // UI States
  bool _isReady = false; 
  bool _showTranscript = false;
  bool _showEmojiPicker = false;
  final List<_FloatingEmoji> _floatingEmojis = [];
  
  // Demo Transkript
  final List<Map<String, dynamic>> _transcriptData = [
    {'sender': 'Alex Johnson', 'text': 'Hello! How are you today?', 'time': '00:05', 'score': 95},
    {'sender': 'You', 'text': 'Hi! I\'m doing great, thanks for asking.', 'time': '00:08', 'score': 92},
    {'sender': 'Alex Johnson', 'text': 'That\'s wonderful! What would you like to talk about?', 'time': '00:12', 'score': 97},
  ];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WakelockPlus.enable();
    }
    
    // Pulse Animasyonu (Connecting Ekranı İçin)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // 3 Saniyelik Hazırlık Simülasyonu
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isReady = true);
    });

    _initializeWebRTC();
    
    // Hoparlörü zorla açmayı dene (Basit timer ile)
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
       if (_isLocalRendererInitialized && _isSpeakerOn) {
          // Helper.setSpeakerphoneOn(true); // Platform specific, şimdilik pasif
       }
    });
  }
  
  // Loglama
  void _log(String message) {
    debugPrint(message);
  }

  // --- WebRTC Logic (Öncekiyle Aynı, kısalttım) ---
  Future<void> _initializeWebRTC() async {
    await [Permission.camera, Permission.microphone].request();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) setState(() => _isLocalRendererInitialized = true);

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    
    _peerConnection = await createPeerConnection(config, {});

    // Media Constraints
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640}, // Kaliteyi biraz artırdım
        'height': {'ideal': 480},
        'frameRate': {'ideal': 24},
      }
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      if (mounted) setState(() => _localRenderer.srcObject = _localStream);
    } catch (e) {
      _log("Media Error: $e");
    }

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        if (mounted) {
           setState(() {
             _remoteStream = event.streams[0];
             _remoteRenderer.srcObject = _remoteStream;
             _isRemoteVideoReady = true;
           });
        }
      }
    };
    
    _peerConnection!.onIceCandidate = (candidate) {
       widget.socket.emit('webrtc_ice_candidate', {
             'roomId': widget.roomId,
             'candidate': candidate.candidate,
             'sdpMLineIndex': candidate.sdpMLineIndex,
             'sdpMid': candidate.sdpMid,
       });
    };
    
    _peerConnection!.onConnectionState = (_) {};
    
    _setupSocketListeners();
    widget.socket.emit('join_room', {'roomId': widget.roomId});

    if (widget.role == 'caller') {
      await Future.delayed(const Duration(seconds: 1));
      var offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      widget.socket.emit('webrtc_offer', {'roomId': widget.roomId, 'offer': {'sdp': offer.sdp, 'type': offer.type}});
    }
  }

  void _setupSocketListeners() {
    widget.socket.on('webrtc_offer', (data) async {
       if (data['from'] == widget.currentUserId) return;
       var offer = data['offer'];
       await _peerConnection!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
       var answer = await _peerConnection!.createAnswer();
       await _peerConnection!.setLocalDescription(answer);
       widget.socket.emit('webrtc_answer', {'roomId': widget.roomId, 'answer': {'sdp': answer.sdp, 'type': answer.type}});
    });

    widget.socket.on('webrtc_answer', (data) async {
       if (data['from'] == widget.currentUserId) return;
       var answer = data['answer'];
       await _peerConnection!.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
    });

    widget.socket.on('webrtc_ice_candidate', (data) async {
       if (data['from'] == widget.currentUserId) return;
       var candidate = RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']);
       await _peerConnection!.addCandidate(candidate);
    });
    
    widget.socket.on('call_ended', (_) => _endCall(remote: true));
  }
  
  void _endCall({bool remote = false}) {
     if (!remote) widget.socket.emit('end_call', {'roomId': widget.roomId});
     _pulseController.dispose();
     _peerConnection?.close();
     _localStream?.dispose();
     _localRenderer.dispose();
     _remoteRenderer.dispose();
     if (!kIsWeb) WakelockPlus.disable();
     if (mounted) Navigator.pop(context);
  }
  
  void _toggleMic() {
    setState(() {
      _isAudioEnabled = !_isAudioEnabled;
      _localStream?.getAudioTracks().forEach((track) => track.enabled = _isAudioEnabled);
    });
  }

  void _toggleCam() {
    setState(() {
      _isVideoEnabled = !_isVideoEnabled;
      _localStream?.getVideoTracks().forEach((track) => track.enabled = _isVideoEnabled);
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
      // Audio switch logic
    });
  }

  void _addFloatingEmojis(String emoji) {
    setState(() => _showEmojiPicker = false);
    for (int i = 0; i < 8; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (!mounted) return;
        final id = DateTime.now().microsecondsSinceEpoch.toString() + i.toString();
        setState(() {
          _floatingEmojis.add(_FloatingEmoji(
            id: id,
            emoji: emoji,
            // Alt barın hemen üzerinden başlasın (ekranın %80'i gibi)
            startTop: MediaQuery.of(context).size.height * 0.75 + (i % 2 == 0 ? 0 : 30), 
          ));
        });
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _floatingEmojis.removeWhere((e) => e.id == id));
        });
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statsTimer?.cancel();
    if (!kIsWeb) WakelockPlus.disable();
    _localStream?.dispose();
    _peerConnection?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // Uzak Video Kontrolü
    bool isRemoteVideoActive = _isRemoteVideoReady &&
        _remoteRenderer.srcObject != null &&
        _remoteRenderer.srcObject!.getVideoTracks().isNotEmpty &&
        _remoteRenderer.srcObject!.getVideoTracks().last.enabled;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1026), // REFERANS GÖRSEL 2 ve 3'teki Derin Lacivert
      body: Stack(
        fit: StackFit.expand,
        children: [
          
          // --- KATMAN 0: ARKA PLAN ---
          // Eğer görüşme hazırsa ve video/avatar modu varsa
          if (_isReady) ...[
             if (isRemoteVideoActive && !_showTranscript)
               Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
             else
               _buildDeepSpaceBackground(), // Avatar Modu Arka Planı
          ]
          else 
            _buildDeepSpaceBackground(), // Connecting Ekranı Arka Planı

          // --- KATMAN 1: ANA İÇERİK ---
          if (_isReady) ...[
             if (_showTranscript)
               Positioned.fill(
                 top: 100, 
                 bottom: 150, 
                 child: _buildTranscriptList(),
               )
             else if (!isRemoteVideoActive)
               // AVATAR MODU (REFERANS Image 3)
               Positioned(
                 top: size.height * 0.25,
                 left: 0, 
                 right: 0,
                 child: _buildAvatarMode(),
               ),
          ] else 
            // CONNECTING MODU (REFERANS Image 2)
            Positioned.fill(
              child: _buildConnectingAnimation(),
            ),



          // --- KATMAN 3: ÜST DIV (HEADER) ---
          if (_isReady)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopDiv(),
            ),

          // --- KATMAN 4: EMOJİLER ---
          ..._floatingEmojis.map((e) => _buildAnimatedEmoji(e)),

          // --- KATMAN 5: ALT DIV (FOOTER) ---
          if (_isReady)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomDiv(),
            ),

          // --- KATMAN 6: TRANSKRİPT BUTONU ---
          // Alt div'in biraz daha üzerinde
          if (_isReady && !_showTranscript)
            Positioned(
              bottom: 155, // Alt panele daha yakın, hizalı
              left: 20,
              child: _buildTranscriptButton(),
            ),

          // --- KATMAN 2: PIP (SEN) --- 
          // Üst barın altında kalmayacak şekilde aşağı çekildi
          if (_isReady)
            Positioned(
              right: 20,
              top: 140, // Üst menüden yeterince uzak
              child: _buildStylishPip(),
            ),
        ],
      ),
    );
  }
  
  // --- YENİ UI BİLEŞENLERİ ---

  Widget _buildTopDiv() {
    return Container(
      // Padding azaltıldı, daha ince bir üst bar
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 5, bottom: 10, left: 16, right: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.9), 
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.arrow_back, color: Colors.white)),
           Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               const Text("Alex Johnson", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
               const SizedBox(height: 2), // Boşluk azaltıldı
               Row(
                 children: [
                   Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                   const SizedBox(width: 6),
                   const Text("00:15", style: TextStyle(color: Colors.white70, fontSize: 12)),
                 ],
               ),
             ],
           ),
           const Icon(Icons.settings, color: Colors.transparent),
        ],
      ),
    );
  }

  Widget _buildBottomDiv() {
    return Container(
      // Paddingler azaltıldı, menü daha kompakt
      padding: const EdgeInsets.only(top: 15, bottom: 20, left: 20, right: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           if (_showEmojiPicker) ...[
             _buildEmojiPicker(),
             const SizedBox(height: 10), // Boşluk azaltıldı
           ],
           _buildControlPanel(),
           const SizedBox(height: 10), // Boşluk azaltıldı
           const Row(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
                Text("Practice your English with native speakers", style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12)),
                SizedBox(width: 5),
                Icon(Icons.school, color: Color(0xFF3B82F6), size: 14)
             ],
           )
        ],
      ),
    );
  }

  // Eski TopBar fonksiyonunu siliyoruz çünkü _buildTopDiv ile değiştirdik.
  // Eski background ve connecting animasyon fonksiyonları burada kalıyor.
  
  Widget _buildDeepSpaceBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3), // Hafif yukarı odaklı
          radius: 1.2,
          colors: [
             Color(0xFF1E3A8A), // Orta Mavilik
             Color(0xFF0B1026), // Çok Koyu Lacivert (Kenarlar)
          ],
        ),
      ),
      child: Stack(
        children: [
           // Parçacık Efektleri (Yıldızlar)
           ...List.generate(30, (index) => Positioned(
              left: (index * 37) % 400.0,
              top: (index * 91) % 800.0,
              child: Container(
                width: index % 3 == 0 ? 3 : 2,
                height: index % 3 == 0 ? 3 : 2,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(index % 5 == 0 ? 0.8 : 0.3),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 4)]
                ),
              )
           ))
        ],
      ),
    );
  }

  // REFERENCE IMAGE 2: CONNECTING ANIMASYONU
  Widget _buildConnectingAnimation() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
               // Dış Halkalar (Pulse)
               ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      double value = (_pulseController.value + index * 0.35) % 1.0;
                      return Opacity(
                        opacity: (1 - value) * 0.5,
                        child: Container(
                          width: 100 + (value * 150),
                          height: 100 + (value * 150),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 1.5),
                          ),
                        ),
                      );
                    },
                  );
               }),
               // Merkez Daire
               Container(
                 width: 100,
                 height: 100,
                 decoration: BoxDecoration(
                   shape: BoxShape.circle,
                   gradient: const LinearGradient(
                     begin: Alignment.topLeft,
                     end: Alignment.bottomRight,
                     colors: [Color(0xFF38BDF8), Color(0xFF2563EB)]
                   ),
                   boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.6), blurRadius: 20, spreadRadius: 5)],
                 ),
                 child: const Icon(Icons.sensors, color: Colors.white, size: 50),
               ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Text("Connecting to User ${widget.matchedUserId.substring(0, 5)}...", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text("Please wait a moment", style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
      ],
    );
  }

  // REFERENCE IMAGE 3: AVATAR MODU
  Widget _buildAvatarMode() {
    return Column(
      children: [
        // Büyük Profil Resmi
        Container(
          width: 160,
          height: 160,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
             shape: BoxShape.circle,
             gradient: LinearGradient(
               colors: [Colors.blue.withOpacity(0.2), Colors.transparent], 
               begin: Alignment.topCenter, end: Alignment.bottomCenter
             ),
          ),
          child: Container(
             decoration: const BoxDecoration(
               shape: BoxShape.circle,
               gradient: LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF2563EB)]), // Mavi Gradient
             ),
             child: const Icon(Icons.person, color: Colors.white, size: 80),
          ),
        ),
        const SizedBox(height: 20),
        const Text("Alex Johnson", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("Speaking English with you", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 16)),
      ],
    );
  }

  // REFERENCE IMAGE 3 & 4: STYLISH PIP
  Widget _buildStylishPip() {
    return Container(
      width: 90,
      height: 130, // Biraz daha uzun dikdörtgen, referans görseldeki gibi
      decoration: BoxDecoration(
        gradient: const LinearGradient(
           begin: Alignment.topCenter,
           end: Alignment.bottomCenter,
           colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)], // Canlı mavi gradient
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _isLocalRendererInitialized && _isVideoEnabled
                ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : const Center(child: Icon(Icons.person_outline, color: Colors.white70, size: 40)), // Video yoksa ikon
            
            // "Sen" etiketi
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text("Sen", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TRANSCRIPT TASARIMI (Sohbet Balonu Tarzı)
  Widget _buildTranscriptList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _transcriptData.length,
      itemBuilder: (context, index) {
        final item = _transcriptData[index];
        final isMe = item['sender'] == 'You';
        return Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
               // İsim ve Süre
               Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                    Text(item['sender'], style: TextStyle(color: isMe ? const Color(0xFF38BDF8) : const Color(0xFFA5B4FC), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 5),
                    Text(item['time'], style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                 ],
               ),
               const SizedBox(height: 4),
               // Balon
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: isMe ? const Color(0xFF0F4C75).withOpacity(0.8) : const Color(0xFF323F68).withOpacity(0.8),
                   borderRadius: BorderRadius.only(
                     topLeft: const Radius.circular(12),
                     topRight: const Radius.circular(12),
                     bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                     bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                   ),
                   border: Border.all(color: Colors.white.withOpacity(0.1)),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      Text(item['text'], style: const TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 6),
                      // Skor Barı
                      Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           SizedBox(
                             width: 100, height: 4, 
                             child: LinearProgressIndicator(
                               value: item['score'] / 100, 
                               backgroundColor: Colors.white10, 
                               color: isMe ? Colors.cyanAccent : Colors.greenAccent
                             ),
                           ),
                           const SizedBox(width: 5),
                           Text("${item['score']}%", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
                         ],
                      )
                   ],
                 ),
               ),
            ],
          ),
        );
      },
    );
  }

  // --- Transkript Butonu (Referans Image 2) ---
  Widget _buildTranscriptButton() {
    return GestureDetector(
      onTap: () => setState(() => _showTranscript = !_showTranscript),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF0EA5E9)], // Mor -> Mavi
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text("Transkript", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
         _buildDataCircleBtn(Icons.emoji_emotions_outlined, false, () => setState(() => _showEmojiPicker = !_showEmojiPicker)),
         _buildDataCircleBtn(_isAudioEnabled ? Icons.mic : Icons.mic_off, !_isAudioEnabled, _toggleMic),
         // Büyük Kırmızı Kapatma Butonu
         GestureDetector(
            onTap: () => _endCall(),
            child: Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.5), blurRadius: 15, spreadRadius: 4)],
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 32),
            ),
         ),
         _buildDataCircleBtn(_isVideoEnabled ? Icons.videocam : Icons.videocam_off, !_isVideoEnabled, _toggleCam),
         _buildDataCircleBtn(_isSpeakerOn ? Icons.volume_up : Icons.phone_in_talk, false, _toggleSpeaker),
      ],
    );
  }

  Widget _buildDataCircleBtn(IconData icon, bool isAlert, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
         width: 50, height: 50,
         decoration: BoxDecoration(
           color: isAlert ? Colors.white : const Color(0xFF1F2937).withOpacity(0.8),
           shape: BoxShape.circle,
           border: Border.all(color: Colors.white.withOpacity(0.1)),
         ),
         child: Icon(icon, color: isAlert ? Colors.black : Colors.white, size: 22),
      ),
    );
  }
  
  Widget _buildEmojiPicker() {
    final emojis = ['👍', '❤️', '😂', '😮', '👏', '🎉', '🔥'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: emojis.map((e) => GestureDetector(
          onTap: () => _addFloatingEmojis(e),
          child: Text(e, style: const TextStyle(fontSize: 24)),
        )).toList(),
      ),
    );
  }

  Widget _buildAnimatedEmoji(_FloatingEmoji emojiData) {
     return TweenAnimationBuilder<double>(
       tween: Tween(begin: -50.0, end: MediaQuery.of(context).size.width + 100),
       duration: const Duration(seconds: 4), 
       builder: (context, value, child) {
         return Positioned(
           left: value,
           top: emojiData.startTop, 
           child: Opacity(
             // Kenarlarda silikleşme
             opacity: (value < 50 || value > MediaQuery.of(context).size.width - 50) ? 0.0 : 0.6,
             child: Text(emojiData.emoji, style: const TextStyle(fontSize: 28)),
           ),
         );
       },
     );
  }
}

// Yardımcı Sınıf
class _FloatingEmoji {
  final String id;
  final String emoji;
  final double startTop;
  _FloatingEmoji({required this.id, required this.emoji, required this.startTop});
}
