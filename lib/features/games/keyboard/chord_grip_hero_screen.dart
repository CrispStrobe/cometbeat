// lib/features/games/keyboard/chord_grip_hero_screen.dart
//
// "Chord Grip Hero" — Falling Keys for chords (docs/PLAN.md original concepts).
// A triad falls down a lane on a real staff; its keys glow on the piano; press
// all of them together before it lands. Every full grip speeds up the next;
// three misses (a chord that lands ungripped) end the run.
//
// Diatonic white-key triads of C major so every grip is playable without black
// keys. SRI: 'keyboard.chord.<root>_<quality>'. Star-gated: primary triads
// (C/F/G major) for beginners, the minor triads (Dm/Em/Am) at 2★.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

/// A diatonic triad of C major (all white keys).
class _Grip {
  const _Grip(this.root, this.quality);
  final Step root;
  final ChordQuality quality;

  List<Pitch> get pitches => Triad(Pitch(root), quality).pitches;

  List<int> get midis => pitches.map((p) => p.midiNumber).toList();

  /// crisp_notation note tokens for the block chord, e.g. "c4+e4+g4:w".
  String get card {
    String tok(Pitch p) {
      final acc = switch (p.alter) { 1 => '#', -1 => 'b', _ => '' };
      return '${p.step.name}$acc${p.octave}';
    }

    return '${pitches.map(tok).join('+')}:w';
  }

  String get id => '${root.name}_${quality.name}';
}

const _primary = [
  _Grip(Step.c, ChordQuality.major),
  _Grip(Step.f, ChordQuality.major),
  _Grip(Step.g, ChordQuality.major),
];
const _minors = [
  _Grip(Step.d, ChordQuality.minor),
  _Grip(Step.e, ChordQuality.minor),
  _Grip(Step.a, ChordQuality.minor),
];

class ChordGripHeroScreen extends StatefulWidget {
  const ChordGripHeroScreen({super.key});

  static const _kTotalChords = 10;
  static const _kMaxLives = 3;

  @visibleForTesting
  static const maxLives = _kMaxLives;
  @visibleForTesting
  static const totalChords = _kTotalChords;

  @override
  State<ChordGripHeroScreen> createState() => _ChordGripHeroScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ChordGripHeroTester {
  int get score;
  int get lives;
  bool get finished;

  /// The MIDI keys of the falling chord that still need pressing.
  List<int> get requiredMidis;
}

class _ChordGripHeroScreenState extends State<ChordGripHeroScreen>
    with SingleTickerProviderStateMixin
    implements ChordGripHeroTester {
  final _random = Random();
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  late _Grip _grip;
  final Set<int> _pressed = {};
  int _spawnMs = 0;
  int _fallMs = 6000;
  int _resolved = 0;
  int _score = 0;
  int _lives = ChordGripHeroScreen._kMaxLives;
  bool _wide = false;
  bool _finished = false;
  int _flashUntil = 0;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  @override
  int get score => _score;
  @override
  int get lives => _lives;
  @override
  bool get finished => _finished;
  @override
  List<int> get requiredMidis =>
      _grip.midis.where((m) => !_pressed.contains(m)).toList();

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor('chord_grip_hero') >= 2;
    _spawn(0);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  int _fallForScore() => (6000 - 350 * _score).clamp(3000, 6000);

  void _spawn(int now) {
    final pool = _wide ? [..._primary, ..._minors] : _primary;
    _grip = pool[_random.nextInt(pool.length)];
    _pressed.clear();
    _spawnMs = now;
    _fallMs = _fallForScore();
  }

  double _progress(int now) => (now - _spawnMs) / _fallMs;

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;
    _now.value = now;
    if (_progress(now) > 1.0) {
      _miss();
    }
  }

  String get _sriId => 'keyboard.chord.${_grip.id}';

  void _onKey(int midi) {
    if (_finished) return;
    if (!_grip.midis.contains(midi)) {
      context.read<AudioService>().playWrong();
      setState(() => _flashUntil = _now.value + 200);
      return;
    }
    if (_pressed.contains(midi)) return;
    context.read<AudioService>().playMidiNote(midi, ms: 320);
    setState(() => _pressed.add(midi));
    if (_pressed.length == _grip.midis.length) _catch();
  }

  void _catch() {
    context.read<AudioService>().playMidiChord(_grip.midis, ms: 700);
    context.read<SriService>().recordResponse(_sriId, true);
    _score++;
    _resolved++;
    _mascot = NoteMascotMood.happy;
    if (_resolved >= ChordGripHeroScreen._kTotalChords) {
      _finish();
    } else {
      setState(() => _spawn(_now.value));
    }
  }

  void _miss() {
    context.read<AudioService>().playWrong();
    context.read<SriService>().recordResponse(_sriId, false);
    _lives--;
    _resolved++;
    _mascot = NoteMascotMood.oops;
    _flashUntil = _now.value + 260;
    if (_lives <= 0 || _resolved >= ChordGripHeroScreen._kTotalChords) {
      _finish();
    } else {
      setState(() => _spawn(_now.value));
    }
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    final stars = scoreToStars('chord_grip_hero', _score, true);
    context.read<ProgressService>().recordResult(
          'chord_grip_hero',
          score: _score,
          stars: stars,
          elapsedMs: _now.value,
        );
    context.read<AudioService>().playFanfare();
    setState(() {
      _mascot = _lives > 0 ? NoteMascotMood.happy : NoteMascotMood.oops;
    });
  }

  void _restart() {
    _ticker.stop();
    setState(() {
      _pressed.clear();
      _resolved = 0;
      _score = 0;
      _lives = ChordGripHeroScreen._kMaxLives;
      _finished = false;
      _flashUntil = 0;
      _mascot = NoteMascotMood.idle;
      _spawn(0);
    });
    _now.value = 0;
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameChordGripHero),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'chord_grip_hero',
                score: _score,
                onRestart: _restart,
              )
            : Column(
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
                        Text(
                          l10n.chordGripHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        for (var i = 0; i < ChordGripHeroScreen._kMaxLives; i++)
                          Icon(
                            i < _lives ? Icons.favorite : Icons.favorite_border,
                            color: i < _lives
                                ? Colors.redAccent
                                : scheme.outlineVariant,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return ValueListenableBuilder<int>(
                          valueListenable: _now,
                          builder: (context, now, _) {
                            final p = _progress(now).clamp(0.0, 1.0);
                            final laneH = constraints.maxHeight;
                            const cardH = 120.0;
                            final top = -cardH + (laneH - cardH) * p;
                            final flash = now < _flashUntil;
                            return ClipRect(
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      height: 4,
                                      color:
                                          flash ? scheme.error : scheme.primary,
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: top,
                                    height: cardH,
                                    child: Center(
                                      child: _ChordCard(notes: _grip.card),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                    child: SizedBox(
                      height: 150,
                      child: PianoKeyboard(
                        showLabels: true,
                        onKeyTap: _onKey,
                        keyColors: {
                          for (final m in _grip.midis)
                            m: _pressed.contains(m)
                                ? Colors.green.shade300
                                : scheme.primaryContainer,
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ChordCard extends StatelessWidget {
  const _ChordCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      height: 116,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Center(
        child: StaffView(
          score: Score.simple(notes: notes),
          staffSpace: 7,
          theme: kidsScoreTheme,
        ),
      ),
    );
  }
}
