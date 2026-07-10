// lib/features/games/note_values/duration_duel_screen.dart
//
// "Was klingt länger?" — two symbols side by side, the child taps the one
// that lasts longer. Trains relative durations, including the insight that
// rests have lengths too (a half rest outlasts a quarter note).
//
// SRI: each round is recorded for BOTH symbols under their symbol items —
// knowing a symbol's duration is the same skill the quiz drills by name.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/tuning.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/music_glyph.dart';
import 'symbol_catalog.dart';

class DurationDuelScreen extends StatefulWidget {
  const DurationDuelScreen({super.key});

  static const totalRounds = 10;
  static const pointsPerRound = 100;

  @override
  State<DurationDuelScreen> createState() => _DurationDuelScreenState();
}

class _DurationDuelScreenState extends State<DurationDuelScreen> {
  final _random = Random();

  int _round = 0;
  int _score = 0;
  late NoteSymbol _left;
  late NoteSymbol _right;
  NoteSymbol? _tapped;
  bool _answeredWrong = false;
  bool _finished = false;

  NoteSymbol get _longer => _left.beats >= _right.beats ? _left : _right;

  @override
  void initState() {
    super.initState();
    _prepareRound();
  }

  void _prepareRound() {
    // Draw two symbols with different durations.
    final pool = [...kNoteSymbols]..shuffle(_random);
    _left = pool.first;
    _right = pool.firstWhere((s) => s.beats != _left.beats);
    _tapped = null;
    _answeredWrong = false;
  }

  void _onTap(NoteSymbol choice) {
    if (_tapped == _longer) return; // round already resolved
    final correct = choice == _longer;

    if (_tapped == null || !_answeredWrong) {
      final sri = context.read<SriService>();
      sri.recordResponse(_left.sriId, correct);
      sri.recordResponse(_right.sriId, correct);
    }

    setState(() {
      _tapped = choice;
      if (correct) {
        if (!_answeredWrong) {
          _score += DurationDuelScreen.pointsPerRound;
        }
        if (_round + 1 >= DurationDuelScreen.totalRounds) {
          _finished = true;
        }
      } else {
        _answeredWrong = true;
      }
    });

    if (correct && !_finished) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _round++;
          _prepareRound();
        });
      });
    }
  }

  void _restart() {
    setState(() {
      _round = 0;
      _score = 0;
      _finished = false;
      _prepareRound();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stars = scoreToStars('duration_duel', _score, true);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameDurationDuel)),
      body: SafeArea(
        child: _finished
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Icon(
                            i < stars ? Icons.star : Icons.star_border,
                            size: 56,
                            color: Colors.amber,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.resultScore(_score),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _restart,
                      icon: const Icon(Icons.replay),
                      label: Text(l10n.playAgain),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.backButton),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      l10n.roundOf(_round + 1, DurationDuelScreen.totalRounds),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.whichLastsLonger,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _duelCard(_left)),
                          const SizedBox(width: 12),
                          Expanded(child: _duelCard(_right)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 28,
                      child: Text(
                        _tapped == null
                            ? ''
                            : _tapped == _longer
                                ? l10n.feedbackCorrect
                                : l10n.feedbackTryAgain,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: _tapped == _longer
                                      ? Colors.green
                                      : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _duelCard(NoteSymbol symbol) {
    final Color? border = _tapped == null
        ? null
        : symbol == _longer && _tapped == _longer
            ? Colors.green
            : symbol == _tapped
                ? Colors.redAccent
                : null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: border != null
            ? BorderSide(color: border, width: 4)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTap(symbol),
        child: Center(child: MusicGlyph(symbol.glyph, size: 84)),
      ),
    );
  }
}
