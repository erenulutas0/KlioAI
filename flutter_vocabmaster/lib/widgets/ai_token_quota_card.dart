import 'package:flutter/material.dart';

import '../services/locale_text_service.dart';

class AiTokenQuotaCard extends StatelessWidget {
  final bool isLoading;
  final int tokenLimit;
  final int tokensUsed;
  final int tokensRemaining;
  final double remainingRatio;
  final String? quotaDateUtc;
  final Map<String, int>? activityEstimates;
  final VoidCallback onRefresh;

  /// Non-null when the last quota request FAILED (auth/network/server).
  /// Kept separate from tokenLimit == 0 so a load failure is never
  /// mislabeled as "quota is not active" (a paying user seeing that text
  /// because of a transient 401 reads it as "my subscription is broken").
  final String? errorText;

  const AiTokenQuotaCard({
    super.key,
    required this.isLoading,
    required this.tokenLimit,
    required this.tokensUsed,
    required this.tokensRemaining,
    required this.remainingRatio,
    required this.quotaDateUtc,
    this.activityEstimates,
    required this.onRefresh,
    this.errorText,
  });

  /// Turns the backend token->action estimates into a short, human-readable
  /// line like "≈ 5 conversations · 6 checks left". Returns null when there is
  /// nothing meaningful to show so the raw token numbers stand on their own.
  String? _activityHint(bool isTurkish) {
    final estimates = activityEstimates;
    if (estimates == null || estimates.isEmpty) return null;

    final conversations = estimates['conversations'] ?? 0;
    final checks = estimates['translationChecks'] ?? 0;

    final parts = <String>[];
    if (conversations > 0) {
      parts.add(isTurkish
          ? '$conversations konuşma'
          : '$conversations conversation${conversations == 1 ? '' : 's'}');
    }
    if (checks > 0) {
      parts.add(isTurkish
          ? '$checks çeviri kontrolü'
          : '$checks translation check${checks == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) return null;

    final joined = parts.join(isTurkish ? ' · ' : ' · ');
    return isTurkish ? '≈ $joined kaldı' : '≈ $joined left';
  }

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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLoading)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                minHeight: 10,
              ),
            )
          else if (errorText != null)
            GestureDetector(
              onTap: onRefresh,
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 14, color: Colors.orange.withValues(alpha: 0.9)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12),
                    ),
                  ),
                  Text(
                    text('Yenile', 'Retry'),
                    style: const TextStyle(
                        color: Color(0xFF22d3ee),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else if (tokenLimit <= 0)
            Text(
              text('Token kotasi aktif degil.', 'Token quota is not active.'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
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
                      color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: remainingRatio.clamp(0.0, 1.0).toDouble(),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor:
                    AlwaysStoppedAnimation<Color>(_barColor(remainingPercent)),
                minHeight: 12,
              ),
            ),
            if (_activityHint(isTurkish) case final hint?) ...[
              const SizedBox(height: 8),
              Text(
                hint,
                style: const TextStyle(
                    color: Color(0xFF22d3ee),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              isTurkish
                  ? 'Kullanilan: ${tokensUsed.toString()} (%${usedPercent.toStringAsFixed(1)})${quotaDateUtc != null ? '  UTC: $quotaDateUtc' : ''}'
                  : 'Used: ${tokensUsed.toString()} (${usedPercent.toStringAsFixed(1)}%)${quotaDateUtc != null ? '  UTC: $quotaDateUtc' : ''}',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
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
