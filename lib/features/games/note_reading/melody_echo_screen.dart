// lib/features/games/note_reading/melody_echo_screen.dart
//
// "Melodie-Echo" — a four-note melody plays; three melody cards are shown
// as notation and the child picks the one they heard. Connects the ear to
// the staff: the wrong cards differ in one or two notes, so careful
// listening AND careful reading are both required.
//
// SRI: 'note_reading.melody.len4'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/game_widgets.dart';

class MelodyEchoScreen extends StatefulWidget {
  const MelodyEchoScreen({super.key});

  static const melodyLength = 4;

  @override
  State<MelodyEchoScreen> createState() => _MelodyEchoScreenState();
}

class _MelodyEchoScreenState extends State<MelodyEchoScreen>
    with QuizRoundMixin {
  final _random = Random();

  late List<int> _melody; // staff positions
  late List<List<int>> _cards; // 3 candidate melodies, shuffled
  late int _correctCard;
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'melody_echo';

  // The melodies themselves are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMelody());
  }

  List<int> _randomMelody() {
    // Stepwise-leaning walk over the staff (positions 1..7).
    var position = 2 + _random.nextInt(4);
    final melody = <int>[position];
    while (melody.length < MelodyEchoScreen.melodyLength) {
      final step = [-2, -1, -1, 1, 1, 2][_random.nextInt(6)];
      position = (position + step).clamp(1, 7);
      melody.add(position);
    }
    return melody;
  }

  /// A decoy: the melody with one or two notes nudged to a neighbor.
  List<int> _variantOf(List<int> melody) {
    final variant = [...melody];
    final changes = 1 + _random.nextInt(2);
    for (var c = 0; c < changes; c++) {
      final i = 1 + _random.nextInt(variant.length - 1); // keep the start
      variant[i] =
          (variant[i] + (_random.nextBool() ? 2 : -2)).clamp(0, 8);
    }
    return variant;
  }

  @override
  void prepareRound() {
    _melody = _randomMelody();
    List<int> decoy1;
    List<int> decoy2;
    do {
      decoy1 = _variantOf(_melody);
    } while (_listEq(decoy1, _melody));
    do {
      decoy2 = _variantOf(_melody);
    } while (_listEq(decoy2, _melody) || _listEq(decoy2, decoy1));

    _cards = [_melody, decoy1, decoy2]..shuffle(_random);
    _correctCard = _cards.indexWhere((c) => _listEq(c, _melody));
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playMelody();
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _playMelody() {
    context.read<AudioService>().playSequence([
      for (final position in _melody)
        (Clef.treble.pitchAt(position).midiNumber, 450),
    ]);
  }

  Score _cardScore(List<int> positions) => Score.simple(
        notes: positions
            .map((p) {
              final pitch = Clef.treble.pitchAt(p);
              return '${pitch.step.name}${pitch.octave}';
            })
            .join(' '),
      );

  void _onCardTap(int index) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = index == _correctCard;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('note_reading.melody.len4', correct);
    }

    final audio = context.read<AudioService>();
    if (correct) {
      _playMelody(); // hear it again while seeing the right card
    } else {
      // Hear what the tapped card actually sounds like — that's the lesson.
      audio.playSequence([
        for (final position in _cards[index])
          (Clef.treble.pitchAt(position).midiNumber, 450),
      ]);
    }

    setState(() {
      _tapped = index;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gameMelodyEcho),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playMelody,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'melody_echo',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.melodyEchoPrompt,
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = 0; i < _cards.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    side: _tapped == null
                                        ? BorderSide.none
                                        : i == _correctCard &&
                                                _tapped == _correctCard
                                            ? const BorderSide(
                                                color: Colors.green,
                                                width: 3)
                                            : i == _tapped
                                                ? const BorderSide(
                                                    color:
                                                        Colors.redAccent,
                                                    width: 3)
                                                : BorderSide.none,
                                  ),
                                  child: InkWell(
                                    onTap: () => _onCardTap(i),
                                    child: Center(
                                      child: StaffView(
                                        score: _cardScore(_cards[i]),
                                        staffSpace: 8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
