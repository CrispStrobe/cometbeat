// lib/features/games/scales/command_caller_screen.dart
//
// "Der Dirigent" / "Follow the Conductor" — conduct the beat pattern. Instead
// of a meaningless tap/hold/swipe reaction, this now teaches METER: the baton
// traces the real conducting pattern for the current time signature, and the
// child follows it beat by beat. Beat 1 is always DOWN (the downbeat you feel);
// the rest trace the standard 2/4, 3/4 and 4/4 figures.
//
//   2/4: down · up            3/4: down · right · up
//   4/4: down · left · right · up
//
// The target zone lights up on each beat (a tick, accented on the downbeat) and
// the child taps it — or uses the arrow keys. A no-fail toy scored by accuracy,
// like Sound Echo; the learning is kinaesthetic (you feel the metre).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// A conducting direction (a zone in the diamond).
enum Beat { up, down, left, right }

/// A metre and its conducting figure.
class _Meter {
  const _Meter(this.signature, this.pattern);
  final String signature; // e.g. "4/4"
  final List<Beat> pattern;
}

class CommandCallerScreen extends StatefulWidget {
  const CommandCallerScreen({super.key});

  static const _meters = [
    _Meter('4/4', [Beat.down, Beat.left, Beat.right, Beat.up]),
    _Meter('3/4', [Beat.down, Beat.right, Beat.up]),
    _Meter('2/4', [Beat.down, Beat.up]),
  ];

  /// The run: two measures of each metre, twice through.
  static const _plan = [0, 0, 1, 1, 2, 2, 0, 0, 1, 1, 2, 2];

  static const _beatMs = 850; // gentle ~70 BPM
  static const _leadMs = 1400; // a one-beat count-in before beat 0
  static const _hitWindowMs = 300;
  static const _perfectMs = 130;

  @visibleForTesting
  static Key zoneKey(Beat b) => ValueKey('conduct_${b.name}');

  @override
  State<CommandCallerScreen> createState() => _CommandCallerScreenState();
}

/// One scheduled beat in the run.
class _ScheduledBeat {
  _ScheduledBeat(this.target, this.timeMs, this.downbeat, this.signature);
  final Beat target;
  final int timeMs;
  final bool downbeat;
  final String signature;
  bool resolved = false;
}

/// Typed window into the game for widget tests.
@visibleForTesting
abstract interface class CommandCallerTester {
  int get score;
  int get hits;
  bool get finished;

  /// The direction expected around now, or null between beats.
  Beat? get expectedNow;
}

enum _Judge { perfect, good, miss }

