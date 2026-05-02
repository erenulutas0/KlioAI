import 'package:flutter/material.dart';

import '../data/grammar_data.dart';

class GrammarTopicDetailPage extends StatefulWidget {
  final GrammarTopic topic;
  final String? initialSubtopicId;

  const GrammarTopicDetailPage({
    super.key,
    required this.topic,
    this.initialSubtopicId,
  });

  @override
  State<GrammarTopicDetailPage> createState() => _GrammarTopicDetailPageState();
}

class _GrammarTopicDetailPageState extends State<GrammarTopicDetailPage> {
  final ScrollController _scrollController = ScrollController();
  String? _expandedSubtopicId;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  String _text(String tr, String en) => _isTurkish ? tr : en;

  String _englishOverview(GrammarSubtopic subtopic) {
    final formula = subtopic.formula.trim();
    final title = subtopic.title.trim();
    if (formula.isEmpty) {
      return '$title is an English grammar pattern. Review the notes and examples below to understand how it works in context.';
    }
    return '$title is an English grammar pattern. Use the formula "$formula" as your guide and study the examples below to see how it works in real sentences.';
  }

  @override
  void initState() {
    super.initState();
    _expandedSubtopicId = widget.initialSubtopicId ??
        (widget.topic.subtopics.isNotEmpty
            ? widget.topic.subtopics.first.id
            : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111827), Color(0xFF0f172a)],
              ),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildSliverAppBar(),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final subtopic = widget.topic.subtopics[index];
                        return _buildSubtopicCard(subtopic);
                      },
                      childCount: widget.topic.subtopics.length,
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

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: const Color(0xFF111827),
      expandedHeight: 180.0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.topic.color.withOpacity(0.3),
                const Color(0xFF111827),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(widget.topic.icon, size: 48, color: widget.topic.color),
                const SizedBox(height: 8),
                Text(
                  _isTurkish ? widget.topic.titleTr : widget.topic.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_isTurkish)
                  Text(
                    widget.topic.title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      pinned: true,
    );
  }

  Widget _buildSubtopicCard(GrammarSubtopic subtopic) {
    final isExpanded = _expandedSubtopicId == subtopic.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isExpanded
              ? widget.topic.color.withOpacity(0.05)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded
                ? widget.topic.color.withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _expandedSubtopicId = isExpanded ? null : subtopic.id;
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isTurkish ? subtopic.titleTr : subtopic.title,
                            style: TextStyle(
                              color:
                                  isExpanded ? widget.topic.color : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isTurkish && subtopic.titleTr != subtopic.title)
                            Text(
                              subtopic.title,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      color: isExpanded ? widget.topic.color : Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 12),
                    Text(
                      _isTurkish
                          ? subtopic.explanation
                          : _englishOverview(subtopic),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      _text('Yapi / Formul', 'Formula'),
                      Icons.functions,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        subtopic.formula,
                        style: const TextStyle(
                          color: Color(0xFF22D3EE),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isTurkish &&
                        subtopic.keyPoints != null &&
                        subtopic.keyPoints!.isNotEmpty) ...[
                      _buildSectionHeader('Can Alici Noktalar', Icons.vpn_key),
                      ...subtopic.keyPoints!.map(
                        (point) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  point,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _buildSectionHeader(
                      _text('Ornekler', 'Examples'),
                      Icons.check_circle_outline,
                    ),
                    ...subtopic.examples.map((example) => _buildExampleRow(example)),
                    const SizedBox(height: 20),
                    if (_isTurkish && subtopic.commonMistakes.isNotEmpty) ...[
                      _buildSectionHeader(
                        'Sik Yapilan Hatalar',
                        Icons.warning_amber,
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: subtopic.commonMistakes
                              .map(
                                (mistake) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    mistake,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_isTurkish && subtopic.comparison != null) ...[
                      _buildSectionHeader(
                        'Karsilastirma',
                        Icons.compare_arrows,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: Text(
                          subtopic.comparison!,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_isTurkish && subtopic.examTip != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF8b5cf6).withOpacity(0.2),
                              const Color(0xFF6366f1).withOpacity(0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF8b5cf6).withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb,
                                color: Colors.amber, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                subtopic.examTip!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: widget.topic.color),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: widget.topic.color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleRow(GrammarExample example) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: example.isCorrect
            ? Colors.white.withOpacity(0.05)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: example.isCorrect
              ? Colors.white10
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                example.isCorrect ? Icons.check_circle : Icons.cancel,
                color: example.isCorrect ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  example.english,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: Text(
              _isTurkish ? example.turkish : 'English usage example',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          if (_isTurkish && example.note != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 6),
              child: Text(
                '?? ${example.note}',
                style: const TextStyle(
                  color: Color(0xFF22D3EE),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
