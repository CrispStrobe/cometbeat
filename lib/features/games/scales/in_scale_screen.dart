// lib/features/games/scales/in_scale_screen.dart
//
// "In the Scale?" — a swipe drill for scale membership: a note sits on a card;
// swipe (or tap, or arrow-key) LEFT if it does NOT belong to the C major scale,
// RIGHT if it DOES. Naturals are in the scale; anything with a sharp is not.
// A wrong answer bounces back (the no-fail loop). Swipe-card format, like Line
// or Space?.
//
// SRI: 'scales.member.<in|out>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _whole = NoteDuration(DurationBase.whole);

class InScaleScreen extends StatefulWidget {
  const InScaleScreen({super.key});

  static const _swipeThreshold = 90.0;

  @override
  State<InScaleScreen> createState() => _InScaleScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class InScaleTester {
  /// Whether the shown note is in the C major scale (the correct answer).
  bool get answerInScale;
  bool get isFinished;
}

class _InScaleScreenState extends State<InScaleScreen>
    with QuizRoundMixin
    implements InScaleTester {
  @override
  bool get answerInScale => _inScale;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late Pitch _pitch;
  late bool _inScale; // true = diatonic (natural) in C major
  double _dragX = 0;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;
  @override
  String get gameType => 'in_scale';
  @override
  bool get playFeedbackSounds => false; // the played pitch is the feedback

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Balance in-scale (a natural) vs out-of-scale (a sharpened natural →
    // chromatic in C major). Avoid E♯/B♯, which read as F/C.
    if (_random.nextBool()) {
      final base = Clef.treble.pitchAt(_random.nextInt(9));
      _pitch = Pitch(base.step, octave: base.octave);
    } else {
      Pitch base;
      do {
        base = Clef.treble.pitchAt(_random.nextInt(9));
      } while (base.step == Step.e || base.step == Step.b);
      _pitch = Pitch(base.step, alter: 1, octave: base.octave);
    }
    _inScale = _pitch.alter == 0;
    _dragX = 0;
    _lastAnswer = null;
  }

  void _commit(bool inScale) {
    if (_lastAnswer == true) return;
    final correct = inScale == _inScale;
    final audio = context.read<AudioService>();

    if (!answeredWrong) {
      context.read<SriService>().recordResponse(
            'scales.member.${_inScale ? 'in' : 'out'}',
            correct,
          );
    }
    if (correct) {
      audio.playMidiNote(_pitch.midiNumber, ms: 500);
    } else {
      audio.playWrong();
    }
    setState(() {
      _lastAnswer = correct;
      _dragX = 0;
    });
    resolveAnswer(correct: correct);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _commit(false); // out
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _commit(true); // in
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([NoteElement.note(_pitch, _whole, id: 'n')]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = (_dragX / InScaleScreen._swipeThreshold).clamp(-1.0, 1.0);

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameInScale),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      RoundHeader(
                        correct: _lastAnswer,
                        round: round + 1,
                        totalRounds: totalRounds,
                        prompt: l10n.inScalePrompt,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          children: [
                            _SwipeLabel(
                              text: l10n.notInScaleLabel,
                              icon: Icons.close,
                              active: progress < -0.3,
                              onTap: () => _commit(false),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onHorizontalDragUpdate: (d) =>
                                    setState(() => _dragX += d.delta.dx),
                                onHorizontalDragEnd: (_) {
                                  if (_dragX <=
                                      -InScaleScreen._swipeThreshold) {
                                    _commit(false);
                                  } else if (_dragX >=
                                      InScaleScreen._swipeThreshold) {
                                    _commit(true);
                                  } else {
                                    setState(() => _dragX = 0);
                                  }
                                },
                                child: Transform.translate(
                                  offset: Offset(_dragX, 0),
                                  child: Transform.rotate(
                                    angle: progress * 0.12,
                                    child: Card(
                                      elevation: 4,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
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
                                ),
                              ),
                            ),
                            _SwipeLabel(
                              text: l10n.inScaleLabel,
                              icon: Icons.check,
                              active: progress > 0.3,
                              onTap: () => _commit(true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FeedbackLine(correct: _lastAnswer),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// A tappable target; swipe the card toward it, tap it, or use the arrow keys.
class _SwipeLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _SwipeLabel({
    required this.text,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color:
              active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? scheme.primary : scheme.outlineVariant,
            width: active ? 2.5 : 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: active ? 34 : 28),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
