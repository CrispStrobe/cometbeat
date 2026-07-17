// "Key Change?" — the modulation ear game (closes the Grades 7-8 modulation
// gap). A short melodic phrase plays: it EITHER stays in one key the whole way,
// OR modulates partway through — its second half shifted up a perfect 4th or 5th
// so the tonal centre audibly moves to a new home note. The child decides "Same
// key" vs "Key changed". No staff — pure listening, with a big replay button.
//
// Build: a phrase is two scale fragments. For "same", both halves are drawn from
// the same major key (each ends on that key's tonic). For "changed", the first
// half establishes the home key, then the second half is transposed up a 4th (5
// semitones) or 5th (7 semitones) so it lands on — and cadences to — a new tonic.
//
// SRI: 'scales.modulation.<same|changed>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ModulationEarScreen extends StatefulWidget {
  const ModulationEarScreen({super.key});

  @override
  State<ModulationEarScreen> createState() => _ModulationEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ModulationEarTester {
  /// Whether the phrase modulates (the correct answer is "Key changed").
  bool get answerChanged;
  bool get isFinished;
}

class _ModulationEarScreenState extends State<ModulationEarScreen>
    with QuizRoundMixin
    implements ModulationEarTester {
  final _random = Random();

  // C major degrees, one octave from the tonic (C4). A phrase's halves are
  // fragments of this ladder, so every half "makes sense" in its own key.
  static const _major = [60, 62, 64, 65, 67, 69, 71, 72];

  // A rising-then-cadencing fragment: up the first few degrees, then home to the
  // tonic — a clear little tonal statement, so the ear can lock onto a key.
  static const _fragment = [0, 2, 4, 2, 0]; // scale-degree indices → tonic-end

  late List<int> _phrase; // the full melody (midi)
  late bool _changed; // does it modulate?
  bool? _tapped; // the child's last choice (true = key changed)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'modulation_ear';

  // Our own feedback: replay the phrase on a correct answer, buzz on a wrong one.
  @override
  bool get playFeedbackSounds => false;

  @override
  bool get answerChanged => _changed;

  @override
  bool get isFinished => finished;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPhrase());
  }

  /// The five-note fragment of C major, transposed by [shift] semitones.
  List<int> _half(int shift) => [for (final d in _fragment) _major[d] + shift];

  @override
  void prepareRound() {
    _changed = _random.nextBool();
    final firstHalf = _half(0); // establish C major
    // For "changed", move the second half to the dominant (up a 5th) or
    // subdominant (up a 4th) — a real key shift the ear can follow home.
    final shift = _changed ? (_random.nextBool() ? 7 : 5) : 0;
    _phrase = [...firstHalf, ..._half(shift)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPhrase();
  }

  void _playPhrase() {
    context.read<AudioService>().playPhrase(_phrase, noteMs: 360);
  }

  void _onAnswer(bool changed) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = changed == _changed;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'scales.modulation.${_changed ? 'changed' : 'same'}',
            correct,
          );
    }
    // Correct → replay the phrase so the shift (or lack of it) is reinforced;
    // wrong → the retro buzz.
    if (correct) {
      _playPhrase();
    } else {
      context.read<AudioService>().playWrong();
    }
    setState(() {
      _tapped = changed;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l10n.gameModulation),
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
                      prompt: l10n.modulationPrompt,
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
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final changed in const [false, true])
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
                                      : changed == _changed &&
                                              _tapped == _changed
                                          ? Colors.green
                                          : changed == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  changed
                                      ? Icons.moving
                                      : Icons.horizontal_rule,
                                ),
                                onPressed: () => _onAnswer(changed),
                                label: Text(
                                  changed
                                      ? l10n.modulationChanged
                                      : l10n.modulationSame,
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
