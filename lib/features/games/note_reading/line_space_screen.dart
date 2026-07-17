// lib/features/games/note_reading/line_space_screen.dart
//
// "Linie oder Zwischenraum?" — a swipe drill for the most basic reading skill:
// a note sits on a card; swipe LEFT if it's on a line, RIGHT if it's in a
// space. A wrong swipe bounces the card back to try again (the app's no-fail
// loop). The first swipe-card format in the app (see docs/PLAN.md).
//
// SRI: 'note_reading.line_space.<line|space>'.

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

class LineSpaceScreen extends StatefulWidget {
  const LineSpaceScreen({super.key, this.clef = Clef.treble});

  final Clef clef;

  static const _swipeThreshold = 90.0;

  @override
  State<LineSpaceScreen> createState() => _LineSpaceScreenState();
}

class _LineSpaceScreenState extends State<LineSpaceScreen> with QuizRoundMixin {
  final _random = Random();

  late Pitch _pitch;
  late bool _isLine;
  double _dragX = 0;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'line_space';

  @override
  String get progressId =>
      widget.clef == Clef.bass ? 'line_space_bass' : 'line_space';

  // The plucked pitch is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // On-staff positions 0..8: even = line, odd = space.
    final position = _random.nextInt(9);
    _pitch = widget.clef.pitchAt(position);
    _isLine = position.isEven;
    _dragX = 0;
    _lastAnswer = null;
  }

  void _commit(bool swipedLeft) {
    if (_lastAnswer == true) return;
    final choseLine = swipedLeft;
    final correct = choseLine == _isLine;
    final audio = context.read<AudioService>();

    if (!answeredWrong) {
      context.read<SriService>().recordResponse(
            'note_reading.line_space.${widget.clef.name}.'
            '${_isLine ? 'line' : 'space'}',
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
      _dragX = 0; // snap back; a correct answer advances via the mixin
    });
    resolveAnswer(correct: correct);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _commit(true); // line
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _commit(false); // space
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress =
        (_dragX / LineSpaceScreen._swipeThreshold).clamp(-1.0, 1.0);

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameLineSpace),
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
                        prompt: l10n.lineSpacePrompt,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          children: [
                            _SwipeLabel(
                              text: l10n.lineLabel,
                              icon: Icons.remove,
                              active: progress < -0.3,
                              onTap: () => _commit(true),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onHorizontalDragUpdate: (d) =>
                                    setState(() => _dragX += d.delta.dx),
                                onHorizontalDragEnd: (_) {
                                  if (_dragX <=
                                      -LineSpaceScreen._swipeThreshold) {
                                    _commit(true);
                                  } else if (_dragX >=
                                      LineSpaceScreen._swipeThreshold) {
                                    _commit(false);
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
                                            score: Score.simple(
                                              clef: widget.clef,
                                              notes:
                                                  '${_pitch.step.name}${_pitch.octave}:w',
                                            ),
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
                              text: l10n.spaceLabel,
                              icon: Icons.crop_square,
                              active: progress > 0.3,
                              onTap: () => _commit(false),
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

/// A tappable Line/Space target. You can swipe the card toward it or just tap
/// it (or use the arrow keys) — the swipe alone was too obscure.
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
        width: 72,
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
