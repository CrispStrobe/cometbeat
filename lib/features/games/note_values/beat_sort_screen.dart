// lib/features/games/note_values/beat_sort_screen.dart
//
// "Schläge sortieren" — a drag-and-drop sorting game: note-value symbols are
// dragged into the bucket for how many beats they last (1, 2 or 4 in 4/4). A
// card only drops into the right bucket; a wrong drop bounces back and buzzes.
// The first sort-into-buckets format in the app (see docs/PLAN.md).
//
// SRI: 'note_values.symbol.<id>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/symbol_catalog.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BeatSortScreen extends StatefulWidget {
  const BeatSortScreen({super.key});

  static const cardCount = 4;
  static const _buckets = [1, 2, 4]; // beats in 4/4

  @override
  State<BeatSortScreen> createState() => _BeatSortScreenState();
}

class _BeatSortScreenState extends State<BeatSortScreen> with QuizRoundMixin {
  final _random = Random();

  // Whole (4), half (2), quarter (1) — clean integer beat values.
  static final _pickable = [
    for (final id in ['quarter_note', 'half_note', 'whole_note'])
      symbolById(id)!,
  ];

  late List<NoteSymbol> _cards; // by index; entry null once placed
  late List<bool> _placed;
  final Map<int, List<NoteSymbol>> _binned = {};
  final Set<int> _recorded = {};
  bool? _lastDropOk; // drives the reacting mascot

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'beat_sort';

  // Drops give their own feedback (buzz on a miss); no generic blips.
  @override
  bool get playFeedbackSounds => false;

  static int _beats4(NoteSymbol s) => (s.beats * 4).round();

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _cards = [
      for (var i = 0; i < BeatSortScreen.cardCount; i++)
        _pickable[_random.nextInt(_pickable.length)],
    ];
    _placed = List.filled(BeatSortScreen.cardCount, false);
    _binned
      ..clear()
      ..addEntries(BeatSortScreen._buckets.map((b) => MapEntry(b, [])));
    _recorded.clear();
    _lastDropOk = null;
  }

  void _onAccept(int cardIndex, int bucket) {
    // Only ever called for a correct bucket (see onWillAccept).
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(_cards[cardIndex].sriId, true);
    }
    setState(() {
      _placed[cardIndex] = true;
      _binned[bucket]!.add(_cards[cardIndex]);
      _lastDropOk = true;
    });
    if (_placed.every((p) => p)) resolveAnswer(correct: true);
  }

  void _onMiss(int cardIndex) {
    context.read<AudioService>().playWrong();
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(_cards[cardIndex].sriId, false);
    }
    setState(() {
      answeredWrong = true;
      _lastDropOk = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameBeatSort),
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
                      prompt: l10n.beatSortPrompt,
                    ),
                    const SizedBox(height: 16),
                    // Card pool.
                    SizedBox(
                      height: 96,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            for (var i = 0; i < _cards.length; i++)
                              if (!_placed[i])
                                Draggable<int>(
                                  data: i,
                                  feedback: _GlyphCard(
                                    glyph: _cards[i].glyph,
                                    dragging: true,
                                  ),
                                  childWhenDragging: const SizedBox(
                                    width: 60,
                                    height: 80,
                                  ),
                                  onDraggableCanceled: (_, __) => _onMiss(i),
                                  child: _GlyphCard(glyph: _cards[i].glyph),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final bucket in BeatSortScreen._buckets)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) =>
                                    _beats4(_cards[d.data]) == bucket,
                                onAcceptWithDetails: (d) =>
                                    _onAccept(d.data, bucket),
                                builder: (context, candidate, __) => _Bucket(
                                  beats: bucket,
                                  label: l10n.beatsCount(bucket),
                                  hovering: candidate.isNotEmpty,
                                  contents: _binned[bucket] ?? const [],
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

class _GlyphCard extends StatelessWidget {
  final String glyph;
  final bool dragging;

  const _GlyphCard({required this.glyph, this.dragging = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 60,
        height: 80,
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
        child: MusicGlyph(glyph, size: 40),
      ),
    );
  }
}

class _Bucket extends StatelessWidget {
  final int beats;
  final String label;
  final bool hovering;
  final List<NoteSymbol> contents;

  const _Bucket({
    required this.beats,
    required this.label,
    required this.hovering,
    required this.contents,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 168,
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
            label,
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
                for (final s in contents) MusicGlyph(s.glyph, size: 44),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
