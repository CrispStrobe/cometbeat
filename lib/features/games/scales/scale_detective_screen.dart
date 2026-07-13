// lib/features/games/scales/scale_detective_screen.dart
//
// "Tonleiter-Detektiv" — a major scale is rendered with one note altered by
// a semitone (visible as an accidental against the key signature); the child
// taps the note that doesn't belong. Element tap via partitura's StaffView.
//
// SRI: 'scales.spot.<tonic>_major'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step, Key;
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class ScaleDetectiveScreen extends StatefulWidget {
  /// Review mode: full SRI item IDs (`scales.spot.<tonic>_major`).
  final List<String>? reviewItemIds;

  const ScaleDetectiveScreen({super.key, this.reviewItemIds});

  @override
  State<ScaleDetectiveScreen> createState() => _ScaleDetectiveScreenState();
}

class _ScaleDetectiveScreenState extends State<ScaleDetectiveScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Difficulty ladder (docs/PLAN.md): a few major keys → all major keys → the
  // harmonic minors, where the raised 7th is a *legitimate* accidental, so the
  // child can no longer just spot "the note with a sharp/flat".
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
  // Minor keys within a single sharp/flat once the harmonic 7th is raised.
  static const _minorTonics = [Step.a, Step.e, Step.d, Step.b, Step.g, Step.c];

  List<Step>? _reviewTonics;
  bool get _isReview => _reviewTonics != null;

  late Step _tonic;
  late ScaleType _scaleType;
  late Key _key;
  late List<Pitch> _pitches; // with the wrong one substituted
  late int _wrongIndex;
  String? _tappedId;
  bool? _lastAnswer;

  @override
  int get totalRounds => _reviewTonics?.length ?? 8;

  @override
  bool get isReviewSession => _isReview;

  @override
  String get gameType => 'scale_detective';

  @override
  void initState() {
    super.initState();
    final parsed = widget.reviewItemIds
        ?.map((id) {
          final tonic = id.split('.').last.split('_').first;
          return Step.values.asNameMap()[tonic];
        })
        .whereType<Step>()
        .toList();
    _reviewTonics = (parsed == null || parsed.isEmpty) ? null : parsed;
    prepareRound();
  }

  @override
  void prepareRound() {
    if (_isReview) {
      _tonic = _reviewTonics![round];
      _scaleType = ScaleType.major;
    } else {
      final stars = context.read<ProgressService>().starsFor('scale_detective');
      if (stars >= 3) {
        _tonic = _minorTonics[_random.nextInt(_minorTonics.length)];
        _scaleType = ScaleType.harmonicMinor;
      } else if (stars >= 2) {
        _tonic = _majorTonics[_random.nextInt(_majorTonics.length)];
        _scaleType = ScaleType.major;
      } else {
        _tonic = _baseTonics[_random.nextInt(_baseTonics.length)];
        _scaleType = ScaleType.major;
      }
    }
    final isMinor = _scaleType != ScaleType.major;
    _key = isMinor ? Key.minor(Pitch(_tonic)) : Key.major(Pitch(_tonic));
    final scale = Scale(Pitch(_tonic), _scaleType).pitches;

    _wrongIndex = 1 + _random.nextInt(scale.length - 2); // not the tonics
    final original = _pitchesOf(scale)[_wrongIndex];
    // Shift by a semitone, away from any existing alteration so we stay
    // within a single sharp/flat (B♭ in F major becomes B natural).
    final shift =
        original.alter == 0 ? (_random.nextBool() ? 1 : -1) : -original.alter;
    final wrong = Pitch(
      original.step,
      alter: original.alter + shift,
      octave: original.octave,
    );

    _pitches = [..._pitchesOf(scale)];
    _pitches[_wrongIndex] = wrong;
    _tappedId = null;
    _lastAnswer = null;
  }

  List<Pitch> _pitchesOf(List<Pitch> scale) => scale;

  String _token(Pitch p) {
    final accidental = switch (p.alter) {
      1 => '#',
      -1 => 'b',
      // Explicit natural where the key signature says otherwise.
      0 when _key.signature.alterFor(p.step) != 0 => 'n',
      _ => '',
    };
    return '${p.step.name}$accidental${p.octave}';
  }

  Score get _score => Score.simple(
        keySignature: _key.signature,
        notes: _pitches.map(_token).join(' '),
      );

  void _onElementTap(String elementId) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = elementId == 'e$_wrongIndex';

    if (_lastAnswer == null || !answeredWrong) {
      final mode = _scaleType == ScaleType.major ? 'major' : 'minor';
      context
          .read<SriService>()
          .recordResponse('scales.spot.${_tonic.name}_$mode', correct);
    }

    setState(() {
      _tappedId = elementId;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = kidsScoreTheme.copyWith(
      elementColors: {
        if (_tappedId != null)
          _tappedId!: _lastAnswer! ? Colors.green : Colors.redAccent,
      },
    );

    return Scaffold(
      appBar: GameAppBar(
        title: _isReview ? l10n.reviewTitle : l10n.gameScaleDetective,
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'scale_detective',
                score: score,
                onRestart: _isReview ? null : restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: _scaleType == ScaleType.major
                          ? l10n.scaleDetectivePrompt(
                              noteNameFor(context, _tonic),
                            )
                          : l10n.scaleDetectivePromptMinor(
                              noteNameFor(context, _tonic),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: StaffView(
                              score: _score,
                              theme: theme,
                              onElementTap: _onElementTap,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                  ],
                ),
              ),
      ),
    );
  }
}
