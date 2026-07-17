// lib/features/games/harmony/cadence_workshop_screen.dart
//
// "Kadenzen-Werkstatt" — build the classic cadence T–S–D–T in a given key.
// Three unlabeled chord cards (rendered notation) are on the table; the
// prompt asks for one function at a time. Every correct pick sounds and is
// appended to the growing cadence staff; the finished cadence plays through.
//
// SRI: 'harmony.cadence.<tonic>_major' (correct = built without a wrong tap).

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
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

class CadenceWorkshopScreen extends StatefulWidget {
  const CadenceWorkshopScreen({super.key});

  @override
  State<CadenceWorkshopScreen> createState() => _CadenceWorkshopScreenState();
}

class _CadenceWorkshopScreenState extends State<CadenceWorkshopScreen>
    with QuizRoundMixin {
  final _random = Random();

  static const _tonics = [Step.c, Step.g, Step.f];
  static const _sequence = [
    HarmonicFunction.tonic,
    HarmonicFunction.subdominant,
    HarmonicFunction.dominant,
    HarmonicFunction.tonic,
  ];

  late Step _tonic;
  late Key _key;
  late List<HarmonicFunction> _cards; // shuffled T/S/D
  int _stepIndex = 0;
  bool? _lastAnswer;
  bool _sriRecorded = false;

  @override
  int get totalRounds => 4;

  @override
  String get gameType => 'cadence_workshop';

  // The chords themselves are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _tonic = _tonics[_random.nextInt(_tonics.length)];
    _key = Key.major(Pitch(_tonic));
    _cards = [...HarmonicFunction.values]..shuffle(_random);
    _stepIndex = 0;
    _lastAnswer = null;
    _sriRecorded = false;
  }

  bool get _complete => _stepIndex >= _sequence.length;

  List<int> _midis(HarmonicFunction f) =>
      _key.triadFor(f).pitches.map((p) => p.midiNumber).toList();

  Score _chordScore(HarmonicFunction f, {String? id}) => Score(
        clef: Clef.treble,
        keySignature: _key.signature,
        measures: [
          Measure([
            NoteElement(
              pitches: _key.triadFor(f).pitches,
              duration: const NoteDuration(DurationBase.whole),
              id: id,
            ),
          ]),
        ],
      );

  Score get _cadenceScore => Score(
        clef: Clef.treble,
        keySignature: _key.signature,
        measures: [
          for (var i = 0; i < _sequence.length; i++)
            Measure([
              if (i < _stepIndex)
                NoteElement(
                  pitches: _key.triadFor(_sequence[i]).pitches,
                  duration: const NoteDuration(DurationBase.whole),
                  id: 'c$i',
                )
              else
                const RestElement(NoteDuration(DurationBase.whole)),
            ]),
        ],
      );

  void _record(bool correct) {
    if (_sriRecorded) return;
    _sriRecorded = true;
    context
        .read<SriService>()
        .recordResponse('harmony.cadence.${_tonic.name}_major', correct);
  }

  void _onCardTap(HarmonicFunction choice) {
    if (_complete) return; // round already resolved
    final audio = context.read<AudioService>();
    final correct = choice == _sequence[_stepIndex];

    if (correct) {
      audio.playMidiChord(_midis(choice), ms: 900);
      setState(() {
        _stepIndex++;
        _lastAnswer = true;
      });
      if (_complete) {
        _record(!answeredWrong);
        audio.playChordSequence(
          [for (final f in _sequence) _midis(f)],
        );
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

  String _functionLabel(AppLocalizations l10n, HarmonicFunction f) =>
      switch (f) {
        HarmonicFunction.tonic => l10n.harmonicTonic,
        HarmonicFunction.subdominant => l10n.harmonicSubdominant,
        HarmonicFunction.dominant => l10n.harmonicDominant,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCadenceWorkshop),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'cadence_workshop',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: _complete
                          ? l10n.feedbackCorrect
                          : l10n.cadencePrompt(
                              _functionLabel(
                                l10n,
                                _sequence[_stepIndex],
                              ),
                              l10n.keyMajorName(noteNameFor(context, _tonic)),
                            ),
                    ),
                    const SizedBox(height: 12),
                    // The growing cadence: T – S – D – T as four measures.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: StaffView(
                          score: _cadenceScore,
                          staffSpace: 9,
                          theme: kidsScoreTheme,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    // The three chord cards (unlabeled — read the staff!).
                    Expanded(
                      child: Row(
                        children: [
                          for (final f in _cards)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => _onCardTap(f),
                                    child: Center(
                                      child: StaffView(
                                        score: _chordScore(f),
                                        staffSpace: 8,
                                      ),
                                    ),
                                  ),
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
    );
  }
}
