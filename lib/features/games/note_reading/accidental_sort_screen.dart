// lib/features/games/note_reading/accidental_sort_screen.dart
//
// "Sharp or Flat?" — a drag-and-drop sorting game on accidental *signs*: each
// note carries a sharp or a flat, and the child drags it into the ♯ or ♭
// basket. Reading the little sign in front of a note is the skill. A card only
// drops into the correct basket; a wrong drop bounces back and buzzes (the
// no-fail loop). The sort-into-buckets format (like Sort the Beats / High or
// Low?), on the sharp/flat dimension (docs/PLAN.md sort backlog).
//
// At 2★ it widens to THREE baskets — Sharp / Natural / Flat — adding the natural
// sign (♮, rendered via NoteElement.showAccidental on an unaltered pitch); below
// 2★ it stays the binary ♯/♭ drill. Mirrors how Step or Skip? grows a third
// option.
//
// SRI: 'accidentals.sign.<sharp|natural|flat>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _whole = NoteDuration(DurationBase.whole);

class AccidentalSortScreen extends StatefulWidget {
  const AccidentalSortScreen({super.key, this.clef = Clef.treble});

  /// Which clef the notes are read in (treble by default; a bass variant reuses
  /// the same screen — sharp-vs-flat is clef-independent, but bass gives
  /// bass-clef reading practice and its own pitches/progress).
  final Clef clef;

  static const cardCount = 4;

  @override
  State<AccidentalSortScreen> createState() => _AccidentalSortScreenState();
}

class _AccidentalSortScreenState extends State<AccidentalSortScreen>
    with QuizRoundMixin {
  final _random = Random();

  late List<Pitch> _cards; // one note per card, each with an accidental
  late List<int> _alter; // card index → +1 sharp / 0 natural / -1 flat
  late List<int> _buckets; // the baskets in play this round (2 or 3 signs)
  late List<bool> _placed;
  late Map<int, List<Pitch>> _binned;
  final Set<int> _recorded = {};
  bool? _lastDropOk;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'accidental_sort';

  // Treble keeps the original id (no progress migration); bass gets its own.
  @override
  String get progressId =>
      widget.clef == Clef.bass ? 'accidental_sort_bass' : 'accidental_sort';

  // Drops give their own feedback (the note sounds on a correct drop, a buzz on
  // a miss); no generic blips.
  @override
  bool get playFeedbackSounds => false;

  static String _signName(int alter) =>
      alter > 0 ? 'sharp' : (alter < 0 ? 'flat' : 'natural');
  static String _signGlyph(int alter) =>
      alter > 0 ? '♯' : (alter < 0 ? '♭' : '♮');
  String _signLabel(AppLocalizations l, int alter) => alter > 0
      ? l.accidentalSharpLabel
      : (alter < 0 ? l.accidentalFlatLabel : l.accidentalNaturalLabel);

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // At 2★ the natural sign joins as a third basket. Guarantee at least one of
    // each active sign so every basket is always in play.
    final wide = context.read<ProgressService>().starsFor(progressId) >= 2;
    _buckets = wide ? const [1, 0, -1] : const [1, -1];

    final signs = [..._buckets];
    while (signs.length < AccidentalSortScreen.cardCount) {
      signs.add(_buckets[_random.nextInt(_buckets.length)]);
    }
    signs.shuffle(_random);

    _cards = [
      for (final alter in signs)
        () {
          final base = widget.clef.pitchAt(1 + _random.nextInt(7));
          return Pitch(base.step, alter: alter, octave: base.octave);
        }(),
    ];
    _alter = signs;
    _placed = List.filled(AccidentalSortScreen.cardCount, false);
    _binned = {for (final b in _buckets) b: <Pitch>[]};
    _recorded.clear();
    _lastDropOk = null;
  }

  void _onAccept(int cardIndex, int alter) {
    // Only ever called for the correct basket (see onWillAccept).
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'accidentals.sign.${_signName(alter)}',
            true,
          );
    }
    context
        .read<AudioService>()
        .playMidiNote(_cards[cardIndex].midiNumber, ms: 400);
    setState(() {
      _placed[cardIndex] = true;
      _binned[alter]!.add(_cards[cardIndex]);
      _lastDropOk = true;
    });
    if (_placed.every((p) => p)) resolveAnswer(correct: true);
  }

  void _onMiss(int cardIndex) {
    context.read<AudioService>().playWrong();
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'accidentals.sign.${_signName(_alter[cardIndex])}',
            false,
          );
    }
    setState(() {
      answeredWrong = true;
      _lastDropOk = false;
    });
  }

  // A natural (unaltered) pitch needs its ♮ forced; sharps/flats show on their
  // own because they deviate from the (keyless) staff.
  Score _score(Pitch p) => Score(
        clef: widget.clef,
        measures: [
          Measure([
            NoteElement.note(
              p,
              _whole,
              id: 'n',
              showAccidental: p.alter == 0 ? true : null,
            ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: widget.clef == Clef.bass
            ? l10n.gameAccidentalSortBass
            : l10n.gameAccidentalSort,
      ),
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
                      correct: finished ? true : _lastDropOk,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.accidentalSortPrompt,
                    ),
                    const SizedBox(height: 16),
                    // Card pool.
                    SizedBox(
                      height: 120,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            for (var i = 0; i < _cards.length; i++)
                              if (!_placed[i])
                                Draggable<int>(
                                  data: i,
                                  feedback: _NoteCard(
                                    score: _score(_cards[i]),
                                    dragging: true,
                                  ),
                                  childWhenDragging: const SizedBox(
                                    width: 84,
                                    height: 104,
                                  ),
                                  onDraggableCanceled: (_, __) => _onMiss(i),
                                  child: _NoteCard(score: _score(_cards[i])),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final alter in _buckets)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) =>
                                    _alter[d.data] == alter,
                                onAcceptWithDetails: (d) =>
                                    _onAccept(d.data, alter),
                                builder: (context, candidate, __) => _Bucket(
                                  glyph: _signGlyph(alter),
                                  label: _signLabel(l10n, alter),
                                  hovering: candidate.isNotEmpty,
                                  contents: _binned[alter] ?? const [],
                                  scoreOf: _score,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: finished ? true : _lastDropOk),
                  ],
                ),
              ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Score score;
  final bool dragging;

  const _NoteCard({required this.score, this.dragging = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 84,
        height: 104,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dragging
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: StaffView(score: score, staffSpace: 7, theme: kidsScoreTheme),
      ),
    );
  }
}

class _Bucket extends StatelessWidget {
  final String glyph;
  final String label;
  final bool hovering;
  final List<Pitch> contents;
  final Score Function(Pitch) scoreOf;

  const _Bucket({
    required this.glyph,
    required this.label,
    required this.hovering,
    required this.contents,
    required this.scoreOf,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 184,
      decoration: BoxDecoration(
        color:
            hovering ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hovering ? scheme.primary : scheme.outlineVariant,
          width: hovering ? 3 : 2,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Text(
            // The SMuFL-free glyph is fine for a big basket label.
            '$label  $glyph',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in contents)
                  SizedBox(
                    width: 64,
                    height: 70,
                    child: StaffView(
                      score: scoreOf(p),
                      staffSpace: 6,
                      theme: kidsScoreTheme,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
