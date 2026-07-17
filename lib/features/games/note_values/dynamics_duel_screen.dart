// lib/features/games/note_values/dynamics_duel_screen.dart
//
// "Louder or Softer?" - two dynamic marks side by side; the child taps the
// louder one. Trains the dynamics vocabulary (pp .. ff) as an ordering, the
// reading twin of the aural loud/soft sense (the sibling of Faster or Slower?).
// The marks are the real SMuFL dynamic glyphs. No-fail loop (a wrong tap buzzes;
// the answer is shown).
//
// SRI: 'reading.dynamics.<mark>' - both marks are recorded each round.

import 'dart:math';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One dynamic mark: its SMuFL glyph [code] point, its [name] (for the SRI
/// item), and its relative loudness [rank] (softer -> louder).
typedef DynamicMark = ({int code, String name, int rank});

/// The dynamic marks the game draws from, softest to loudest. The codes are the
/// standard SMuFL dynamics (single-glyph combined marks for pp/mp/mf/ff).
const kDynamicMarks = <DynamicMark>[
  (code: 0xE52B, name: 'pp', rank: 1), // dynamicPP
  (code: 0xE520, name: 'p', rank: 2), // dynamicPiano
  (code: 0xE52C, name: 'mp', rank: 3), // dynamicMP
  (code: 0xE52D, name: 'mf', rank: 4), // dynamicMF
  (code: 0xE522, name: 'f', rank: 5), // dynamicForte
  (code: 0xE52F, name: 'ff', rank: 6), // dynamicFF
];

class DynamicsDuelScreen extends StatefulWidget {
  const DynamicsDuelScreen({super.key});

  @override
  State<DynamicsDuelScreen> createState() => _DynamicsDuelScreenState();
}

class _DynamicsDuelScreenState extends State<DynamicsDuelScreen>
    with QuizRoundMixin<DynamicsDuelScreen> {
  final _random = Random();

  late DynamicMark _left;
  late DynamicMark _right;
  DynamicMark? _tapped;

  DynamicMark get _louder => _left.rank >= _right.rank ? _left : _right;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'dynamics_duel';

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    final pool = [...kDynamicMarks]..shuffle(_random);
    _left = pool.first;
    _right = pool.firstWhere((m) => m.rank != _left.rank);
    _tapped = null;
  }

  String _sriId(DynamicMark m) => 'reading.dynamics.${m.name}';

  void _onTap(DynamicMark choice) {
    if (_tapped == _louder) return; // round already resolved
    final correct = choice == _louder;

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
      appBar: GameAppBar(title: l10n.gameDynamicsDuel),
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
                      correct: _tapped == null ? null : _tapped == _louder,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.whichIsLouder,
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
                      correct: _tapped == null ? null : _tapped == _louder,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _duelCard(DynamicMark mark) {
    final Color? border = _tapped == null
        ? null
        : mark == _louder && _tapped == _louder
            ? Colors.green
            : mark == _tapped
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
        onTap: () => _onTap(mark),
        child:
            Center(child: MusicGlyph(String.fromCharCode(mark.code), size: 96)),
      ),
    );
  }
}
