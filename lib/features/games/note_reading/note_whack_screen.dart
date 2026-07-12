// lib/features/games/note_reading/note_whack_screen.dart
//
// "Note Whack" — whack-a-mole reading under gentle reaction pressure (docs/PLAN.md
// original-concepts backlog). Noteheads pop up in a grid of holes; a target
// letter is called ("Find: A") and the child whacks the matching notes before
// they duck. Correct whacks grow a combo; a wrong whack costs a heart. A fixed
// run of [_kTargetWhacks] keeps the rounds/score/1-3★ loop, with the hole
// lifespan shrinking as the run goes on for arcade tension.
//
// Difficulty widens with mastery like the reading quizzes: comfortable octaves
// for beginners, the ledger octaves at 2★+. SRI: 'note_reading.<clef>.<step>
// <octave>' on the whacked note, feeding the shared reading SM-2 engine.

import 'dart:math';

// Material also exports `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/note_reading/note_colors.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/note_mascot.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

/// A note popped up in one of the holes.
class _Mole {
  _Mole({
    required this.pitch,
    required this.spawnMs,
    required this.lifeMs,
    required this.card,
  });

  final Pitch pitch;
  final int spawnMs;
  final int lifeMs;
  final Widget card;

  bool expiredAt(int now) => now - spawnMs > lifeMs;
}

class NoteWhackScreen extends StatefulWidget {
  const NoteWhackScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  /// Holes in the grid (3 × 2).
  static const _kHoles = 6;

  /// Successful whacks that complete a run — the star-rating budget.
  static const _kTargetWhacks = 12;

  /// Wrong whacks allowed before the run ends early.
  static const _kMaxLives = 3;

  @visibleForTesting
  static const maxLives = _kMaxLives;
  @visibleForTesting
  static const targetWhacks = _kTargetWhacks;
  @visibleForTesting
  static const holes = _kHoles;

