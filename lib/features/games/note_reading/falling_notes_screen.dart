// lib/features/games/note_reading/falling_notes_screen.dart
//
// "Notenregen" / "Falling Notes" — the app's first arcade format (docs/PLAN.md,
// gamified backlog: "notes fall to a staff/keyboard, name them before they
// land; combo + speed-up. Highest kid-appeal."). Notes drift down a starlit
// lane on real partitura staves; the child names the most urgent (lowest) one
// with a letter pad before it crosses the glowing hit-line. Catches burst into
// sparks, grow a combo multiplier and ramp the fall speed; three misses end the
// run. A fixed run of [_kTotalNotes] notes keeps the rounds/score/stars loop of
// every other game, with escalating speed for arcade tension.
//
// Difficulty widens with mastery like the reading quizzes: naturals on the
// staff for beginners, the middle-C ledger neighbourhood at 2★+.
//
// SRI: 'note_reading.treble.<step><octave>' — the same namespace the Reading
// Quiz reviews, so caught/missed notes feed the shared SM-2 engine.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
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
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

/// One note falling down the lane.
class _FallingNote {
  _FallingNote({
    required this.id,
    required this.pitch,
    required this.spawnMs,
    required this.fallMs,
    required this.column,
    required this.card,
  });

  final int id;
  final Pitch pitch;

  /// Ticker time (ms) at which the note appeared, and how long it takes to
  /// travel from the top of the lane to the hit-line.
  final int spawnMs;
  final int fallMs;

  /// Which horizontal lane (0.._kColumns-1) the note drifts down.
  final int column;

  /// The partitura staff card, built once at spawn. StaffView is a
  /// LeafRenderObjectWidget, so re-parenting it into a moving Positioned every
  /// frame only re-composites — it never re-lays-out.
  final Widget card;

  /// 0.0 at spawn, 1.0 when the note reaches the hit-line, >1 once it has
  /// passed (a miss).
  double progressAt(int nowMs) => (nowMs - spawnMs) / fallMs;
}

/// A spark thrown off when a note is caught.
class _Spark {
  _Spark({
    required this.x0,
    required this.y0,
    required this.vx,
    required this.vy,
    required this.spawnMs,
    required this.color,
  });

  final double x0, y0, vx, vy;
  final int spawnMs;
  final Color color;

  static const lifeMs = 620;
}

/// How the child answers a falling note.
enum FallingMode {
  /// Tap the letter name on a 7-button pad (drills reading → `note_reading`).
  name,

  /// Tap the matching key on a piano (drills staff → key → `keyboard.find`).
  play,
}

class FallingNotesScreen extends StatefulWidget {
  const FallingNotesScreen({
    super.key,
    this.mode = FallingMode.name,
    this.clef = Clef.treble,
  });

  /// Whether the note is answered by naming it or by playing it on the piano.
  final FallingMode mode;

  /// Reading clef (name mode only; play mode is fixed to the piano's range).
  final Clef clef;

  /// Notes per run — the round budget behind the star rating.
  static const _kTotalNotes = 15;

  /// Misses allowed before the run ends early.
  static const _kMaxLives = 3;

  @visibleForTesting
  static const maxLives = _kMaxLives;

  /// Horizontal lanes the notes drift down.
  static const _kColumns = 4;

  /// Letter pad, in scale order.
  static const _kSteps = [
    Step.c,
    Step.d,
    Step.e,
    Step.f,
    Step.g,
    Step.a,
    Step.b,
  ];

  static const _cardW = 76.0;
  static const _cardH = 96.0;

  @override
  State<FallingNotesScreen> createState() => _FallingNotesScreenState();
}

/// Typed window into the game state for widget tests (the state class itself is
/// private). Cast `tester.state<...>()` to this.
@visibleForTesting
abstract interface class FallingNotesTester {
  int get score;
  int get lives;
  int get caughtCount;
  bool get finished;

  /// The pitch the letter pad currently addresses, or null if nothing is in
  /// play — used to tap the correct name in tests.
  Pitch? activeTargetPitch();
}

