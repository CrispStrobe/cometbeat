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
  Map<String, Uint8List Function(ModuleDoc)> formats = const {},
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
  final targets =
      formats.isEmpty ? {'s3m': convertToS3m, 'it': convertToIt} : formats;
  for (final entry in targets.entries) {
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

  // --- PANNING: invisible to every metric the sweep had ----------------------
  //
  // The sweep downmixes both sides to mono before comparing, so a pan effect
  // cannot register at all — the same shape of blind spot as spectral being
  // amplitude-invariant (which hid tremolo's 4x depth) and the reason the
  // envelope metric had to be added. These fixtures exist so the pan metric has
  // something to prove itself against.
  //
  // Yxy panbrello is also the one LFO whose rate I deliberately left
  // unverified: ProTracker has no panbrello, so the 64/x finding that fixed
  // vibrato said nothing about it, and IT's own rule is different again
  // (a 256-entry table stepped by the speed nibble). It has been sitting on
  // 32/x with a comment admitting as much.
  _emit('panbrello_Yxy', 0x1E, 0x48, holdRows: 24);
  // A slower, deeper one: if the RATE is wrong the two disagree about how many
  // sweeps fit in the run, which is far easier to see than a single cycle.
  _emit('panbrello_slow_Yxy', 0x1E, 0x28, holdRows: 24);

  // Xxx set-pan, held STATIC — the control that separates a depth error from a
  // pan-LAW difference.
  //
  // Panbrello's travel came out 0.89 against the references' 0.98, and travel
  // alone cannot say why: our pan value is +/-0.533 and constant-power panning
  // maps that to a measured balance of +/-0.445, so the numbers are
  // self-consistent whether the DEPTH is 9% shallow or the LAW differs. A fixed
  // pan position has no depth in it, so whatever it shows is the law.
  //
  // 0xC0 is three-quarters right. Linear panning would measure +0.50 there;
  // constant power measures +0.414. The two are far enough apart to read off.
  _emit('setpan_right_Xxx', 0x8, 0xC0, holdRows: 24);
  _emit('setpan_left_Xxx', 0x8, 0x40, holdRows: 24);

  // Ixy tremor — the last effect in the set with no audio fixture at all.
  //
  // On for x ticks, off for y, repeating. A pure VOLUME effect, so the spectral
  // gate is blind to it by construction and only the envelope metric can say
  // anything — which is precisely why it went unmeasured until that metric
  // existed. There IS a trajectory test (`tracker_effect_coverage_test`), so
  // the arithmetic has been pinned; what has never been checked is whether the
  // arithmetic matches what a tracker actually does.
  //
  // 3 on / 2 off at speed 6 gives a pattern that does not divide evenly into
  // the row, so a per-row rather than per-tick implementation drifts visibly
  // instead of coincidentally agreeing.
  //
  // Also written as XM, which the other fixtures here are not. FastTracker II
  // is the one tracker that runs tremor differently (it skips tick 0 and reads
  // a zero nibble literally), and that difference is now a profile field — so
  // it needs a fixture of its own rather than being taken on the reference
  // players' word. `I32` has no zero nibble, so what this one measures is the
  // tick-0 half of the rule.
  _emit(
    'tremor_Ixy',
    0x1D,
    0x32,
    holdRows: 24,
    formats: {'s3m': convertToS3m, 'it': convertToIt, 'xm': convertToXm},
  );

  // `I00` — both nibbles zero, and no earlier parameter to fall back on.
  //
  // Our trajectory test asserted this "leaves the note fully on" (cycle 0 → no
  // gate), which was an assumption nobody had checked. libxmp says otherwise:
  // outside FT2 a zero nibble is incremented to ONE, so `I00` alternates every
  // tick. That is a source reading rather than a measurement, and a source
  // reading is exactly what was not enough for the tremor counter itself — so
  // it gets a fixture instead of a footnote.
  _emit(
    'tremor_I00',
    0x1D,
    0x00,
    holdRows: 24,
    formats: {'s3m': convertToS3m, 'it': convertToIt, 'xm': convertToXm},
  );

  stdout.writeln('done — S3M + IT, one command each, 32 rows, speed 6/125');
}
