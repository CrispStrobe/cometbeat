// lib/features/games/note_reading/note_order_screen.dart
//
// "Der Reihe nach" — a sequencing game: four note cards appear shuffled; tap
// them from the lowest pitch to the highest. Each correct tap plays its pitch
// and locks with a number badge; a wrong tap buzzes and waits. The first
// ordering/sequence format in the app (see docs/PLAN.md gamification backlog).
//
// SRI: 'note_reading.order.len<N>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class NoteOrderScreen extends StatefulWidget {
  const NoteOrderScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const cardCount = 4;

  @override
  State<NoteOrderScreen> createState() => _NoteOrderScreenState();
}

class _NoteOrderScreenState extends State<NoteOrderScreen> with QuizRoundMixin {
  final _random = Random();

  late List<Pitch> _cards; // display order (shuffled)
  late List<int> _rank; // _rank[i] = ascending position of _cards[i]
  int _placed = 0; // how many correct in a row so far this round

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'note_order';

  @override
  String get progressId =>
      widget.clef == Clef.bass ? 'note_order_bass' : 'note_order';

  // Each tap plays its own pitch; wrong taps buzz.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Four distinct treble notes across the staff and ledger neighbourhood.
    final positions = [
      for (var p = -3; p <= 10; p++) p,
    ]..shuffle(_random);
    _cards = [
      for (final p in positions.take(NoteOrderScreen.cardCount))
        widget.clef.pitchAt(p),
    ];
    // Rank each card by pitch (ties impossible — positions are distinct).
    final order = List.generate(_cards.length, (i) => i)
      ..sort((a, b) => _cards[a].midiNumber.compareTo(_cards[b].midiNumber));
    _rank = List.filled(_cards.length, 0);
    for (var r = 0; r < order.length; r++) {
      _rank[order[r]] = r;
    }
    _placed = 0;
  }

  void _onTap(int index) {
    if (_rank[index] < _placed) return; // already placed
    final audio = context.read<AudioService>();

    if (_rank[index] == _placed) {
      // Correct next-lowest note.
      audio.playMidiNote(_cards[index].midiNumber, ms: 450);
      setState(() => _placed++);
      if (_placed == NoteOrderScreen.cardCount) {
        if (!answeredWrong) {
          context.read<SriService>().recordResponse(
                'note_reading.order.${widget.clef.name}.'
                'len${NoteOrderScreen.cardCount}',
                true,
              );
        }
        resolveAnswer(correct: true);
      }
    } else {
      // Out of order.
      audio.playWrong();
      if (!answeredWrong) {
        context.read<SriService>().recordResponse(
              'note_reading.order.${widget.clef.name}.'
              'len${NoteOrderScreen.cardCount}',
              false,
            );
      }
      setState(() => answeredWrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameNoteOrder),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.noteOrderPrompt,
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (var i = 0; i < _cards.length; i++)
                              _OrderCard(
                                pitch: _cards[i],
                                clef: widget.clef,
                                placedOrder:
                                    _rank[i] < _placed ? _rank[i] + 1 : null,
                                onTap: () => _onTap(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.noteOrderHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Pitch pitch;
  final Clef clef;

  /// 1-based lock position once placed, else null (still tappable).
  final int? placedOrder;
  final VoidCallback onTap;

  const _OrderCard({
    required this.pitch,
    required this.clef,
    required this.placedOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placed = placedOrder != null;
    return GestureDetector(
      onTap: placed ? null : onTap,
      child: Container(
        width: 84,
        height: 108,
        decoration: BoxDecoration(
          color: placed ? Colors.green.shade100 : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: placed ? Colors.green : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: StaffView(
                score: Score.simple(
                  clef: clef,
                  notes: '${pitch.step.name}${pitch.octave}:w',
                ),
                staffSpace: 7,
                theme: kidsScoreTheme,
              ),
            ),
            if (placed)
              Positioned(
                top: 4,
                left: 4,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.green,
                  child: Text(
                    '$placedOrder',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