  @override
  State<NoteWhackScreen> createState() => _NoteWhackScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class NoteWhackTester {
  int get score;
  int get lives;
  int get whacks;
  bool get finished;
  Step get targetStep;

  /// A hole index whose mole matches the current target, or null if none is up.
  int? holeMatchingTarget();
}

class _NoteWhackScreenState extends State<NoteWhackScreen>
    with SingleTickerProviderStateMixin
    implements NoteWhackTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);

  final List<_Mole?> _holes =
      List<_Mole?>.filled(NoteWhackScreen._kHoles, null);

  late Step _target;
  int _now = 0;
  int _nextSpawnMs = 500;

  int _score = 0;
  int _combo = 0;
  int _whacks = 0;
  int _lives = NoteWhackScreen._kMaxLives;
  bool _wideRange = false;
  bool _finished = false;
  int _flashUntil = 0;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  int get _multiplier => (1 + _combo ~/ 3).clamp(1, 5);

  String get _gameId =>
      widget.clef == Clef.bass ? 'note_whack_bass' : 'note_whack';

  @override
  int get score => _score;
  @override
  int get lives => _lives;
  @override
  int get whacks => _whacks;
  @override
  bool get finished => _finished;
  @override
  Step get targetStep => _target;

  @override
  int? holeMatchingTarget() {
    for (var i = 0; i < _holes.length; i++) {
      if (_holes[i]?.pitch.step == _target) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _wideRange = context.read<ProgressService>().starsFor(_gameId) >= 2;
    _target = _randomStep();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Step _randomStep() => Step.values[_random.nextInt(Step.values.length)];

  // Holes duck faster and refill quicker as the run progresses.
  int _lifeMs() => (3000 - 130 * _whacks).clamp(1500, 3000);
  int _spawnGapMs() => (1000 - 40 * _whacks).clamp(550, 1000);

  List<int> _octavePool() {
    if (widget.clef == Clef.bass) return _wideRange ? [1, 2, 3, 4] : [2, 3];
    return _wideRange ? [3, 4, 5, 6] : [4, 5];
  }

  int get _visibleCount => _holes.where((m) => m != null).length;

  bool get _targetVisible => holeMatchingTarget() != null;

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;
    _now = now;
    var changed = false;

    // Duck expired moles.
    for (var i = 0; i < _holes.length; i++) {
      if (_holes[i] != null && _holes[i]!.expiredAt(now)) {
        _holes[i] = null;
        changed = true;
      }
    }

    // Spawn into an empty hole, keeping a few holes clear.
    if (now >= _nextSpawnMs && _visibleCount < 4) {
      final empty = [
        for (var i = 0; i < _holes.length; i++)
          if (_holes[i] == null) i,
      ];
      if (empty.isNotEmpty) {
        // Force a target note up if none is currently showing, so the run
        // never stalls; otherwise ~45% match the target for a steady supply.
        final mustMatch = !_targetVisible;
        final matchTarget = mustMatch || _random.nextDouble() < 0.45;
        _holes[empty[_random.nextInt(empty.length)]] = _makeMole(matchTarget);
        _nextSpawnMs = now + _spawnGapMs();
        changed = true;
      }
    }

    if (changed) setState(() {});
  }

  _Mole _makeMole(bool matchTarget) {
    final step = matchTarget
        ? _target
        : (Step.values.toList()..remove(_target))[_random.nextInt(6)];
    final octs = _octavePool();
    final pitch = Pitch(step, octave: octs[_random.nextInt(octs.length)]);
    return _Mole(
      pitch: pitch,
      spawnMs: _now,
      lifeMs: _lifeMs(),
      card: _buildCard(pitch),
    );
  }

  String _sriId(Pitch p) =>
      'note_reading.${widget.clef.name}.${p.step.name}${p.octave}';

  void _onHole(int i) {
    if (_finished) return;
    final mole = _holes[i];
    if (mole == null) return;

    if (mole.pitch.step == _target) {
      context.read<AudioService>().playMidiNote(mole.pitch.midiNumber, ms: 420);
      context.read<SriService>().recordResponse(_sriId(mole.pitch), true);
      setState(() {
        _holes[i] = null;
        _score += 10 * _multiplier;
        _combo++;
        _whacks++;
        _mascot = NoteMascotMood.happy;
        _target = _randomStep();
      });
      if (_whacks >= NoteWhackScreen._kTargetWhacks) _finish();
    } else {
      context.read<AudioService>().playWrong();
      context.read<SriService>().recordResponse(_sriId(mole.pitch), false);
      setState(() {
        _holes[i] = null;
        _combo = 0;
        _lives--;
        _flashUntil = _now + 260;
        _mascot = NoteMascotMood.oops;
      });
      if (_lives <= 0) _finish();
    }
  }

  // Keyboard: a letter key whacks a visible mole with that name.
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
    for (var i = 0; i < _holes.length; i++) {
      if (_holes[i]?.pitch.step == step) {
        _onHole(i);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    final stars = scoreToStars(_gameId, _score, true);
    context.read<ProgressService>().recordResult(
          _gameId,
          score: _score,
          stars: stars,
          elapsedMs: _now,
        );
    context.read<AudioService>().playFanfare();
    setState(() {
      _mascot = _lives > 0 ? NoteMascotMood.happy : NoteMascotMood.oops;
    });
  }

  void _restart() {
    _ticker.stop();
    setState(() {
      for (var i = 0; i < _holes.length; i++) {
        _holes[i] = null;
      }
      _now = 0;
      _nextSpawnMs = 500;
      _score = 0;
      _combo = 0;
      _whacks = 0;
      _lives = NoteWhackScreen._kMaxLives;
      _flashUntil = 0;
      _finished = false;
      _mascot = NoteMascotMood.idle;
      _target = _randomStep();
    });
    _ticker.start();
  }

  Widget _buildCard(Pitch pitch) {
    final colorScaffold = context.read<SettingsService>().colorScaffold;
    return StaffView(
      score: Score(
        clef: widget.clef,
        measures: [
          Measure([
            NoteElement.note(
              pitch,
              const NoteDuration(DurationBase.whole),
              id: 'n',
            ),
          ]),
        ],
      ),
      staffSpace: 7,
      theme: colorScaffold
          ? PartituraTheme.kids.copyWith(
              elementColors: {'n': pitchClassColor(pitch.step)},
            )
          : PartituraTheme.kids,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScaffold = context.watch<SettingsService>().colorScaffold;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameNoteWhack)),
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
                    _Hud(
                      score: _score,
                      multiplier: _multiplier,
                      lives: _lives,
                      maxLives: NoteWhackScreen._kMaxLives,
                      mascot: _mascot,
                    ),
                    _TargetBanner(
                      name: noteNameFor(context, _target),
                      color: colorScaffold ? pitchClassColor(_target) : null,
                      prompt: l10n.noteWhackPrompt,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        // Explicit 3 × 2 flex grid: every hole is an equal
                        // flex box that fills its cell, so the whole cell is
                        // reliably tappable.
                        child: Column(
                          children: [
                            for (var row = 0; row < 2; row++)
                              Expanded(
                                child: Row(
                                  children: [
                                    for (var col = 0; col < 3; col++)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: _HoleView(
                                            key: ValueKey(
                                              'whack_hole_${row * 3 + col}',
                                            ),
                                            mole: _holes[row * 3 + col],
                                            flash: _now < _flashUntil,
                                            reduceMotion: reduceMotion,
                                            onTap: () => _onHole(row * 3 + col),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        l10n.noteWhackHint,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A single hole: a rounded well with a note that pops up and ducks down.
class _HoleView extends StatelessWidget {
  const _HoleView({
    super.key,
    required this.mole,
    required this.flash,
    required this.reduceMotion,
    required this.onTap,
  });

  final _Mole? mole;
  final bool flash;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: flash ? scheme.error : scheme.outlineVariant,
            width: flash ? 3 : 1.5,
          ),
        ),
        child: Center(
          child: AnimatedScale(
            scale: mole != null ? 1.0 : 0.0,
            duration: Duration(milliseconds: reduceMotion ? 0 : 160),
            curve: Curves.easeOutBack,
            child: mole == null
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 5),
                      ],
                    ),
                    child: Center(child: mole!.card),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The "Find: A" banner naming the note to whack.
class _TargetBanner extends StatelessWidget {
  const _TargetBanner({
    required this.name,
    required this.color,
    required this.prompt,
  });

  final String name;
  final Color? color;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prompt, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 10),
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (color ?? scheme.primary).withValues(alpha: 0.20),
              shape: BoxShape.circle,
              border: Border.all(color: color ?? scheme.primary, width: 2),
            ),
            child: Text(
              name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color ?? scheme.primary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Score / combo / lives / mascot strip.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.score,
    required this.multiplier,
    required this.lives,
    required this.maxLives,
    required this.mascot,
  });

  final int score;
  final int multiplier;
  final int lives;
  final int maxLives;
  final NoteMascotMood mascot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          NoteMascot(mood: mascot, size: 30),
          const SizedBox(width: 8),
          const Icon(Icons.star, color: Colors.amber, size: 22),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (multiplier > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                l10n.fallingMultiplier(multiplier),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          const Spacer(),
          for (var i = 0; i < maxLives; i++)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(
                i < lives ? Icons.favorite : Icons.favorite_border,
                color: i < lives ? Colors.redAccent : scheme.outlineVariant,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }
}
