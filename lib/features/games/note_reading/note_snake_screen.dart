// lib/features/games/note_reading/note_snake_screen.dart
//
// "Note Snake" — reading + the classic arcade snake (docs/PLAN.md original
// concepts). A target note is shown on the staff; letters sit on a grid; steer
// the snake (arrow keys or the on-screen pad) to eat the letter that names the
// note. Eating the wrong letter — or biting your own tail — ends the run.
//
// Star-gated range like the reading quizzes. SRI: 'note_reading.<clef>.<step>
// <octave>' on the target note.

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

class NoteSnakeScreen extends StatefulWidget {
  const NoteSnakeScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const _cols = 6;
  static const _rows = 5;
  static const _foodCount = 4;

  @override
  State<NoteSnakeScreen> createState() => _NoteSnakeScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class NoteSnakeTester {
  int get score;
  bool get finished;
  Step get targetStep;

  /// Clears the board and drops a single [step] letter one cell ahead of the
  /// snake's head (wrapping), so a single tick will move onto it.
  void debugFoodAhead(Step step);
}

class _NoteSnakeScreenState extends State<NoteSnakeScreen>
    with SingleTickerProviderStateMixin
    implements NoteSnakeTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);

  // Head is first. Cells are Point(col, row).
  late List<Point<int>> _snake;
  Point<int> _dir = const Point(1, 0);
  Point<int> _pendingDir = const Point(1, 0);
  final Map<Point<int>, Step> _food = {};

  late Pitch _target;
  int _lastMoveMs = 0;
  int _score = 0;
  bool _wide = false;
  bool _finished = false;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  @override
  int get score => _score;
  @override
  bool get finished => _finished;
  @override
  Step get targetStep => _target.step;

  String get _gameId =>
      widget.clef == Clef.bass ? 'note_snake_bass' : 'note_snake';

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(_gameId) >= 2;
    _snake = [const Point(2, 2), const Point(1, 2)];
    for (var i = 0; i < NoteSnakeScreen._foodCount; i++) {
      _spawnFood();
    }
    _pickTarget();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _stepMs() => (480 - 12 * _score).clamp(260, 480);

  Iterable<Point<int>> get _empties sync* {
    for (var r = 0; r < NoteSnakeScreen._rows; r++) {
      for (var c = 0; c < NoteSnakeScreen._cols; c++) {
        final p = Point(c, r);
        if (!_snake.contains(p) && !_food.containsKey(p)) yield p;
      }
    }
  }

  void _spawnFood() {
    final empties = _empties.toList();
    if (empties.isEmpty) return;
    final cell = empties[_random.nextInt(empties.length)];
    _food[cell] = Step.values[_random.nextInt(Step.values.length)];
  }

  // The target's letter must be present among the current food.
  void _pickTarget() {
    final steps = _food.values.toSet().toList();
    final step = steps[_random.nextInt(steps.length)];
    final octs = widget.clef == Clef.bass
        ? (_wide ? [2, 3, 4] : [2, 3])
        : (_wide ? [4, 5, 6] : [4, 5]);
    _target = Pitch(step, octave: octs[_random.nextInt(octs.length)]);
  }

  Point<int> _wrap(Point<int> p) => Point(
        (p.x + NoteSnakeScreen._cols) % NoteSnakeScreen._cols,
        (p.y + NoteSnakeScreen._rows) % NoteSnakeScreen._rows,
      );

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;
    if (now - _lastMoveMs < _stepMs()) return;
    _lastMoveMs = now;
    _move();
  }

  void _move() {
    // Apply the queued turn (never a direct reversal).
    if (_pendingDir + _dir != const Point(0, 0)) _dir = _pendingDir;
    final head = _wrap(Point(_snake.first.x + _dir.x, _snake.first.y + _dir.y));

    // Bite yourself → over.
    if (_snake.contains(head)) {
      _finish();
      return;
    }

    final food = _food[head];
    if (food != null) {
      if (food == _target.step) {
        context.read<AudioService>().playMidiNote(_target.midiNumber, ms: 320);
        context.read<SriService>().recordResponse(_sriId(_target), true);
        setState(() {
          _snake.insert(0, head); // grow (don't pop the tail)
          _food.remove(head);
          _score++;
          _mascot = NoteMascotMood.happy;
          _spawnFood();
          _pickTarget();
        });
      } else {
        context.read<AudioService>().playWrong();
        context.read<SriService>().recordResponse(_sriId(_target), false);
        _finish();
      }
    } else {
      setState(() {
        _snake.insert(0, head);
        _snake.removeLast();
      });
    }
  }

  String _sriId(Pitch p) =>
      'note_reading.${widget.clef.name}.${p.step.name}${p.octave}';

  void _steer(Point<int> dir) {
    if (_finished) return;
    // Ignore a direct reversal into the neck.
    if (dir + _dir == const Point(0, 0)) return;
    _pendingDir = dir;
  }

  static final _arrowKeys = <LogicalKeyboardKey, Point<int>>{
    LogicalKeyboardKey.arrowUp: const Point(0, -1),
    LogicalKeyboardKey.arrowDown: const Point(0, 1),
    LogicalKeyboardKey.arrowLeft: const Point(-1, 0),
    LogicalKeyboardKey.arrowRight: const Point(1, 0),
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final dir = _arrowKeys[event.logicalKey];
    if (dir == null) return KeyEventResult.ignored;
    _steer(dir);
    return KeyEventResult.handled;
  }

  @override
  void debugFoodAhead(Step step) {
    _food.clear();
    final ahead =
        _wrap(Point(_snake.first.x + _dir.x, _snake.first.y + _dir.y));
    _food[ahead] = step;
    // Add a second matching-target food so _pickTarget stays valid after a
    // correct eat clears the board.
    for (final cell in _empties) {
      if (cell != ahead) {
        _food[cell] = _target.step;
        break;
      }
    }
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    final stars = scoreToStars(_gameId, _score, true);
    context.read<ProgressService>().recordResult(
          _gameId,
          score: _score,
          stars: stars,
        );
    context.read<AudioService>().playFanfare();
    setState(() => _mascot = NoteMascotMood.oops);
  }

  void _restart() {
    _ticker.stop();
    setState(() {
      _snake = [const Point(2, 2), const Point(1, 2)];
      _dir = const Point(1, 0);
      _pendingDir = const Point(1, 0);
      _food.clear();
      _score = 0;
      _finished = false;
      _lastMoveMs = 0;
      _mascot = NoteMascotMood.idle;
      for (var i = 0; i < NoteSnakeScreen._foodCount; i++) {
        _spawnFood();
      }
      _pickTarget();
    });
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScaffold = context.watch<SettingsService>().colorScaffold;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameNoteSnake),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: _gameId,
                score: _score,
                onRestart: _restart,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          NoteMascot(mood: _mascot, size: 28),
                          const SizedBox(width: 8),
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '$_score',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          Text(
                            l10n.noteSnakePrompt,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 74,
                            height: 84,
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
                              staffSpace: 6,
                              theme: colorScaffold
                                  ? kidsScoreTheme.copyWith(
                                      elementColors: {
                                        'target': pitchClassColor(_target.step),
                                      },
                                    )
                                  : kidsScoreTheme,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio:
                              NoteSnakeScreen._cols / NoteSnakeScreen._rows,
                          child: _Board(
                            cols: NoteSnakeScreen._cols,
                            rows: NoteSnakeScreen._rows,
                            snake: _snake,
                            food: _food,
                            colorScaffold: colorScaffold,
                          ),
                        ),
                      ),
                    ),
                    _DPad(onSteer: _steer, color: scheme.primary),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.cols,
    required this.rows,
    required this.snake,
    required this.food,
    required this.colorScaffold,
  });

  final int cols;
  final int rows;
  final List<Point<int>> snake;
  final Map<Point<int>, Step> food;
  final bool colorScaffold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: cols,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var r = 0; r < rows; r++)
          for (var c = 0; c < cols; c++) _cell(context, scheme, Point(c, r)),
      ],
    );
  }

  Widget _cell(BuildContext context, ColorScheme scheme, Point<int> p) {
    final isHead = snake.isNotEmpty && snake.first == p;
    final isBody = snake.contains(p);
    final letterStep = food[p];

    Color fill;
    Widget? child;
    if (isHead) {
      fill = scheme.primary;
    } else if (isBody) {
      fill = scheme.primary.withValues(alpha: 0.55);
    } else if (letterStep != null) {
      fill = colorScaffold
          ? pitchClassColor(letterStep).withValues(alpha: 0.35)
          : scheme.secondaryContainer;
      child = Text(
        noteNameFor(context, letterStep),
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
    } else {
      fill = scheme.surfaceContainerHighest;
    }

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// A four-way steering pad for touch play (keyboard uses the arrow keys).
class _DPad extends StatelessWidget {
  const _DPad({required this.onSteer, required this.color});

  final void Function(Point<int>) onSteer;
  final Color color;

  Widget _btn(IconData icon, Point<int> dir) => Padding(
        padding: const EdgeInsets.all(3),
        child: IconButton.filledTonal(
          icon: Icon(icon),
          onPressed: () => onSteer(dir),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.keyboard_arrow_up, const Point(0, -1)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _btn(Icons.keyboard_arrow_left, const Point(-1, 0)),
            const SizedBox(width: 44),
            _btn(Icons.keyboard_arrow_right, const Point(1, 0)),
          ],
        ),
        _btn(Icons.keyboard_arrow_down, const Point(0, 1)),
      ],
    );
  }
}
