// lib/features/games/composition/grid_composer_screen.dart
//
// "Farb-Melodie" / "Colour Melody" — a composing grid for pre-readers. Five
// coloured rows (a C-pentatonic, so every tune sounds good) × eight beats. The
// child taps cells to place notes; each tap sounds, and the grid renders to a
// REAL crisp_notation Score shown underneath — so a non-reader is quietly
// writing notation. Play the tune back, or clear and start over. No stars, no
// wrong answers — free creation is the point (like Meine Melodie, but no reading
// needed to start).
//
// One note per beat keeps it a clean single-voice melody; empty beats are rests.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _quarter = NoteDuration(DurationBase.quarter);

class GridComposerScreen extends StatefulWidget {
  const GridComposerScreen({super.key});

  /// Beats across (two 4/4 bars of quarter notes).
  static const columns = 8;

  // Pitch rows, top (high) → bottom (low): a C-major pentatonic, so any
  // combination is consonant. Highest at the top matches staff intuition.
  static const _rowSteps = [Step.a, Step.g, Step.e, Step.d, Step.c];

  @override
  State<GridComposerScreen> createState() => _GridComposerScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class GridComposerTester {
  /// Row placed in each beat column (null = rest). Length == [columns].
  List<int?> get columns;

  /// The live Score the grid renders to.
  Score get score;
  void tapCell(int col, int row);
}

class _GridComposerScreenState extends State<GridComposerScreen>
    implements GridComposerTester {
  // One row index per beat, or null for a rest. One note per beat.
  final List<int?> _col = List<int?>.filled(GridComposerScreen.columns, null);

  // Octave 4 is Pitch's default (middle-C register) — a comfortable range.
  List<Pitch> get _rowPitches =>
      [for (final s in GridComposerScreen._rowSteps) Pitch(s)];

  @override
  List<int?> get columns => List.unmodifiable(_col);
  @override
  Score get score => _score;

  @override
  void tapCell(int col, int row) => _onTap(col, row);

  void _onTap(int col, int row) {
    setState(() {
      // Tapping the active cell clears the beat; otherwise (re)places the note.
      _col[col] = _col[col] == row ? null : row;
    });
    if (_col[col] != null) {
      context
          .read<AudioService>()
          .playMidiNote(_rowPitches[row].midiNumber, ms: 320);
    }
  }

  // The grid → a real single-voice Score: each beat is a note or a quarter rest,
  // grouped into 4/4 bars.
  Score get _score {
    final elements = [
      for (final r in _col)
        if (r == null)
          const RestElement(_quarter)
        else
          NoteElement.note(_rowPitches[r], _quarter),
    ];
    return Score(
      clef: Clef.treble,
      measures: [
        for (var i = 0; i < elements.length; i += 4)
          Measure(elements.sublist(i, (i + 4).clamp(0, elements.length))),
      ],
    );
  }

  bool get _hasNotes => _col.any((r) => r != null);

  void _play() {
    // Each beat is a one-note chord, or an empty list (a rest → silence), so the
    // rhythm plays back with its gaps intact.
    final beats = [
      for (final r in _col)
        if (r == null) <int>[] else [_rowPitches[r].midiNumber],
    ];
    context.read<AudioService>().playChordSequence(beats, ms: 360);
  }

  void _clear() => setState(
        () => _col.fillRange(0, GridComposerScreen.columns, null),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rowColors = [
      for (final s in GridComposerScreen._rowSteps) pitchClassColor(s),
    ];

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameGridComposer),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                l10n.gridComposerPrompt,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // The colour grid.
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    for (var row = 0;
                        row < GridComposerScreen._rowSteps.length;
                        row++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              for (var col = 0;
                                  col < GridComposerScreen.columns;
                                  col++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: _Cell(
                                      color: rowColors[row],
                                      active: _col[col] == row,
                                      onTap: () => _onTap(col, row),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // The notation it renders to — the bridge to reading.
              Expanded(
                flex: 2,
                child: Card(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: StaffView(
                        score: _score,
                        staffSpace: 9,
                        theme: kidsScoreTheme,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _hasNotes ? _play : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l10n.gridComposerPlay),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _hasNotes ? _clear : null,
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.gridComposerClear),
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.color,
    required this.active,
    required this.onTap,
  });

  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.35),
            width: active ? 3 : 1.5,
          ),
        ),
      ),
    );
  }
}
