// lib/features/games/measures/measure_fill_screen.dart
//
// "Takt-Füller" — a measure with a given time signature is partially filled;
// the child picks the note value that completes it exactly. Durations are
// computed in sixteenths; on success the completed measure is rendered.
//
// SRI: 'measures.fill.<beats>_<beatUnit>'.

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'dart:math';

import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/music_glyph.dart';
import '../widgets/game_widgets.dart';

/// Note durations in sixteenths, with their DSL letters and display glyphs.
const _durations = <int, (String, String)>{
  16: ('w', Smufl.wholeNote),
  8: ('h', Smufl.halfNote),
  4: ('q', Smufl.quarterNote),
  2: ('e', Smufl.eighthNote),
  1: ('s', Smufl.sixteenthNote),
};

class MeasureFillScreen extends StatefulWidget {
  const MeasureFillScreen({super.key});

  @override
  State<MeasureFillScreen> createState() => _MeasureFillScreenState();
}

class _MeasureFillScreenState extends State<MeasureFillScreen>
    with QuizRoundMixin {
  final _random = Random();

  static const _timeSignatures = [
    TimeSignature.twoFour,
    TimeSignature.threeFour,
    TimeSignature.fourFour,
  ];

  late TimeSignature _timeSignature;
  late List<String> _prefixTokens; // rendered, incomplete measure
  late int _remainder16; // the missing duration, in 16ths
  late List<int> _options; // 4 durations in 16ths
  bool _completed = false; // render the completed measure after success
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  String _randomPitchToken() {
    // Naturals within the staff (positions 2..8) keep stems tidy.
    final pitch = Clef.treble.pitchAt(2 + _random.nextInt(7));
    return '${pitch.step.name}${pitch.octave}';
  }

  @override
  void prepareRound() {
    _timeSignature =
        _timeSignatures[_random.nextInt(_timeSignatures.length)];
    final capacity = _timeSignature.beats * (16 ~/ _timeSignature.beatUnit);

    // The missing piece: a half, quarter or eighth that fits with room for
    // at least one prefix note.
    final candidates = [8, 4, 2].where((d) => d < capacity).toList();
    _remainder16 = candidates[_random.nextInt(candidates.length)];

    // Fill the rest of the measure with random h/q/e notes.
    _prefixTokens = [];
    var remaining = capacity - _remainder16;
    while (remaining > 0) {
      final fits = [8, 4, 2].where((d) => d <= remaining).toList();
      final d = fits[_random.nextInt(fits.length)];
      _prefixTokens.add('${_randomPitchToken()}:${_durations[d]!.$1}');
      remaining -= d;
    }

    final distractors = _durations.keys.where((d) => d != _remainder16).toList()
      ..shuffle(_random);
    _options = ([_remainder16, ...distractors.take(3)]..shuffle(_random));
    _completed = false;
    _lastAnswer = null;
  }

  Score get _renderedScore => Score.simple(
        timeSignature: _timeSignature,
        notes: [
          ..._prefixTokens,
          if (_completed)
            '${_randomPitchToken()}:${_durations[_remainder16]!.$1}',
        ].join(' '),
      );

  void _onAnswer(int duration16) {
    if (_completed) return; // round already resolved
    final correct = duration16 == _remainder16;

    if (_lastAnswer == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'measures.fill.${_timeSignature.beats}_${_timeSignature.beatUnit}',
            correct,
          );
    }

    setState(() {
      _lastAnswer = correct;
      if (correct) _completed = true;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameMeasureFill)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'measure_fill',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.measureFillPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: StaffView(
                              score: _renderedScore,
                              staffSpace: 12,
                              theme: PartituraTheme.kids,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final option in _options)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: _GlyphButton(
                                glyph: _durations[option]!.$2,
                                onTap: () => _onAnswer(option),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _GlyphButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;

  const _GlyphButton({required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 88,
          child: Center(child: MusicGlyph(glyph, size: 40)),
        ),
      ),
    );
  }
}