class _FallingNotesScreenState extends State<FallingNotesScreen>
    with SingleTickerProviderStateMixin
    implements FallingNotesTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);

  // Repaints only the moving layer (notes + sparks) each frame, leaving the
  // HUD and letter pad untouched until a scoring event calls setState.
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  final List<_FallingNote> _notes = [];
  final List<_Spark> _sparks = [];

  int _nextId = 0;
  int _spawnedCount = 0;
  int _resolvedCount = 0; // caught + missed
  int _caughtCount = 0;
  int _nextSpawnMs = 700; // first note after a short beat
  int _lastColumn = -1;

  int _score = 0;
  int _combo = 0; // consecutive catches
  int _bestCombo = 0;
  int _lives = FallingNotesScreen._kMaxLives;
  int _level = 1;

  bool _wideRange = false; // ledger notes unlocked at 2★+
  bool _finished = false;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  // Transient juice, expressed as "active until this ticker time".
  int _speedUpUntil = 0;
  int _flashUntil = 0; // red hit-line flash on a miss / wrong tap

  /// Score multiplier grows every 3 consecutive catches, capped at ×5.
  int get _multiplier => (1 + _combo ~/ 3).clamp(1, 5);

  /// Star-thresholds / progress key: distinct per mode and clef.
  String get _gameId => widget.mode == FallingMode.play
      ? 'falling_keys'
      : widget.clef == Clef.bass
          ? 'falling_notes_bass'
          : 'falling_notes';

  @override
  int get score => _score;
  @override
  int get lives => _lives;
  @override
  int get caughtCount => _caughtCount;
  @override
  bool get finished => _finished;

  @override
  Pitch? activeTargetPitch() => activeNote()?.pitch;

  /// The note the letter pad currently addresses: the lowest on-screen,
  /// uncaught note. Null when nothing is in play.
  _FallingNote? activeNote() {
    _FallingNote? best;
    var bestP = -1.0;
    for (final n in _notes) {
      final p = n.progressAt(_now.value);
      if (p >= 0 && p <= 1.0 && p > bestP) {
        bestP = p;
        best = n;
      }
    }
    return best;
  }

  @override
  void initState() {
    super.initState();
    // Play mode keeps notes to white keys inside the piano's range, so no
    // ledger widening there.
    _wideRange = widget.mode == FallingMode.name &&
        context.read<ProgressService>().starsFor(_gameId) >= 2;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  // --- Speed / difficulty tuning ---------------------------------------------

  // Level 1 starts gentle (~half the old speed); it ramps as catches climb.
  int _fallMsForLevel(int level) =>
      (9000 - 900 * (level - 1)).clamp(3600, 9000);

  int _spawnGapForLevel(int level) =>
      (2600 - 220 * (level - 1)).clamp(1400, 2600);

  // --- Game loop -------------------------------------------------------------

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;

    // Spawn due notes.
    while (_spawnedCount < FallingNotesScreen._kTotalNotes &&
        now >= _nextSpawnMs) {
      _spawn(now);
      _nextSpawnMs = now + _spawnGapForLevel(_level);
    }

    // Retire notes that crossed the hit-line uncaught.
    var missed = false;
    for (var i = _notes.length - 1; i >= 0; i--) {
      if (_notes[i].progressAt(now) > 1.0) {
        _onMiss(_notes.removeAt(i));
        missed = true;
      }
    }

    // Drop expired sparks.
    _sparks.removeWhere((s) => now - s.spawnMs > _Spark.lifeMs);

    _now.value = now; // repaint the moving layer

    if (missed) setState(() {}); // HUD (lives/combo) changed
    _maybeFinish();
  }

  void _spawn(int now) {
    // Naturals on the staff for beginners; the middle-C ledger neighbourhood
    // once the game has earned two stars.
    final pos = _wideRange
        ? -3 + _random.nextInt(14) // -3..10 (incl. middle C at -2)
        : _random.nextInt(9); // 0..8, bottom line to top line
    final pitch = widget.clef.pitchAt(pos);

    // Avoid dropping two notes down the same lane back-to-back.
    var column = _random.nextInt(FallingNotesScreen._kColumns);
    if (column == _lastColumn) {
      column = (column + 1) % FallingNotesScreen._kColumns;
    }
    _lastColumn = column;

    _notes.add(
      _FallingNote(
        id: _nextId++,
        pitch: pitch,
        spawnMs: now,
        fallMs: _fallMsForLevel(_level),
        column: column,
        card: _buildCard(pitch),
      ),
    );
    _spawnedCount++;
  }

  void _onMiss(_FallingNote note) {
    context.read<AudioService>().playWrong();
    context.read<SriService>().recordResponse(_sriId(note.pitch), false);
    _resolvedCount++;
    _lives--;
    _combo = 0;
    _mascot = NoteMascotMood.oops;
    _flashUntil = _now.value + 260;
  }

  void _onLetter(Step step) {
    if (_finished) return;
    final target = activeNote();
    if (target == null) return;

    if (step == target.pitch.step) {
      _onCatch(target);
    } else {
      _onWrongTap();
    }
  }

  // Name mode is keyboard-steerable: the C..B letter keys name the active note.
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
    if (event is! KeyDownEvent || widget.mode != FallingMode.name) {
      return KeyEventResult.ignored;
    }
    final step = _letterKeys[event.logicalKey];
    if (step == null) return KeyEventResult.ignored;
    _onLetter(step);
    return KeyEventResult.handled;
  }

  void _onKey(int midi) {
    if (_finished) return;
    final target = activeNote();
    if (target == null) return;

    if (midi == target.pitch.midiNumber) {
      _onCatch(target);
    } else {
      _onWrongTap();
    }
  }

  void _onCatch(_FallingNote note) {
    _notes.remove(note);
    context.read<AudioService>().playMidiNote(note.pitch.midiNumber, ms: 420);
    context.read<SriService>().recordResponse(_sriId(note.pitch), true);

    _resolvedCount++;
    _caughtCount++;
    _combo++;
    _bestCombo = max(_bestCombo, _combo);
    _score += 10 * _multiplier;
    _mascot = NoteMascotMood.happy;
    _emitSparks(note);

    // Speed tier rises every four catches — a visible "Speed up!" beat.
    final nextLevel = 1 + _caughtCount ~/ 4;
    if (nextLevel > _level) {
      _level = nextLevel;
      _speedUpUntil = _now.value + 1100;
    }

    setState(() {}); // HUD: score / combo
    _maybeFinish();
  }

  void _onWrongTap() {
    context.read<AudioService>().playWrong();
    _combo = 0; // a wrong name breaks the streak but costs no life
    _mascot = NoteMascotMood.oops;
    _flashUntil = _now.value + 220;
    setState(() {});
  }

  void _emitSparks(_FallingNote note) {
    final size = _laneSize;
    if (size == null) return;
    final p = note.progressAt(_now.value).clamp(0.0, 1.0);
    final cx =
        _columnX(note.column, size.width) + FallingNotesScreen._cardW / 2;
    final cy = _noteTop(p, size.height) + FallingNotesScreen._cardH / 2;
    final color = pitchClassColor(note.pitch.step);
    for (var i = 0; i < 14; i++) {
      final a = _random.nextDouble() * 2 * pi;
      final speed = 90 + _random.nextDouble() * 220;
      _sparks.add(
        _Spark(
          x0: cx,
          y0: cy,
          vx: cos(a) * speed,
          vy: sin(a) * speed - 60, // bias upward for a fountain feel
          spawnMs: _now.value,
          color: color,
        ),
      );
    }
  }

  void _maybeFinish() {
    if (_finished) return;
    if (_lives <= 0 || _resolvedCount >= FallingNotesScreen._kTotalNotes) {
      _finish();
    }
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    final won = _lives > 0;
    final stars = scoreToStars(_gameId, _score, true);
    context.read<ProgressService>().recordResult(
          _gameId,
          score: _score,
          stars: stars,
          elapsedMs: _now.value,
        );
    context.read<AudioService>().playFanfare();
    setState(() {
      _mascot = won ? NoteMascotMood.happy : NoteMascotMood.oops;
    });
  }

  void _restart() {
    _ticker.stop();
    setState(() {
      _notes.clear();
      _sparks.clear();
      _nextId = 0;
      _spawnedCount = 0;
      _resolvedCount = 0;
      _caughtCount = 0;
      _nextSpawnMs = 700;
      _lastColumn = -1;
      _score = 0;
      _combo = 0;
      _bestCombo = 0;
      _lives = FallingNotesScreen._kMaxLives;
      _level = 1;
      _speedUpUntil = 0;
      _flashUntil = 0;
      _finished = false;
      _mascot = NoteMascotMood.idle;
    });
    _now.value = 0;
    _ticker.start();
  }

  // Reading the note feeds the shared reading namespace; playing it feeds the
  // staff→key namespace (both natural-only here, so no accidental token).
  String _sriId(Pitch p) => widget.mode == FallingMode.play
      ? 'keyboard.find.${p.step.name}${p.octave}'
      : 'note_reading.${widget.clef.name}.${p.step.name}${p.octave}';

  Widget _buildCard(Pitch pitch) => StaffView(
        score: Score.simple(
          clef: widget.clef,
          notes: '${pitch.step.name}${pitch.octave}:w',
        ),
        staffSpace: 8,
        theme: PartituraTheme.kids,
      );

  // --- Geometry --------------------------------------------------------------

  Size? _laneSize;

  double get _hitLineY => (_laneSize?.height ?? 0) - 14;

  double _noteTop(double progress, double laneH) {
    // Card top: from just above the lane to card-centre resting on the line.
    const cardH = FallingNotesScreen._cardH;
    final end = (laneH - 14) - cardH / 2;
    return -cardH + (end + cardH) * progress;
  }

  double _columnX(int column, double laneW) {
    const cardW = FallingNotesScreen._cardW;
    const pad = 14.0;
    final usable = (laneW - 2 * pad - cardW).clamp(0.0, double.infinity);
    if (FallingNotesScreen._kColumns == 1) return (laneW - cardW) / 2;
    return pad + usable * column / (FallingNotesScreen._kColumns - 1);
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isPlay = widget.mode == FallingMode.play;

    return Scaffold(
      appBar: AppBar(
        title: Text(isPlay ? l10n.gameFallingKeys : l10n.gameFallingNotes),
      ),
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
                      combo: _combo,
                      lives: _lives,
                      maxLives: FallingNotesScreen._kMaxLives,
                      mascot: _mascot,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _laneSize = constraints.biggest;
                          return _buildLane(context, l10n);
                        },
                      ),
                    ),
                    if (isPlay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                        child: SizedBox(
                          height: 150,
                          // C4..G5 covers the natural falling notes (E4..F5).
                          child: PianoKeyboard(
                            showLabels: true,
                            onKeyTap: _onKey,
                          ),
                        ),
                      )
                    else
                      _LetterPad(
                        steps: FallingNotesScreen._kSteps,
                        onTap: _onLetter,
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLane(BuildContext context, AppLocalizations l10n) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surfaceContainerHighest,
              scheme.surface,
              scheme.surfaceContainerHigh,
            ],
          ),
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: _now,
          builder: (context, now, _) {
            final size = _laneSize ?? Size.zero;
            final active = activeNote();
            final flash = now < _flashUntil;
            final speedUp = now < _speedUpUntil;

            return Stack(
              children: [
                // Starfield + hit-line + sparks, all one painter.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LanePainter(
                      nowMs: now,
                      hitLineY: _hitLineY,
                      sparks: _sparks,
                      lineColor: flash ? scheme.error : scheme.primary,
                      glow: (_combo >= 3 ? 1.0 : 0.5) + (flash ? 0.5 : 0.0),
                      starColor: scheme.onSurface.withValues(alpha: 0.10),
                      reduceMotion: reduceMotion,
                    ),
                  ),
                ),
                // Falling notes.
                for (final note in _notes)
                  _positionedNote(note, size, active, reduceMotion),
                // "Speed up!" banner.
                if (speedUp)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _SpeedUpBanner(text: l10n.fallingSpeedUp),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _positionedNote(
    _FallingNote note,
    Size size,
    _FallingNote? active,
    bool reduceMotion,
  ) {
    final p = note.progressAt(_now.value);
    final top = _noteTop(p.clamp(0.0, 1.0), size.height);
    final left = _columnX(note.column, size.width);
    final isActive = active != null && active.id == note.id;

    return Positioned(
      left: left,
      top: top,
      width: FallingNotesScreen._cardW,
      height: FallingNotesScreen._cardH,
      child: _NoteCard(active: isActive, child: note.card),
    );
  }
}

