// lib/features/games/note_values/value_order_screen.dart
//
// "Longest First" — the ordering/sequence format applied to note *values*: four
// note-value symbols appear shuffled; tap them from the longest to the shortest.
// Each correct tap plays that duration and locks with a number badge; a wrong
// tap buzzes. The note-values sibling of Note Order (which orders pitches).
//
// SRI: 'note_values.order.len<N>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/symbol_catalog.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ValueOrderScreen extends StatefulWidget {
  const ValueOrderScreen({super.key});

  static const cardCount = 4;

  @override
  State<ValueOrderScreen> createState() => _ValueOrderScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ValueOrderTester {
  /// Card display-indices in the correct tap order (longest → shortest).
  List<int> get tapOrder;
  bool get isFinished;
}

class _ValueOrderScreenState extends State<ValueOrderScreen>
    with QuizRoundMixin
    implements ValueOrderTester {
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

  // The five note values (whole → sixteenth); rests aren't used here.
  static final _pool =
      kNoteSymbols.where((s) => !s.id.contains('rest')).toList();

  late List<NoteSymbol> _cards; // shuffled display order
  late List<int> _rank; // _rank[i] = target position of _cards[i] (0 = longest)
  int _placed = 0;

  @override
  int get totalRounds => 8;
  @override
  String get gameType => 'value_order';
  @override
  bool get playFeedbackSounds => false; // each tap plays its own duration

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _cards = [..._pool]..shuffle(_random);
    _cards = _cards.take(ValueOrderScreen.cardCount).toList();
    // Rank longest → shortest (largest beats first). Values are distinct, so
    // no ties.
    final order = List.generate(_cards.length, (i) => i)
      ..sort((a, b) => _cards[b].beats.compareTo(_cards[a].beats));
    _rank = List.filled(_cards.length, 0);
    for (var r = 0; r < order.length; r++) {
      _rank[order[r]] = r;
    }
    _placed = 0;
  }

  String get _sriId => 'note_values.order.len${ValueOrderScreen.cardCount}';

  void _onTap(int index) {
    if (_rank[index] < _placed) return; // already placed
    final audio = context.read<AudioService>();

    if (_rank[index] == _placed) {
      audio.playNoteLength(_cards[index].beats * 4, isRest: false);
      setState(() => _placed++);
      if (_placed == ValueOrderScreen.cardCount) {
        if (!answeredWrong) {
          context.read<SriService>().recordResponse(_sriId, true);
        }
        resolveAnswer(correct: true);
      }
    } else {
      audio.playWrong();
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
      appBar: GameAppBar(title: l10n.gameValueOrder),
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
                      prompt: l10n.valueOrderPrompt,
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
                              _ValueCard(
                                key: ValueKey('value_card_$i'),
                                symbol: _cards[i],
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
                      l10n.valueOrderHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  final NoteSymbol symbol;

  /// 1-based lock position once placed, else null (still tappable).
  final int? placedOrder;
  final VoidCallback onTap;

  const _ValueCard({
    super.key,
    required this.symbol,
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
            Center(child: MusicGlyph(symbol.glyph, size: 52)),
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
