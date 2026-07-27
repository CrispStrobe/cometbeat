// PLAN.md §6 task X10 — the sample-playback layer, one property per fixture.
//
// This is the layer BENEATH everything else on the ladder: effects and flow all
// resolve to "read the sample at this position with this volume", and if the
// read pointer is wrong none of the rest can be right. It is also where a
// one-sample rounding error once turned `SampleInstrument.loops` false and made
// every held note a ~30 ms click on the commonest MOD loop layout — 0.746
// spectral against libopenmpt, and completely invisible to structure-only tests.
//
// These are **XM**, not MOD. MOD samples are 8-bit with forward loops only, so a
// MOD fixture cannot exercise ping-pong or 16-bit at all. That drops micromod
// (MOD only) and leaves openmpt123 and libxmp — two independent engines, which
// is still enough for the inter-reference baseline the audit gates on.
//
// The waveform is deliberately a RAMP across the loop region rather than a sine.
// A ramp read forward and wrapped is a sawtooth (one discontinuity per loop);
// the same ramp bounced is a triangle (no discontinuity). So the two loop types
// have obviously different spectra, and a fixture that plays the wrong one — or
// wraps a sample off by one — cannot quietly resemble the right answer.
//
// Regenerate:  dart run tool/make_sample_fixtures.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _rows = 32;
const _channels = 4;
const _note = 60;

/// A ramp from −1 to +1 over [n] samples.
///
/// Read forward and wrapped this is a sawtooth; bounced it is a triangle. The
/// harmonic series of the two differ sharply (a sawtooth has every harmonic, a
/// triangle only the odd ones, falling much faster), which is exactly the
/// contrast that makes a wrong loop type impossible to mistake for a right one.
Float64List _ramp(int n) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = -1.0 + 2.0 * i / (n - 1);
  }
  return out;
}

/// One fixture: a single note on channel 0, held for the whole pattern so the
/// loop (or its absence) is what fills the time.
void _emit(String name, DocSample sample) {
  final doc = ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'sample $name',
    channelCount: _channels,
    order: const [0],
    samples: [sample],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < _rows; r++)
            [
              if (r == 0)
                const DocCell(note: _note, instrument: 1, volume: 64)
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
  final bytes = convertToXm(doc);
  File('test/fixtures/sample/$name.xm').writeAsBytesSync(bytes);
  stdout.writeln('  $name.xm  ${bytes.length} bytes');
}

void main() {
  Directory('test/fixtures/sample').createSync(recursive: true);
  stdout.writeln('X10 sample-playback fixtures:');

  // A plain forward loop over the whole sample — the commonest layout there is,
  // and the one the rescale bug broke.
  _emit(
    'loop_forward',
    DocSample(name: 'ramp', pcm: _ramp(512), loopLength: 512),
  );

  // The same sample bounced. Against `loop_forward` this isolates the loop TYPE
  // from everything else: identical PCM, identical length, different fold.
  _emit(
    'loop_pingpong',
    DocSample(name: 'ramp', pcm: _ramp(512), loopLength: 512, pingPong: true),
  );

  // A SHORT loop inside a longer sample: 32 frames of loop after a 256-frame
  // lead-in. Short loops are where wrap arithmetic is least forgiving — an
  // off-by-one is a 3% pitch error here and inaudible at 512.
  _emit(
    'loop_short',
    DocSample(
      name: 'ramp',
      pcm: _ramp(288),
      loopStart: 256,
      loopLength: 32,
    ),
  );

  // 16-bit. The PCM is identical to `loop_forward`; only the storage width
  // differs, so any divergence is the reader's bit-depth path and nothing else.
  _emit(
    'sample_16bit',
    DocSample(
      name: 'ramp16',
      pcm: _ramp(512),
      loopLength: 512,
      sixteenBit: true,
    ),
  );

  // No loop at all, held far past the end. The note must STOP; a reader that
  // wraps anyway would sustain, and one that reads past the buffer would emit
  // noise. Both are loud failures against a reference that simply goes quiet.
  _emit('oneshot_held', DocSample(name: 'ramp', pcm: _ramp(512)));

  stdout.writeln('done — one note each, 32 rows, held to the end');
}
