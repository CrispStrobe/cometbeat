// lib/features/games/note_reading/staff_runner_screen.dart
//
// "Staff Runner" — endless generative sight-reading at kid scale (docs/PLAN.md
// original concepts, a stepping-stone to the generative-sight-reading big
// swing). One note sits at the read-line with a depleting timer bar; name it
// before the bar empties. Every correct read speeds up the next; three misses
// (wrong name or a timeout) end the run. Score = notes read.
//
// Star-gated range like the reading quizzes. SRI: 'note_reading.<clef>.<step>
// <octave>', the shared reading pool.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _wholeNote = NoteDuration(DurationBase.whole);

class StaffRunnerScreen extends StatefulWidget {
  const StaffRunnerScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const _kMaxLives = 3;

  @visibleForTesting
  static const maxLives = _kMaxLives;

  static const _steps = [
    Step.c,
    Step.d,
    Step.e,
    Step.f,
    Step.g,
    Step.a,
    Step.b,
  ];

  @override
  State<StaffRunnerScreen> createState() => _StaffRunnerScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class StaffRunnerTester {
  int get score;
  int get lives;
  bool get finished;
  Step get targetStep;

  /// Milliseconds the current note has left before it times out.
  int get remainingMs;
}

class _StaffRunnerScreenState extends State<StaffRunnerScreen>
    with SingleTickerProviderStateMixin
    implements StaffRunnerTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  late Pitch _target;
  int _noteStartMs = 0;
  int _noteMs = 4000;
  int _score = 0;
  int _lives = StaffRunnerScreen._kMaxLives;
  bool _wide = false;
  bool _finished = false;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  @override
  int get score => _score;
  @override
  int get lives => _lives;
  @override
  bool get finished => _finished;
  @override
  Step get targetStep => _target.step;
  @override
  int get remainingMs => (_noteStartMs + _noteMs) - _now.value;

  String get _gameId =>
      widget.clef == Clef.bass ? 'staff_runner_bass' : 'staff_runner';

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(_gameId) >= 2;
    _nextNote(0);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  // Time budget per note shrinks as the streak grows — the "speed up".
  int _budgetFor(int score) => (4000 - 120 * score).clamp(1600, 4000);

  void _nextNote(int now) {
    final pos = _wide ? -3 + _random.nextInt(14) : _random.nextInt(9);
    _target = widget.clef.pitchAt(pos);
    _noteStartMs = now;
    _noteMs = _budgetFor(_score);
  }

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;
    _now.value = now;
    if (now - _noteStartMs > _noteMs) {
      _miss(timedOut: true);
    }
  }

  String _sriId(Pitch p) =>
      'note_reading.${widget.clef.name}.${p.step.name}${p.octave}';

  void _onLetter(Step step) {
    if (_finished) return;
    if (step == _target.step) {
      context.read<AudioService>().playMidiNote(_target.midiNumber, ms: 340);
      context.read<SriService>().recordResponse(_sriId(_target), true);
      setState(() {
        _score++;
        _mascot = NoteMascotMood.happy;
        _nextNote(_now.value);
      });
    } else {
      _miss(timedOut: false);
    }
  }

  void _miss({required bool timedOut}) {
    context.read<AudioService>().playWrong();
    context.read<SriService>().recordResponse(_sriId(_target), false);
    _lives--;
    _mascot = NoteMascotMood.oops;
    if (_lives <= 0) {
      _finish();
    } else {
      setState(() => _nextNote(_now.value));
    }
  }

  static final _letterKeys = <LogicalKeyboardKey, Step>{
    LogicalKeyboardKey.keyC: Step.c,
    LogicalKeyboardKey.keyD: Step.d,
    LogicalKeyboardKey.keyE: Step.e,
    LogicalKeyboardKey.keyF: Step.f,
    LogicalKeyboardKey.keyG: Step.g,
    LogicalKeyboardKey.keyA: Step.a,
    LogicalKeyboardKey.keyB: Step.b,
  };

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final step = _letterKeys[event.logicalKey];
    if (step == null) return KeyEventResult.ignored;
    _onLetter(step);
    return KeyEventResult.handled;
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    final stars = scoreToStars(_gameId, _score, true);
    context.read<ProgressService>().recordResult(
          _gameId,
          score: _score,
          stars: stars,
          elapsedMs: _now.value,
        );
    context.read<AudioService>().playFanfare();
    setState(() => _mascot = NoteMascotMood.oops);
  }

  void _restart() {
    _ticker.stop();
    setState(() {
      _score = 0;
      _lives = StaffRunnerScreen._kMaxLives;
      _finished = false;
      _mascot = NoteMascotMood.idle;
      _nextNote(0);
    });
    _now.value = 0;
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScaffold = context.watch<SettingsService>().colorScaffold;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameStaffRunner),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: _gameId,
                score: _score,
                onRestart: _restart,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: _onKeyEvent,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          NoteMascot(mood: _mascot, size: 30),
                          const SizedBox(width: 8),
                          const Icon(Icons.star, color: Colors.amber, size: 22),
                          const SizedBox(width: 4),
                          Text(
                            '$_score',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          for (var i = 0; i < StaffRunnerScreen._kMaxLives; i++)
                            Icon(
                              i < _lives
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: i < _lives
                                  ? Colors.redAccent
                                  : scheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                    // Timer bar: the note's remaining reading time.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _now,
                        builder: (context, now, _) {
                          final frac = (1 - (now - _noteStartMs) / _noteMs)
                              .clamp(0.0, 1.0);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: frac,
                              minHeight: 10,
                              backgroundColor: scheme.surfaceContainerHighest,
                              color: frac < 0.3 ? scheme.error : scheme.primary,
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 16,
                            ),
                            child: StaffView(
                              score: Score(
                                clef: widget.clef,
                                measures: [
                                  Measure([
                                    NoteElement.note(
                                      _target,
                                      _wholeNote,
                                      id: 'target',
                                    ),
                                  ]),
                                ],
                              ),
                              staffSpace: 16,
                              theme: colorScaffold
                                  ? kidsScoreTheme.copyWith(
                                      elementColors: {
                                        'target': pitchClassColor(_target.step),
                                      },
                                    )
                                  : kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _LetterPad(
                      steps: StaffRunnerScreen._steps,
                      onTap: _onLetter,
                      colorScaffold: colorScaffold,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The 7-letter naming pad, tinted by pitch class when the colour scaffold is on.
class _LetterPad extends StatelessWidget {
  const _LetterPad({
    required this.steps,
    required this.onTap,
    required this.colorScaffold,
  });

  final List<Step> steps;
  final ValueChanged<Step> onTap;
  final bool colorScaffold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      child: Row(
        children: [
          for (final step in steps)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: SizedBox(
                  height: 60,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: colorScaffold
                          ? pitchClassColor(step).withValues(alpha: 0.30)
                          : null,
                      textStyle: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => onTap(step),
                    child: Text(noteNameFor(context, step)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
