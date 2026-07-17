// lib/features/games/composition/melody_doodle_screen.dart
//
// "Melody doodle" — draw a line, hear it as a tune. The freehand contour is
// quantised to one C-pentatonic note per beat (so every doodle sounds good) and
// rendered to a REAL crisp_notation Score underneath, exactly like Colour Melody
// — but the input is a gesture, not taps, so a pre-reader can "draw music".
// A sandbox: no stars, no wrong answers.
//
// One note per beat keeps it a clean single-voice melody; untouched beats rest.

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

/// Quantises a freehand contour into one pitch row per beat column.
///
/// [points] are in the canvas's local pixels and [size] is its box. Each point
/// falls in the column under its x; a column's rows are averaged, so a scribble
/// reads as its overall height rather than its last pixel. **y is inverted** —
/// the top of the canvas is row 0, the HIGHEST note (staff intuition). Columns
/// the line never crossed are rests (null). Pure, so it is unit-tested.
List<int?> doodleToColumns(
  List<Offset> points,
  Size size, {
  required int columns,
  required int rows,
}) {
  if (size.width <= 0 || size.height <= 0 || columns <= 0 || rows <= 0) {
    return List<int?>.filled(columns > 0 ? columns : 0, null);
  }
  final sums = List<double>.filled(columns, 0);
  final counts = List<int>.filled(columns, 0);
  for (final p in points) {
    final c = (p.dx / size.width * columns).floor().clamp(0, columns - 1);
    sums[c] += (p.dy / size.height).clamp(0.0, 1.0);
    counts[c]++;
  }
  return [
    for (var c = 0; c < columns; c++)
      if (counts[c] == 0)
        null
      else
        ((sums[c] / counts[c]) * rows).floor().clamp(0, rows - 1),
  ];
}

class MelodyDoodleScreen extends StatefulWidget {
  const MelodyDoodleScreen({super.key});

  /// Beats across (two 4/4 bars of quarter notes) — matches Colour Melody.
  static const columns = 8;

  // Pitch rows, top (high) → bottom (low): a C-major pentatonic, so any contour
  // is consonant. Highest at the top matches both the staff and the gesture.
  static const rowSteps = [Step.a, Step.g, Step.e, Step.d, Step.c];

  @override
  State<MelodyDoodleScreen> createState() => _MelodyDoodleScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class MelodyDoodleTester {
  /// Row drawn in each beat column (null = rest). Length == [columns].
  List<int?> get columns;

  /// The live Score the doodle renders to.
  Score get score;
}

class _MelodyDoodleScreenState extends State<MelodyDoodleScreen>
    implements MelodyDoodleTester {
  final List<Offset> _points = [];
  Size _canvas = Size.zero;

  // Octave 4 is Pitch's default (middle-C register) — a comfortable range.
  List<Pitch> get _rowPitches =>
      [for (final s in MelodyDoodleScreen.rowSteps) Pitch(s)];

  @override
  List<int?> get columns => doodleToColumns(
        _points,
        _canvas,
        columns: MelodyDoodleScreen.columns,
        rows: MelodyDoodleScreen.rowSteps.length,
      );

  @override
  Score get score => _score;

  void _addPoint(Offset p) {
    final before = columns;
    setState(() => _points.add(p));
    // Sound a note only when the drawing crosses into a NEW beat, so a slow
    // drag doesn't machine-gun the same pitch.
    final after = columns;
    for (var c = 0; c < after.length; c++) {
      final row = after[c];
      if (row != null && before[c] != row) {
        context.read<AudioService>().playMidiNote(
              _rowPitches[row].midiNumber,
              ms: 260,
            );
        break;
      }
    }
  }

  // The contour → a real single-voice Score: each beat is a note or a quarter
  // rest, grouped into 4/4 bars.
  Score get _score {
    final elements = [
      for (final r in columns)
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

  bool get _hasNotes => columns.any((r) => r != null);

  void _play() {
    // Each beat is a one-note chord, or an empty list (a rest → silence), so the
    // rhythm plays back with its gaps intact.
    final beats = [
      for (final r in columns)
        if (r == null) <int>[] else [_rowPitches[r].midiNumber],
    ];
    context.read<AudioService>().playChordSequence(beats, ms: 360);
  }

  void _clear() => setState(_points.clear);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final rowColors = [
      for (final s in MelodyDoodleScreen.rowSteps) pitchClassColor(s),
    ];

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameMelodyDoodle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                l10n.melodyDoodlePrompt,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // The drawing surface.
              Expanded(
                flex: 5,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    // Record the box so the quantiser can map pixels → beats.
                    if (size != _canvas) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && size != _canvas) {
                          setState(() => _canvas = size);
                        }
                      });
                    }
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: GestureDetector(
                        key: const ValueKey('melody-doodle-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _addPoint(d.localPosition),
                        onPanUpdate: (d) => _addPoint(d.localPosition),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _DoodlePainter(
                            points: _points,
                            columns: columns,
                            rowColors: rowColors,
                            gridColor: scheme.outlineVariant,
                            inkColor: scheme.primary,
                          ),
                        ),
                      ),
                    );
                  },
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
                      label: Text(l10n.myMelodyPlay),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _hasNotes ? _clear : null,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(l10n.myMelodyClear),
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

/// Draws the beat guides, the child's freehand ink, and a coloured dot per
/// quantised beat — so they see the line *become* notes as they draw.
class _DoodlePainter extends CustomPainter {
  const _DoodlePainter({
    required this.points,
    required this.columns,
    required this.rowColors,
    required this.gridColor,
    required this.inkColor,
  });

  final List<Offset> points;
  final List<int?> columns;
  final List<Color> rowColors;
  final Color gridColor;
  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    const cols = MelodyDoodleScreen.columns;
    final rows = MelodyDoodleScreen.rowSteps.length;
    final colW = size.width / cols;
    final rowH = size.height / rows;

    // Beat guides.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var c = 1; c < cols; c++) {
      canvas.drawLine(
        Offset(c * colW, 0),
        Offset(c * colW, size.height),
        grid,
      );
    }

    // The quantised result: one dot per sounded beat, at its row.
    for (var c = 0; c < columns.length && c < cols; c++) {
      final row = columns[c];
      if (row == null) continue;
      canvas.drawCircle(
        Offset((c + 0.5) * colW, (row + 0.5) * rowH),
        (colW * 0.22).clamp(4.0, 14.0),
        Paint()..color = rowColors[row.clamp(0, rowColors.length - 1)],
      );
    }

    // The child's ink, on top.
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = inkColor.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DoodlePainter old) =>
      old.points.length != points.length || old.columns != columns;
}
