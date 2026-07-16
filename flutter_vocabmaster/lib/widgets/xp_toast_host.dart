import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_state_provider.dart';

/// Global "+15 XP" bildirimi: MaterialApp.builder içinde tüm ekranların
/// üzerinde yaşar, AppStateProvider'ın xpGainSeq olayını dinler ve her
/// pozitif XP kazancında kısa süreliğine küçük bir rozet gösterir.
/// Seviye atlanınca rozet büyür ve "Level up!" yazar.
class XpToastHost extends StatefulWidget {
  final Widget child;

  const XpToastHost({super.key, required this.child});

  @override
  State<XpToastHost> createState() => _XpToastHostState();
}

class _XpToastHostState extends State<XpToastHost> {
  AppStateProvider? _appState;
  int _lastSeenSeq = 0;
  int _lastSeenGoalSeq = 0;
  int _lastSeenFreezeSeq = 0;
  int _visibleAmount = 0;
  bool _visibleLevelUp = false;
  bool _visibleGoalComplete = false;
  bool _visibleFreezeUsed = false;
  bool _showing = false;
  Timer? _hideTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppStateProvider>();
    if (!identical(appState, _appState)) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = appState;
      _lastSeenSeq = appState.xpGainSeq;
      _lastSeenGoalSeq = appState.dailyGoalCelebrationSeq;
      _lastSeenFreezeSeq = appState.streakFreezeUsedSeq;
      appState.addListener(_onAppStateChanged);
    }
  }

  void _onAppStateChanged() {
    final appState = _appState;
    if (appState == null) {
      return;
    }
    // Dondurucu kullanımı ve hedef kutlaması XP chip'inden önceliklidir.
    if (appState.streakFreezeUsedSeq != _lastSeenFreezeSeq) {
      _lastSeenFreezeSeq = appState.streakFreezeUsedSeq;
      _lastSeenSeq = appState.xpGainSeq;
      _presentToast(
        amount: 0,
        levelUp: false,
        goalComplete: false,
        freezeUsed: true,
        durationMs: 3000,
      );
      return;
    }
    if (appState.dailyGoalCelebrationSeq != _lastSeenGoalSeq) {
      _lastSeenGoalSeq = appState.dailyGoalCelebrationSeq;
      _lastSeenSeq = appState.xpGainSeq;
      _presentToast(
        amount: appState.lastXpGainAmount,
        levelUp: false,
        goalComplete: true,
        freezeUsed: false,
        durationMs: 3000,
      );
      return;
    }
    if (appState.xpGainSeq == _lastSeenSeq) {
      return;
    }
    _lastSeenSeq = appState.xpGainSeq;
    _presentToast(
      amount: appState.lastXpGainAmount,
      levelUp: appState.lastXpGainLeveledUp,
      goalComplete: false,
      freezeUsed: false,
      durationMs: appState.lastXpGainLeveledUp ? 2600 : 1500,
    );
  }

  void _presentToast({
    required int amount,
    required bool levelUp,
    required bool goalComplete,
    required bool freezeUsed,
    required int durationMs,
  }) {
    _hideTimer?.cancel();
    setState(() {
      _visibleAmount = amount;
      _visibleLevelUp = levelUp;
      _visibleGoalComplete = goalComplete;
      _visibleFreezeUsed = freezeUsed;
      _showing = true;
    });
    _hideTimer = Timer(Duration(milliseconds: durationMs), () {
      if (mounted) {
        setState(() => _showing = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: IgnorePointer(
              child: AnimatedSlide(
                offset: _showing ? Offset.zero : const Offset(0, -1.2),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _showing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _visibleFreezeUsed
                              ? const Color(0xFF60A5FA)
                              : _visibleGoalComplete
                                  ? const Color(0xFF4ADE80)
                                  : _visibleLevelUp
                                      ? const Color(0xFFFACC15)
                                      : const Color(0xFF22d3ee)
                                          .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _visibleFreezeUsed
                                ? '❄️'
                                : _visibleGoalComplete
                                    ? '🎯'
                                    : _visibleLevelUp
                                        ? '🎉'
                                        : '⚡',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _visibleFreezeUsed
                                ? context.tr('streak.freeze.used')
                                : _visibleGoalComplete
                                    ? context.tr('goal.toast.complete')
                                    : _visibleLevelUp
                                        ? '${context.tr('xp.toast.levelUp')}  +$_visibleAmount XP'
                                        : '+$_visibleAmount XP',
                            style: TextStyle(
                              color: _visibleFreezeUsed
                                  ? const Color(0xFF60A5FA)
                                  : _visibleGoalComplete
                                      ? const Color(0xFF4ADE80)
                                      : _visibleLevelUp
                                          ? const Color(0xFFFACC15)
                                          : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
