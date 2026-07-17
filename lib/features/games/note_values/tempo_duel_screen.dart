// lib/features/games/note_values/tempo_duel_screen.dart
//
// "Faster or Slower?" — two Italian tempo terms side by side; the child taps the
// faster one. Trains the tempo-word vocabulary (Largo … Presto) as an ordering,
// the reading twin of the aural tempo sense. No staff, no glyphs — the marks are
// the words themselves. No-fail loop (a wrong tap buzzes; the answer is shown).
//
// SRI: 'reading.tempo.<term>' — both terms are recorded each round.

import 'dart:math';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One Italian tempo term with its relative speed [rank] (slower → faster).
typedef TempoTerm = ({String name, int rank});

/// The tempo words the game draws from, slowest to fastest.
const kTempoTerms = <TempoTerm>[
  (name: 'Largo', rank: 1),
  (name: 'Adagio', rank: 2),
  (name: 'Andante', rank: 3),
  (name: 'Moderato', rank: 4),
  (name: 'Allegro', rank: 5),
  (name: 'Vivace', rank: 6),
  (name: 'Presto', rank: 7),
];

class TempoDuelScreen extends StatefulWidget {
  const TempoDuelScreen({super.key});

  @override
  State<TempoDuelScreen> createState() => _TempoDuelScreenState();
}

class _TempoDuelScreenState extends State<TempoDuelScreen>
    with QuizRoundMixin<TempoDuelScreen> {
  final _random = Random();

  late TempoTerm _left;
  late TempoTerm _right;
  TempoTerm? _tapped;

  TempoTerm get _faster => _left.rank >= _right.rank ? _left : _right;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'tempo_duel';

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    final pool = [...kTempoTerms]..shuffle(_random);
    _left = pool.first;
    _right = pool.firstWhere((t) => t.rank != _left.rank);
    _tapped = null;
  }

  String _sriId(TempoTerm t) => 'reading.tempo.${t.name.toLowerCase()}';

  void _onTap(TempoTerm choice) {
    if (_tapped == _faster) return; // round already resolved
    final correct = choice == _faster;

    if (_tapped == null || !answeredWrong) {
      final sri = context.read<SriService>();
      sri.recordResponse(_sriId(_left), correct);
      sri.recordResponse(_sriId(_right), correct);
    }

    setState(() => _tapped = choice);
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTempoDuel),
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
                      correct: _tapped == null ? null : _tapped == _faster,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.whichIsFaster,
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
                      correct: _tapped == null ? null : _tapped == _faster,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _duelCard(TempoTerm term) {
    final Color? border = _tapped == null
        ? null
        : term == _faster && _tapped == _faster
            ? Colors.green
            : term == _tapped
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
        onTap: () => _onTap(term),
        child: Center(
          // Tempo marks are set in a bold italic serif.
          child: Text(
            term.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'serif',
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.bold,
              fontSize: 30,
            ),
          ),
        ),
      ),
    );
  }
}
