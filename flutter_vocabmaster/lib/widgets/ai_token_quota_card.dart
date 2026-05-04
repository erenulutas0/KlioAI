import 'package:flutter/material.dart';

import '../services/locale_text_service.dart';

class AiTokenQuotaCard extends StatelessWidget {
  final bool isLoading;
  final int tokenLimit;
  final int tokensUsed;
  final int tokensRemaining;
  final double remainingRatio;
  final String? quotaDateUtc;
  final VoidCallback onRefresh;

  const AiTokenQuotaCard({
    super.key,
    required this.isLoading,
    required this.tokenLimit,
    required this.tokensUsed,
    required this.tokensRemaining,
    required this.remainingRatio,
    required this.quotaDateUtc,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isTurkish = LocaleTextService.isTurkish;
    String text(String tr, String en) => isTurkish ? tr : en;
    final double remainingPercent =
        (remainingRatio * 100.0).clamp(0.0, 100.0).toDouble();
    final double usedPercent =
        (100.0 - remainingPercent).clamp(0.0, 100.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_outlined,
                  color: Color(0xFF22d3ee), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text('Gunluk AI Token', 'Daily AI Tokens'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: onRefresh,
                child: Icon(
                  Icons.refresh,
                  size: 16,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLoading)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.1),
                minHeight: 10,
              ),
            )
          else if (tokenLimit <= 0)
            Text(
              text('Token kotasi aktif degil.', 'Token quota is not active.'),
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tokensRemaining.toString()} / ${tokenLimit.toString()}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  isTurkish
                      ? '%${remainingPercent.toStringAsFixed(1)} kaldi'
                      : '${remainingPercent.toStringAsFixed(1)}% left',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: remainingRatio.clamp(0.0, 1.0).toDouble(),
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor:
                    AlwaysStoppedAnimation<Color>(_barColor(remainingPercent)),
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isTurkish
                  ? 'Kullanilan: ${tokensUsed.toString()} (%${usedPercent.toStringAsFixed(1)})${quotaDateUtc != null ? '  UTC: $quotaDateUtc' : ''}'
                  : 'Used: ${tokensUsed.toString()} (${usedPercent.toStringAsFixed(1)}%)${quotaDateUtc != null ? '  UTC: $quotaDateUtc' : ''}',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Color _barColor(double remainingPercent) {
    if (remainingPercent <= 15) {
      return const Color(0xFFef4444);
    }
    if (remainingPercent <= 35) {
      return const Color(0xFFf59e0b);
    }
    return const Color(0xFF10b981);
  }
}
