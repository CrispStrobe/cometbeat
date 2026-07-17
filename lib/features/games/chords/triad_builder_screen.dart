// lib/features/games/chords/triad_builder_screen.dart
//
// "Dreiklang-Baumeister" — the root is given on the staff; the child taps
// the two missing notes of the root-position triad (third and fifth: the
// next two lines-or-spaces up). Every placed note sounds; the finished
// triad is played as a chord. The first constructive/building game.
//
// SRI: 'chords.build.<root>_major' (correct = built without a wrong tap).

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class TriadBuilderScreen extends StatefulWidget {
  const TriadBuilderScreen({super.key});

  @override
  State<TriadBuilderScreen> createState() => _TriadBuilderScreenState();
}

class _TriadBuilderScreenState extends State<TriadBuilderScreen>
    with QuizRoundMixin {
  final _random = Random();

  late Pitch _root;
  late int _rootPosition;
  final Set<int> _placedPositions = {}; // relative: 2 and 4 above the root
  int? _wrongPosition; // flashes red briefly
  bool _sriRecorded = false;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'triad_builder';

  // Placed pitches and the completed chord are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _rootPosition = _random.nextInt(5); // triad top stays on the staff
    _root = Clef.treble.pitchAt(_rootPosition);
    _placedPositions.clear();
    _wrongPosition = null;
    _sriRecorded = false;
  }

  bool get _complete => _placedPositions.length == 2;

  Score get _score {
    final pitches = [
      _root,
      for (final offset in _placedPositions)
        Clef.treble.pitchAt(_rootPosition + offset),
      if (_wrongPosition != null) Clef.treble.pitchAt(_wrongPosition!),
    ]..sort((a, b) => a.diatonicIndex.compareTo(b.diatonicIndex));

    // A single measure: only the note's *height* (pitch) matters, and a second
    // measure just made taps land far from where the note appears. A larger
    // staff space keeps the target comfortable.
    return Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: pitches,
            duration: const NoteDuration(DurationBase.whole),
            id: 'triad',
          ),
        ]),
      ],
    );
  }

  void _record(bool correct) {
    if (_sriRecorded) return;
    _sriRecorded = true;
    context
        .read<SriService>()
        .recordResponse('chords.build.${_root.step.name}_major', correct);
  }

  void _onStaffTap(StaffTarget target) {
    if (_complete) return; // round already resolved
    final offset = target.staffPosition - _rootPosition;
    final audio = context.read<AudioService>();

    if ((offset == 2 || offset == 4) && !_placedPositions.contains(offset)) {
      audio.playMidiNote(
        Clef.treble.pitchAt(target.staffPosition).midiNumber,
        ms: 500,
      );
      setState(() {
        _placedPositions.add(offset);
        _wrongPosition = null;
      });
      if (_complete) {
        _record(!answeredWrong);
        audio.playMidiChord([
          _root.midiNumber,
          Clef.treble.pitchAt(_rootPosition + 2).midiNumber,
          Clef.treble.pitchAt(_rootPosition + 4).midiNumber,
        ]);
        resolveAnswer(correct: true);
      }
    } else {
      _record(false);
      audio.playWrong();
      setState(() => _wrongPosition = target.staffPosition);
      resolveAnswer(correct: false);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _wrongPosition = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The whole chord element flashes red on a wrong tap, green when done.
    final theme = kidsScoreTheme.copyWith(
      elementColors: {
        if (_wrongPosition != null) 'triad': Colors.redAccent,
        if (_complete) 'triad': Colors.green,
      },
    );

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTriadBuilder),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'triad_builder',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _wrongPosition != null
                          ? false
                          : _complete
                              ? true
                              : null,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.triadBuilderPrompt(
                        noteNameFor(context, _root.step),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: InteractiveStaff(
                              score: _score,
                              theme: theme,
                              // Fixed scale: fit-to-width explodes on a
                              // near-empty score (clef + one chord).
                              staffSpace: 22,
                              ghostDuration:
                                  const NoteDuration(DurationBase.whole),
                              onStaffTap: _onStaffTap,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(
                      correct: _wrongPosition != null
                          ? false
                          : _complete
                              ? true
                              : null,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
