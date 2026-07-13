// lib/features/games/chords/chord_chart_screen.dart
//
// "Chord Chart" — lead-sheet literacy: a chord SYMBOL is shown (G, Dm, D7…) and
// the child taps the matching NOTATION among four little staves. The inverse of
// Name That Chord (notation → symbol); here you read the symbol, as on a real
// song chart, and recognise the chord shape. Symbols come from partitura's
// `chordSymbolFor`, so they're spelled the same way the library names them.
//
// SRI: 'chords.symbol.<symbol>'.

import 'dart:math';

// Material's Stepper also exports `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

/// One answer option: a chord's notation plus the symbol it spells.
class _ChordOption {
  final List<Pitch> pitches;
  final String symbol;
  const _ChordOption(this.pitches, this.symbol);
}

class ChordChartScreen extends StatefulWidget {
  const ChordChartScreen({super.key});

  @override
  State<ChordChartScreen> createState() => _ChordChartScreenState();
}

/// Test handle onto the running game (the target varies per round).
@visibleForTesting
abstract interface class ChordChartTester {
  String get targetSymbol;

  /// Index (in staff/card order) of the option matching the symbol.
  int get targetIndex;
  bool get isFinished;
}

class _ChordChartScreenState extends State<ChordChartScreen>
    with QuizRoundMixin
    implements ChordChartTester {
  final _random = Random();

  static const _easyRoots = [Step.c, Step.f, Step.g];
  static const _allRoots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  int _stars = 0;
  late List<_ChordOption> _options;
  late int _targetIndex;
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  bool get playFeedbackSounds => false; // the chord plays on a correct tap

  @override
  String get gameType => 'chord_chart';

  @override
  String get targetSymbol => _options[_targetIndex].symbol;
  @override
  int get targetIndex => _targetIndex;
  @override
  bool get isFinished => finished;

  List<Step> get _roots => _stars >= 1 ? _allRoots : _easyRoots;

  List<ChordQuality> get _qualities => _stars >= 2
      ? const [
          ChordQuality.major,
          ChordQuality.minor,
          ChordQuality.diminished,
        ]
      : const [ChordQuality.major, ChordQuality.minor];

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
  }

  _ChordOption _chord(Step root, ChordQuality quality) {
    final pitches = Triad(Pitch(root), quality).pitches;
    return _ChordOption(pitches, chordSymbolFor(pitches) ?? '?');
  }

  @override
  void prepareRound() {
    // Four options with distinct symbols; a random one is the target.
    final chosen = <String, _ChordOption>{};
    var guard = 0;
    while (chosen.length < 4 && guard++ < 60) {
      final opt = _chord(
        _roots[_random.nextInt(_roots.length)],
        _qualities[_random.nextInt(_qualities.length)],
      );
      chosen.putIfAbsent(opt.symbol, () => opt);
    }
    _options = chosen.values.toList()..shuffle(_random);
    _targetIndex = _random.nextInt(_options.length);
    _tapped = null;
    _lastAnswer = null;
  }

  Score _chordScore(List<Pitch> pitches) => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: pitches,
              duration: const NoteDuration(DurationBase.whole),
              id: 'c',
            ),
          ]),
        ],
      );

  void _onAnswer(int index) {
    if (_lastAnswer == true) return; // round already won
    final correct = index == _targetIndex;

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('chords.symbol.$targetSymbol', correct);
    }

    final audio = context.read<AudioService>();
    if (correct) {
      audio.playMidiChord(
        _options[_targetIndex].pitches.map((p) => p.midiNumber).toList(),
      );
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = index;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Color? _cardColor(int index) {
    if (_tapped == null) return null;
    if (index == _targetIndex) return Colors.green.shade100;
    if (index == _tapped) return Colors.red.shade100;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameChordChart)),
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
                      prompt: l10n.chordChartPrompt,
                    ),
                    const SizedBox(height: 8),
                    // The chord symbol, lead-sheet style.
                    Text(
                      targetSymbol,
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.3,
                        children: [
                          for (var i = 0; i < _options.length; i++)
                            Card(
                              color: _cardColor(i),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _onAnswer(i),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Center(
                                    child: StaffView(
                                      score: _chordScore(_options[i].pitches),
                                      staffSpace: 12,
                                      theme: PartituraTheme.kids,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                  ],
                ),
              ),
      ),
    );
  }
}
