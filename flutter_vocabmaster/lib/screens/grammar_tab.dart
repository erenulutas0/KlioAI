import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/grammar_data.dart';
import '../data/grammar_repository.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';
import 'grammar_topic_detail_page.dart';

class GrammarTab extends StatefulWidget {
  const GrammarTab({super.key});

  @override
  State<GrammarTab> createState() => _GrammarTabState();
}

class _GrammarTabState extends State<GrammarTab> {
  String _selectedFilter = 'all';

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  String _text(String tr, String en) => _isTurkish ? tr : en;

  AppThemeConfig _currentTheme() {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme();
    final allTopics = GrammarRepository.getAllTopics();
    final topics = _filterTopics(allTopics);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selectedTheme.colors.accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectedTheme.colors.accent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.menu_book_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('Gramer Calisma', 'Grammar Practice'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _text(
                        'Konu anlatimlari ve detayli notlar',
                        'Grammar notes and topic guides',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              _buildFilterChip('all'),
              const SizedBox(width: 8),
              _buildFilterChip('core'),
              const SizedBox(width: 8),
              _buildFilterChip('advanced'),
              const SizedBox(width: 8),
              _buildFilterChip('exam'),
              const SizedBox(width: 8),
              _buildFilterChip('bonus'),
            ],
          ),
        ),
        ...topics.map((topic) => _buildTopicCard(context, topic)),
        const SizedBox(height: 80),
      ],
    );
  }

  List<GrammarTopic> _filterTopics(List<GrammarTopic> all) {
    if (_selectedFilter == 'all') return all;
    return all.where((topic) => topic.level == _selectedFilter).toList();
  }

  String _filterLabel(String key) {
    switch (key) {
      case 'core':
        return _text('Temel', 'Core');
      case 'advanced':
        return _text('Ileri', 'Advanced');
      case 'exam':
        return _text('Sinav', 'Exam');
      case 'bonus':
        return 'Bonus';
      default:
        return _text('Tumu', 'All');
    }
  }

  Widget _buildFilterChip(String key) {
    final selectedTheme = _currentTheme();
    final isSelected = _selectedFilter == key;
    final accent = selectedTheme.colors.accent;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withOpacity(0.18)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? accent.withOpacity(0.76)
                : Colors.white.withOpacity(0.10),
            width: 1.2,
          ),
        ),
        child: Text(
          _filterLabel(key),
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTopicCard(BuildContext context, GrammarTopic topic) {
    final selectedTheme = _currentTheme();
    final subtopicCount = topic.subtopics.length;
    final exampleCount =
        topic.subtopics.isNotEmpty && topic.subtopics[0].id != 'coming_soon'
            ? topic.subtopics.fold(0, (sum, sub) => sum + sub.examples.length)
            : 0;
    final isComingSoon =
        topic.subtopics.isNotEmpty && topic.subtopics[0].id == 'coming_soon';
    final accent = selectedTheme.colors.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (isComingSoon) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(_text('Bu icerik yakinda eklenecek!', 'Coming soon!')),
                duration: const Duration(seconds: 1),
              ),
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
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.32)),
                ),
                child: Icon(topic.icon, color: accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isTurkish ? topic.titleTr : topic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isTurkish ? topic.title : _filterLabel(topic.level),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selectedTheme.colors.textSecondary
                            .withOpacity(0.78),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isComingSoon
                          ? Colors.white.withOpacity(0.05)
                          : accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isComingSoon
                          ? _text('Yakinda', 'Soon')
                          : _text(
                              '$subtopicCount Baslik', '$subtopicCount Topics'),
                      style: TextStyle(
                        color: isComingSoon ? Colors.white54 : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!isComingSoon && exampleCount > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _text(
                            '$exampleCount+ Ornek', '$exampleCount+ Examples'),
                        style: TextStyle(
                          color: accent.withOpacity(0.85),
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                color: selectedTheme.colors.textSecondary.withOpacity(0.35),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
