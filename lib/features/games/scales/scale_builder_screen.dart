// lib/features/games/scales/scale_builder_screen.dart
//
// "Tonleiter-Baumeister" — the tonic is given (with the key signature); the
// child builds the major scale by tapping the next line/space, note by note,
// up to the octave. Every placed note sounds with its correct pitch (the key
// signature supplies the accidentals); the finished scale plays through.
//
// SRI: 'scales.build.<tonic>_major' (correct = built without a wrong tap).

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step` (Stepper) and `Key`; crisp_notation's win here.
import 'package:flutter/material.dart' hide Step, Key;
import 'package:provider/provider.dart';

class ScaleBuilderScreen extends StatefulWidget {
  const ScaleBuilderScreen({super.key});

  @override
  State<ScaleBuilderScreen> createState() => _ScaleBuilderScreenState();
}

class _ScaleBuilderScreenState extends State<ScaleBuilderScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Difficulty ladder: a few majors → all majors → the natural minors
  // (docs/PLAN.md) for broader scale exposure.
  static const _baseTonics = [Step.c, Step.f, Step.g];
  static const _majorTonics = [
    Step.c,
    Step.d,
    Step.e,
    Step.f,
    Step.g,
    Step.a,
    Step.b,
  ];
  static const _minorTonics = [Step.a, Step.e, Step.d, Step.b, Step.g, Step.c];

  late Step _tonic;
  late ScaleType _scaleType;
  late Key _key;
  late List<Pitch> _scale; // 8 ascending pitches
  late int _tonicPosition;
  int _placedCount = 1; // the tonic is pre-placed
  bool? _lastAnswer;
  bool _sriRecorded = false;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'scale_builder';

  // Placed pitches and the finished scale are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    final stars = context.read<ProgressService>().starsFor('scale_builder');
    if (stars >= 3) {
      _tonic = _minorTonics[_random.nextInt(_minorTonics.length)];
      _scaleType = ScaleType.naturalMinor;
    } else if (stars >= 2) {
      _tonic = _majorTonics[_random.nextInt(_majorTonics.length)];
      _scaleType = ScaleType.major;
    } else {
      _tonic = _baseTonics[_random.nextInt(_baseTonics.length)];
      _scaleType = ScaleType.major;
    }
    final isMinor = _scaleType != ScaleType.major;
    _key = isMinor ? Key.minor(Pitch(_tonic)) : Key.major(Pitch(_tonic));
    _scale = Scale(Pitch(_tonic), _scaleType).pitches;
    _tonicPosition = Pitch(_tonic).staffPosition(Clef.treble);
    _placedCount = 1;
    _lastAnswer = null;
    _sriRecorded = false;
  }

  bool get _complete => _placedCount >= _scale.length;

  Score get _score => Score(
        clef: Clef.treble,
        keySignature: _key.signature,
        measures: [
          Measure([
            for (var i = 0; i < _placedCount; i++)
              NoteElement(
                pitches: [_scale[i]],
                duration: const NoteDuration(DurationBase.quarter),
                id: 'n$i',
              ),
          ]),
          // Whole-rest measure keeps the tappable staff wide while the
          // scale is still short.
          if (_placedCount < 5)
            const Measure([RestElement(NoteDuration(DurationBase.whole))]),
        ],
      );

  void _record(bool correct) {
    if (_sriRecorded) return;
    _sriRecorded = true;
    final mode = _scaleType == ScaleType.major ? 'major' : 'minor';
    context
        .read<SriService>()
        .recordResponse('scales.build.${_tonic.name}_$mode', correct);
  }

  void _onStaffTap(StaffTarget target) {
    if (_complete) return; // round already resolved
    final audio = context.read<AudioService>();
    final expectedPosition = _tonicPosition + _placedCount;

    if (target.staffPosition == expectedPosition) {
      final pitch = _scale[_placedCount];
      audio.playMidiNote(pitch.midiNumber, ms: 450);
      setState(() {
        _placedCount++;
        _lastAnswer = true;
      });
      if (_complete) {
        _record(!answeredWrong);
        audio.playSequence([
          for (final p in _scale) (p.midiNumber, 320),
        ]);
        resolveAnswer(correct: true);
      }
    } else {
      _record(false);
      audio.playWrong();
      setState(() => _lastAnswer = false);
      resolveAnswer(correct: false);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || _complete) return;
        setState(() => _lastAnswer = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameScaleBuilder),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'scale_builder',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: _scaleType == ScaleType.major
                          ? l10n.scaleBuilderPrompt(
                              noteNameFor(context, _tonic),
                            )
                          : l10n.scaleBuilderPromptMinor(
                              noteNameFor(context, _tonic),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: InteractiveStaff(
                              score: _score,
                              theme: kidsScoreTheme,
                              staffSpace: 13,
                              onStaffTap: _onStaffTap,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _scale.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(
                              i < _placedCount
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                  ],
                ),
              ),
      ),
    );
  }
}
