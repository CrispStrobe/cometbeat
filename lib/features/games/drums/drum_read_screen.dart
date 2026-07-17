// lib/features/games/drums/drum_read_screen.dart
//
// "Drum Read" — read a rhythm on the neutral percussion staff (crisp_notation's
// percussion clef) and tap it back on the drum pad in time. After a one-bar
// count-in, the two shown bars are "live"; each tap is judged Perfect/Good/Miss
// against the notated onsets over a steady click. A no-fail rhythm-reading toy,
// scored like Beat Runner.
//
// The game's own Ticker is the master clock, so click, notation and tap timing
// share one reference (no audio-latency drift). SRI-free (a performance toy).

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/tuning.dart';
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

class DrumReadScreen extends StatefulWidget {
  const DrumReadScreen({super.key});

  static const _beatMs = 700; // ~86 BPM
  static const _countInBeats = 4; // one bar of "get ready" clicks
  static const _hitWindowMs = 220;
  static const _perfectMs = 100;

  // One-bar 4/4 patterns (durations in beats; each sums to 4).
  static const _patterns = <List<double>>[
    [1, 1, 1, 1],
    [2, 1, 1],
    [1, 1, 2],
    [2, 2],
    [1, 0.5, 0.5, 1, 1],
    [0.5, 0.5, 1, 1, 1],
  ];

  @visibleForTesting
  static const padKey = ValueKey('drum_pad');

  static String _durToken(double beats) {
    if (beats >= 2) return 'h';
    if (beats >= 1) return 'q';
    return 'e';
  }

  @override
  State<DrumReadScreen> createState() => _DrumReadScreenState();
}

/// A notated onset the child must play.
class _Onset {
  _Onset(this.timeMs);
  final int timeMs;
  bool resolved = false;
}

@visibleForTesting
abstract interface class DrumReadTester {
  int get score;
  int get hits;
  int get noteCount;
  bool get finished;

  /// The scheduled play time (ms) of onset [i].
  int onsetTimeMs(int i);
}

enum _Judgement { perfect, good, miss }

class _DrumReadScreenState extends State<DrumReadScreen>
    with SingleTickerProviderStateMixin
    implements DrumReadTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  late final List<List<double>> _bars;
  late final List<_Onset> _onsets;
  late final String _notation;
  late final int _totalBeats;

  int _score = 0;
  int _hits = 0;
  int _lastBeatClicked = -1;
  bool _finished = false;

  _Judgement? _lastJudgement;
  int _judgementUntil = 0;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  @override
  int get score => _score;
  @override
  int get hits => _hits;
  @override
  int get noteCount => _onsets.length;
  @override
  bool get finished => _finished;
  @override
  int onsetTimeMs(int i) => _onsets[i].timeMs;

  @override
  void initState() {
    super.initState();
    _bars = [
      DrumReadScreen
          ._patterns[_random.nextInt(DrumReadScreen._patterns.length)],
      DrumReadScreen
          ._patterns[_random.nextInt(DrumReadScreen._patterns.length)],
    ];
    // Notation: a fixed drum position (b4) with each pattern's durations,
    // bars separated by '|'.
    _notation = _bars
        .map(
          (bar) =>
              bar.map((d) => 'b4:${DrumReadScreen._durToken(d)}').join(' '),
        )
        .join(' | ');

    // Onsets: after the count-in, each note's start on the beat grid.
    final onsets = <_Onset>[];
    var cursor = DrumReadScreen._countInBeats.toDouble();
    for (final bar in _bars) {
      for (final beats in bar) {
        onsets.add(_Onset((cursor * DrumReadScreen._beatMs).round()));
        cursor += beats;
      }
    }
    _onsets = onsets;
    _totalBeats = cursor.round();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  int get _currentBeat => (_now.value / DrumReadScreen._beatMs).floor();

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;

    // Steady click on every beat, accented on each bar's downbeat.
    while (_lastBeatClicked + 1 < _totalBeats &&
        now >= (_lastBeatClicked + 1) * DrumReadScreen._beatMs) {
      _lastBeatClicked++;
      final down = _lastBeatClicked % 4 == 0;
      context.read<AudioService>().playMidiNote(down ? 84 : 72, ms: 80);
      setState(() {}); // update the beat counter during the count-in
    }

    var missed = false;
    for (final o in _onsets) {
      if (!o.resolved && now > o.timeMs + DrumReadScreen._hitWindowMs) {
        o.resolved = true;
        _lastJudgement = _Judgement.miss;
        _judgementUntil = now + 320;
        _mascot = NoteMascotMood.oops;
        missed = true;
      }
    }

    _now.value = now;
    if (missed) setState(() {});

    if (now > _onsets.last.timeMs + DrumReadScreen._hitWindowMs + 500) {
      _finish();
    }
  }

  void _onTap() {
    if (_finished) return;
    final now = _now.value;
    var best = -1;
    var bestDelta = DrumReadScreen._hitWindowMs + 1;
    for (var i = 0; i < _onsets.length; i++) {
      if (_onsets[i].resolved) continue;
      final d = (now - _onsets[i].timeMs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = i;
      }
    }
    context.read<AudioService>().playMidiNote(48, ms: 140); // low drum-ish hit
    if (best < 0) return;

    _onsets[best].resolved = true;
    _hits++;
    final perfect = bestDelta <= DrumReadScreen._perfectMs;
    _score += perfect ? 20 : 10;
    _lastJudgement = perfect ? _Judgement.perfect : _Judgement.good;
    _judgementUntil = now + 320;
    _mascot = NoteMascotMood.happy;
    setState(() {});
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    context.read<AudioService>().playFanfare();
    context.read<ProgressService>().recordResult(
          'drum_read',
          score: _score,
          stars: scoreToStars('drum_read', _score, true),
        );
    setState(() {});
  }

  void _restart() {
    _ticker.stop();
    for (final o in _onsets) {
      o.resolved = false;
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
      appBar: GameAppBar(title: l10n.gameDrumRead),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'drum_read',
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
                          // Count-in indicator during the first bar.
                          ValueListenableBuilder<int>(
                            valueListenable: _now,
                            builder: (context, now, _) {
                              final beat = _currentBeat;
                              if (beat >= DrumReadScreen._countInBeats) {
                                return Text(
                                  l10n.drumReadGo,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                );
                              }
                              return Text(
                                '${beat + 1}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: StaffView(
                          score: Score.simple(
                            clef: Clef.percussion,
                            timeSignature: TimeSignature.fourFour,
                            notes: _notation,
                          ),
                          staffSpace: 12,
                          theme: kidsScoreTheme,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GestureDetector(
                          key: DrumReadScreen.padKey,
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _onTap(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: scheme.primary, width: 4),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.album,
                                size: 96,
                                color: scheme.primary.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        l10n.drumReadHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_now.value < _judgementUntil && _lastJudgement != null)
                      _JudgementText(judgement: _lastJudgement!, l10n: l10n),
                  ],
                ),
              ),
      ),
    );
  }
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
