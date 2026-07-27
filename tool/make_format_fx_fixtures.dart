// PLAN.md §6 X9 — effects that exist only OUTSIDE the ProTracker command set.
//
// Every fixture in `test/fixtures/fx/` is a MOD, so nothing in the audit
// exercises the S3M/IT command set at all. That matters because those formats
// carry effects MOD has no encoding for, and `module_convert.dart` maps several
// of them with an approximation its own comment admits to:
//
//     case 4: // D — volume slide (Dxy: x up / y down — matches our Axy; fine
//       //     slides with an 0xF nibble are approximated as a normal slide)
//
// A FINE slide is not a small normal slide — it is a different mechanism. `DF2`
// slides by 2 ONCE, on tick 0 of the row. The MOD `Axy` it becomes slides every
// tick for the whole row. At the default speed of 6 that is five extra
// applications of a much larger nibble, so "approximated" may be understating
// it by an order of magnitude. The same shape applies to `EFx`/`FFx` (fine
// portamento) and `EEx`/`FEx` (EXTRA fine, a quarter step).
//
// These fixtures are authored as doc cells whose MOD-numbered effect converts to
// the S3M/IT letter command we want, then written as **S3M and IT**. The MOD
// rendering of the same cell means something else entirely, which is precisely
// why the effect needs its own per-format fixture rather than a shared one.
//
// Regenerate:  dart run tool/make_format_fx_fixtures.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _rows = 32;
const _channels = 4;
const _note = 60;

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

/// One note on channel 0, then [effect]/[param] for [holdRows] rows.
///
/// [holdRows] matters and defaults to 8, not the whole pattern. X1 already
/// learned this the hard way on the MOD portamento fixtures: held for all 31
/// rows a slide runs off the end of the period table and CLAMPING dominates,
/// at which point the fixture measures the reference players' clamp policies
/// rather than our slide — and they disagree with each other about those. I
/// repeated the mistake here on the first cut and had to bound it again.
///
/// Written as S3M **and** IT: they share the letter command set, so a
/// divergence in one and not the other localises the fault to that reader
/// rather than to the shared conversion.
void _emit(
  String name,
  int effect,
  int param, {
  int volume = 64,
  int holdRows = 8,
}) {
  final wave = _wave();
  final doc = ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'fmt $name',
    channelCount: _channels,
    order: const [0],
    samples: [DocSample(name: 'saw4', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < _rows; r++)
            [
              if (r == 0)
                DocCell(note: _note, instrument: 1, volume: volume)
              else if (r <= holdRows)
                DocCell(effect: effect, effectParam: param)
              else
                DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        _channels,
      ),
    ],
  );
  for (final entry in {'s3m': convertToS3m, 'it': convertToIt}.entries) {
    final bytes = entry.value(doc);
    File('test/fixtures/fmt/$name.${entry.key}').writeAsBytesSync(bytes);
    stdout.writeln('  $name.${entry.key}  ${bytes.length} bytes');
  }
}

void main() {
  Directory('test/fixtures/fmt').createSync(recursive: true);
  stdout.writeln('X9 per-format effect fixtures (S3M/IT letter commands):');

  // Dxy volume slide, the ordinary per-tick forms first as CONTROLS. If these
  // deviate too then the problem is the whole D mapping, not the fine variants.
  _emit('volslide_down_D0y', 0xA, 0x02, holdRows: 12);
  _emit('volslide_up_Dx0', 0xA, 0x20, volume: 8, holdRows: 12);

  // DFx / DxF — FINE volume slide, once per row rather than once per tick.
  _emit('fine_volslide_down_DFx', 0xA, 0xF2, holdRows: 20);
  _emit('fine_volslide_up_DxF', 0xA, 0x2F, volume: 8, holdRows: 20);

  // Exx / Fxx portamento: plain (control), fine (Ex F), extra fine (Ex E).
  _emit('porta_down_Exx', 0x2, 0x04);
  _emit('fine_porta_down_EFx', 0x2, 0xF4, holdRows: 20);
  _emit('extrafine_porta_down_EEx', 0x2, 0xE4, holdRows: 20);
  _emit('porta_up_Fxx', 0x1, 0x04);
  _emit('fine_porta_up_FFx', 0x1, 0xF4, holdRows: 20);

  stdout.writeln('done — S3M + IT, one command each, 32 rows, speed 6/125');
}
