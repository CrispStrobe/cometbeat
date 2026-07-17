// "Which Family?" — a knowledge/reading multiple-choice game. Each round names a
// well-known instrument (a text label with a neutral music icon); the child taps
// which orchestral family it belongs to: Strings / Woodwind / Brass / Percussion
// / Keyboard. This is deliberately a READING quiz, not a timbre-ID one — the
// app's synth has only a few timbres, so hearing the instrument would be
// unreliable. Same multiple-choice shape as which_clef (QuizRoundMixin +
// AnswerGrid). SRI `timbre.family.<family>`.

import 'dart:math';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The five instrument families offered as answers.
enum InstrumentFamily { strings, woodwind, brass, percussion, keyboard }

/// One quiz item: an instrument name (localised) and the family it belongs to.
class _Instrument {
  const _Instrument(this.name, this.family);
  final String Function(AppLocalizations) name;
  final InstrumentFamily family;
}

/// The ~15+ well-known instruments this game quizzes, grouped by family.
const List<_Instrument> _kInstruments = [
  // Strings — bowed or plucked.
  _Instrument(_iViolin, InstrumentFamily.strings),
  _Instrument(_iCello, InstrumentFamily.strings),
  _Instrument(_iGuitar, InstrumentFamily.strings),
  _Instrument(_iHarp, InstrumentFamily.strings),
  // Woodwind — blown, reed or edge.
  _Instrument(_iFlute, InstrumentFamily.woodwind),
  _Instrument(_iClarinet, InstrumentFamily.woodwind),
  _Instrument(_iOboe, InstrumentFamily.woodwind),
  _Instrument(_iSaxophone, InstrumentFamily.woodwind),
  _Instrument(_iRecorder, InstrumentFamily.woodwind),
  // Brass — blown through a cup mouthpiece.
  _Instrument(_iTrumpet, InstrumentFamily.brass),
  _Instrument(_iTrombone, InstrumentFamily.brass),
  _Instrument(_iHorn, InstrumentFamily.brass),
  _Instrument(_iTuba, InstrumentFamily.brass),
  // Percussion — struck.
  _Instrument(_iDrums, InstrumentFamily.percussion),
  _Instrument(_iXylophone, InstrumentFamily.percussion),
  _Instrument(_iTimpani, InstrumentFamily.percussion),
  _Instrument(_iTriangle, InstrumentFamily.percussion),
  // Keyboard.
  _Instrument(_iPiano, InstrumentFamily.keyboard),
  _Instrument(_iOrgan, InstrumentFamily.keyboard),
];

// Instrument-name accessors (kept as top-level tear-offs so the list is const).
String _iViolin(AppLocalizations l) => l.instrViolin;
String _iCello(AppLocalizations l) => l.instrCello;
String _iGuitar(AppLocalizations l) => l.instrGuitar;
String _iHarp(AppLocalizations l) => l.instrHarp;
String _iFlute(AppLocalizations l) => l.instrFlute;
String _iClarinet(AppLocalizations l) => l.instrClarinet;
String _iOboe(AppLocalizations l) => l.instrOboe;
String _iSaxophone(AppLocalizations l) => l.instrSaxophone;
String _iRecorder(AppLocalizations l) => l.instrRecorder;
String _iTrumpet(AppLocalizations l) => l.instrTrumpet;
String _iTrombone(AppLocalizations l) => l.instrTrombone;
String _iHorn(AppLocalizations l) => l.instrHorn;
String _iTuba(AppLocalizations l) => l.instrTuba;
String _iDrums(AppLocalizations l) => l.instrDrums;
String _iXylophone(AppLocalizations l) => l.instrXylophone;
String _iTimpani(AppLocalizations l) => l.instrTimpani;
String _iTriangle(AppLocalizations l) => l.instrTriangle;
String _iPiano(AppLocalizations l) => l.instrPiano;
String _iOrgan(AppLocalizations l) => l.instrOrgan;

String _familyKey(InstrumentFamily f) => switch (f) {
      InstrumentFamily.strings => 'strings',
      InstrumentFamily.woodwind => 'woodwind',
      InstrumentFamily.brass => 'brass',
      InstrumentFamily.percussion => 'percussion',
      InstrumentFamily.keyboard => 'keyboard',
    };

String _familyLabel(AppLocalizations l, InstrumentFamily f) => switch (f) {
      InstrumentFamily.strings => l.familyStrings,
      InstrumentFamily.woodwind => l.familyWoodwind,
      InstrumentFamily.brass => l.familyBrass,
      InstrumentFamily.percussion => l.familyPercussion,
      InstrumentFamily.keyboard => l.familyKeyboard,
    };

class InstrumentFamilyScreen extends StatefulWidget {
  const InstrumentFamilyScreen({super.key});

  @override
  State<InstrumentFamilyScreen> createState() => _InstrumentFamilyScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class InstrumentFamilyTester {
  /// Lowercase key of the shown instrument's family — the correct answer
  /// (`strings`/`woodwind`/`brass`/`percussion`/`keyboard`).
  String get answerFamily;
  bool get isFinished;
}

class _InstrumentFamilyScreenState extends State<InstrumentFamilyScreen>
    with QuizRoundMixin
    implements InstrumentFamilyTester {
  final _random = Random();

  // All five families are always offered as options.
  static const _options = InstrumentFamily.values;

  late _Instrument _instrument; // the shown instrument = the correct answer
  InstrumentFamily? _tapped; // the last option tapped this round
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'instrument_family';

  @override
  String get answerFamily => _familyKey(_instrument.family);

  @override
  bool get isFinished => finished;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Avoid repeating the same instrument two rounds running.
    _Instrument next;
    do {
      next = _kInstruments[_random.nextInt(_kInstruments.length)];
    } while (_hasPrevious &&
        next.family == _instrument.family &&
        _random.nextBool());
    _instrument = next;
    _tapped = null;
    _lastAnswer = null;
  }

  bool _hasPrevious = false;

  void _onAnswer(InstrumentFamily choice) {
    if (_lastAnswer == true) return; // round already cleared
    final correct = choice == _instrument.family;
    // Record only the first attempt of the round (retries aren't re-counted).
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'timbre.family.${_familyKey(_instrument.family)}',
            correct,
          );
    }
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
      _hasPrevious = true;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(title: l10n.gameInstrumentFamily),
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
                      prompt: l10n.instrumentFamilyPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 24,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.music_note,
                                  size: 44,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _instrument.name(l10n),
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final f in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              backgroundColor: _tapped == null
                                  ? null
                                  : f == _instrument.family
                                      ? Colors.green
                                      : f == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(f),
                            child: Text(_familyLabel(l10n, f)),
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
