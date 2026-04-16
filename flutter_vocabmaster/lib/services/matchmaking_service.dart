import 'package:flutter/foundation.dart';
import 'dart:async'; // Completer için gerekli
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

/// Eşleşme durumu
enum MatchStatus {
  idle,
  searching,
  matched,
  inCall,
  error,
}

/// Eşleşme bilgisi
class MatchInfo {
  final String roomId;
  final String matchedUserId;
  final String role; // 'caller' or 'callee'

  MatchInfo({
    required this.roomId,
    required this.matchedUserId,
    required this.role,
  });
}

/// Socket.IO ile eşleşme servisi
class MatchmakingService extends ChangeNotifier {
  io.Socket? _socket;
  MatchStatus _status = MatchStatus.idle;
  MatchInfo? _matchInfo;
  String? _userId;
  int _queueSize = 0;
  String? _errorMessage;
  int _waitingTimeSeconds = 0; // Bekleme süresi (saniye)
  Timer? _heartbeatTimer; // Heartbeat timer
  
  // Callback'ler
  Function(String message)? onQueueTimeout; // Kuyruk timeout callback
  
  // Socket.IO port (backend'de 9092 olarak tanımlı)
  static const int _socketPort = 9092;
  static const int _heartbeatIntervalMs = 5000; // 5 saniye

  MatchStatus get status => _status;
  MatchInfo? get matchInfo => _matchInfo;
  int get queueSize => _queueSize;
  String? get errorMessage => _errorMessage;
  int get waitingTimeSeconds => _waitingTimeSeconds;
  bool get isConnected => _socket?.connected ?? false;
  io.Socket? get socket => _socket;
  String? get userId => _userId;

  // Connection lock için
  Completer<void>? _connectionCompleter;


  /// Socket.IO'ya bağlan (Bağlantı kurulana kadar bekler)
  Future<void> connect() async {
    if (_socket != null && _socket!.connected) {
      debugPrint('MatchmakingService: Already connected');
      return;
    }

    // Eğer zaten bağlanmaya çalışıyorsa, o işlemi bekle
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      debugPrint('MatchmakingService: Already connecting, waiting...');
      return _connectionCompleter!.future;
    }

    _connectionCompleter = Completer<void>();

    try {
      final baseUrl = await AppConfig.baseUrl;
      final socketUrl = baseUrl.replaceFirst(RegExp(r':\d+'), ':$_socketPort');
      
      debugPrint('MatchmakingService: Connecting to $socketUrl');

      // Socket yoksa oluştur
      if (_socket == null) {
      _socket = io.io(socketUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'forceNew': true,
        'reconnection': true,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'reconnectionAttempts': 99,
        'timeout': 20000, // 20 saniye socket timeout
      });

      _setupEventListeners(); // Listener'ları bir kez ekle
      } else {
         // Varsa sadece connect de
      }

