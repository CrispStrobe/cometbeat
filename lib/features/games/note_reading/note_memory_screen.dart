// lib/features/games/note_reading/note_memory_screen.dart
//
// "Noten-Memory" — a concentration/pairs game: a grid of face-down cards hides
// six note↔name pairs. Flip two; if a note-on-staff card and its letter-name
// card match, they stay. Every flip plays the pitch, so the ear helps too.
// Fewer moves → more stars. The first pairs/memory format in the app (see
// docs/PLAN.md gamification backlog).
//
// SRI: a matched pair records a correct 'note_reading.treble.<pitch>' read.

import 'dart:async';
import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class NoteMemoryScreen extends StatefulWidget {
  const NoteMemoryScreen({super.key});

  static const pairCount = 6;

  @override
  State<NoteMemoryScreen> createState() => _NoteMemoryScreenState();
}

/// One tile in the grid: a note-on-staff face or a letter-name face, both
/// belonging to [pairId].
class _Card {
  final int pairId;
  final bool isStaff;
  final Pitch pitch;
  bool revealed = false;
  bool matched = false;

  _Card(this.pairId, this.isStaff, this.pitch);
}

class _NoteMemoryScreenState extends State<NoteMemoryScreen> {
  final _random = Random();
  late List<_Card> _deck;
  int? _firstIndex; // index of the first flipped card this turn
  bool _busy = false; // waiting out a mismatch flip-back
  int _moves = 0;
  int _matched = 0;
  bool _finished = false;
  Timer? _flipBackTimer;

  @override
  void initState() {
    super.initState();
    _deal();
  }

  @override
  void dispose() {
    _flipBackTimer?.cancel();
    super.dispose();
  }

  void _deal() {
    // Six distinct treble naturals in and just below/above the staff.
    final positions = [-2, 0, 1, 2, 4, 5]..shuffle(_random);
    final pitches = [
      for (final p in positions.take(NoteMemoryScreen.pairCount))
        Clef.treble.pitchAt(p),
    ];
    _deck = [
      for (var i = 0; i < pitches.length; i++) ...[
        _Card(i, true, pitches[i]),
        _Card(i, false, pitches[i]),
      ],
    ]..shuffle(_random);
    _firstIndex = null;
    _busy = false;
    _moves = 0;
    _matched = 0;
    _finished = false;
  }

  int get _score {
    // 100 per pair, minus 20 for every move beyond a flawless run.
    const perfect = NoteMemoryScreen.pairCount;
    final extraMoves = _moves > perfect ? _moves - perfect : 0;
    final raw = _matched * 100 - 20 * extraMoves;
    return raw < 100 ? 100 : raw;
  }

  void _onTap(int index) {
    if (_busy || _finished) return;
    final card = _deck[index];
    if (card.revealed || card.matched) return;

    context.read<AudioService>().playMidiNote(card.pitch.midiNumber, ms: 500);
    setState(() => card.revealed = true);

    if (_firstIndex == null) {
      _firstIndex = index;
      return;
    }

    // Second card of the turn.
    _moves++;
    final first = _deck[_firstIndex!];
    if (first.pairId == card.pairId) {
      // A match.
      context.read<SriService>().recordResponse(
            'note_reading.treble.${card.pitch.step.name}${card.pitch.octave}',
            true,
          );
      setState(() {
        first.matched = true;
        card.matched = true;
        _matched++;
        _firstIndex = null;
      });
      if (_matched == NoteMemoryScreen.pairCount) _finish();
    } else {
      // A miss — show both briefly, then flip back.
      _busy = true;
      _flipBackTimer?.cancel();
      _flipBackTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          first.revealed = false;
          card.revealed = false;
          _firstIndex = null;
          _busy = false;
        });
      });
    }
  }

  void _finish() {
    final audio = context.read<AudioService>();
    audio.playFanfare();
    context.read<ProgressService>().recordResult(
          'note_memory',
          score: _score,
          stars: scoreToStars('note_memory', _score, true),
        );
    setState(() => _finished = true);
  }

  void _restart() => setState(_deal);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameNoteMemory),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'note_memory',
                score: _score,
                onRestart: _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      l10n.noteMemoryPrompt,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.noteMemoryMoves(_moves),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: GridView.count(
                            crossAxisCount: 4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            children: [
                              for (var i = 0; i < _deck.length; i++)
                                _MemoryTile(
                                  card: _deck[i],
                                  onTap: () => _onTap(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  final _Card card;
  final VoidCallback onTap;

  const _MemoryTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faceUp = card.revealed || card.matched;

    Widget face;
    if (!faceUp) {
      face = Container(
        key: const ValueKey('back'),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.music_note, color: scheme.onPrimaryContainer),
      );
    } else {
      face = Container(
        key: ValueKey('front_${card.pairId}_${card.isStaff}'),
        decoration: BoxDecoration(
          color: card.matched ? Colors.green.shade100 : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: card.matched ? Colors.green : scheme.outlineVariant,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        child: card.isStaff
            ? StaffView(
                score: Score.simple(
                  notes: '${card.pitch.step.name}${card.pitch.octave}:w',
                ),
                staffSpace: 7,
                theme: kidsScoreTheme,
              )
            : Text(
                noteNameFor(context, card.pitch.step),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: card.matched
                          ? Colors.green.shade900
                          : scheme.onSurface,
                    ),
              ),
      );
    }

    return GestureDetector(
      onTap: faceUp ? null : onTap,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: face,
      ),
    );
  }
}
