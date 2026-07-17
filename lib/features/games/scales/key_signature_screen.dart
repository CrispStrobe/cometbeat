// lib/features/games/scales/key_signature_screen.dart
//
// "Welche Tonart?" / "Key Signature Detective" — read a key signature and name
// the major key (docs/PLAN.md, original concepts). Nothing else in the app
// drills key signatures. Scoped to keys whose tonic is a natural letter
// (C G D A E B F), so the answer buttons never need an accidental and the
// German B = H convention is handled by the shared note-naming toggle.
//
// SRI: 'key_sig.<tonic>' (e.g. 'key_sig.g').

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// A major key with a natural-letter tonic.
class _MajorKey {
  const _MajorKey(this.fifths, this.tonic);

  final int fifths; // + = sharps, - = flats
  final Step tonic;
}

class KeySignatureScreen extends StatefulWidget {
  const KeySignatureScreen({super.key});

  static const _totalRounds = 10;

  // Natural-letter tonics only, ordered by accidental count.
  static const _all = [
    _MajorKey(0, Step.c),
    _MajorKey(-1, Step.f), // 1 flat
    _MajorKey(1, Step.g), // 1 sharp
    _MajorKey(2, Step.d), // 2 sharps
    _MajorKey(3, Step.a), // 3 sharps
    _MajorKey(4, Step.e), // 4 sharps
    _MajorKey(5, Step.b), // 5 sharps (German H)
  ];

  @override
  State<KeySignatureScreen> createState() => _KeySignatureScreenState();
}

/// Typed window into the game for widget tests (the state class is private).
@visibleForTesting
abstract interface class KeySignatureTester {
  int get round;
  int get score;

  /// Tonic step of the current key (its letter is the right answer).
  Step get correctTonic;
}

class _KeySignatureScreenState extends State<KeySignatureScreen>
    with QuizRoundMixin
    implements KeySignatureTester {
  final _random = Random();

  late _MajorKey _target;
  late List<_MajorKey> _options;
  Step? _tapped;

  @override
  Step get correctTonic => _target.tonic;

  @override
  int get totalRounds => KeySignatureScreen._totalRounds;

  @override
  String get gameType => 'key_sig';

  // The tonic triad is the reward on a correct answer.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Beginners: C, F, G, D (0–2 accidentals). Two stars adds A, E, B.
    final wide = context.read<ProgressService>().starsFor('key_sig') >= 2;
    final pool = wide
        ? [...KeySignatureScreen._all]
        : KeySignatureScreen._all.where((k) => k.fifths.abs() <= 2).toList();

    _target = pool[_random.nextInt(pool.length)];
    final distractors = pool.where((k) => k.tonic != _target.tonic).toList()
      ..shuffle(_random);
    _options = [_target, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
  }

  String get _sriId => 'key_sig.${_target.tonic.name}';

  List<int> get _tonicTriad {
    final root = Pitch(_target.tonic).midiNumber;
    return [root, root + 4, root + 7];
  }

  void _onAnswer(_MajorKey choice) {
    if (_tapped == _target.tonic) return; // round already solved
    final correct = choice.tonic == _target.tonic;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
    }
    if (correct) {
      context.read<AudioService>().playMidiChord(_tonicTriad);
    } else {
      context.read<AudioService>().playWrong();
    }

    setState(() => _tapped = choice.tonic);
    resolveAnswer(correct: correct);
  }

  NoteMascotMood get _mascotMood => _tapped == null
      ? NoteMascotMood.idle
      : _tapped == _target.tonic
          ? NoteMascotMood.happy
          : NoteMascotMood.oops;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameKeySignature),
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
                      correct:
                          _tapped == null ? null : _tapped == _target.tonic,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.keySignaturePrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: StaffView(
                                  score: Score.simple(
                                    keySignature: KeySignature(_target.fifths),
                                    notes: 'r:w',
                                  ),
                                  staffSpace: 15,
                                  theme: kidsScoreTheme,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: NoteMascot(mood: _mascotMood, size: 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(
                      correct:
                          _tapped == null ? null : _tapped == _target.tonic,
                    ),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _buttonColor(option.tonic),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(
                              l10n.keyMajorLabel(
                                noteNameFor(context, option.tonic),
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

  Color? _buttonColor(Step tonic) {
    if (_tapped == null) return null;
    if (tonic == _target.tonic && _tapped == _target.tonic) {
      return Colors.green;
    }
    if (tonic == _tapped && tonic != _target.tonic) return Colors.redAccent;
    return null;
  }
}
