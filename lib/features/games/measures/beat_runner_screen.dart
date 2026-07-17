// lib/features/games/measures/beat_runner_screen.dart
//
// "Im Takt" / "Beat Runner" — read and play a rhythm in time. Reworked from a
// flat metronome (tapping a steady pulse taught nothing) into a rhythm-reading
// lane: note-value markers fall spaced by their REAL durations — a half note
// takes twice as long to arrive as a quarter, an eighth half as long — and the
// child taps each as it crosses the hit-line, over a steady click. So a good
// run means the child has read and performed the rhythm.
//
// The game's own Ticker is the master clock, so the click, the falling markers
// and the tap timing all reference one clock — no audio-latency drift. Taps
// score Perfect/Good by accuracy; a no-fail toy scored like Sound Echo.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class BeatRunnerScreen extends StatefulWidget {
  const BeatRunnerScreen({super.key});

  static const _beatMs = 700; // ~86 BPM
  static const _travelMs = 1400; // a marker is airborne for two beats
  static const _leadMs = _travelMs + 500;
  static const _hitWindowMs = 200;
  static const _perfectMs = 90;

  // One-measure 4/4 rhythm patterns (durations in beats; each sums to 4).
  static const _patterns = <List<double>>[
    [1, 1, 1, 1],
    [2, 1, 1],
    [1, 1, 2],
    [2, 2],
    [1, 0.5, 0.5, 1, 1],
    [0.5, 0.5, 1, 1, 1],
    [1, 1, 0.5, 0.5, 1],
  ];

  static const _measures = 4;

  static String _glyphFor(double beats) {
    if (beats >= 4) return Smufl.wholeNote;
    if (beats >= 2) return Smufl.halfNote;
    if (beats >= 1) return Smufl.quarterNote;
    return Smufl.eighthNote;
  }

  @visibleForTesting
  static const padKey = ValueKey('beat_pad');

  @override
  State<BeatRunnerScreen> createState() => _BeatRunnerScreenState();
}

/// A note in the falling rhythm.
class _RhythmNote {
  _RhythmNote(this.timeMs, this.glyph, this.column);
  final int timeMs; // when it lands on the hit-line
  final String glyph;
  final int column; // gentle horizontal offset so equal onsets don't overlap
  bool resolved = false;
}

@visibleForTesting
abstract interface class BeatRunnerTester {
  int get score;
  int get hits;
  int get noteCount;
  bool get finished;

  /// Landing time (ms) of note [i] — lets tests tap it on the beat.
  int noteTimeMs(int i);
}

enum _Judgement { perfect, good, miss }

