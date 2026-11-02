// lib/features/games/note_values/dynamics_order_screen.dart
//
// "Soft to Loud" — the ordering/sequence format applied to *dynamics*: four
// dynamic marks appear shuffled; tap them from the softest to the loudest. Each
// correct tap locks with a number badge; a wrong tap buzzes. The dynamics
// sibling of Longest First (which orders note values) — a distinct skill from
// matching a mark to its meaning (Connect the Dynamics) or comparing two
// (Louder or Softer?): here it's the whole pp…ff ladder in order.
//
// When the ladder is complete a "Good to know" card names the four marks
// ("mf  mezzoforte = halblaut") on the pp…ff loudness ladder and plays them
// softest → loudest, lighting each rung as it sounds; the solved round holds
// for kExplanationHold (or until "Next").
//
// SRI: 'reading.dynamics.order'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/dynamics_demo.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart'
    show DynamicMark, kDynamicMarks;
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DynamicsOrderScreen extends StatefulWidget {
  const DynamicsOrderScreen({super.key});

  static const cardCount = 4;

  @override
  State<DynamicsOrderScreen> createState() => _DynamicsOrderScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class DynamicsOrderTester {
  /// Card display-indices in the correct tap order (softest → loudest).
  List<int> get tapOrder;
  bool get isFinished;
}

class _DynamicsOrderScreenState extends State<DynamicsOrderScreen>
    with QuizRoundMixin
    implements DynamicsOrderTester {
  @override
  List<int> get tapOrder {
    final order = List.filled(_cards.length, 0);
    for (var i = 0; i < _rank.length; i++) {
      order[_rank[i]] = i;
    }
    return order;
  }

  @override
  bool get isFinished => finished;

  final _random = Random();

  late List<DynamicMark> _cards; // shuffled display order
  late List<int> _rank; // _rank[i] = target position of _cards[i] (0 = softest)
  int _placed = 0;

  /// Terms the explanation card shows (empty until the ladder is complete).
  List<MusicTerm> _explain = const [];
  final _demo = DynamicsDemo();

  @override
  int get totalRounds => 8;
  @override
  String get gameType => 'dynamics_order';
  @override
  bool get playFeedbackSounds => false; // a wrong tap buzzes; correct is silent

  @override
  Duration get advanceDelay => kExplanationHold;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void dispose() {
    _demo.dispose();
    super.dispose();
  }

  @override
  void prepareRound() {
    _cards = [...kDynamicMarks]..shuffle(_random);
    _cards = _cards.take(DynamicsOrderScreen.cardCount).toList();
    // Rank softest → loudest. Marks have distinct ranks, so no ties.
    final order = List.generate(_cards.length, (i) => i)
      ..sort((a, b) => _cards[a].rank.compareTo(_cards[b].rank));
    _rank = List.filled(_cards.length, 0);
    for (var r = 0; r < order.length; r++) {
      _rank[order[r]] = r;
    }
    _placed = 0;
    _explain = const [];
    _demo.stop();
  }

  static const _sriId = 'reading.dynamics.order';

  void _onTap(int index) {
    if (_rank[index] < _placed) return; // already placed

    if (_rank[index] == _placed) {
      setState(() => _placed++);
      if (_placed == DynamicsOrderScreen.cardCount) {
        if (!answeredWrong) {
          context.read<SriService>().recordResponse(_sriId, true);
        }
        final ladder = [
          for (final m in _cards) MusicTerm.dynamicFromMark(m.name)!,
        ]..sort((a, b) => a.rank.compareTo(b.rank));
        setState(() => _explain = ladder);
        resolveAnswer(correct: true);
        if (!finished) {
          _demo.play(context.read<AudioService>(), ladder, notesPerLevel: 1);
        }
      }
    } else {
      context.read<AudioService>().playWrong();
      if (!answeredWrong) {
        context.read<SriService>().recordResponse(_sriId, false);
      }
      setState(() => answeredWrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameDynamicsOrder),
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
                      prompt: l10n.dynamicsOrderPrompt,
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
                              _DynamicCard(
                                key: ValueKey('dynamic_card_$i'),
                                mark: _cards[i],
                                placedOrder:
                                    _rank[i] < _placed ? _rank[i] + 1 : null,
                                onTap: () => _onTap(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_explain.isNotEmpty)
                      AnswerExplanation(
                        terms: _explain,
                        sounding: _demo.sounding,
                        onNext: advancePending ? advanceNow : null,
                      )
                    else
                      Text(
                        l10n.dynamicsOrderHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _DynamicCard extends StatelessWidget {
  final DynamicMark mark;

  /// 1-based lock position once placed, else null (still tappable).
  final int? placedOrder;
  final VoidCallback onTap;

  const _DynamicCard({
    super.key,
    required this.mark,
    required this.placedOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placed = placedOrder != null;
    return GestureDetector(
      onTap: placed ? null : onTap,
      child: Container(
        width: 96,
        height: 100,
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
            Center(child: MusicGlyph(String.fromCharCode(mark.code), size: 44)),
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
