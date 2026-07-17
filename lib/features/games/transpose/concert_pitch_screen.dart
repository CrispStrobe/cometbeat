// lib/features/games/transpose/concert_pitch_screen.dart
//
// "Concert Pitch" — transposing-instrument reading (docs/PLAN.md, built on
// crisp_notation's Transposition support). A written note is shown for a named
// transposing instrument (B♭ trumpet, E♭ alto sax, F horn); the child names the
// concert pitch that actually sounds. crisp_notation's `transposeBy` does the maths,
// so the letter answer is exact.
//
// Star-gated: the B♭ instruments alone for beginners; E♭ and F added at 2★.
// SRI: 'transpose.<instrument>.<written-step>'.

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
// Material also exports `Step` and `Interval`; crisp_notation's win here.
import 'package:flutter/material.dart' hide Interval, Step;
import 'package:provider/provider.dart';

/// A transposing instrument: its transposition and a display name.
class _Instrument {
  const _Instrument(this.id, this.transposition, this.name);
  final String id;
  final Transposition transposition;
  final String Function(AppLocalizations) name;
}

final _instruments = <_Instrument>[
  _Instrument('bb', Transposition.bFlat, (l) => l.concertInstrumentBb),
  _Instrument('eb', Transposition.eFlat, (l) => l.concertInstrumentEb),
  _Instrument('f', Transposition.f, (l) => l.concertInstrumentF),
];

class ConcertPitchScreen extends StatefulWidget {
  const ConcertPitchScreen({super.key});

  @override
  State<ConcertPitchScreen> createState() => _ConcertPitchScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ConcertPitchTester {
  /// The correct concert-pitch letter for the current round.
  Step get answerStep;
}

class _ConcertPitchScreenState extends State<ConcertPitchScreen>
    with QuizRoundMixin
    implements ConcertPitchTester {
  static const _wholeNote = NoteDuration(DurationBase.whole);

  final _random = Random();

  late _Instrument _instrument;
  late Pitch _written;
  late Pitch _concert;
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;
  bool _wide = false;

  @override
  Step get answerStep => _concert.step;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'concert_pitch';

  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  Pitch _toConcert(Pitch written, Transposition t) {
    var p = written.transposeBy(t.interval, descending: t.down);
    for (var i = 0; i < t.octaves; i++) {
      p = p.transposeBy(Interval.perfectOctave, descending: t.down);
    }
    return p;
  }

  @override
  void prepareRound() {
    final pool = _wide ? _instruments : [_instruments.first];
    _instrument = pool[_random.nextInt(pool.length)];
    // Natural written notes in a comfortable treble range.
    _written = Clef.treble.pitchAt(2 + _random.nextInt(7)); // 2..8
    _concert = _toConcert(_written, _instrument.transposition);

    final distractors = [...Step.values]
      ..remove(_concert.step)
      ..shuffle(_random);
    _options = [_concert.step, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _concert.step;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'transpose.${_instrument.id}.${_written.step.name}',
            correct,
          );
    }
    if (correct) {
      context.read<AudioService>().playMidiNote(_concert.midiNumber);
    } else {
      context.read<AudioService>().playWrong();
    }
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameConcertPitch),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
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
                      prompt: l10n.concertPitchPrompt(_instrument.name(l10n)),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 12,
                            ),
                            child: StaffView(
                              score: Score(
                                clef: Clef.treble,
                                measures: [
                                  Measure([
                                    NoteElement.note(
                                      _written,
                                      _wholeNote,
                                      id: 'written',
                                    ),
                                  ]),
                                ],
                              ),
                              staffSpace: 14,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.concertPitchHint,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _concert.step
                                      ? Colors.green
                                      : option == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(noteNameFor(context, option)),
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
