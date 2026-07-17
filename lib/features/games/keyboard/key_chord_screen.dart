// lib/features/games/keyboard/key_chord_screen.dart
//
// "Akkord-Griff" — grab the chord: the game names (and plays) a major
// triad; the child taps all three keys, any order. C/F/G major are all
// white keys; at 2+ stars D, A and E major join and bring the black keys
// into play (F#, C#, G#).
//
// SRI: 'keyboard.chord.<root>_major'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show ChordQuality, Pitch, Step, Triad;
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class KeyChordScreen extends StatefulWidget {
  const KeyChordScreen({super.key});

  @override
  State<KeyChordScreen> createState() => _KeyChordScreenState();
}

class _KeyChordScreenState extends State<KeyChordScreen> with QuizRoundMixin {
  final _random = Random();

  static const _baseRoots = [Step.c, Step.f, Step.g]; // all-white triads
  static const _advancedRoots = [
    Step.c,
    Step.f,
    Step.g,
    Step.d,
    Step.a,
    Step.e,
  ];

  late Step _root;
  late Set<int> _targetMidis;
  final Set<int> _foundMidis = {};
  int? _wrongMidi;
  bool _sriRecorded = false;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'key_chord';

  // The chord notes are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playArpeggio());
  }

  @override
  void prepareRound() {
    final roots = context.read<ProgressService>().starsFor('key_chord') >= 2
        ? _advancedRoots
        : _baseRoots;
    _root = roots[_random.nextInt(roots.length)];
    _targetMidis = Triad(Pitch(_root), ChordQuality.major)
        .pitches
        .map((p) => p.midiNumber)
        .toSet();
    _foundMidis.clear();
    _wrongMidi = null;
    _sriRecorded = false;
    if (round > 0) _playArpeggio();
  }

  bool get _complete => _foundMidis.length == _targetMidis.length;

  void _playArpeggio() {
    final midis = _targetMidis.toList()..sort();
    context
        .read<AudioService>()
        .playSequence([for (final m in midis) (m, 350)]);
  }

  void _record(bool correct) {
    if (_sriRecorded) return;
    _sriRecorded = true;
    context
        .read<SriService>()
        .recordResponse('keyboard.chord.${_root.name}_major', correct);
  }

  void _onKeyTap(int midi) {
    if (_complete) return; // round already resolved
    final audio = context.read<AudioService>();

    if (_targetMidis.contains(midi) && !_foundMidis.contains(midi)) {
      audio.playMidiNote(midi, ms: 450);
      setState(() {
        _foundMidis.add(midi);
        _wrongMidi = null;
      });
      if (_complete) {
        _record(!answeredWrong);
        audio.playMidiChord(_targetMidis.toList(), ms: 1100);
        resolveAnswer(correct: true);
      }
    } else if (!_targetMidis.contains(midi)) {
      audio.playWrong();
      _record(false);
      setState(() => _wrongMidi = midi);
      resolveAnswer(correct: false);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _complete) return;
        setState(() => _wrongMidi = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameKeyChord,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playArpeggio,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'key_chord',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _wrongMidi != null
                          ? false
                          : _complete
                              ? true
                              : null,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.keyChordPrompt(noteNameFor(context, _root)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(
                                  i < _foundMidis.length
                                      ? Icons.music_note
                                      : Icons.music_note_outlined,
                                  size: 40,
                                  color: i < _foundMidis.length
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(
                      correct: _wrongMidi != null
                          ? false
                          : _complete
                              ? true
                              : null,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 170,
                      child: PianoKeyboard(
                        showLabels: true,
                        onKeyTap: _onKeyTap,
                        keyColors: {
                          for (final midi in _foundMidis) midi: Colors.green,
                          if (_wrongMidi != null) _wrongMidi!: Colors.redAccent,
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