class _BeatRunnerScreenState extends State<BeatRunnerScreen>
    with SingleTickerProviderStateMixin
    implements BeatRunnerTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  late final List<_RhythmNote> _notes = _buildRhythm();
  late final int _totalBeats;

  int _score = 0;
  int _hits = 0;
  int _lastBeatClicked = -1;
  bool _finished = false;

  _Judgement? _lastJudgement;
  int _judgementUntil = 0;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  List<_RhythmNote> _buildRhythm() {
    final notes = <_RhythmNote>[];
    var beatCursor = 0.0;
    var col = 0;
    for (var m = 0; m < BeatRunnerScreen._measures; m++) {
      final pattern = BeatRunnerScreen
          ._patterns[_random.nextInt(BeatRunnerScreen._patterns.length)];
      for (final beats in pattern) {
        final timeMs = BeatRunnerScreen._leadMs +
            (beatCursor * BeatRunnerScreen._beatMs).round();
        notes.add(
          _RhythmNote(timeMs, BeatRunnerScreen._glyphFor(beats), col % 3),
        );
        col++;
        beatCursor += beats;
      }
    }
    _totalBeats = beatCursor.round();
    return notes;
  }

  @override
  int get score => _score;
  @override
  int get hits => _hits;
  @override
  int get noteCount => _notes.length;
  @override
  bool get finished => _finished;
  @override
  int noteTimeMs(int i) => _notes[i].timeMs;

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

  double _progress(_RhythmNote n, int now) =>
      (now - (n.timeMs - BeatRunnerScreen._travelMs)) /
      BeatRunnerScreen._travelMs;

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;

    // A steady click on every beat, accented on the bar's downbeat.
    while (_lastBeatClicked + 1 < _totalBeats &&
        now >=
            BeatRunnerScreen._leadMs +
                (_lastBeatClicked + 1) * BeatRunnerScreen._beatMs) {
      _lastBeatClicked++;
      final down = _lastBeatClicked % 4 == 0;
      context.read<AudioService>().playMidiNote(down ? 84 : 72, ms: 90);
    }

    var missed = false;
    for (final n in _notes) {
      if (!n.resolved && now > n.timeMs + BeatRunnerScreen._hitWindowMs) {
        n.resolved = true;
        _lastJudgement = _Judgement.miss;
        _judgementUntil = now + 350;
        _mascot = NoteMascotMood.oops;
        missed = true;
      }
    }

    _now.value = now;
    if (missed) setState(() {});

    if (now > _notes.last.timeMs + BeatRunnerScreen._hitWindowMs + 500) {
      _finish();
    }
  }

  void _onTap() {
    if (_finished) return;
    final now = _now.value;

    var best = -1;
    var bestDelta = BeatRunnerScreen._hitWindowMs + 1;
    for (var i = 0; i < _notes.length; i++) {
      if (_notes[i].resolved) continue;
      final d = (now - _notes[i].timeMs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = i;
      }
    }
    if (best < 0) return;

    _notes[best].resolved = true;
    _hits++;
    final perfect = bestDelta <= BeatRunnerScreen._perfectMs;
    _score += perfect ? 20 : 10;
    _lastJudgement = perfect ? _Judgement.perfect : _Judgement.good;
    _judgementUntil = now + 350;
    _mascot = NoteMascotMood.happy;
    context
        .read<AudioService>()
        .playMidiNote(67, ms: 150); // a wood-block-ish hit
    setState(() {});
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    context.read<AudioService>().playFanfare();
    context.read<ProgressService>().recordResult(
          'beat_runner',
          score: _score,
          stars: scoreToStars('beat_runner', _score, true),
        );
    setState(() {});
  }

  void _restart() {
    _ticker.stop();
    for (final n in _notes) {
      n.resolved = false;
    }
    _score = 0;
    _hits = 0;
    _lastBeatClicked = -1;
    _lastJudgement = null;
    _finished = false;
    _mascot = NoteMascotMood.idle;
    _now.value = 0;
    setState(() {});
    _ticker.start();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameBeatRunner),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'beat_runner',
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
                          Flexible(
                            child: Text(
                              l10n.beatRunnerHint,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        key: BeatRunnerScreen.padKey,
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) => _onTap(),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.biggest;
                            final hitY = size.height * 0.82;
                            return ValueListenableBuilder<int>(
                              valueListenable: _now,
                              builder: (context, now, _) {
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // The hit-line.
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: hitY,
                                      child: Container(
                                        height: 3,
                                        color: scheme.primary,
                                      ),
                                    ),
                                    Positioned(
                                      left: size.width / 2 - 30,
                                      top: hitY - 30,
                                      child: _TargetRing(color: scheme.primary),
                                    ),
                                    for (final n in _notes)
                                      if (_visible(n, now))
                                        _fallingMarker(
                                          n,
                                          size,
                                          hitY,
                                          now,
                                          scheme,
                                        ),
                                    if (now < _judgementUntil &&
                                        _lastJudgement != null)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        top: hitY - 92,
                                        child: _JudgementText(
                                          judgement: _lastJudgement!,
                                          l10n: l10n,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  bool _visible(_RhythmNote n, int now) {
    final p = _progress(n, now);
    if (p < 0 || p > 1.3) return false;
    if (n.resolved && p > 1.0) return false;
    return true;
  }

  Widget _fallingMarker(
    _RhythmNote n,
    Size size,
    double hitY,
    int now,
    ColorScheme scheme,
  ) {
    final p = _progress(n, now);
    const markerSize = 56.0;
    final cx = size.width / 2 + (n.column - 1) * 4.0;
    final y = p * hitY;
    return Positioned(
      left: cx - markerSize / 2,
      top: y - markerSize / 2,
      width: markerSize,
      height: markerSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: n.resolved ? Colors.green.shade200 : scheme.tertiaryContainer,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.tertiary, width: 2),
        ),
        child: Center(
          child:
              MusicGlyph(n.glyph, size: 30, color: scheme.onTertiaryContainer),
        ),
      ),
    );
  }
}

class _TargetRing extends StatelessWidget {
  const _TargetRing({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.6), width: 3),
        ),
      );
}

class _JudgementText extends StatelessWidget {
  const _JudgementText({required this.judgement, required this.l10n});
  final _Judgement judgement;
  final AppLocalizations l10n;
  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (judgement) {
      _Judgement.perfect => (l10n.beatPerfect, Colors.amber),
      _Judgement.good => (l10n.beatGood, Colors.lightGreen),
      _Judgement.miss => (l10n.beatMiss, Colors.redAccent),
    };
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
