import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/animated_background.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';

class ChatDetailPage extends StatefulWidget {
  final int userId;
  final String name;
  final String avatar;
  final String status;

  const ChatDetailPage({
    super.key,
    required this.userId,
    required this.name,
    required this.avatar,
    required this.status,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  List<dynamic> messages = [];
  Timer? _timer;
  int? _currentUserId;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadMessages();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) => _loadMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final userId = await _authService.getUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _chatService.getMessages(widget.userId);
      if (mounted) {
        setState(() {
          messages = msgs;
        });
        // Scroll to bottom only if strictly needed or on first load
        // _scrollToBottom(); 
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text;
    _messageController.clear();

    try {
      await _chatService.sendMessage(widget.userId, content);
      await _loadMessages();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderilemedi: $e')),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          Column(
            children: [
              // Custom AppBar
              SafeArea(
                bottom: false,
                child: Builder(
                  builder: (context) {
                    final isOnline = widget.status == 'Çevrimiçi';
                    return ModernCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                      variant: BackgroundVariant.primary,
                      showBorder: false,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 12),
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: isOnline 
                                    ? const Color(0xFF22d3ee) 
                                    : Colors.grey.shade600,
                                child: Text(widget.avatar, style: const TextStyle(fontSize: 20)),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green : Colors.grey.shade500,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF1e1b4b), width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 3, 
                                      backgroundColor: isOnline ? Colors.green : Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.status, 
                                      style: TextStyle(
                                        color: isOnline ? Colors.green.shade300 : Colors.white54, 
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Messages
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('Henüz mesaj yok', style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return _buildMessageBubble(msg);
                        },
                      ),
              ),

              // Message Input
              SafeArea(
                top: false,
                child: ModernCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  variant: BackgroundVariant.primary,
                  showBorder: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: TextField(
                            controller: _messageController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Mesajınızı yazın...',
                              hintStyle: TextStyle(color: Colors.white38),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Send Button
                      GestureDetector(
                        onTap: _sendMessage,
                        child: ModernCard(
                          width: 48,
                          height: 48,
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(12),
                          variant: BackgroundVariant.accent,
                          showGlow: true,
                          child: const Center(
                            child: Icon(Icons.send, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic msg) {
    // Backend returns sender object map inside message
    final senderMap = msg['sender'];
    final senderId = senderMap != null ? senderMap['id'] : null;
    final isMe = _currentUserId != null && senderId == _currentUserId;

    // Backend 'createdAt' is likely ISO string
    // Parse time roughly
    String timeStr = '';
    if (msg['createdAt'] != null) {
      try {
        final date = DateTime.parse(msg['createdAt']);
        timeStr = "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
      } catch (e) {
        timeStr = '';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              gradient: isMe
                  ? const LinearGradient(colors: [Color(0xFF06b6d4), Color(0xFF3182ce)])
                  : null,
              color: isMe ? null : const Color(0xFF334155).withOpacity(0.5),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              msg['content'] ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

