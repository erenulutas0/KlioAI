import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/global_matchmaking_sheet.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/bottom_nav.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/user_data_service.dart';
import '../services/api_key_manager.dart';
import '../services/groq_api_client.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import 'login_page.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import '../widgets/ai_token_quota_card.dart';
import '../services/subscription_service.dart';
import 'subscription_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _selectedTheme = 'Buz Mavisi';

  // State for notification settings
  bool _pushNotifications = true;
  bool _emailNotifications = true;
  bool _achievementNotifications = true;
  bool _friendRequestNotifications = true;

  // Profile picture state
  String? _profileImageType;
  String? _profileImagePath;
  String? _avatarSeed;
  
  final List<String> _predefinedAvatars = [
    'Eren', 'Aria', 'Leo', 'Mia', 'Noah', 'Ava', 'Ethan', 'Zoe', 'Jack', 'Luna'
  ];

  // Kullanıcı verileri - Provider'dan alınacak, ama local cache de tutulacak
  Map<String, dynamic>? _user;
  bool _isLoading = false; // Artık false başlıyor çünkü Provider'dan alacağız
  
  // Gerçek veriler - Provider'dan başlangıç değerlerini al
  final UserDataService _userDataService = UserDataService();
  final ApiService _apiService = ApiService();
  int _totalWords = 0;
  int _streak = 0;
  int _totalXp = 0;
  int _level = 1;
  List<Map<String, dynamic>> _friends = [];
  bool _isAiQuotaLoading = false;
  int _aiTokenLimit = 0;
  int _aiTokensUsed = 0;
  int _aiTokensRemaining = 0;
  double _aiRemainingRatio = 1.0;
  String? _aiQuotaDateUtc;

  // BYOK (Bring Your Own Key) State
  final ApiKeyManager _apiKeyManager = ApiKeyManager();
  bool _hasApiKey = false;
  bool _useOwnKey = false;
  ApiKeyStatus? _apiKeyStatus;
  

  @override
  void initState() {
    super.initState();
    
    // Provider'dan mevcut verileri hemen al (anlık gösterim için)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromProvider();
    });
    
    _loadApiKeyStatus();
    _loadFriends(); // Arkadaşları ayrıca yükle
    _loadSubscriptionInfo();
    _loadAiTokenQuotaStatus();
  }

  void _loadSubscriptionInfo() async {
    try {
      final status = await SubscriptionService().getUserSubscriptionStatus();
      if (mounted) {
        setState(() {
          _user = {...?_user, ...status};
        });
      }
    } catch (e) {
      debugPrint('Abonelik yükleme hatası: $e');
    }
  }

  void _loadFromProvider() {
    final appState = context.read<AppStateProvider>();
    setState(() {
      _totalWords = appState.userStats['totalWords'] ?? 0;
      _streak = appState.userStats['streak'] ?? 0;
      _totalXp = appState.userStats['xp'] ?? 0;
      _level = appState.userStats['level'] ?? 1;
      
      // Profile image from provider
      _profileImageType = appState.profileImageType;
      _profileImagePath = appState.profileImagePath;
      _avatarSeed = appState.avatarSeed.isNotEmpty ? appState.avatarSeed : 'Eren';
      
      // User info from provider (anlık gösterim)
      _user = appState.userInfo;
    });
    
    // Eğer userInfo henüz yüklenmediyse, arka planda yükle
    if (_user == null) {
      _loadUserInfo();
    }
  }

  Future<void> _loadUserInfo() async {
    final authService = AuthService();
    var user = await authService.getUser();

    // Force refresh subscription status from backend
    try {
      final subStatus = await SubscriptionService().getUserSubscriptionStatus();
      if (user != null) {
        final updatedUser = Map<String, dynamic>.from(user);
        updatedUser.addAll(subStatus);
        user = updatedUser;
        
        // Update persistent cache
        await authService.updateUser(user);
      }
    } catch (e) {
      debugPrint('Abonelik durumu yenilenirken hata: $e');
    }

    if (mounted && user != null) {
      setState(() {
        _user = user;
      });
      // Update global state
      if (mounted) {
        context.read<AppStateProvider>().refreshUserData();
      }
    }
  }

  Future<void> _loadFriends() async {
    final friends = await _userDataService.getFriends();
    if (mounted) {
      setState(() {
        _friends = friends;
      });
    }
  }

  Future<void> _loadApiKeyStatus() async {
    final hasKey = await _apiKeyManager.hasApiKey();
    final useOwn = await _apiKeyManager.useOwnKey;
    final status = await GroqApiClient.checkApiKeyStatus();
    
    if (mounted) {
      setState(() {
        _hasApiKey = hasKey;
        _useOwnKey = useOwn;
        _apiKeyStatus = status;
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _loadAiTokenQuotaStatus() async {
    if (mounted) {
      setState(() {
        _isAiQuotaLoading = true;
      });
    }

    try {
      final data = await _apiService.chatbotQuotaStatus();
      final limit = _toInt(data['tokenLimit']);
      final used = _toInt(data['tokensUsed']);
      final remainingFromApi = _toInt(data['tokensRemaining']);
      final int remaining = limit > 0
          ? ((limit - used).clamp(0, limit) as int)
          : remainingFromApi;
      final double ratio = limit > 0
          ? (remaining / limit).clamp(0.0, 1.0).toDouble()
          : 1.0;

      if (mounted) {
        setState(() {
          _aiTokenLimit = limit;
          _aiTokensUsed = used;
          _aiTokensRemaining = remaining;
          _aiRemainingRatio = ratio;
          _aiQuotaDateUtc = data['dateUtc']?.toString();
          _isAiQuotaLoading = false;
        });
      }
    } catch (e) {
      debugPrint('AI token quota yuklenemedi: $e');
      if (mounted) {
        setState(() {
          _isAiQuotaLoading = false;
        });
      }
    }
  }

  Future<void> _handleLostData() async {
    if (Platform.isAndroid) {
      final picker = ImagePicker();
      final LostDataResponse response = await picker.retrieveLostData();
      if (response.isEmpty) return;
      if (response.file != null) {
        setState(() {
          _profileImagePath = response.file!.path;
          _profileImageType = 'gallery';
        });
        await _saveProfileImageSettings();
      }
    }
  }

  Future<void> _loadProfileImageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profileImageType = prefs.getString('profile_image_type') ?? 'avatar';
      _profileImagePath = prefs.getString('profile_image_path');
      _avatarSeed = prefs.getString('profile_avatar_seed') ?? 'Eren';
    });
  }

  Future<void> _saveProfileImageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_profileImageType != null) {
      await prefs.setString('profile_image_type', _profileImageType!);
    }
    if (_profileImagePath != null) {
      await prefs.setString('profile_image_path', _profileImagePath!);
    }
    if (_avatarSeed != null) {
      await prefs.setString('profile_avatar_seed', _avatarSeed!);
    }
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _profileImagePath = pickedFile.path;
        _profileImageType = 'gallery';
      });
      await _saveProfileImageSettings();
    }
  }

  Future<void> _pickImageFromCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    
    if (pickedFile != null) {
      setState(() {
        _profileImagePath = pickedFile.path;
        _profileImageType = 'gallery';
      });
      await _saveProfileImageSettings();
    }
  }

  void _showProfileImageMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1e293b).withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Profil Fotoğrafını Değiştir',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMenuOption(Icons.face, 'Avatar', () {
                    Navigator.pop(context);
                    _showAvatarSelection();
                  }),
                  _buildMenuOption(Icons.text_fields, 'Harf', () async {
                    setState(() => _profileImageType = 'initials');
                    await _saveProfileImageSettings();
                    Navigator.pop(context);
                  }),
                  _buildMenuOption(Icons.photo_library, 'Galeri', () {
                    Navigator.pop(context);
                    _pickImageFromGallery();
                  }),
                  _buildMenuOption(Icons.camera_alt, 'Kamera', () {
                    Navigator.pop(context);
                    _pickImageFromCamera();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAvatarSelection() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: ModernCard(
          variant: BackgroundVariant.primary,
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Avatar Seçin',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.transparent,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _predefinedAvatars.length,
                    itemBuilder: (context, index) {
                      final seed = _predefinedAvatars[index];
                      final isSelected = _profileImageType == 'avatar' && _avatarSeed == seed;
                      return GestureDetector(
                        onTap: () async {
                          setState(() {
                            _avatarSeed = seed;
                            _profileImageType = 'avatar';
                          });
                          await _saveProfileImageSettings();
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF0ea5e9) : Colors.white.withOpacity(0.1),
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(
                                color: const Color(0xFF0ea5e9).withOpacity(0.4),
                                blurRadius: 8,
                              )
                            ] : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.network(
                              'https://api.dicebear.com/7.x/avataaars/png?seed=$seed',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(icon, color: const Color(0xFF0ea5e9), size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  void _copyUserTag() {
    final userTag = _user?['userTag'] ?? '';
    if (userTag.isNotEmpty) {
      // Clipboard'a kopyala
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$userTag panoya kopyalandı!'),
          backgroundColor: const Color(0xFF06b6d4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(

      backgroundColor: const Color(0xFF111827),
      // AppBar'ı kaldırdık, böylece özel header scroll ile birlikte hareket edecek
      body: Stack(
        children: [
          // Yağış animasyonu en arkada ve tüm ekranı kaplıyor
          const Positioned.fill(
            child: AnimatedBackground(isDark: true),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  _buildCustomHeader(context),
                  const SizedBox(height: 20),
                  _buildProfileCard(),
                  const SizedBox(height: 24),
                  _buildThemeSelection(),
                  const SizedBox(height: 24),
                  // _buildApiSettings(),
                  // const SizedBox(height: 24),
                  _buildAccountSettings(),
                  // const SizedBox(height: 24),
                  // _buildFriendsSection(),
                  const SizedBox(height: 32),
                  _buildLogoutButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // MVP: GlobalMatchmakingSheet disabled for v1.0
          // const GlobalMatchmakingSheet(),
          BottomNav(
            currentIndex: -1, 
            onTap: (index) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => MainScreen(initialIndex: index),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        const Text(
          'Profil',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Sağ tarafta başlığı ortalamak için boşluk (görünmez buton)
        const IconButton(
          onPressed: null,
          icon: Icon(Icons.arrow_back, color: Colors.transparent),
        ),
      ],
    );
  }

  void _showFullImage(String displayName) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.width * 0.85, // Square aspect ratio
              decoration: BoxDecoration(
                color: const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    InteractiveViewer(
                      maxScale: 4.0,
                      child: Center(
                         child: _buildBigImage(displayName),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBigImage(String displayName) {
     if (_profileImageType == 'gallery' && _profileImagePath != null) {
      return Image.file(File(_profileImagePath!), fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    } else if (_profileImageType == 'initials') {
      return _buildInitialsWidget(displayName);
    } else {
      return CachedNetworkImage(
        imageUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=${_avatarSeed ?? displayName}',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Color(0xFF0ea5e9), strokeWidth: 2)),
        errorWidget: (context, url, error) => _buildInitialsWidget(displayName),
      );
    }
  }

  Widget _buildProfileImageWidget(String displayName) {
    if (_profileImageType == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0ea5e9), strokeWidth: 2),
      );
    }
    
    if (_profileImageType == 'gallery' && _profileImagePath != null) {
      return Image.file(
        File(_profileImagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildInitialsWidget(displayName),
      );

    } else if (_profileImageType == 'initials') {
      return _buildInitialsWidget(displayName);
    } else {
      // Default avatar
      return CachedNetworkImage(
        imageUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=${_avatarSeed ?? displayName}',
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Color(0xFF0ea5e9), strokeWidth: 2)),
        errorWidget: (context, url, error) => _buildInitialsWidget(displayName),
      );
    }
  }

  Widget _buildInitialsWidget(String displayName) {
    final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF0ea5e9),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final displayName = _user?['displayName'] ?? 'Kullanıcı';
    final userTag = _user?['userTag'] ?? '#00000';
    final email = _user?['email'] ?? '';
    final level = _user?['level'] ?? 1;
    final totalXp = _user?['totalXp'] ?? 0;
    // final currentStreak = _user?['currentStreak'] ?? 0; // Not used locally if using stats map
    // final wordsLearned = _user?['wordsLearned'] ?? 0;   // Not used locally

    // XP hesaplama
    final xpThresholds = [0, 100, 250, 500, 1000, 2000, 3500, 5500, 8000, 11000, 15000];
    final currentLevelXp = level <= 10 ? xpThresholds[level - 1] : 15000 + ((level - 11) * 5000);
    final nextLevelXp = level <= 10 ? xpThresholds[level] : 15000 + ((level - 10) * 5000);
    final xpProgress = totalXp - currentLevelXp;
    final xpNeeded = nextLevelXp - currentLevelXp;
    final progressValue = xpNeeded > 0 ? xpProgress / xpNeeded : 0.0;
    final xpRemaining = nextLevelXp - totalXp;

    final isPro = _user?['subscriptionEndDate'] != null;

    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => _showFullImage(displayName),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    // PRO gradient ring for subscribers
                    gradient: isPro
                        ? const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFF8C00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    border: !isPro
                        ? Border.all(color: Colors.white.withOpacity(0.1), width: 3)
                        : null,
                    boxShadow: [
                      if (isPro)
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _buildProfileImageWidget(displayName),
                    ),
                  ),
                ),
              ),
              // PRO Crown Badge for subscribers
              if (isPro)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF111827), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.workspace_premium, color: Colors.white, size: 16),
                  ),
                ),
              Positioned(
                bottom: -2,
                right: -2,
                child: GestureDetector(
                  onTap: _showProfileImageMenu,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0ea5e9),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF111827), width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                  ),
                ),
              ),
              Positioned(
                bottom: -10,
                left: -10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3b82f6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF111827), width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.emoji_events, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '$level',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          // UserTag GİZLENDİ (Backend'de mevcut)
          /*
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
               Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF06b6d4), Color(0xFF3b82f6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  userTag,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
               // Copy tag button
               GestureDetector(
                onTap: _copyUserTag,
                child: Icon(Icons.copy, color: Colors.white.withOpacity(0.5), size: 16),
               )
            ],
          ),
          */
          const SizedBox(height: 8),
          
          // Subscription Status
          if (!isPro) ...[
            const SizedBox(height: 8),
             Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_outlined, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Ücretsiz Plan',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
               ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                   await Navigator.push(context, MaterialPageRoute(builder: (context) => const SubscriptionPage()));
                   if (mounted) _loadUserInfo(); // Reload after return
                },
                icon: const Icon(Icons.flash_on, size: 18),
                label: const Text('PRO\'ya Yükselt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22D3EE),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
          ] else ...[
             const SizedBox(height: 8),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
               decoration: BoxDecoration(
                 color: const Color(0xFFFFD700).withOpacity(0.2),
                 borderRadius: BorderRadius.circular(20),
                 border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
               ),
               child: const Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 16),
                   SizedBox(width: 6),
                   Text('PRO Üye', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
                 ],
               ),
             )
          ],
          
          const SizedBox(height: 24),
          
          // XP Bar Progress
          Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         const Text(
                          'XP İlerlemesi',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$totalXp / $nextLevelXp',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progressValue.clamp(0.0, 1.0),
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3b82f6)),
                        minHeight: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                     Text(
                      'Sonraki seviyeye $xpRemaining XP kaldı',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),

          const SizedBox(height: 16),
          AiTokenQuotaCard(
            isLoading: _isAiQuotaLoading,
            tokenLimit: _aiTokenLimit,
            tokensUsed: _aiTokensUsed,
            tokensRemaining: _aiTokensRemaining,
            remainingRatio: _aiRemainingRatio,
            quotaDateUtc: _aiQuotaDateUtc,
            onRefresh: _loadAiTokenQuotaStatus,
          ),
              
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildStatItem(Icons.emoji_events_outlined, '$_totalWords', 'Toplam\nKelime', const Color(0xFF0ea5e9))),
              const SizedBox(width: 12),
              Expanded(child: _buildStatItem(Icons.calendar_today_outlined, '$_streak', 'Gün Serisi', const Color(0xFF0ea5e9))),
              const SizedBox(width: 12),
              Expanded(child: _buildStatItem(Icons.military_tech_outlined, '$_level', 'Seviye', const Color(0xFF0ea5e9))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelection() {
    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0ea5e9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.palette_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tema Seçimi',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Uygulamanın rengini özelleştirin',
                    style: TextStyle(color: const Color(0xFF38bdf8), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildThemeOption('Buz Mavisi', const Color(0xFF0284c7), true),
              _buildThemeOption('Mor', const Color(0xFF7c3aed), false, isComingSoon: true),
              _buildThemeOption('Yeşil', const Color(0xFF059669), false, isComingSoon: true),
              _buildThemeOption('Turuncu', const Color(0xFFea580c), false, isComingSoon: true),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.palette, color: Color(0xFF0ea5e9), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      children: [
                        const TextSpan(text: 'Şu an '),
                        TextSpan(
                          text: _selectedTheme,
                          style: const TextStyle(color: Color(0xFF0ea5e9), fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' teması kullanılıyor'),
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

  Widget _buildThemeOption(String name, Color color, bool isSelected, {bool isComingSoon = false}) {
    return GestureDetector(
      onTap: isComingSoon ? null : () => setState(() => _selectedTheme = name),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1e293b),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF0ea5e9) : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: const Color(0xFF0ea5e9).withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (isComingSoon)
                Container(
                  color: Colors.black.withOpacity(0.6),
                  child: const Center(
                    child: Text(
                      'Yakında',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSettings() {
    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_outline, color: Color(0xFF0ea5e9), size: 24),
              SizedBox(width: 12),
              Text(
                'Hesap Ayarları',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsTile(Icons.person_outline, 'Profili Düzenle', _showEditProfileDialog),
          const SizedBox(height: 12),
          _buildSettingsTile(Icons.notifications_none, 'Bildirim Tercihleri', _showNotificationSettingsDialog),
          const SizedBox(height: 12),
          _buildSettingsTile(Icons.lock_outline, 'Gizlilik Ayarları', _showPrivacySettingsDialog),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF38bdf8), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
          ],
        ),
      ),
    );
  }

  // Dialog Implementation
  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1e1b4b),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     const Row(
                       children: [
                         Icon(Icons.person_outline, color: Color(0xFF0ea5e9), size: 24),
                         SizedBox(width: 12),
                         Text(
                           'Profili Düzenle',
                           style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                         ),
                       ],
                     ),
                     IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 24),
                _buildLabel('İsim'),
                _buildDarkTextField(initialValue: 'Eren'),
                const SizedBox(height: 16),
                _buildLabel('Email'),
                _buildDarkTextField(initialValue: 'eren@vocabmaster.com'),
                 const SizedBox(height: 16),
                _buildLabel('Bio'),
                _buildDarkTextField(hint: 'Kendinizi tanıtın...', maxLines: 4),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0072ff),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Değişiklikleri Kaydet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotificationSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Dialog(
          backgroundColor: const Color(0xFF1e1b4b),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(24),
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Expanded(
                         child: Row(
                           children: [
                             Icon(Icons.notifications_active_outlined, color: Color(0xFF0ea5e9), size: 24),
                             SizedBox(width: 12),
                             Flexible(
                               child: Text(
                                 'Bildirim Tercihleri',
                                 style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),
                           ],
                         ),
                       ),
                       IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSwitchTile('Push Bildirimleri', 'Yeni mesajlar ve güncellemeler', _pushNotifications, (v) => setStateDialog(() => _pushNotifications = v)),
                  const SizedBox(height: 12),
                   _buildSwitchTile('Email Bildirimleri', 'Haftalık özet ve önemli bilgiler', _emailNotifications, (v) => setStateDialog(() => _emailNotifications = v)),
                   const SizedBox(height: 12),
                    _buildSwitchTile('Başarım Bildirimleri', 'Yeni rozetler ve seviye atlamalar', _achievementNotifications, (v) => setStateDialog(() => _achievementNotifications = v)),
                    const SizedBox(height: 12),
                     _buildSwitchTile('Arkadaş İstekleri', 'Yeni arkadaşlık istekleri', _friendRequestNotifications, (v) => setStateDialog(() => _friendRequestNotifications = v)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPrivacySettingsDialog() {
     showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1e1b4b),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Expanded(
                         child: Row(
                           children: [
                             Icon(Icons.lock_outline, color: Color(0xFF0ea5e9), size: 24),
                             SizedBox(width: 12),
                             Flexible(
                               child: Text(
                                 'Gizlilik Ayarları',
                                 style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),
                           ],
                         ),
                       ),
                       IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildPrivacyTile(Icons.person_outline, 'Profil Görünürlüğü', 'Herkes'),
                   const SizedBox(height: 12),
                   _buildPrivacyTile(Icons.verified_user_outlined, 'Aktivite Durumu', 'Çevrimiçi/Çevrimdışı göster'),
                    const SizedBox(height: 12),
                    _buildPrivacyTile(Icons.people_outline, 'Arkadaş İstekleri', 'Herkesten kabul et'),
                     const SizedBox(height: 12),
                     _buildPrivacyTile(Icons.lock_open, 'Mesajlar', 'Sadece arkadaşlar'),
              ],
            ),
          ),
        ),
      ),
     );
  }
  
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text, style: const TextStyle(color: Color(0xFF38bdf8), fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildDarkTextField({String? initialValue, String? hint, int maxLines = 1}) {
    return TextFormField(
      initialValue: initialValue,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
         color: Colors.white.withOpacity(0.05),
         borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(color: const Color(0xFF06b6d4).withOpacity(0.7), fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value, 
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: const Color(0xFF0072ff),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyTile(IconData icon, String title, String subtitle) {
     return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
         color: Colors.white.withOpacity(0.05),
         borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF06b6d4), size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                 Text(subtitle, style: TextStyle(color: const Color(0xFF06b6d4).withOpacity(0.7), fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
        ],
      ),
     );
  }

  // ignore: unused_element
  Widget _buildFriendsSection() {
    final onlineFriends = _friends.where((f) => f['isOnline'] == true).toList();
    final offlineFriends = _friends.where((f) => f['isOnline'] != true).toList();
    
    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people_outline, color: Color(0xFF0ea5e9), size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Arkadaşlar',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (onlineFriends.isNotEmpty)
                Container(
                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                   decoration: BoxDecoration(
                     color: const Color(0xFF059669).withOpacity(0.2),
                     borderRadius: BorderRadius.circular(8),
                     border: Border.all(color: const Color(0xFF059669)),
                   ),
                   child: Text('${onlineFriends.length} Çevrimiçi', style: const TextStyle(color: Color(0xFF34d399), fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          
          if (_friends.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.person_add_outlined, color: Colors.white.withOpacity(0.3), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Henüz arkadaşınız yok',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kullanıcı ID\'si ile arkadaş ekleyerek birlikte pratik yapabilirsiniz!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                ],
              ),
            ),
          ] else ...[
            if (onlineFriends.isNotEmpty) ...[
              Text(
                'ÇEVRİMİÇİ',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...onlineFriends.map((friend) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFriendItem(
                  friend['name'] ?? '',
                  friend['status'] ?? '',
                  true,
                  friend['avatar'] ?? '👤',
                  friend['id'] ?? 0,
                ),
              )),
              const SizedBox(height: 12),
            ],
            if (offlineFriends.isNotEmpty) ...[
              Text(
                'ÇEVRİMDIŞI',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...offlineFriends.map((friend) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFriendItem(
                  friend['name'] ?? '',
                  friend['lastSeen'] ?? 'Uzun süredir çevrimdışı',
                  false,
                  friend['avatar'] ?? '👤',
                  friend['id'] ?? 0,
                ),
              )),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFriendItem(String name, String status, bool isOnline, String avatar, int seed) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFF0ea5e9) : Colors.grey[800],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: Text(avatar, style: const TextStyle(fontSize: 24))),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF22c55e) : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1e1b4b), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: isOnline ? const Color(0xFF38bdf8) : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
        ],
      ),
    );
  }

  // ==================== API Settings (BYOK) ====================

  // ignore: unused_element
  Widget _buildApiSettings() {
    final statusColor = _apiKeyStatus?.source == ApiKeySource.userProvided
        ? const Color(0xFF10b981)
        : _apiKeyStatus?.source == ApiKeySource.environment
            ? const Color(0xFFf59e0b)
            : const Color(0xFFef4444);
    
    final statusIcon = _apiKeyStatus?.source == ApiKeySource.userProvided
        ? Icons.check_circle
        : _apiKeyStatus?.source == ApiKeySource.environment
            ? Icons.info_outline
            : Icons.warning_amber_rounded;

    return ModernCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF8b5cf6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.key, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'API Anahtarı',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Groq AI bağlantısı',
                      style: TextStyle(color: const Color(0xFF38bdf8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Durum göstergesi
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _apiKeyStatus?.source == ApiKeySource.userProvided
                          ? 'Aktif'
                          : _apiKeyStatus?.source == ApiKeySource.environment
                              ? 'Demo'
                              : 'Yok',
                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Bilgi kartı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _apiKeyStatus?.source == ApiKeySource.userProvided
                            ? 'Kendi API Anahtarınız Kullanılıyor'
                            : _apiKeyStatus?.source == ApiKeySource.environment
                                ? 'Demo Modu (Sınırlı Kullanım)'
                                : 'API Anahtarı Gerekli',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _apiKeyStatus?.source == ApiKeySource.userProvided
                            ? 'Sınırsız AI özelliklerinin keyfini çıkarın!'
                            : _apiKeyStatus?.source == ApiKeySource.environment
                                ? 'Kendi anahtarınızı ekleyerek sınırsız kullanın'
                                : 'AI özelliklerini kullanmak için anahtar ekleyin',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Aksiyon butonları
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showApiKeyDialog,
                  icon: Icon(_hasApiKey ? Icons.edit : Icons.add, size: 18),
                  label: Text(_hasApiKey ? 'Anahtarı Değiştir' : 'Anahtar Ekle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8b5cf6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_hasApiKey) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1e1b4b),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('API Anahtarını Sil?', style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'API anahtarınız silinecek ve demo moduna geçilecek.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFef4444)),
                            child: const Text('Sil', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    
                    if (confirm == true) {
                      await _apiKeyManager.deleteApiKey();
                      await _loadApiKeyStatus();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('API anahtarı silindi'),
                            backgroundColor: Color(0xFFef4444),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFef4444)),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFef4444).withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          
          // Yardım linki
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1e1b4b),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      const Icon(Icons.help_outline, color: Color(0xFF8b5cf6)),
                      const SizedBox(width: 8),
                      const Text('Ücretsiz API Anahtarı', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Groq, ücretsiz API anahtarı sunuyor! Şu adımları izleyin:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        _buildHelpStep('1', 'console.groq.com adresine gidin'),
                        _buildHelpStep('2', 'Google veya GitHub ile giriş yapın'),
                        _buildHelpStep('3', '"API Keys" bölümüne gidin'),
                        _buildHelpStep('4', '"Create API Key" butonuna tıklayın'),
                        _buildHelpStep('5', 'Oluşturulan anahtarı kopyalayın'),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10b981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10b981).withOpacity(0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFF10b981), size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ücretsiz tier: Günlük 14.400 istek!',
                                  style: TextStyle(color: Color(0xFF10b981), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Anladım', style: TextStyle(color: Color(0xFF8b5cf6))),
                    ),
                  ],
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline, color: Colors.white.withOpacity(0.5), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Ücretsiz API anahtarı nasıl alınır?',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF8b5cf6),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    bool isSuccess = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1e1b4b),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF8b5cf6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.key, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('API Anahtarı Ekle', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Groq API anahtarınızı girin:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'gsk_xxxxxxxxxxxxxxxx',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontFamily: 'monospace'),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.vpn_key, color: Color(0xFF8b5cf6)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste, color: Colors.white54),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          controller.text = data!.text!;
                        }
                      },
                    ),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFef4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFef4444).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Color(0xFFef4444), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isSuccess) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10b981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10b981).withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF10b981), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'API anahtarı geçerli! ✓',
                          style: TextStyle(color: Color(0xFF10b981), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8b5cf6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.security, color: Color(0xFF8b5cf6), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Anahtarınız cihazınızda şifreli olarak saklanır.',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: Text('İptal', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final key = controller.text.trim();
                      
                      if (key.isEmpty) {
                        setStateDialog(() => errorMessage = 'API anahtarı boş olamaz');
                        return;
                      }
                      
                      if (!_apiKeyManager.isValidApiKeyFormat(key)) {
                        setStateDialog(() => errorMessage = 'Geçersiz format. Anahtar "gsk_" ile başlamalı.');
                        return;
                      }
                      
                      setStateDialog(() {
                        isLoading = true;
                        errorMessage = null;
                      });
                      
                      // API anahtarını test et
                      final result = await GroqApiClient.testApiKey(key);
                      
                      if (result.isValid) {
                        await _apiKeyManager.saveApiKey(key);
                        setStateDialog(() {
                          isLoading = false;
                          isSuccess = true;
                        });
                        
                        await Future.delayed(const Duration(milliseconds: 800));
                        if (ctx.mounted) Navigator.pop(ctx);
                        
                        await _loadApiKeyStatus();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('API anahtarı başarıyla kaydedildi!'),
                                ],
                              ),
                              backgroundColor: Color(0xFF10b981),
                            ),
                          );
                        }
                      } else {
                        setStateDialog(() {
                          isLoading = false;
                          errorMessage = result.message;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8b5cf6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Çıkış Yap', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFef4444), foregroundColor: Colors.white),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
       await AuthService().logout();
       if (mounted) {
         Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
       }
    }
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _handleLogout,
      child: ModernCard(
        height: 56,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(16),
        variant: BackgroundVariant.primary, // Using primary to match "Arkadaslar" card as requested
        child: const Center(
          child: Text(
            'Çıkış Yap',
            style: TextStyle(
              color: Color(0xFFe879f9), // Keep the text color as purple/pinkish
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
