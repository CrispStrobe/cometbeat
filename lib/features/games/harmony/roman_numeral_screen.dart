// lib/features/games/harmony/roman_numeral_screen.dart
//
// "Roman Numerals" (Stufen-Quiz) — read/hear a diatonic triad in a key and name
// its Roman numeral (I, ii, iii, IV, V, vi, vii°). Built on partitura_core's
// new harmonic analysis: the chord is built with `Triad`, then read back with
// `romanNumeralOf(pitches, key)` so the *library* names the numeral — the same
// engine will later carry sevenths, inversions and minor keys.
//
// A step up from the Function Quiz (which only names T/S/D): here every diatonic
// degree is in play. SRI: 'harmony.roman.<symbol>'.

import 'dart:math';

// Material also exports `Step` (Stepper), `Key` (widget key) and `Interval`
// (animation); partitura's win here.
import 'package:flutter/material.dart' hide Interval, Key, Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class RomanNumeralScreen extends StatefulWidget {
  const RomanNumeralScreen({super.key});

  @override
  State<RomanNumeralScreen> createState() => _RomanNumeralScreenState();
}

/// Test handle onto the running game (the state class is private, and the
/// correct answer varies per round).
@visibleForTesting
abstract interface class RomanNumeralTester {
  String get targetSymbol;
  bool get isFinished;
}

