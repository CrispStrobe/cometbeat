// lib/features/games/note_reading/odd_one_out_screen.dart
//
// "Odd One Out" — a reading-discrimination drill: three notes appear; two share
// the same letter name (at different octaves), one is a different letter. Tap
// the odd one out. Trains rapid letter-name reading across the staff rather
// than mere notehead matching. A new discrimination format (see docs/PLAN.md).
//
// Star-gated range (staff → ledger octaves), colour-scaffold aware, keyboard
// 1/2/3, reacting mascot. SRI: 'note_reading.<clef>.<step><octave>' on the odd
// note, so it feeds the same reading pool as the Reading Quiz.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _wholeNote = NoteDuration(DurationBase.whole);

class OddOneOutScreen extends StatefulWidget {
  const OddOneOutScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const cardCount = 3;

  @override
  State<OddOneOutScreen> createState() => _OddOneOutScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class OddOneOutTester {
  /// Display index of the odd-letter card in the current round.
  int get oddIndex;
}

class _OddOneOutScreenState extends State<OddOneOutScreen>
    with QuizRoundMixin
    implements OddOneOutTester {
  @override
  int get oddIndex => _oddIndex;

  final _random = Random();

  late List<Pitch> _cards; // display order
  late int _oddIndex; // which display card is the odd letter
  int? _wrongIndex; // last wrong tap, for red feedback
  bool _solved = false;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'odd_one_out';

  @override
  String get progressId =>
      widget.clef == Clef.bass ? 'odd_one_out_bass' : 'odd_one_out';

  // We play the odd note's own pitch on a correct tap; buzz on a wrong one.
  @override
  bool get playFeedbackSounds => false;

  // Number keys 1–3 whack the matching card.
  static final _digitKeys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.numpad1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.numpad2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.numpad3: 2,
  };

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  List<int> _octavePool() {
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    if (widget.clef == Clef.bass) {
      return wide ? [1, 2, 3, 4] : [2, 3];
    }
    return wide ? [3, 4, 5, 6] : [4, 5];
  }

  @override
  void prepareRound() {
    final steps = List<Step>.from(Step.values)..shuffle(_random);
    final commonStep = steps[0];
    final oddStep = steps[1];
    final octs = _octavePool()..shuffle(_random);

    // Two common notes at two distinct octaves + one odd-letter note.
    final cards = <Pitch>[
      Pitch(commonStep, octave: octs[0]),
      Pitch(commonStep, octave: octs[1]),
      Pitch(oddStep, octave: octs[_random.nextInt(octs.length)]),
    ];
    final order = [0, 1, 2]..shuffle(_random);
    _cards = [for (final i in order) cards[i]];
    _oddIndex = order.indexOf(2);
    _wrongIndex = null;
    _solved = false;
  }

  String _sriId(Pitch p) =>
      'note_reading.${widget.clef.name}.${p.step.name}${p.octave}';

  void _onTap(int index) {
    if (_solved) return;
    final odd = _cards[_oddIndex];
    final correct = index == _oddIndex;

    if (correct) {
      context.read<AudioService>().playMidiNote(odd.midiNumber);
      context.read<SriService>().recordResponse(_sriId(odd), true);
      setState(() => _solved = true);
      resolveAnswer(correct: true);
    } else {
      context.read<AudioService>().playWrong();
      if (!answeredWrong) {
        context.read<SriService>().recordResponse(_sriId(odd), false);
      }
      setState(() {
        answeredWrong = true;
        _wrongIndex = index;
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final i = _digitKeys[event.logicalKey];
    if (i == null || i >= OddOneOutScreen.cardCount) {
      return KeyEventResult.ignored;
    }
    _onTap(i);
    return KeyEventResult.handled;
  }

  NoteMascotMood get _mascotMood => _solved
      ? NoteMascotMood.happy
      : (answeredWrong ? NoteMascotMood.oops : NoteMascotMood.idle);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScaffold = context.watch<SettingsService>().colorScaffold;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameOddOneOut),
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
                        prompt: l10n.oddOneOutPrompt,
                      ),
                      const SizedBox(height: 8),
                      NoteMascot(mood: _mascotMood, size: 40),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (var i = 0; i < _cards.length; i++)
                                _NoteCard(
                                  pitch: _cards[i],
                                  clef: widget.clef,
                                  colorScaffold: colorScaffold,
                                  state: _solved && i == _oddIndex
                                      ? _CardState.correct
                                      : (_wrongIndex == i
                                          ? _CardState.wrong
                                          : _CardState.idle),
                                  onTap: () => _onTap(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.oddOneOutHint,
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

class _NoteCard extends StatelessWidget {
  final Pitch pitch;
  final Clef clef;
  final bool colorScaffold;
  final _CardState state;
  final VoidCallback onTap;

  const _NoteCard({
    required this.pitch,
    required this.clef,
    required this.colorScaffold,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (border, fill) = switch (state) {
      _CardState.correct => (Colors.green, Colors.green.shade100),
      _CardState.wrong => (Colors.red, Colors.red.shade100),
      _CardState.idle => (theme.dividerColor, theme.cardColor),
    };
    final staffTheme = colorScaffold
        ? kidsScoreTheme.copyWith(
            elementColors: {'n': pitchClassColor(pitch.step)},
          )
        : kidsScoreTheme;

    return GestureDetector(
      onTap: state == _CardState.idle ? onTap : null,
      child: Container(
        width: 96,
        height: 128,
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
            staffSpace: 8,
            theme: staffTheme,
          ),
        ),
      ),
    );
  }
}
