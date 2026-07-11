// lib/features/games/harmony/function_ear_screen.dart
//
// "Funktion hören" — functional ear training and the audio grow-up of the
// Function Quiz. A I–IV–V–I cadence establishes the key by ear (no staff),
// then a target chord is played; the child names its function: Tonika,
// Subdominante or Dominante. Big replay button re-plays the whole context;
// a smaller button repeats just the target chord.
//
// SRI: 'harmony.hear.<tonic>_<function>' — a distinct namespace from the
// notation-based 'harmony.function.*', so the two drill (and re-drill via
// the weak-spot engine) independently.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step, Key;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class FunctionEarScreen extends StatefulWidget {
  /// Review mode: full SRI item IDs (`harmony.hear.<tonic>_<function>`).
  final List<String>? reviewItemIds;

  const FunctionEarScreen({super.key, this.reviewItemIds});

  @override
  State<FunctionEarScreen> createState() => _FunctionEarScreenState();
}

class _FunctionEarScreenState extends State<FunctionEarScreen>
    with QuizRoundMixin {
  final _random = Random();

  // Beginner keys; the audio never shows a signature, so no octave concerns
  // beyond a comfortable register (tonic anchored at octave 4).
  static const _tonics = [Step.c, Step.g, Step.f];

  List<(Step, HarmonicFunction)>? _reviewItems;
  bool get _isReview => _reviewItems != null;

  late Step _tonic;
  late Key _key;
  late HarmonicFunction _function;
  HarmonicFunction? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => _reviewItems?.length ?? 10;

  @override
  bool get isReviewSession => _isReview;

  @override
  String get gameType => 'function_ear';

  @override
  void initState() {
    super.initState();
    final parsed = widget.reviewItemIds
        ?.map((id) {
          final parts = id.split('.').last.split('_');
          if (parts.length != 2) return null;
          final tonic = Step.values.asNameMap()[parts[0]];
          final function = HarmonicFunction.values.asNameMap()[parts[1]];
          return (tonic == null || function == null) ? null : (tonic, function);
        })
        .whereType<(Step, HarmonicFunction)>()
        .toList();
    _reviewItems = (parsed == null || parsed.isEmpty) ? null : parsed;
    prepareRound();
    // Play the first round once the tree is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _playContext());
  }

  @override
  void prepareRound() {
    if (_isReview) {
      final (tonic, function) = _reviewItems![round];
      _tonic = tonic;
      _function = function;
    } else {
      _tonic = _tonics[_random.nextInt(_tonics.length)];
      _function = HarmonicFunction
          .values[_random.nextInt(HarmonicFunction.values.length)];
    }
    _key = Key.major(Pitch(_tonic));
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playContext();
  }

  List<int> _midis(HarmonicFunction f) =>
      _key.triadFor(f).pitches.map((p) => p.midiNumber).toList();

  /// The full context: I–IV–V–I cadence, then the target chord.
  void _playContext() {
    context.read<AudioService>().playCadenceThenTarget(
      [
        _midis(HarmonicFunction.tonic),
        _midis(HarmonicFunction.subdominant),
        _midis(HarmonicFunction.dominant),
        _midis(HarmonicFunction.tonic),
      ],
      _midis(_function),
    );
  }

  /// Just the target chord again, for a focused second listen.
  void _playTarget() {
    context.read<AudioService>().playMidiChord(_midis(_function));
  }

  String _functionLabel(AppLocalizations l10n, HarmonicFunction f) =>
      switch (f) {
        HarmonicFunction.tonic => l10n.harmonicTonic,
        HarmonicFunction.subdominant => l10n.harmonicSubdominant,
        HarmonicFunction.dominant => l10n.harmonicDominant,
      };

  void _onAnswer(HarmonicFunction choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _function;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'harmony.hear.${_tonic.name}_${_function.name}',
            correct,
          );
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
      appBar: AppBar(
        title: Text(_isReview ? l10n.reviewTitle : l10n.gameFunctionEar),
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'function_ear',
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
                      prompt: l10n.functionEarPrompt(
                        l10n.keyMajorName(noteNameFor(context, _tonic)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playContext,
                        ),
                      ),
                    ),
                    Text(
                      l10n.functionEarReplayHint,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    TextButton.icon(
                      onPressed: _playTarget,
                      icon: const Icon(Icons.music_note),
                      label: Text(l10n.functionEarTargetAgain),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        for (final option in HarmonicFunction.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : option == _function &&
                                              _tapped == _function
                                          ? Colors.green
                                          : option == _tapped
                                              ? Colors.redAccent
                                              : null,
                                ),
                                onPressed: () => _onAnswer(option),
                                child: Text(_functionLabel(l10n, option)),
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