class _CommandCallerScreenState extends State<CommandCallerScreen>
    with SingleTickerProviderStateMixin
    implements CommandCallerTester {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  late final List<_ScheduledBeat> _beats = _buildSchedule();

  int _score = 0;
  int _hits = 0;
  int _lastTickPlayed = -1;
  bool _finished = false;

  _Judge? _lastJudge;
  Beat? _lastJudgeDir;
  int _judgeUntil = 0;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  static List<_ScheduledBeat> _buildSchedule() {
    final beats = <_ScheduledBeat>[];
    var t = CommandCallerScreen._leadMs;
    for (final meterIndex in CommandCallerScreen._plan) {
      final meter = CommandCallerScreen._meters[meterIndex];
      for (var b = 0; b < meter.pattern.length; b++) {
        beats.add(
          _ScheduledBeat(meter.pattern[b], t, b == 0, meter.signature),
        );
        t += CommandCallerScreen._beatMs;
      }
    }
    return beats;
  }

  @override
  int get score => _score;
  @override
  int get hits => _hits;
  @override
  bool get finished => _finished;

  @override
  Beat? get expectedNow {
    final b = _nearestOpenBeat(_now.value);
    return b?.target;
  }

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  _ScheduledBeat? _nearestOpenBeat(int now) {
    _ScheduledBeat? best;
    var bestDelta = CommandCallerScreen._hitWindowMs + 1;
    for (final b in _beats) {
      if (b.resolved) continue;
      final d = (now - b.timeMs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = b;
      }
    }
    return best;
  }

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;

    // Tick on each beat, accented on the downbeat, as the baton lands.
    while (_lastTickPlayed + 1 < _beats.length &&
        now >= _beats[_lastTickPlayed + 1].timeMs) {
      _lastTickPlayed++;
      final b = _beats[_lastTickPlayed];
      context.read<AudioService>().playMidiNote(b.downbeat ? 76 : 69, ms: 120);
    }

    // A beat whose window closed unhit is a miss.
    var missed = false;
    for (final b in _beats) {
      if (!b.resolved && now > b.timeMs + CommandCallerScreen._hitWindowMs) {
        b.resolved = true;
        _lastJudge = _Judge.miss;
        _judgeUntil = now + 300;
        _mascot = NoteMascotMood.oops;
        missed = true;
      }
    }

    _now.value = now;
    if (missed) setState(() {});

    if (now > _beats.last.timeMs + CommandCallerScreen._hitWindowMs + 400) {
      _finish();
    }
  }

  void _onBeat(Beat dir) {
    if (_finished) return;
    final now = _now.value;
    final beat = _nearestOpenBeat(now);
    if (beat == null) return;

    if (beat.target != dir) {
      // Wrong direction — breaks the combo but costs nothing (no-fail).
      _lastJudge = _Judge.miss;
      _lastJudgeDir = dir;
      _judgeUntil = now + 300;
      setState(() => _mascot = NoteMascotMood.oops);
      context.read<AudioService>().playWrong();
      return;
    }

    beat.resolved = true;
    _hits++;
    final delta = (now - beat.timeMs).abs();
    final perfect = delta <= CommandCallerScreen._perfectMs;
    _score += perfect ? 20 : 10;
    _lastJudge = perfect ? _Judge.perfect : _Judge.good;
    _lastJudgeDir = dir;
    _judgeUntil = now + 300;
    context.read<AudioService>().playMidiNote(beat.downbeat ? 84 : 79, ms: 160);
    setState(() => _mascot = NoteMascotMood.happy);
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    context.read<AudioService>().playFanfare();
    context.read<ProgressService>().recordResult(
          'command_caller',
          score: _score,
          stars: scoreToStars('command_caller', _score, true),
        );
    setState(() {});
  }

  void _restart() {
    _ticker.stop();
    for (final b in _beats) {
      b.resolved = false;
    }
    _score = 0;
    _hits = 0;
    _lastTickPlayed = -1;
    _lastJudge = null;
    _finished = false;
    _mascot = NoteMascotMood.idle;
    _now.value = 0;
    setState(() {});
    _ticker.start();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final dir = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => Beat.up,
      LogicalKeyboardKey.arrowDown => Beat.down,
      LogicalKeyboardKey.arrowLeft => Beat.left,
      LogicalKeyboardKey.arrowRight => Beat.right,
      _ => null,
    };
    if (dir == null) return KeyEventResult.ignored;
    _onBeat(dir);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCommandCaller),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'command_caller',
                score: _score,
                onRestart: _restart,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
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
                          Text(
                            l10n.conductorPrompt,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _now,
                          builder: (context, now, _) {
                            final active = _nearestOpenBeat(now);
                            // Light the target only around its beat time.
                            final lit = (active != null &&
                                    now >= active.timeMs - 260 &&
                                    now <=
                                        active.timeMs +
                                            CommandCallerScreen._hitWindowMs)
                                ? active.target
                                : null;
                            final judgeDir =
                                now < _judgeUntil ? _lastJudgeDir : null;
                            return _ConductorPad(
                              lit: lit,
                              signature:
                                  active?.signature ?? _beats.first.signature,
                              onBeat: _onBeat,
                              judge: now < _judgeUntil ? _lastJudge : null,
                              judgeDir: judgeDir,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ConductorPad extends StatelessWidget {
  const _ConductorPad({
    required this.lit,
    required this.signature,
    required this.onBeat,
    required this.judge,
    required this.judgeDir,
  });

  final Beat? lit;
  final String signature;
  final ValueChanged<Beat> onBeat;
  final _Judge? judge;
  final Beat? judgeDir;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final zone = (w < h ? w : h) * 0.30;

        Widget place(Beat b, Alignment a) => Align(
              alignment: a,
              child: _Zone(
                key: CommandCallerScreen.zoneKey(b),
                dir: b,
                size: zone,
                lit: lit == b,
                judge: judgeDir == b ? judge : null,
                onTap: () => onBeat(b),
              ),
            );

        return Stack(
          children: [
            place(Beat.up, Alignment.topCenter),
            place(Beat.down, Alignment.bottomCenter),
            place(Beat.left, Alignment.centerLeft),
            place(Beat.right, Alignment.centerRight),
            // Centre: the current time signature.
            Center(
              child: Container(
                width: zone,
                height: zone,
                alignment: Alignment.center,
                child: Text(
                  signature,
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Zone extends StatelessWidget {
  const _Zone({
    super.key,
    required this.dir,
    required this.size,
    required this.lit,
    required this.judge,
    required this.onTap,
  });

  final Beat dir;
  final double size;
  final bool lit;
  final _Judge? judge;
  final VoidCallback onTap;

  static const _icons = {
    Beat.up: Icons.north,
    Beat.down: Icons.south,
    Beat.left: Icons.west,
    Beat.right: Icons.east,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = judge == _Judge.perfect || judge == _Judge.good
        ? Colors.green.shade300
        : judge == _Judge.miss
            ? Colors.red.shade200
            : lit
                ? scheme.primary
                : scheme.surfaceContainerHighest;
    final fg = lit ? scheme.onPrimary : scheme.onSurfaceVariant;

    return GestureDetector(
      onTapDown: (_) => onTap(),
      child: AnimatedScale(
        scale: lit ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow:
                lit ? [BoxShadow(color: scheme.primary, blurRadius: 22)] : null,
          ),
          child: Icon(
            _icons[dir],
            size: size * 0.5,
            color: fg,
          ),
        ),
      ),
    );
  }
}
