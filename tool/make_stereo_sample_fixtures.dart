// PLAN.md §6 X10 — STEREO samples, the last unmeasured thing in the sample
// layer.
//
// Every sample fixture so far is mono, so nothing has ever asked whether a
// stereo sample survives the round trip and reaches both ears. IT is the only
// one of our four formats that stores them (flag `0x04`; XM samples are mono by
// definition, and MOD/S3M do not have the concept), so these are IT only, which
// leaves libopenmpt and libxmp as the two references.
//
// **The signature is deliberately extreme: a tone in the LEFT channel and
// silence in the RIGHT.** A subtle difference between the two sides would be
// exactly the kind of thing a mono downmix hides — which is not hypothetical,
// it is how panning went unmeasured through this entire audit until the pan
// metric was added. Hard left is unmissable in any metric, including the ones
// that were blind before.
//
// The mono fixture beside it is the CONTROL: identical notes, identical length,
// one channel of PCM. If both render alike, the stereo payload is being dropped
// somewhere and the "stereo" fixture is only proving that mono still works.
//
// Regenerate:  dart run tool/make_stereo_sample_fixtures.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _rows = 24;
const _channels = 4;
const _note = 60;

Float64List _sine(int n, {double amplitude = 1.0}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amplitude * math.sin(2 * math.pi * i / n);
  }
  return out;
}

Float64List _silence(int n) => Float64List(n);

/// One held note, so whatever the sample is doing fills the whole render.
ModuleDoc _doc(DocSample sample) => ModuleDoc(
      sourceFormat: ModuleFormat.mod,
      title: 'stereo',
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

void _emit(String name, DocSample sample) {
  final bytes = convertToIt(_doc(sample));
  File('test/fixtures/stereo/$name.it').writeAsBytesSync(bytes);
  stdout.writeln('  $name.it  ${bytes.length} bytes');
}

void main() {
  Directory('test/fixtures/stereo').createSync(recursive: true);
  stdout.writeln('X10 stereo-sample fixtures (IT only):');
  const n = 256;

  // The CONTROL: one channel of PCM, nothing else different.
  _emit(
    'sample_mono',
    DocSample(name: 'mono', pcm: _sine(n), loopLength: n),
  );

  // Hard left: a tone on the left, silence on the right. A render that drops
  // the stereo payload plays this centred and identical to the control.
  _emit(
    'sample_stereo_left',
    DocSample(
      name: 'left',
      pcm: _sine(n),
      pcmRight: _silence(n),
      loopLength: n,
    ),
  );

  // The mirror. Two fixtures rather than one because a SIGN error — left and
  // right swapped — is invisible in a single-sided test: it would still measure
  // "hard to one side", just the wrong one.
  _emit(
    'sample_stereo_right',
    DocSample(
      name: 'right',
      pcm: _silence(n),
      pcmRight: _sine(n),
      loopLength: n,
    ),
  );

  stdout.writeln('done — one held note, 24 rows');
}
