// lib/features/games/note_values/tempo_order_screen.dart
//
// "Slow to Fast" — the ordering/sequence format applied to *tempo words*: four
// Italian tempo terms appear shuffled; tap them from slowest to fastest. Each
// correct tap locks with a number badge; a wrong tap buzzes. The tempo sibling
// of Longest First / Soft to Loud — a distinct skill from comparing two
// (Faster or Slower?) or matching a term to its meaning (Connect the Tempo
// Words): here it's the whole Largo…Presto ladder in order.
//
// When the order is complete a "Good to know" card names the four words
// ("Andante = gehend") each with a beat dot pulsing at its typical speed; the
// solved round holds for kExplanationHold (or until "Next").
//
// SRI: 'reading.tempo.order'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/note_values/tempo_duel_screen.dart'
    show TempoTerm, kTempoTerms;
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TempoOrderScreen extends StatefulWidget {
  const TempoOrderScreen({super.key});

  static const cardCount = 4;

  @override
  State<TempoOrderScreen> createState() => _TempoOrderScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TempoOrderTester {
  /// Card display-indices in the correct tap order (slowest → fastest).
  List<int> get tapOrder;
  bool get isFinished;
}

class _TempoOrderScreenState extends State<TempoOrderScreen>
    with QuizRoundMixin
    implements TempoOrderTester {
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

  late List<TempoTerm> _cards; // shuffled display order
  late List<int> _rank; // _rank[i] = target position of _cards[i] (0 = slowest)
  int _placed = 0;

  /// Terms the explanation card shows (empty until the order is complete).
  List<MusicTerm> _explain = const [];

  @override
  int get totalRounds => 8;
  @override
  String get gameType => 'tempo_order';
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
  void prepareRound() {
    _cards = [...kTempoTerms]..shuffle(_random);
    _cards = _cards.take(TempoOrderScreen.cardCount).toList();
    // Rank slowest → fastest. Terms have distinct ranks, so no ties.
    final order = List.generate(_cards.length, (i) => i)
      ..sort((a, b) => _cards[a].rank.compareTo(_cards[b].rank));
    _rank = List.filled(_cards.length, 0);
    for (var r = 0; r < order.length; r++) {
      _rank[order[r]] = r;
    }
    _placed = 0;
    _explain = const [];
  }

  static const _sriId = 'reading.tempo.order';

  void _onTap(int index) {
    if (_rank[index] < _placed) return; // already placed

    if (_rank[index] == _placed) {
      setState(() => _placed++);
      if (_placed == TempoOrderScreen.cardCount) {
        if (!answeredWrong) {
          context.read<SriService>().recordResponse(_sriId, true);
        }
        setState(
          () => _explain = [
            for (final t in _cards) MusicTerm.tempoFromMark(t.name)!,
          ]..sort((a, b) => a.rank.compareTo(b.rank)),
        );
        resolveAnswer(correct: true);
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
      appBar: GameAppBar(title: l10n.gameTempoOrder),
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
                      prompt: l10n.tempoOrderPrompt,
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
                              _TempoCard(
                                key: ValueKey('tempo_card_$i'),
                                term: _cards[i],
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
                        onNext: advancePending ? advanceNow : null,
                      )
                    else
                      Text(
                        l10n.tempoOrderHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TempoCard extends StatelessWidget {
  final TempoTerm term;

  /// 1-based lock position once placed, else null (still tappable).
  final int? placedOrder;
  final VoidCallback onTap;

  const _TempoCard({
    super.key,
    required this.term,
    required this.placedOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placed = placedOrder != null;
    return GestureDetector(
      onTap: placed ? null : onTap,
      child: Container(
        width: 116,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: placed ? Colors.green.shade100 : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: placed ? Colors.green : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              term.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
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