/// The falling staff card: a glassy tile that lights up when it's the note the
/// letter pad currently names.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: active ? 0.98 : 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? scheme.primary : scheme.outlineVariant,
            width: active ? 3 : 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.55),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ]
              : const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Score / combo / lives / mascot strip above the lane.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.score,
    required this.multiplier,
    required this.combo,
    required this.lives,
    required this.maxLives,
    required this.mascot,
  });

  final int score;
  final int multiplier;
  final int combo;
  final int lives;
  final int maxLives;
  final NoteMascotMood mascot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final showCombo = multiplier > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
          // Combo multiplier pill, pulsing in as it grows.
          AnimatedScale(
            scale: showCombo ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Container(
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

/// The 7-letter naming pad, tinted by pitch class when the colour scaffold is on.
class _LetterPad extends StatelessWidget {
  const _LetterPad({required this.steps, required this.onTap});

  final List<Step> steps;
  final ValueChanged<Step> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScaffold = context.watch<SettingsService>().colorScaffold;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      child: Row(
        children: [
          for (final step in steps)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: SizedBox(
                  height: 62,
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

class _SpeedUpBanner extends StatelessWidget {
  const _SpeedUpBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.tertiary.withValues(alpha: 0.5),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: scheme.onTertiaryContainer, size: 20),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

/// Paints the drifting starfield, the neon hit-line, and the catch sparks —
/// everything that animates every frame, in one cheap pass.
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.nowMs,
    required this.hitLineY,
    required this.sparks,
    required this.lineColor,
    required this.glow,
    required this.starColor,
    required this.reduceMotion,
  });

  final int nowMs;
  final double hitLineY;
  final List<_Spark> sparks;
  final Color lineColor;
  final double glow;
  final Color starColor;
  final bool reduceMotion;

  // A fixed pseudo-random star layout (seeded, so it's stable across frames).
  static final List<Offset> _stars = _makeStars();
  static List<Offset> _makeStars() {
    final r = Random(42);
    return [
      for (var i = 0; i < 46; i++) Offset(r.nextDouble(), r.nextDouble()),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Twinkling starfield.
    final starPaint = Paint()..color = starColor;
    for (var i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final twinkle =
          reduceMotion ? 1.0 : 0.5 + 0.5 * sin(nowMs / 700 + i * 1.3).abs();
      final radius = (0.6 + (i % 3) * 0.6) * twinkle;
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * (hitLineY - 4)),
        radius,
        starPaint,
      );
    }

    // The glowing hit-line.
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.30 * glow)
      ..strokeWidth = 16
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawLine(
      Offset(0, hitLineY),
      Offset(size.width, hitLineY),
      glowPaint,
    );
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(0, hitLineY),
      Offset(size.width, hitLineY),
      linePaint,
    );

    // Catch sparks: little fountains that fade and fall.
    for (final s in sparks) {
      final t = nowMs - s.spawnMs;
      if (t < 0 || t > _Spark.lifeMs) continue;
      final dt = t / 1000.0;
      final x = s.x0 + s.vx * dt;
      final y = s.y0 + s.vy * dt + 520 * dt * dt; // gravity
      final life = 1 - t / _Spark.lifeMs;
      canvas.drawCircle(
        Offset(x, y),
        1.5 + 2.5 * life,
        Paint()..color = s.color.withValues(alpha: life.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LanePainter old) => true;
}
