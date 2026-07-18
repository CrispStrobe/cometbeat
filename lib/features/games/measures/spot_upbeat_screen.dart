// lib/features/games/measures/spot_upbeat_screen.dart
//
// "Spot the Upbeat" (Auftakt) — a reading drill on where a tune begins. Some
// melodies start on the downbeat (a full first measure), others start with a
// pickup / anacrusis (an incomplete first measure — a few notes BEFORE the first
// barline). The child reads the opening and decides: upbeat, or on the beat?
// Big staff card, two tap buttons, no-fail loop.
//
// At 2★ the note-counting shortcut is defeated: a downbeat bar can use mixed
// rhythms (half + two quarters → only three notes but still a full bar) and the
// pickup can be one OR two notes, so the answer needs real metric reading.
//
// SRI: 'measures.upbeat.<yes|no>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/features/games/widgets/reading_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _q = NoteDuration(DurationBase.quarter);
const _h = NoteDuration(DurationBase.half);

class SpotUpbeatScreen extends StatefulWidget {
  const SpotUpbeatScreen({super.key});

  @override
  State<SpotUpbeatScreen> createState() => _SpotUpbeatScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SpotUpbeatTester {
  /// Whether the shown melody starts with an upbeat — the correct answer.
  bool get answerUpbeat;
  bool get isFinished;

  /// Structural check: the shown first measure is an incomplete pickup bar
  /// (holds less than the meter). The whole cue rides on this matching
  /// [answerUpbeat] every round.
  bool get shownFirstBarIsPickup;
}

class _SpotUpbeatScreenState extends State<SpotUpbeatScreen>
    with QuizRoundMixin
    implements SpotUpbeatTester {
  @override
  bool get answerUpbeat => _upbeat;
  @override
  bool get isFinished => finished;
  @override
  bool get shownFirstBarIsPickup {
    final first = _cardScore.measures.first;
    return first.pickup &&
        first.totalDuration < TimeSignature.fourFour.toFraction();
  }

  final _random = Random();
  final _pb = ScorePlayback();

  late bool _upbeat; // does the melody start with a pickup?
  late Score _cardScore; // the melody shown this round
  late List<int> _midi; // its pitches, for the correct-answer playback
  bool? _tapped; // last choice (true = upbeat)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'spot_upbeat';

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  // A correct answer plays the melody (so the lilt is heard); a miss buzzes.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    final hard = context.read<ProgressService>().starsFor(gameType) >= 2;
    _upbeat = _random.nextBool();
    _buildMelody(hard: hard);
    _tapped = null;
    _lastAnswer = null;
  }

  /// Builds a short two-bar phrase. A comfortable stepwise walk on the treble
  /// staff keeps every round readable; the ONLY structural difference between an
  /// upbeat and an on-the-beat phrase is the incomplete first (pickup) measure.
  void _buildMelody({required bool hard}) {
    var pos = 3 + _random.nextInt(4); // 3..6, mid-staff
    final midi = <int>[];
    var idc = 0; // ids in play order (n0, n1, …) so playback can light them
    Pitch next() {
      final step = const [-2, -1, 1, 2][_random.nextInt(4)];
      pos = (pos + step).clamp(1, 7);
      final p = Clef.treble.pitchAt(pos);
      midi.add(p.midiNumber);
      return p;
    }

    NoteElement note(NoteDuration d) =>
        NoteElement.note(next(), d, id: 'n${idc++}');

    List<NoteElement> quarters(int n) => [for (var i = 0; i < n; i++) note(_q)];

    // A full 4/4 bar: four quarters, or (hard) a mixed rhythm that still fills
    // the bar but shows fewer noteheads — so counting notes can't win.
    Measure fullBar() => hard && _random.nextBool()
        ? Measure([note(_h), note(_q), note(_q)])
        : Measure(quarters(4));

    final measures = <Measure>[];
    if (_upbeat) {
      // Pickup of one (or, at 2★, up to two) quarters, then bars that complete
      // the phrase — a proper anacrusis (the pickup is borrowed from the last
      // bar, so the total is two whole 4/4 bars).
      final pickup = hard ? 1 + _random.nextInt(2) : 1;
      measures.add(Measure(quarters(pickup), pickup: true));
      measures.add(fullBar());
      measures.add(Measure(quarters(4 - pickup)));
    } else {
      // On the beat: two complete bars, a full downbeat first measure.
      measures.add(fullBar());
      measures.add(fullBar());
    }

    _midi = midi;
    _cardScore = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: measures,
    );
  }

  void _onAnswer(bool upbeat) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = upbeat == _upbeat;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'measures.upbeat.${_upbeat ? 'yes' : 'no'}',
            correct,
          );
    }
    if (correct) {
      audio.playPhrase(_midi, noteMs: 360);
      // Light each note as it sounds (ids n0, n1, … in play order).
      _pb.play([
        for (var i = 0; i < _midi.length; i++) (ids: {'n$i'}, ms: 360),
      ]);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = upbeat;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameSpotUpbeat),
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
                      prompt: l10n.spotUpbeatPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: ReadingStaffView(
                              score: _cardScore,
                              staffSpace: 13,
                              playback: _pb,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final upbeat in const [true, false])
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
                                      : upbeat == _upbeat && _tapped == _upbeat
                                          ? Colors.green
                                          : upbeat == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  upbeat
                                      ? Icons.call_made
                                      : Icons.vertical_align_bottom,
                                ),
                                onPressed: () => _onAnswer(upbeat),
                                label: Text(
                                  upbeat
                                      ? l10n.spotUpbeatUpbeat
                                      : l10n.spotUpbeatOnBeat,
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
