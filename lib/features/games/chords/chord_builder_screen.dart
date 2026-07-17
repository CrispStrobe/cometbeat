// lib/features/games/chords/chord_builder_screen.dart
//
// "Chord Builder" — build the named chord by tapping three notes onto the staff.
// crisp_notation's `identifyChord` grades what you built, so **any voicing counts**:
// root position or an inversion, in any octave, is accepted as long as the
// pitch classes spell the target chord. The interactive counterpart to Name
// That Chord, and the reason the chord engine can grade more than root position.
//
// Star-gated: major/minor for beginners; diminished/augmented added at 2★.
// SRI: 'chords.build.<root>_<quality>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _wholeRest = RestElement(NoteDuration(DurationBase.whole));
const _emptyScore = Score(
  clef: Clef.treble,
  measures: [
    Measure([_wholeRest]),
  ],
);

/// Maps the target triad quality to the type identifyChord reports.
const _typeFor = <ChordQuality, ChordType>{
  ChordQuality.major: ChordType.major,
  ChordQuality.minor: ChordType.minor,
  ChordQuality.diminished: ChordType.diminished,
  ChordQuality.augmented: ChordType.augmented,
};

class ChordBuilderScreen extends StatefulWidget {
  const ChordBuilderScreen({super.key});

  @override
  State<ChordBuilderScreen> createState() => _ChordBuilderScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ChordBuilderTester {
  /// The three concert pitches of the target chord (a correct answer).
  List<Pitch> get targetPitches;

  /// Places [pitch] as if the child tapped that spot on the staff.
  void debugPlace(Pitch pitch);

  /// Grades the currently-placed notes.
  void debugCheck();
}

class _ChordBuilderScreenState extends State<ChordBuilderScreen>
    with QuizRoundMixin
    implements ChordBuilderTester {
  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  final _random = Random();

  late Step _root;
  late ChordQuality _quality;
  late List<Pitch> _targetPitches;
  final List<Pitch> _placed = [];
  bool? _lastAnswer;
  bool _wide = false;

  @override
  List<Pitch> get targetPitches => _targetPitches;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'chord_builder';

  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  @override
  void prepareRound() {
    _root = _roots[_random.nextInt(_roots.length)];
    final pool = _wide
        ? ChordQuality.values
        : const [ChordQuality.major, ChordQuality.minor];
    _quality = pool[_random.nextInt(pool.length)];
    _targetPitches = Triad(Pitch(_root), _quality).pitches;
    _placed.clear();
    _lastAnswer = null;
  }

  String _tok(Pitch p) {
    final acc = switch (p.alter) { 1 => '#', -1 => 'b', _ => '' };
    return '${p.step.name}$acc${p.octave}';
  }

  String get _targetSymbol => chordSymbolFor(_targetPitches) ?? '?';

  Score get _score => _placed.isEmpty
      ? _emptyScore
      : Score.simple(notes: '${_placed.map(_tok).join('+')}:w');

  void _place(Pitch pitch) {
    if (_lastAnswer == true || _placed.length >= 3) return;
    final pc = pitch.midiNumber % 12;
    if (_placed.any((p) => p.midiNumber % 12 == pc)) return; // no duplicates
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 450);
    setState(() => _placed.add(pitch));
  }

  void _clear() {
    if (_lastAnswer == true) return;
    setState(() {
      _placed.clear();
      _lastAnswer = null;
    });
  }

  void _check() {
    if (_lastAnswer == true || _placed.length < 3) return;
    final analysis = identifyChord(_placed);
    final correct = analysis != null &&
        analysis.root.step == _root &&
        analysis.type == _typeFor[_quality];

    if (!answeredWrong || _lastAnswer == null) {
      context.read<SriService>().recordResponse(
            'chords.build.${_root.name}_${_quality.name}',
            correct,
          );
    }
    if (correct) {
      context
          .read<AudioService>()
          .playMidiChord(_placed.map((p) => p.midiNumber).toList());
    } else {
      context.read<AudioService>().playWrong();
    }
    setState(() => _lastAnswer = correct);
    resolveAnswer(correct: correct);
  }

  @override
  void debugPlace(Pitch pitch) => _place(pitch);
  @override
  void debugCheck() => _check();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameChordBuilder),
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
                      prompt: l10n.chordBuilderPrompt(_targetSymbol),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 12,
                            ),
                            child: InteractiveStaff(
                              score: _score,
                              staffSpace: 16,
                              theme: kidsScoreTheme,
                              onStaffTap: (t) =>
                                  _place(t.pitchFor(Clef.treble)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.chordBuilderHint,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _placed.isEmpty ? null : _clear,
                            icon: const Icon(Icons.backspace),
                            label: Text(l10n.chordBuilderClear),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _placed.length == 3 ? _check : null,
                            icon: const Icon(Icons.check),
                            label: Text(l10n.chordBuilderCheck),
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
