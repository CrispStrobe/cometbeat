// PLAN.md §6 tasks X5–X7 — flow control, one shape per fixture, in EVERY format.
//
// The per-effect fixtures (`make_effect_fixtures.dart`) all live in one pattern
// and never leave it, so they cannot exercise the order list at all. These do
// the opposite: almost no effects, but a real jump/break/loop, written out as
// MOD **and** XM **and** S3M **and** IT.
//
// Emitting the same musical intent into all four formats is the point. The
// formats disagree about how flow parameters are ENCODED — most sharply, the
// pattern-break row is decimal-coded in MOD/S3M/XM and plain hex in IT — so a
// reader or writer that gets one format's convention wrong renders that format
// alone at the wrong row while the other three stay right. A single-format
// fixture cannot show that; four can, because the references agree with each
// other on all four.
//
// The break target is deliberately **row 16**: the smallest interesting value
// where decimal and hex disagree (0x16 read as decimal is 16, read as hex is
// 22). A target under 10 would round-trip identically under either convention
// and prove nothing.
//
// Regenerate:  dart run tool/make_flow_fixtures.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kFxPatternBreak, kFxPositionJump;

const _rows = 64;
const _channels = 4;
const _breakTargetRow = 16;

/// A short looped saw, same shape as the effect fixtures so the two sets sound
/// like the same instrument and their numbers stay comparable.
Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final phase = 2 * math.pi * i / n;
    var v = 0.0;
    for (var k = 1; k <= 4; k++) {
      v += math.sin(phase * k) / k;
    }
    out[i] = v / 2.0834;
  }
  return out;
}

/// Our canonical pattern-break parameter is DECIMAL-coded into the two nibbles,
/// matching `setPatternBreak` and the replayer's decode. The format writers are
/// responsible for re-coding it where a format disagrees.
int _breakParam(int row) => ((row ~/ 10) << 4) | (row % 10);

/// A pattern whose rows carry a note every [every] rows, so the render has
/// enough structure for a misplaced landing row to show up as a different
/// sequence rather than just a different length.
DocPattern _notes(int pattern, {int every = 4, DocCell? lastRow}) {
  return DocPattern(
    [
      for (var r = 0; r < _rows; r++)
        [
          if (r == _rows - 1 && lastRow != null)
            lastRow
          else if (r % every == 0)
            // Walk the scale so each row is distinguishable by ear and by
            // spectrum; offset per pattern so the two patterns never alias.
            DocCell(note: 48 + pattern * 5 + (r ~/ every) % 12, instrument: 1)
          else
            DocCell.empty,
          DocCell.empty,
          DocCell.empty,
          DocCell.empty,
        ],
    ],
    _channels,
  );
}

void _emit(String name, ModuleDoc doc) {
  final targets = {
    'mod': convertToMod,
    'xm': convertToXm,
    's3m': convertToS3m,
    'it': convertToIt,
  };
  for (final entry in targets.entries) {
    final bytes = entry.value(doc);
    File('test/fixtures/flow/$name.${entry.key}').writeAsBytesSync(bytes);
    stdout.writeln('  $name.${entry.key}  ${bytes.length} bytes');
  }
}

void main() {
  Directory('test/fixtures/flow').createSync(recursive: true);
  final wave = _wave();
  stdout.writeln('X5–X7 flow fixtures:');

  ModuleDoc doc(String title, List<int> order, List<DocPattern> patterns) =>
      ModuleDoc(
        sourceFormat: ModuleFormat.mod,
        title: title,
        channelCount: _channels,
        order: order,
        samples: [DocSample(name: 'saw4', pcm: wave, loopLength: wave.length)],
        patterns: patterns,
      );

  // Dxx / Cxx — break out of pattern 0 into pattern 1 at row 16.
  //
  // This is the one that catches the decimal-vs-hex split: 40 of the 64 rows of
  // pattern 1 should be skipped. Reading the parameter with the wrong
  // convention lands on row 22 instead and plays six rows fewer, which is a
  // large, obvious divergence rather than a subtle one.
  _emit(
    'break_row16',
    doc('flow break row16', const [
      0,
      1
    ], [
      _notes(
        0,
        lastRow: DocCell(
          effect: kFxPatternBreak,
          effectParam: _breakParam(_breakTargetRow),
        ),
      ),
      _notes(1),
    ]),
  );

  // Bxx — position jump back to the first order entry, with a break in the
  // second. Jump and break interact (a break on the same row as a jump takes
  // the jump's destination and the break's row), and that interaction is a
  // classic source of divergence between replayers.
  _emit(
    'jump_and_break',
    doc('flow jump+break', const [
      0,
      1,
      2
    ], [
      _notes(0),
      _notes(
        1,
        lastRow: DocCell(
          effect: kFxPositionJump,
          effectParam: 2,
        ),
      ),
      _notes(2),
    ]),
  );

  stdout.writeln('done');
}
