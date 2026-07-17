// lib/features/games/scales/echo_sequence_screen.dart
//
// "Ton-Echo" / "Sound Echo" — a melodic-memory game turned into a reading toy.
// Four pentatonic pads each carry a pitch AND its notehead on a mini-staff. The
// app lights and plays a growing sequence; the child echoes it back. What makes
// it educative is that the *cues fade as the sequence grows*: it starts with
// colour + sound + notation, then drops the colour, then the sound — until at
// the longest runs the child is reading the noteheads alone. One wrong pad ends
// the run; the score is the longest sequence reached.
//
// No SRI — short-term memory, not a drilled fact — but now it trains ear↔staff.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

enum _Phase { watching, repeating, over }

/// A perceptual channel a step can be shown through.
enum Cue { colour, sound, note }

class EchoSequenceScreen extends StatefulWidget {
  const EchoSequenceScreen({super.key});

  // A C-major pentatonic (C D E G) in octave 5 — clean on the treble staff and
  // consonant in any order.
  static const _pitches = [
    Pitch(Step.c, octave: 5),
    Pitch(Step.d, octave: 5),
    Pitch(Step.e, octave: 5),
    Pitch(Step.g, octave: 5),
  ];

  /// Which cues are active for a sequence of the given length — they thin out
  /// as it grows, so notation carries more and more of the load. Notation is
  /// always on (the pads stay readable and tappable).
  static Set<Cue> cuesFor(int length) {
    if (length < 4) return {Cue.colour, Cue.sound, Cue.note};
    if (length < 6) return {Cue.sound, Cue.note};
    if (length < 8) return {Cue.colour, Cue.note};
    return {Cue.note};
  }

  @override
  State<EchoSequenceScreen> createState() => _EchoSequenceScreenState();
}

class _EchoSequenceScreenState extends State<EchoSequenceScreen> {
  final _random = Random();
  final List<int> _sequence = [];
  _Phase _phase = _Phase.watching;
  int _watchPos = 0;
  int _inputIndex = 0;
  int _best = 0; // longest sequence completed
  int? _lit; // currently highlighted pad

  Timer? _watchTimer;
  Timer? _flashTimer;
  Timer? _startTimer;

  Set<Cue> get _cues => EchoSequenceScreen.cuesFor(_sequence.length);

  int _midi(int pad) => EchoSequenceScreen._pitches[pad].midiNumber;

  @override
  void initState() {
    super.initState();
    _startTimer = Timer(const Duration(milliseconds: 600), _addAndWatch);
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _flashTimer?.cancel();
    _startTimer?.cancel();
    super.dispose();
  }

  void _addAndWatch() {
    if (!mounted) return;
    _sequence.add(_random.nextInt(EchoSequenceScreen._pitches.length));
    _startWatch();
  }

  void _startWatch() {
    setState(() {
      _phase = _Phase.watching;
      _watchPos = 0;
      _inputIndex = 0;
      _lit = null;
    });
    _watchStep();
  }

  void _watchStep() {
    if (!mounted) return;
    if (_watchPos >= _sequence.length) {
      setState(() => _phase = _Phase.repeating);
      return;
    }
    final pad = _sequence[_watchPos];
    setState(() => _lit = pad);
    if (_cues.contains(Cue.sound)) {
      context.read<AudioService>().playMidiNote(_midi(pad));
    }
    _watchTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      setState(() => _lit = null);
      _watchTimer = Timer(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        _watchPos++;
        _watchStep();
      });
    });
  }

  void _flash(int pad) {
    setState(() => _lit = pad);
    // A tap sounds only when the sound cue is on, so the silent (reading) levels
    // stay honest.
    if (_cues.contains(Cue.sound)) {
      context.read<AudioService>().playMidiNote(_midi(pad), ms: 350);
    }
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _lit = null);
    });
  }

  void _onPad(int pad) {
    if (_phase != _Phase.repeating) return;
    _flash(pad);

    if (pad == _sequence[_inputIndex]) {
      _inputIndex++;
      if (_inputIndex == _sequence.length) {
        _best = _sequence.length;
        setState(() => _phase = _Phase.watching);
        _startTimer = Timer(const Duration(milliseconds: 700), _addAndWatch);
      }
    } else {
      _gameOver();
    }
  }

  void _gameOver() {
    context.read<AudioService>().playWrong();
    context.read<ProgressService>().recordResult(
          'echo_sequence',
          score: _best * 100,
          stars: scoreToStars('echo_sequence', _best * 100, true),
        );
    setState(() => _phase = _Phase.over);
  }

  void _restart() {
    _watchTimer?.cancel();
    _flashTimer?.cancel();
    _startTimer?.cancel();
    _sequence.clear();
    _best = 0;
    _lit = null;
    setState(() => _phase = _Phase.watching);
    _startTimer = Timer(const Duration(milliseconds: 500), _addAndWatch);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cues = _cues;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameEchoSequence),
      body: SafeArea(
        child: _phase == _Phase.over
            ? GameResultView(
                gameType: 'echo_sequence',
                score: _best * 100,
                onRestart: _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      _phase == _Phase.watching
                          ? l10n.echoWatch
                          : l10n.echoRepeat,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.echoLength(_sequence.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    _CueBar(cues: cues),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            children: [
                              for (var i = 0;
                                  i < EchoSequenceScreen._pitches.length;
                                  i++)
                                _Pad(
                                  pitch: EchoSequenceScreen._pitches[i],
                                  showColour: cues.contains(Cue.colour),
                                  showNote: cues.contains(Cue.note),
                                  lit: _lit == i,
                                  onTap: _phase == _Phase.repeating
                                      ? () => _onPad(i)
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Shows which cues are active this level (colour / sound / notation).
class _CueBar extends StatelessWidget {
  const _CueBar({required this.cues});
  final Set<Cue> cues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(IconData icon, bool on) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(
            icon,
            size: 22,
            color: on ? scheme.primary : scheme.outlineVariant,
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip(Icons.palette, cues.contains(Cue.colour)),
        chip(Icons.volume_up, cues.contains(Cue.sound)),
        chip(Icons.music_note, cues.contains(Cue.note)),
      ],
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({
    required this.pitch,
    required this.showColour,
    required this.showNote,
    required this.lit,
    required this.onTap,
  });

  final Pitch pitch;
  final bool showColour;
  final bool showNote;
  final bool lit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = pitchClassColor(pitch.step);
    final base = showColour ? colour : scheme.surfaceContainerHighest;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: lit
              ? (showColour ? colour : scheme.primaryContainer)
              : base.withValues(alpha: showColour ? 0.55 : 1.0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: lit ? scheme.primary : scheme.outlineVariant,
            width: lit ? 4 : 2,
          ),
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: scheme.primary,
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: showNote
            ? Center(
                child: StaffView(
                  score: Score.simple(
                    notes: '${pitch.step.name}${pitch.octave}:w',
                  ),
                  staffSpace: 9,
                  theme: kidsScoreTheme,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
