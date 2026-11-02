// lib/features/games/expression/articulation_ear_screen.dart
//
// "Smooth or Short?" — an ear-training game on *articulation*: a short 4-note
// phrase plays either legato (each note fills its beat, smooth and connected) or
// staccato (short pokes separated by rests, detached and bouncy), and the child
// decides which. No staff is shown; it is pure listening — the aural twin of the
// glyph-reading "Read the Mark" game. Big replay button; two answer buttons.
// No-fail loop (a wrong answer just buzzes).
//
// Both readings use the SAME notes over the SAME total time — only the note
// lengths differ (legato fills each beat; staccato is a short note + a rest), so
// the contrast is purely articulation. Synthesized with playTimedChords, whose
// empty-pitch entries render as the staccato rests.
//
// SRI: 'articulation.hear.<staccato|legato>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ArticulationEarScreen extends StatefulWidget {
  const ArticulationEarScreen({super.key});

  @override
  State<ArticulationEarScreen> createState() => _ArticulationEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ArticulationEarTester {
  /// Whether the phrase is legato (smooth — the correct answer).
  bool get answerLegato;
  bool get isFinished;
}

class _ArticulationEarScreenState extends State<ArticulationEarScreen>
    with QuizRoundMixin
    implements ArticulationEarTester {
  @override
  bool get answerLegato => _legato;
  @override
  bool get isFinished => finished;

  final _random = Random();

  // A 4-note phrase (do–re–mi–fa) on a per-beat grid. Legato: each note fills
  // its beat. Staccato: a short poke then a rest of the remainder — same notes,
  // same total time, only the length differs.
  static const _beatMs = 320;
  static const _pokeMs = 110;
  static const _steps = [0, 2, 4, 5]; // major do-re-mi-fa

  late List<int> _phrase;
  late bool _legato; // is it smooth (vs short/detached)?
  bool? _tapped; // the child's last choice (true = legato)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'articulation_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPhrase());
  }

  @override
  Duration get advanceDelay => kExplanationHold;

  @override
  void prepareRound() {
    // A comfortable mid-register root (G4..C5) so the whole phrase stays singable.
    final root = 67 + _random.nextInt(6); // 67..72
    _phrase = [for (final s in _steps) root + s];
    _legato = _random.nextBool();
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPhrase();
  }

  /// Plays the phrase: legato = each note fills its beat back-to-back; staccato =
  /// a short poke then a rest (empty pitch list) filling the rest of the beat.
  void _playPhrase() {
    final events = <(List<int>, int)>[];
    for (final note in _phrase) {
      if (_legato) {
        events.add(([note], _beatMs));
      } else {
        events.add(([note], _pokeMs));
        events.add((const <int>[], _beatMs - _pokeMs)); // the detaching rest
      }
    }
    context.read<AudioService>().playTimedChords(events);
  }

  void _onAnswer(bool legato) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = legato == _legato;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'articulation.hear.${_legato ? 'legato' : 'staccato'}',
            correct,
          );
    }

    setState(() {
      _tapped = legato;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameArticulationEar),
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
                      prompt: l10n.articulationEarPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playPhrase,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    // After an answer: what the term means (the right one, or
                    // the one tapped if wrong), with a small picture of it.
                    if (_tapped != null) ...[
                      AnswerExplanation(
                        terms: [
                          _tapped! ? MusicTerm.legato : MusicTerm.staccato,
                        ],
                        onNext: advancePending ? advanceNow : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerRow(
                      children: [
                        for (final legato in const [true, false])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : legato == _legato && _tapped == _legato
                                          ? Colors.green
                                          : legato == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  legato ? Icons.waves : Icons.more_horiz,
                                ),
                                onPressed: () => _onAnswer(legato),
                                label: Text(
                                  legato
                                      ? l10n.articulationSmoothLabel
                                      : l10n.articulationShortLabel,
                                ),
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
