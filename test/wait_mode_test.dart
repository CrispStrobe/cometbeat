// "Wait mode" pacing: a wrong answer never advances the round or fails the
// game — the child retries until correct, at their own pace. This is the
// behaviour of QuizRoundMixin.resolveAnswer, which every quiz game shares, so
// the contract is tested once here at the source.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _WaitGame extends StatefulWidget {
  const _WaitGame();
  @override
  State<_WaitGame> createState() => _WaitGameState();
}

class _WaitGameState extends State<_WaitGame> with QuizRoundMixin<_WaitGame> {
  @override
  int get totalRounds => 3;
  @override
  String get gameType => 'note_value_quiz';
  @override
  void prepareRound() {}
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('a wrong answer never advances or fails the round',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => ProgressService()),
        ],
        child: const MaterialApp(home: _WaitGame()),
      ),
    );
    final state = tester.state<_WaitGameState>(find.byType(_WaitGame));

    // Repeated wrong answers: the round never moves, the game never finishes.
    for (var i = 0; i < 3; i++) {
      state.resolveAnswer(correct: false);
      await tester.pump();
      expect(state.round, 0);
      expect(state.finished, isFalse);
      expect(state.answeredWrong, isTrue);
    }

    // The correct answer finally advances (after the 700ms auto-advance).
    state.resolveAnswer(correct: true);
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.round, 1);
  });
}
