// lib/features/games/note_values/duration_duel_screen.dart
//
// "Was klingt länger?" — two symbols side by side, the child taps the one
// that lasts longer. Trains relative durations, including the insight that
// rests have lengths too (a half rest outlasts a quarter note).
//
// SRI: each round is recorded for BOTH symbols under their symbol items —
// knowing a symbol's duration is the same skill the quiz drills by name.

import 'dart:math';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/symbol_catalog.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DurationDuelScreen extends StatefulWidget {
  const DurationDuelScreen({super.key});

  @override
  State<DurationDuelScreen> createState() => _DurationDuelScreenState();
}

class _DurationDuelScreenState extends State<DurationDuelScreen>
    with QuizRoundMixin<DurationDuelScreen> {
  final _random = Random();

  late NoteSymbol _left;
  late NoteSymbol _right;
  NoteSymbol? _tapped;

  NoteSymbol get _longer => _left.beats >= _right.beats ? _left : _right;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'duration_duel';

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Draw two symbols with different durations.
    final pool = [...kNoteSymbols]..shuffle(_random);
    _left = pool.first;
    _right = pool.firstWhere((s) => s.beats != _left.beats);
    _tapped = null;
  }

  void _onTap(NoteSymbol choice) {
    if (_tapped == _longer) return; // round already resolved
    final correct = choice == _longer;

    if (_tapped == null || !answeredWrong) {
      final sri = context.read<SriService>();
      sri.recordResponse(_left.sriId, correct);
      sri.recordResponse(_right.sriId, correct);
    }

    setState(() => _tapped = choice);
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameDurationDuel),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _tapped == null ? null : _tapped == _longer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.whichLastsLonger,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _duelCard(_left)),
                          const SizedBox(width: 12),
                          Expanded(child: _duelCard(_right)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(
                      correct: _tapped == null ? null : _tapped == _longer,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _duelCard(NoteSymbol symbol) {
    final Color? border = _tapped == null
        ? null
        : symbol == _longer && _tapped == _longer
            ? Colors.green
            : symbol == _tapped
                ? Colors.redAccent
                : null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: border != null
            ? BorderSide(color: border, width: 4)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTap(symbol),
        child: Center(child: MusicGlyph(symbol.glyph, size: 84)),
      ),
    );
  }
}
