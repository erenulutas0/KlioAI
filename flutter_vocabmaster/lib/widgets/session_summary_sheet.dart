import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_state_provider.dart';

/// Oturum sonu özeti: "+X XP, N kart, 🔥 seri, günlük hedef n/m".
/// Duolingo-tarzı döngünün "kapanış anı" - pratik sayfaları doğal oturum
/// sonlarında [show] ile çağırır. Veriler zaten lokalde mevcut; salt UI.
class SessionSummarySheet extends StatelessWidget {
  final int xpEarned;
  final int itemsCompleted;

  const SessionSummarySheet({
    super.key,
    required this.xpEarned,
    required this.itemsCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required int xpEarned,
    required int itemsCompleted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // Küçük ekranlarda içerik varsayılan 9/16 yükseklik sınırını aşabiliyor;
      // scroll-controlled + içteki SingleChildScrollView taşmayı engeller.
      isScrollControlled: true,
      builder: (_) => SessionSummarySheet(
        xpEarned: xpEarned,
        itemsCompleted: itemsCompleted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<AppStateProvider>().userStats;
    final streak = stats['streak'] ?? 0;
    final learnedToday = stats['learnedToday'] ?? 0;
    final dailyGoal = stats['dailyGoal'] ?? 5;

    return SafeArea(
      child: Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            context.tr('session.summary.title'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _statBox(
                icon: Icons.bolt,
                iconColor: const Color(0xFFFACC15),
                value: '+$xpEarned',
                label: context.tr('session.summary.xp'),
              ),
              const SizedBox(width: 10),
              _statBox(
                icon: Icons.style_outlined,
                iconColor: const Color(0xFF22d3ee),
                value: '$itemsCompleted',
                label: context.tr('session.summary.items'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statBox(
                icon: Icons.local_fire_department,
                iconColor: const Color(0xFFFB923C),
                value: '$streak',
                label: context.tr('session.summary.streak'),
              ),
              const SizedBox(width: 10),
              _statBox(
                icon: Icons.flag_outlined,
                iconColor: const Color(0xFF4ADE80),
                value: '$learnedToday / $dailyGoal',
                label: context.tr('session.summary.goal'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22d3ee),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                context.tr('session.summary.cta'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
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

  Widget _statBox({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
