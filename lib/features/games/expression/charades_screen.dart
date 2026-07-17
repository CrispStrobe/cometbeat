// lib/features/games/expression/charades_screen.dart
//
// "Dynamics & Tempo Charades" — an ear game for expressive vocabulary the app
// doesn't otherwise touch (docs/PLAN.md original concepts). A short phrase plays
// either at one of four tempi (Adagio→Presto) or one of four dynamic levels
// (pp→ff); the child names what they heard. Big replay button; keyboard 1–4.
//
// Star-gated: the two clear extremes for beginners, all four terms at 2★+.
// SRI: 'expression.hear.tempo.<term>' / 'expression.hear.dynamics.<term>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// What a round asks about.
enum _Kind { tempo, dynamics }

/// A tempo term with its per-note duration (ms).
enum _Tempo {
  adagio(800, 'Adagio'),
  andante(520, 'Andante'),
  allegro(330, 'Allegro'),
  presto(200, 'Presto');

  const _Tempo(this.noteMs, this.label);
  final int noteMs;
  final String label;
}

/// A dynamic term with its playback gain (0..1) and notation symbol.
enum _Dyn {
  pp(0.12, 'pp'),
  p(0.35, 'p'),
  f(0.7, 'f'),
  ff(1.0, 'ff');

  const _Dyn(this.gain, this.label);
  final double gain;
  final String label;
}

class CharadesScreen extends StatefulWidget {
  const CharadesScreen({super.key});

  @override
  State<CharadesScreen> createState() => _CharadesScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class CharadesTester {
  /// The button label of the current round's correct answer.
  String get answerLabel;
  bool get isFinished;
}

class _CharadesScreenState extends State<CharadesScreen>
    with QuizRoundMixin
    implements CharadesTester {
  @override
  String get answerLabel => _label(_answer);
  @override
  bool get isFinished => finished;

  // A neutral little rising arpeggio, so tempo/dynamics is the only variable.
  static const _phrase = [60, 64, 67, 72];

  final _random = Random();

  late _Kind _kind;
  late List<Object> _options; // _Tempo or _Dyn values
  late Object _answer;
  Object? _tapped;
  bool? _lastAnswer;
  bool _wide = false;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'charades';

  // We play the phrase ourselves; the tap feedback blips are fine on top.
  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPhrase());
  }

  @override
  void prepareRound() {
    _kind = _random.nextBool() ? _Kind.tempo : _Kind.dynamics;
    if (_kind == _Kind.tempo) {
      _options = _wide
          ? _Tempo.values.toList()
          : [_Tempo.adagio, _Tempo.presto]; // clear slow vs fast
    } else {
      _options =
          _wide ? _Dyn.values.toList() : [_Dyn.p, _Dyn.f]; // clear soft vs loud
    }
    _answer = _options[_random.nextInt(_options.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playPhrase();
  }

  void _playPhrase() {
    final audio = context.read<AudioService>();
    if (_answer is _Tempo) {
      audio.playPhrase(_phrase, noteMs: (_answer as _Tempo).noteMs, gain: 0.8);
    } else {
      audio.playPhrase(_phrase, noteMs: 360, gain: (_answer as _Dyn).gain);
    }
  }

  String _sriId() {
    final term =
        _answer is _Tempo ? (_answer as _Tempo).name : (_answer as _Dyn).name;
    return 'expression.hear.${_kind.name}.$term';
  }

  void _onAnswer(Object choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _answer;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId(), correct);
    }
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  String _label(Object o) => o is _Tempo ? o.label : (o as _Dyn).label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameCharades),
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
                      prompt: _kind == _Kind.tempo
                          ? l10n.charadesTempoPrompt
                          : l10n.charadesDynamicsPrompt,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 88,
                          padding: const EdgeInsets.all(30),
                          icon: Icon(
                            _kind == _Kind.tempo
                                ? Icons.speed
                                : Icons.graphic_eq,
                          ),
                          tooltip: l10n.listenAgain,
                          onPressed: _playPhrase,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
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
                                  : option == _answer
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
                            child: Text(_label(option)),
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
