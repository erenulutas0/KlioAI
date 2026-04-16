import 'package:flutter/material.dart';
import '../data/grammar_data.dart';
import '../data/grammar_repository.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import 'grammar_topic_detail_page.dart';

class GrammarTab extends StatefulWidget {
  const GrammarTab({super.key});

  @override
  State<GrammarTab> createState() => _GrammarTabState();
}

class _GrammarTabState extends State<GrammarTab> {
  String _selectedFilter = 'Tümü'; // Tümü, Temel, İleri, Sınav

  @override
  Widget build(BuildContext context) {
    final allTopics = GrammarRepository.getAllTopics();
    final topics = _filterTopics(allTopics);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF8b5cf6), // Purple
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8b5cf6).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.menu_book_outlined, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gramer Çalışma',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Konu anlatımları ve detaylı notlar',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),

        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            children: [
              _buildFilterChip('Tümü', null),
              const SizedBox(width: 8),
              _buildFilterChip('Temel (Core)', 'core'),
              const SizedBox(width: 8),
              _buildFilterChip('İleri (Adv)', 'advanced'),
              const SizedBox(width: 8),
              _buildFilterChip('Sınav (Exam)', 'exam'),
              const SizedBox(width: 8),
              _buildFilterChip('Bonus', 'bonus'),
            ],
          ),
        ),

        // Topics Grid
        ...topics.map((topic) => _buildTopicCard(context, topic)),
        
        const SizedBox(height: 80), // Bottom padding
      ],
    );
  }

  List<GrammarTopic> _filterTopics(List<GrammarTopic> all) {
    if (_selectedFilter == 'Tümü') return all;
    
    String levelKey = '';
    if (_selectedFilter.contains('Temel')) {
      levelKey = 'core';
    } else if (_selectedFilter.contains('İleri')) {
      levelKey = 'advanced';
    } else if (_selectedFilter.contains('Sınav')) {
      levelKey = 'exam';
    } else if (_selectedFilter == 'Bonus') {
      levelKey = 'bonus';
    }
    
    return all.where((t) => t.level == levelKey).toList();
  }

  Widget _buildFilterChip(String label, String? levelKey) {
    bool isSelected = false;
    if (levelKey == null) {
      isSelected = _selectedFilter == 'Tümü';
    } else {
      isSelected = _selectedFilter.contains(levelKey == 'core' ? 'Temel' : (levelKey == 'advanced' ? 'İleri' : (levelKey == 'exam' ? 'Sınav' : 'Bonus')));
    }

    Color color = Colors.grey;
    if(levelKey != null) {
        color = GrammarLevelColors.getColor(levelKey);
    } else {
        color = Colors.blue; 
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTopicCard(BuildContext context, GrammarTopic topic) {
    final subtopicCount = topic.subtopics.length;
    final exampleCount = topic.subtopics.isNotEmpty && topic.subtopics[0].id != 'coming_soon' 
      ? topic.subtopics.fold(0, (sum, sub) => sum + sub.examples.length) 
      : 0;
      
    final isComingSoon = topic.subtopics.isNotEmpty && topic.subtopics[0].id == 'coming_soon';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (isComingSoon) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bu içerik yakında eklenecek!'), duration: Duration(seconds: 1)),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GrammarTopicDetailPage(topic: topic),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: ModernCard(
          variant: BackgroundVariant.primary,
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(16),
          showGlow: false,
          child: Row(
            children: [
              // Icon Box
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: topic.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: topic.color.withOpacity(0.3)),
                ),
                child: Icon(topic.icon, color: topic.color, size: 28),
              ),
              const SizedBox(width: 16),
              
              // Text Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.titleTr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topic.title,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isComingSoon ? Colors.grey.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isComingSoon ? 'Yakında' : '$subtopicCount Başlık',
                      style: TextStyle(
                        color: isComingSoon ? Colors.grey : Colors.white70, 
                        fontSize: 10,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ),
                  if (!isComingSoon && exampleCount > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$exampleCount+ Örnek',
                        style: TextStyle(color: topic.color.withOpacity(0.8), fontSize: 10),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

