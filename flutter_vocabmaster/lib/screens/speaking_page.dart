import 'package:flutter/material.dart';
import '../widgets/animated_background.dart';
import '../widgets/bottom_nav.dart';
import 'ai_bot_chat_page.dart';

class SpeakingPage extends StatelessWidget {
  const SpeakingPage({super.key});

  Widget _buildScenarioCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String scenario,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Senaryoya göre işlem yap
          if (['job_interview_followup', 'academic_presentation_qa', 'explaining_to_manager'].contains(scenario)) {
            // Bu senaryolar için kullanıcıdan konu/bağlam iste
            _showContextInputModal(context, scenario, title, color);
          } else {
            // Diğer senaryolar (örn: Disagreement) direkt başla
            _navigateToChat(context, scenario, title, null);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.3),
                color.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                // Header with back button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.mic, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'Konuşma Pratiği',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Speaking Test Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1e3a8a).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.mic_none, color: Colors.white, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Konuşma Testi',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        'Konuşma becerilerinizi test edin',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('IELTS Konuşma'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF9333ea),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('TOEFL Konuşma'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF16a34a),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Owen Chat Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1e3a8a).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0ea5e9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.mic, color: Colors.white, size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  const Expanded(
                                    child: Text(
                                      'Merhaba! Ben Owen, İngilizce konuşma öğretmeniniz. Birlikte İngilizce pratik edelim! Bugünkü gününüz nasıl?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Padding(
                                padding: EdgeInsets.only(left: 60),
                                child: Icon(Icons.volume_up, color: Colors.white54, size: 20),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Professional Scenarios Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1e3a8a).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.work_outline, color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Profesyonel Senaryolar',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        'İş hayatı için pratik yapın',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              
                              // Scenario Cards Grid
                              GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.1,
                                children: [
                                  // Job Interview Follow-up
                                  _buildScenarioCard(
                                    context,
                                    icon: Icons.business_center,
                                    title: 'Job Interview\nFollow-up',
                                    subtitle: 'Mülakat sonrası takip',
                                    color: const Color(0xFF8b5cf6),
                                    scenario: 'job_interview_followup',
                                  ),
                                  
                                  // Academic Presentation Q&A
                                  _buildScenarioCard(
                                    context,
                                    icon: Icons.school,
                                    title: 'Academic\nPresentation Q&A',
                                    subtitle: 'Sunum soru-cevap',
                                    color: const Color(0xFF0ea5e9),
                                    scenario: 'academic_presentation_qa',
                                  ),
                                  
                                  // Disagreement with a colleague
                                  _buildScenarioCard(
                                    context,
                                    icon: Icons.people_outline,
                                    title: 'Disagreement\nwith Colleague',
                                    subtitle: 'Meslektaşla anlaşmazlık',
                                    color: const Color(0xFFf59e0b),
                                    scenario: 'disagreement_colleague',
                                  ),
                                  
                                  // Explaining a decision to a manager
                                  _buildScenarioCard(
                                    context,
                                    icon: Icons.person_outline,
                                    title: 'Explaining to\nManager',
                                    subtitle: 'Yöneticiye açıklama',
                                    color: const Color(0xFF10b981),
                                    scenario: 'explaining_to_manager',
                                  ),
                                ],
                              ),
                            ],
                          ),
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
      bottomNavigationBar: BottomNav(
        currentIndex: 2, // Menu index
        onTap: (index) {
          if (index != 2) {
            Navigator.pop(context);
          }
        },
      ),
    );
  }
  void _navigateToChat(BuildContext context, String scenario, String title, String? contextText) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIBotChatPage(
          initialScenario: scenario,
          initialScenarioName: title.replaceAll('\n', ' '),
          scenarioContext: contextText,
        ),
      ),
    );
  }

  void _showContextInputModal(BuildContext context, String scenario, String title, Color color) {
    final TextEditingController textController = TextEditingController();
    String hintText = '';
    String labelText = '';
    String instructionText = '';

    switch (scenario) {
      case 'job_interview_followup':
        labelText = 'Başvurduğun Pozisyon/Şirket';
        hintText = 'Örn: Senior React Developer @ Google';
        instructionText = 'Hangi pozisyon veya şirket için görüştüğünü belirtirsen, HR ona göre sorular soracak.';
        break;
      case 'academic_presentation_qa':
        labelText = 'Sunum Konusu';
        hintText = 'Örn: Climate Change Impact on Agriculture';
        instructionText = 'Yaptığın sunumun konusunu kısaca yaz.';
        break;
      case 'explaining_to_manager':
        labelText = 'Açıklanacak Durum';
        hintText = 'Örn: Server çöktüğü için proje gecikti';
        instructionText = 'Yöneticiye neyi açıklaman veya savunman gerektiğini yaz.';
        break;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: Text(title.replaceAll('\n', ' '), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(instructionText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: labelText,
                hintText: hintText,
                labelStyle: const TextStyle(color: Colors.white60),
                hintStyle: const TextStyle(color: Colors.white30),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color),
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.black12,
              ),
              maxLines: 2,
              maxLength: 100, // Karakter sınırlaması
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToChat(context, scenario, title, textController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Başla'),
          ),
        ],
      ),
    );
  }
}

