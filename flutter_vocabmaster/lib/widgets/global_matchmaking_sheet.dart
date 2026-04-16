import 'package:flutter/material.dart';
import '../services/global_state.dart';
import 'matchmaking_banner.dart';

class GlobalMatchmakingSheet extends StatelessWidget {
  const GlobalMatchmakingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.isMatching,
      builder: (context, isMatching, child) {
        if (!isMatching) return const SizedBox.shrink();
        
        return MatchmakingBanner(
          onCancel: () {
            GlobalState.matchmakingService.leaveQueue();
            GlobalState.isMatching.value = false;
          },
        );
      },
    );
  }
}

