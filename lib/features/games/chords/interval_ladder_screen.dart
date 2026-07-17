// lib/features/games/chords/interval_ladder_screen.dart
//
// "Interval Ladder" — interval *construction* (docs/PLAN.md original concepts).
// A base note is shown; a chip says how far and which way to climb (▲3 = a
// third up); the child taps the candidate note at that interval. Trains
// building intervals on the staff, not just naming them.
//
// Star-gated: thirds/fifths up for beginners; all sizes and both directions at
// 2★. SRI: 'chords.interval.build.<n><up|down>' (diatonic step distance).

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _wholeNote = NoteDuration(DurationBase.whole);

/// A diatonic interval: its ordinal (as shown, e.g. 3 for a third) and the
/// number of staff positions it spans (a third = 2 positions).
class _Interval {
  const _Interval(this.ordinal, this.steps);
  final int ordinal;
  final int steps;
}

const _intervals = <_Interval>[
  _Interval(2, 1),
  _Interval(3, 2),
  _Interval(4, 3),
  _Interval(5, 4),
  _Interval(6, 5),
  _Interval(8, 7),
];

class IntervalLadderScreen extends StatefulWidget {
  const IntervalLadderScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const optionCount = 4;

  @override
  State<IntervalLadderScreen> createState() => _IntervalLadderScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class IntervalLadderTester {
  /// Display index of the correct target card in the current round.
  int get correctIndex;
}

class _IntervalLadderScreenState extends State<IntervalLadderScreen>
    with QuizRoundMixin
    implements IntervalLadderTester {
  @override
  int get correctIndex => _correct;

  final _random = Random();

  late Pitch _base;
  late _Interval _interval;
  late bool _up;
  late List<Pitch> _options;
  late int _correct;
  int? _tapped;
  bool _solved = false;
  bool _wide = false;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'interval_ladder';

  @override
  bool get playFeedbackSounds => false;

  static final _digitKeys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.numpad1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.numpad2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.numpad3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.numpad4: 3,
  };

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  // Renderable staff-position window for the clef (a couple of ledger lines).
  static const _lo = -5;
  static const _hi = 12;

  @override
  void prepareRound() {
    final pool = _wide ? _intervals : const [_Interval(3, 2), _Interval(5, 4)];

    // Choose an interval, a direction, and a base note so the target still
    // lands inside the renderable window.
    late int basePos;
    late int targetPos;
    while (true) {
      _interval = pool[_random.nextInt(pool.length)];
      _up = _wide ? _random.nextBool() : true;
      basePos = _lo + 2 + _random.nextInt(_hi - _lo - 3);
      targetPos = basePos + (_up ? _interval.steps : -_interval.steps);
      if (targetPos >= _lo && targetPos <= _hi) break;
    }

    _base = widget.clef.pitchAt(basePos);
    final target = widget.clef.pitchAt(targetPos);

    // Distractors: the nearest available positions to the target (never the
    // base or the target), shuffled — always enough, even at the staff edges.
    final used = {basePos, targetPos};
    final candidates = [
      for (var pos = _lo; pos <= _hi; pos++)
        if (!used.contains(pos)) pos,
    ]..sort(
        (a, b) => (a - targetPos).abs().compareTo((b - targetPos).abs()),
      );
    final near = candidates.take(6).toList()..shuffle(_random);
    final distractors = [
      for (final pos in near.take(IntervalLadderScreen.optionCount - 1))
        widget.clef.pitchAt(pos),
    ];

    final cards = [target, ...distractors];
    final order = List.generate(cards.length, (i) => i)..shuffle(_random);
    _options = [for (final i in order) cards[i]];
    _correct = order.indexOf(0);
    _tapped = null;
    _solved = false;
  }

  String get _sriId =>
      'chords.interval.build.${_interval.ordinal}${_up ? 'up' : 'down'}';

  void _onTap(int index) {
    if (_solved) return;
    final audio = context.read<AudioService>();
    final correct = index == _correct;

    if (correct) {
      audio.playSequence([
        (_base.midiNumber, 380),
        (_options[_correct].midiNumber, 520),
      ]);
      context.read<SriService>().recordResponse(_sriId, true);
      setState(() => _solved = true);
      resolveAnswer(correct: true);
    } else {
      audio.playWrong();
      if (!answeredWrong) {
        context.read<SriService>().recordResponse(_sriId, false);
      }
      setState(() {
        answeredWrong = true;
        _tapped = index;
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final i = _digitKeys[event.logicalKey];
    if (i == null || i >= IntervalLadderScreen.optionCount) {
      return KeyEventResult.ignored;
    }
    _onTap(i);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameIntervalLadder),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      RoundHeader(
                        round: round + 1,
                        totalRounds: totalRounds,
                        prompt: l10n.intervalLadderPrompt,
                      ),
                      const SizedBox(height: 12),
                      // Base note + the "climb this far" chip.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _MiniStaff(pitch: _base, clef: widget.clef),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _up
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color: scheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_interval.ordinal}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: scheme.onPrimaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (var i = 0; i < _options.length; i++)
                                _MiniStaff(
                                  pitch: _options[i],
                                  clef: widget.clef,
                                  state: _solved && i == _correct
                                      ? _CardState.correct
                                      : (_tapped == i
                                          ? _CardState.wrong
                                          : _CardState.idle),
                                  onTap: () => _onTap(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        l10n.intervalLadderHint,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

enum _CardState { idle, correct, wrong }

class _MiniStaff extends StatelessWidget {
  const _MiniStaff({
    required this.pitch,
    required this.clef,
    this.state,
    this.onTap,
  });

  final Pitch pitch;
  final Clef clef;

  /// Null = the fixed base note (not a choice); otherwise a tappable option.
  final _CardState? state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (border, fill) = switch (state) {
      _CardState.correct => (Colors.green, Colors.green.shade100),
      _CardState.wrong => (Colors.red, Colors.red.shade100),
      _ => (theme.dividerColor, theme.cardColor),
    };

    final card = Container(
      width: 90,
      height: 116,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 2),
      ),
      child: Center(
        child: StaffView(
          score: Score(
            clef: clef,
            measures: [
              Measure([NoteElement.note(pitch, _wholeNote, id: 'n')]),
            ],
          ),
          staffSpace: 7,
          theme: kidsScoreTheme,
        ),
      ),
    );

    if (state == null) return card;
    return GestureDetector(
      onTap: state == _CardState.idle ? onTap : null,
      child: card,
    );
  }
}