      // Bağlantı başarılı olduğunda completer'ı tamamla
      _socket!.once('connect', (_) {
        if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
           _connectionCompleter!.complete();
        }
      });
      
      // Hata durumunda da tamamla (Hata fırlatmak yerine)
      _socket!.once('connect_error', (err) {
         debugPrint('MatchmakingService: Connect Error via once: $err');
         if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
           // _connectionCompleter!.completeError(err); // Hata fırlatma, logla
           _connectionCompleter!.complete(); 
         }
      });

      _socket!.connect();
      
      // Timeout koruması (15 saniye)
      return _connectionCompleter!.future.timeout(const Duration(seconds: 15), onTimeout: () {
         debugPrint('MatchmakingService: Connection timed out');
         _status = MatchStatus.error;
         _errorMessage = 'Bağlantı zaman aşımı. Sunucuya ulaşılamıyor.';
         notifyListeners();
      });

    } catch (e) {
      debugPrint('MatchmakingService: Connection exception: $e');
      _status = MatchStatus.error;
      _errorMessage = 'Bağlantı hatası: $e';
      notifyListeners();
      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete();
      }
    }
  }

  // Listener kurulumunu ayrı tutuyoruz, connect içinde çağrılıyor ama socket null check var
  void _setupEventListeners() {
    if (_socket == null) return;
    
    // Eski listenerları temizle, duplicate olmasın
    _socket!.clearListeners();

    _socket!.onConnect((_) {
      debugPrint('MatchmakingService: Connected');
      _status = MatchStatus.idle;
      _errorMessage = null;
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      debugPrint('MatchmakingService: Disconnected');
      _status = MatchStatus.idle;
      _matchInfo = null;
      _stopHeartbeat(); // Heartbeat'i durdur
      notifyListeners();
    });

    _socket!.onConnectError((data) {
      debugPrint('MatchmakingService: Connect error: $data');
      // Her hatada UI'ı hemen bozmayalım, reconnect deneyecek
      // _status = MatchStatus.error; 
      // _errorMessage = 'Bağlantı hatası. Tekrar bağlanılıyor...';
      // notifyListeners();
    });

    // Kuyruk durumu (bekleme süresi dahil)
    _socket!.on('queue_status', (data) {
      debugPrint('MatchmakingService: Queue status: $data');
      _status = MatchStatus.searching;
      _queueSize = data['queueSize'] ?? 0;
      _waitingTimeSeconds = data['waitingTime'] ?? 0;
      notifyListeners();
    });

    // Kuyruk timeout (60 saniye doldu)
    _socket!.on('queue_timeout', (data) {
      debugPrint('MatchmakingService: Queue timeout: $data');
      _status = MatchStatus.idle;
      _stopHeartbeat();
      _waitingTimeSeconds = 0;
      
      // Callback varsa çağır
      if (onQueueTimeout != null) {
        String message = data['message'] ?? 'Eşleşme bulunamadı.';
        onQueueTimeout!(message);
      }
      
      notifyListeners();
    });

    // Eşleşme bulundu
    _socket!.on('match_found', (data) {
      debugPrint('MatchmakingService: Match found: $data');
      _status = MatchStatus.matched;
      _stopHeartbeat(); // Arama durdu, heartbeat'i durdur
      _waitingTimeSeconds = 0;
      _matchInfo = MatchInfo(
        roomId: data['roomId'],
        matchedUserId: data['matchedUserId'],
        role: data['role'],
      );
      notifyListeners();
    });

    // Görüşme sonlandı
    _socket!.on('call_ended', (_) {
      debugPrint('MatchmakingService: Call ended');
      leftCall();
    });
    
    // WebRTC sinyalleri VideoCallPage tarafından dinlenecek
    // _socket!.on('webrtc_offer', ...); // Kaldırıldı
  }


  /// Eşleşme kuyruğuna katıl
  Future<void> joinQueue({String? userId}) async {
    // Bağlantı yoksa önce bağlanmayı dene
    if (_socket == null || !_socket!.connected) {
      debugPrint('MatchmakingService: Socket not connected, attempting to connect...');
      await connect();
      
      // Hala bağlı değilse iptal et
      if (_socket == null || !_socket!.connected) {
         debugPrint('MatchmakingService: Failed to connect, cannot join queue.');
         _status = MatchStatus.error;
         _errorMessage = 'Sunucuya bağlanılamadı.';
         notifyListeners();
         return;
      }
    }

    _userId = userId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _status = MatchStatus.searching;
    _waitingTimeSeconds = 0;
    notifyListeners();

    _socket!.emit('join_queue', {'userId': _userId});
    debugPrint('MatchmakingService: Joined queue with userId: $_userId');
    
    // Heartbeat timer'ı başlat
    _startHeartbeat();
  }

  /// Kuyruktan ayrıl
  void leaveQueue() {
    _stopHeartbeat(); // Heartbeat'i durdur
    
    if (_socket != null && _socket!.connected) {
      _socket!.emit('leave_queue', _userId);
    }
    _status = MatchStatus.idle;
    _waitingTimeSeconds = 0;
    notifyListeners();
  }
  
  /// Heartbeat timer'ı başlat
  void _startHeartbeat() {
    _stopHeartbeat(); // Önce varsa durdur
    
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: _heartbeatIntervalMs),
      (_) {
        if (_socket != null && _socket!.connected && _status == MatchStatus.searching) {
          _socket!.emit('heartbeat', {'userId': _userId});
          debugPrint('MatchmakingService: Heartbeat sent');
        }
      },
    );
    debugPrint('MatchmakingService: Heartbeat timer started');
  }
  
  /// Heartbeat timer'ı durdur
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    debugPrint('MatchmakingService: Heartbeat timer stopped');
  }


  /// Odaya katıl
  void joinRoom(String roomId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('join_room', {'roomId': roomId});
      _status = MatchStatus.inCall;
      notifyListeners();
    }
  }

  /// WebRTC offer gönder
  void sendOffer(String roomId, Map<String, dynamic> offer) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('webrtc_offer', {
        'roomId': roomId,
        'offer': offer,
      });
    }
  }

  /// WebRTC answer gönder
  void sendAnswer(String roomId, Map<String, dynamic> answer) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('webrtc_answer', {
        'roomId': roomId,
        'answer': answer,
      });
    }
  }

  /// ICE candidate gönder
  void sendIceCandidate(String roomId, Map<String, dynamic> candidate) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('webrtc_ice_candidate', {
        'roomId': roomId,
        'candidate': candidate,
      });
    }
  }

  /// Görüşmeyi sonlandır
  void endCall() {
    if (_socket != null && _socket!.connected && _matchInfo != null) {
      _socket!.emit('end_call', {'roomId': _matchInfo!.roomId});
    }
    _status = MatchStatus.idle;
    _matchInfo = null;
    notifyListeners();
  }

  /// Bağlantıyı kes
  void disconnect() {
    _stopHeartbeat(); // Heartbeat'i durdur
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _status = MatchStatus.idle;
    _matchInfo = null;
    _waitingTimeSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopHeartbeat(); // Heartbeat'i durdur
    disconnect();
    super.dispose();
  }


  // UI Helper methods
  void setInCall() {
    _status = MatchStatus.inCall;
    notifyListeners();
  }
  
  void leftCall() {
     _status = MatchStatus.idle;
     _matchInfo = null;
     // Socket'i kapatma, belki yeniden arama yapar
     notifyListeners();
  }

  /// Socket event listener ekle (WebRTC için)
  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }
}