class _RomanNumeralScreenState extends State<RomanNumeralScreen>
    with QuizRoundMixin
    implements RomanNumeralTester {
  @override
  String get targetSymbol => _target.symbol;
  @override
  bool get isFinished => finished;

  final _random = Random();

  // Widen with mastery, like the other quizzes.
  static const _easyKeys = [Key.major(Pitch(Step.c))];
  static const _midKeys = [
    Key.major(Pitch(Step.c)),
    Key.major(Pitch(Step.f)),
    Key.major(Pitch(Step.g)),
  ];
  // Natural-tonic keys only, so the key name renders without a missing
  // accidental (noteNameFor spells the letter, not the tonic's alteration).
  static const _majorKeys = [
    Key.major(Pitch(Step.c)),
    Key.major(Pitch(Step.g)),
    Key.major(Pitch(Step.d)),
    Key.major(Pitch(Step.f)),
    Key.major(Pitch(Step.a)),
  ];
  static const _minorKeys = [
    Key.minor(Pitch(Step.a)),
    Key.minor(Pitch(Step.e)),
    Key.minor(Pitch(Step.d)),
  ];
  static const _easyDegrees = [1, 4, 5]; // the primary triads (T/S/D)
  static const _allDegrees = [1, 2, 3, 4, 5, 6, 7];

  // (interval above the tonic, quality) per scale degree. Minor uses the
  // harmonic-minor dominant (V) and leading-tone vii°.
  static const _majorSpec = <int, (Interval?, ChordQuality)>{
    1: (null, ChordQuality.major),
    2: (Interval.majorSecond, ChordQuality.minor),
    3: (Interval.majorThird, ChordQuality.minor),
    4: (Interval.perfectFourth, ChordQuality.major),
    5: (Interval.perfectFifth, ChordQuality.major),
    6: (Interval.majorSixth, ChordQuality.minor),
    7: (Interval.majorSeventh, ChordQuality.diminished),
  };
  static const _minorSpec = <int, (Interval?, ChordQuality)>{
    1: (null, ChordQuality.minor),
    2: (Interval.majorSecond, ChordQuality.diminished),
    3: (Interval.minorThird, ChordQuality.major),
    4: (Interval.perfectFourth, ChordQuality.minor),
    5: (Interval.perfectFifth, ChordQuality.major),
    6: (Interval.minorSixth, ChordQuality.major),
    7: (Interval.majorSeventh, ChordQuality.diminished),
  };

  int _stars = 0;

  late Key _key;
  late int _degree;
  int _inversion = 0;
  late Triad _triad;
  late RomanNumeral _target;
  late List<String> _options; // Roman-numeral choices for this round
  String? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  // The chord audio is the feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  String get gameType => 'roman_numeral';

  // At mastery (2★) the pool adds the far major keys AND the minor keys.
  List<Key> get _keyPool => _stars >= 2
      ? const [..._majorKeys, ..._minorKeys]
      : _stars >= 1
          ? _midKeys
          : _easyKeys;

  List<int> get _degreePool => _stars >= 1 ? _allDegrees : _easyDegrees;

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  ChordType _chordType(ChordQuality q) => switch (q) {
        ChordQuality.major => ChordType.major,
        ChordQuality.minor => ChordType.minor,
        ChordQuality.diminished => ChordType.diminished,
        ChordQuality.augmented => ChordType.augmented,
      };

  /// The diatonic triad on [degree] of [key] (major or minor qualities), in the
  /// given [inversion] (0 root position, 1 first, 2 second).
  Triad _diatonicTriad(Key key, int degree, {int inversion = 0}) {
    final (interval, quality) =
        (key.isMajor ? _majorSpec : _minorSpec)[degree]!;
    final root = interval == null ? key.tonic : key.tonic.transposeBy(interval);
    return Triad(root, quality, inversion: inversion);
  }

  /// Let the library name the numeral (falls back to a direct build if the
  /// analyser ever declines a chord). Root position — used for distractors.
  String _symbolFor(Key key, int degree) {
    final triad = _diatonicTriad(key, degree);
    return romanNumeralOf(triad.pitches, key)?.symbol ??
        RomanNumeral(degree, ChordType.major, 0).symbol;
  }

  @override
  void prepareRound() {
    _key = _keyPool[_random.nextInt(_keyPool.length)];
    _degree = _degreePool[_random.nextInt(_degreePool.length)];
    // At mastery, ~40% of chords are inverted (first or second), so the numeral
    // carries a figured-bass figure (e.g. V6, ii6/4).
    _inversion =
        (_stars >= 2 && _random.nextInt(10) < 4) ? 1 + _random.nextInt(2) : 0;
    _triad = _diatonicTriad(_key, _degree, inversion: _inversion);
    _target = romanNumeralOf(_triad.pitches, _key) ??
        RomanNumeral(_degree, _chordType(_triad.quality), _inversion);

    // Options: the answer plus distractors drawn from the other diatonic
    // degrees of this key (unique symbols), four buttons total.
    final pool = <String>{_target.symbol};
    final others = [..._allDegrees]..shuffle(_random);
    for (final d in others) {
      if (pool.length >= 4) break;
      pool.add(_symbolFor(_key, d));
    }
    _options = pool.toList()..shuffle(_random);

    _tapped = null;
    _lastAnswer = null;
  }

  void _playChord() => context
      .read<AudioService>()
      .playArpeggioThenChord(_triad.pitches.map((p) => p.midiNumber).toList());

  void _onAnswer(String symbol) {
    if (_lastAnswer == true) return; // round already won
    final correct = symbol == _target.symbol;

    // Record the first try per round (mirrors the other quizzes).
    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('harmony.roman.${_target.symbol}', correct);
    }

    final audio = context.read<AudioService>();
    if (correct) {
      audio.playMidiChord(_triad.pitches.map((p) => p.midiNumber).toList());
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = symbol;
      _lastAnswer = correct;
    });
    final advanced = resolveAnswer(correct: correct);
    if (advanced && !finished) {
      // The next round's chord plays after the auto-advance delay.
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted && !finished) _playChord();
      });
    }
  }

  Score get _chordScore => Score(
        clef: Clef.treble,
        keySignature: _key.signature,
        measures: [
          Measure([
            NoteElement(
              pitches: _triad.pitches,
              duration: const NoteDuration(DurationBase.whole),
              id: 'chord',
            ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final keyName = '${noteNameFor(context, _key.tonic.step)} '
        '${_key.isMajor ? l10n.majorLabel : l10n.minorLabel}';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameRomanNumeral)),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.romanNumeralPrompt(keyName),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 32),
                                child: StaffView(
                                  score: _chordScore,
                                  staffSpace: 15,
                                  theme: kidsScoreTheme,
                                ),
                              ),
                              const SizedBox(height: 8),
                              IconButton.filledTonal(
                                onPressed: _playChord,
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.romanNumeralReplay,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final symbol in _options)
                          SizedBox(
                            width: 96,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                backgroundColor: _tapped == null
                                    ? null
                                    : symbol == _target.symbol
                                        ? Colors.green
                                        : symbol == _tapped
                                            ? Colors.redAccent
                                            : null,
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _onAnswer(symbol),
                              child: Text(symbol),
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
