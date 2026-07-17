// lib/features/games/note_reading/articulation_read_screen.dart
//
// "Read the Mark" — an articulation-reading drill. A single note carries one
// articulation glyph (staccato dot, tenuto dash, accent wedge, marcato wedge),
// drawn by crisp_notation, and the child matches the glyph to its NAME. This
// fills a gap: ties/slurs and note values are covered, but the note-attached
// articulation marks — the vocabulary of HOW a note is played — weren't.
// Binary at 1★ (Staccato vs Accent — the most distinct); the full four-way
// (adding Tenuto and Marcato) from 2★. Big staff card, tap buttons, no-fail.
//
// SRI: 'reading.articulation.<staccato|tenuto|accent|marcato>'.

import 'dart:math';

import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:provider/provider.dart';

const _quarter = NoteDuration(DurationBase.quarter);

/// The four note-attached articulation marks this game reads. The binary tier
/// uses just staccato vs accent (a dot vs a wedge — the clearest contrast); the
/// four-way tier adds the held (tenuto) and strongly-accented (marcato) marks.
const _binary = [Articulation.staccato, Articulation.accent];
const _allMarks = [
  Articulation.staccato,
  Articulation.tenuto,
  Articulation.accent,
  Articulation.marcato,
];

class ArticulationReadScreen extends StatefulWidget {
  const ArticulationReadScreen({super.key});

  @override
  State<ArticulationReadScreen> createState() => _ArticulationReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ArticulationReadTester {
  /// The correct articulation this round.
  Articulation get answer;
  bool get isFinished;
}

class _ArticulationReadScreenState extends State<ArticulationReadScreen>
    with QuizRoundMixin
    implements ArticulationReadTester {
  @override
  Articulation get answer => _mark;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late Articulation _mark; // the correct mark this round
  late Pitch _pitch; // the note it sits on
  bool _fourWay = false; // 2★+: all four marks
  Articulation? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'articulation_read';

  // A correct answer sounds the note (short for staccato); a miss buzzes.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _fourWay = context.read<ProgressService>().starsFor(progressId) >= 2;
    final choices = _fourWay ? _allMarks : _binary;
    _mark = choices[_random.nextInt(choices.length)];
    // A comfortable pitch on the treble staff (positions 1..7).
    _pitch = Clef.treble.pitchAt(1 + _random.nextInt(7));
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(Articulation choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _mark;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.articulation.${_mark.name}',
            correct,
          );
    }
    if (correct) {
      // A short poke for staccato, a fuller tone otherwise — a small aural cue.
      audio.playPhrase(
        [_pitch.midiNumber],
        noteMs: _mark == Articulation.staccato ? 150 : 500,
      );
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  static IconData _iconFor(Articulation a) => switch (a) {
        Articulation.staccato => Icons.fiber_manual_record, // a dot
        Articulation.tenuto => Icons.remove, // a dash
        Articulation.accent => Icons.navigate_next, // a wedge ">"
        Articulation.marcato => Icons.expand_less, // a wedge "^"
        _ => Icons.music_note,
      };

  static String _labelFor(AppLocalizations l, Articulation a) => switch (a) {
        Articulation.staccato => l.articulationStaccato,
        Articulation.tenuto => l.articulationTenuto,
        Articulation.accent => l.articulationAccent,
        Articulation.marcato => l.articulationMarcato,
        _ => a.name,
      };

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(_pitch, _quarter, articulations: {_mark}, id: 'n'),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final choices = _fourWay ? _allMarks : _binary;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameArticulation),
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
                      prompt: l10n.articulationPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: StaffView(
                              score: _cardScore,
                              staffSpace: 14,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final a in choices)
                          SizedBox(
                            width: choices.length > 2 ? 150 : 160,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                backgroundColor: _tapped == null
                                    ? null
                                    : a == _mark && _tapped == _mark
                                        ? Colors.green
                                        : a == _tapped
                                            ? Colors.redAccent
                                            : null,
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              icon: Icon(_iconFor(a)),
                              onPressed: () => _onAnswer(a),
                              label: Text(_labelFor(l10n, a)),
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
