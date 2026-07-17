// lib/features/games/note_values/rhythm_tap_screen.dart
//
// "Rhythmus-Echo" — a one-measure rhythm is played (and shown as notation);
// the child taps it back on a big pad. Timing is compared onset-by-onset
// relative to the first tap, so absolute start doesn't matter.
//
// SRI: 'note_values.rhythm.p<index>'.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show Score, StaffView, TimeSignature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class _Pattern {
  /// Note durations in beats (4/4, sums to 4).
  final List<double> beats;
  final String dsl; // for notation display, on a fixed pitch

  const _Pattern(this.beats, this.dsl);

  /// Relative onset times in beats (first note at 0).
  List<double> get onsets {
    final result = <double>[];
    var t = 0.0;
    for (final b in beats) {
      result.add(t);
      t += b;
    }
    return result;
  }
}

const _patterns = <_Pattern>[
  _Pattern([1, 1, 1, 1], 'g4:q g4 g4 g4'),
  _Pattern([1, 1, 2], 'g4:q g4 g4:h'),
  _Pattern([2, 1, 1], 'g4:h g4:q g4'),
  _Pattern([1, 0.5, 0.5, 1, 1], 'g4:q g4:e g4 g4:q g4'),
  _Pattern([0.5, 0.5, 1, 0.5, 0.5, 1], 'g4:e g4 g4:q g4:e g4 g4:q'),
];

class RhythmTapScreen extends StatefulWidget {
  const RhythmTapScreen({super.key});

  static const beatMs = 600; // 100 BPM
  static const toleranceMs = 170;

  @override
  State<RhythmTapScreen> createState() => _RhythmTapScreenState();
}

class _RhythmTapScreenState extends State<RhythmTapScreen> with QuizRoundMixin {
  final _random = Random();

  late int _patternIndex;
  _Pattern get _pattern => _patterns[_patternIndex];
  // Each press captures both its onset and how long the pad was held, so long
  // notes must actually be held down (not just tapped).
  final List<({int onset, int duration})> _presses = [];
  final Stopwatch _stopwatch = Stopwatch();
  int? _pressStart;
  bool _holding = false;
  bool? _lastAnswer;

  /// A long note (half or longer) must be held roughly this long to count.
  static const _longHoldMs = 780;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'rhythm_tap';

  // Taps click on their own; blips would muddle the rhythm.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPattern());
  }

  @override
  void prepareRound() {
    _patternIndex = _random.nextInt(_patterns.length);
    _presses.clear();
    _pressStart = null;
    _holding = false;
    _stopwatch
      ..stop()
      ..reset();
    _lastAnswer = null;
    if (round > 0) _playPattern();
  }

  void _playPattern() {
    context.read<AudioService>().playSequence([
      for (final b in _pattern.beats)
        (79, (b * RhythmTapScreen.beatMs).round()), // G5 taps
    ]);
  }

  void _onPressDown() {
    if (_lastAnswer != null) return; // evaluating/resolved
    if (_presses.length >= _pattern.beats.length) return;
    if (!_stopwatch.isRunning) _stopwatch.start();
    // Sound the note from the first tap, and keep it ringing while held — the
    // note is cut on release, so the child hears exactly how long they held.
    context.read<AudioService>().playMidiNote(79, ms: 2500);
    setState(() {
      _holding = true;
      _pressStart = _stopwatch.elapsedMilliseconds;
    });
  }

  void _onPressUp() {
    if (_lastAnswer != null || _pressStart == null) return;
    final duration = _stopwatch.elapsedMilliseconds - _pressStart!;
    context.read<AudioService>().stop(); // end the held note now
    setState(() {
      _presses.add((onset: _pressStart!, duration: duration));
      _pressStart = null;
      _holding = false;
    });
    if (_presses.length == _pattern.beats.length) _evaluate();
  }

  void _evaluate() {
    final expected = _pattern.onsets
        .map((b) => (b * RhythmTapScreen.beatMs).round())
        .toList();
    final t0 = _presses.first.onset;
    var correct = true;
    for (var i = 0; i < expected.length; i++) {
      final relative = _presses[i].onset - t0;
      if ((relative - expected[i]).abs() > RhythmTapScreen.toleranceMs) {
        correct = false;
        break;
      }
      // Long notes (half or more) must actually be held, not just tapped.
      if (_pattern.beats[i] >= 2 && _presses[i].duration < _longHoldMs) {
        correct = false;
        break;
      }
    }

    context
        .read<SriService>()
        .recordResponse('note_values.rhythm.p$_patternIndex', correct);
    final audio = context.read<AudioService>();
    correct ? audio.playCorrect() : audio.playWrong();

    setState(() => _lastAnswer = correct);
    if (correct) {
      resolveAnswer(correct: true);
    } else {
      // Full retry: wrong rhythm resets the presses after a beat.
      resolveAnswer(correct: false);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          _presses.clear();
          _pressStart = null;
          _holding = false;
          _stopwatch
            ..stop()
            ..reset();
          _lastAnswer = null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameRhythmTap,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playPattern,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'rhythm_tap',
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
                      prompt: l10n.rhythmTapPrompt,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: StaffView(
                          score: Score.simple(
                            timeSignature: TimeSignature.fourFour,
                            notes: _pattern.dsl,
                          ),
                          staffSpace: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pattern.beats.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              i < _presses.length
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Listener(
                          onPointerDown: (_) => _onPressDown(),
                          onPointerUp: (_) => _onPressUp(),
                          onPointerCancel: (_) => _onPressUp(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 80),
                            decoration: BoxDecoration(
                              color: _holding
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Center(
                              child: Text(
                                _holding ? l10n.rhythmTapHold : l10n.tapHere,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _holding
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                          : null,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
