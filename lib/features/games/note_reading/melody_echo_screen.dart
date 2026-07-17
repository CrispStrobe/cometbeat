// lib/features/games/note_reading/melody_echo_screen.dart
//
// "Melodie-Echo" — a four-note melody plays; three melody cards are shown
// as notation and the child picks the one they heard. Connects the ear to
// the staff: the wrong cards differ in one or two notes, so careful
// listening AND careful reading are both required.
//
// SRI: 'note_reading.melody.len4'.

import 'dart:async';
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
import 'package:provider/provider.dart';

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

  static const _noteMs = 450;
  // Tracks the current playback so the next melody never cuts it off.
  final Stopwatch _playbackClock = Stopwatch();
  int _lastPlayedNotes = MelodyEchoScreen.melodyLength;
  Timer? _nextMelodyTimer;

  // Karaoke highlight while a card previews: which card, and which note in it.
  int? _playCard;
  int _playIndex = -1;
  int _previewToken = 0;

  @override
  void dispose() {
    _nextMelodyTimer?.cancel();
    _previewToken++; // stop any running preview loop
    super.dispose();
  }

  /// Play card [i]'s melody and light its notes left-to-right in time, so the
  /// ear connects to the notation. Scheduled against an absolute clock so the
  /// highlight can't drift behind the audio.
  Future<void> _previewCard(int i) async {
    final token = ++_previewToken;
    _playPositions(_cards[i]);
    final clock = Stopwatch()..start();
    for (var k = 0; k < _cards[i].length; k++) {
      final wait = k * _noteMs - clock.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      if (!mounted || token != _previewToken) return;
      setState(() {
        _playCard = i;
        _playIndex = k;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: _noteMs));
    if (!mounted || token != _previewToken) return;
    setState(() {
      _playCard = null;
      _playIndex = -1;
    });
  }

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
      variant[i] = (variant[i] + (_random.nextBool() ? 2 : -2)).clamp(0, 8);
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
    _previewToken++; // cancel any in-flight highlight
    _playCard = null;
    _playIndex = -1;
    if (round > 0) _playMelodyAfterCurrent();
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _playMelody() => _playPositions(_melody);

  void _playPositions(List<int> positions) {
    _playbackClock
      ..reset()
      ..start();
    _lastPlayedNotes = positions.length;
    context.read<AudioService>().playSequence([
      for (final position in positions)
        (Clef.treble.pitchAt(position).midiNumber, _noteMs),
    ]);
  }

  int get _playbackRemainingMs =>
      (_lastPlayedNotes * _noteMs) - _playbackClock.elapsedMilliseconds;

  /// Plays the round's melody, but waits for any in-flight playback to finish
  /// so one round's melody never cuts off the previous one.
  void _playMelodyAfterCurrent() {
    _nextMelodyTimer?.cancel();
    final remaining = _playbackRemainingMs;
    if (remaining <= 0) {
      _playMelody();
    } else {
      _nextMelodyTimer = Timer(Duration(milliseconds: remaining), () {
        if (mounted) _playMelody();
      });
    }
  }

  Score _cardScore(List<int> positions) => Score.simple(
        notes: positions.map((p) {
          final pitch = Clef.treble.pitchAt(p);
          return '${pitch.step.name}${pitch.octave}';
        }).join(' '),
      );

  void _onCardTap(int index) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = index == _correctCard;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('note_reading.melody.len4', correct);
    }

    if (correct) {
      // Don't replay on correct: the next round's melody would cut it off.
      // The child just heard it — advance cleanly instead.
    } else {
      // Hear what the tapped card actually sounds like — and see its notes
      // light up — that's the lesson.
      unawaited(_previewCard(index));
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
      appBar: GameAppBar(
        title: l10n.gameMelodyEcho,
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
                      correct: _lastAnswer,
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
                                  vertical: 4,
                                ),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: _tapped == null
                                        ? BorderSide.none
                                        : i == _correctCard &&
                                                _tapped == _correctCard
                                            ? const BorderSide(
                                                color: Colors.green,
                                                width: 3,
                                              )
                                            : i == _tapped
                                                ? const BorderSide(
                                                    color: Colors.redAccent,
                                                    width: 3,
                                                  )
                                                : BorderSide.none,
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Positioned.fill(
                                        child: InkWell(
                                          onTap: () => _onCardTap(i),
                                          child: Center(
                                            child: StaffView(
                                              score: _cardScore(_cards[i]),
                                              staffSpace: 8,
                                              theme: kidsScoreTheme,
                                              highlightedIds: _playCard == i &&
                                                      _playIndex >= 0
                                                  ? {'e$_playIndex'}
                                                  : const {},
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Hear this melody and watch its notes
                                      // light up left-to-right.
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: IconButton(
                                          icon: const Icon(Icons.volume_up),
                                          iconSize: 20,
                                          tooltip: l10n.listenAgain,
                                          onPressed: () =>
                                              unawaited(_previewCard(i)),
                                        ),
                                      ),
                                    ],
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
