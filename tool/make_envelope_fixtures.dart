// PLAN.md §6 — envelopes and fadeout, the last unmeasured layer of the ladder.
//
// MOD and S3M have no envelopes, so every fixture here is **XM and IT**, and
// they are authored differently on purpose: XM hangs the envelope off the
// SAMPLE, IT off a separate instrument record. Writing the same musical intent
// through both encodings is what makes a divergence in one and not the other
// point at that writer rather than at the shaping model.
//
// ⚠️ **These fixtures are less independent than the rest of the suite, and it
// matters more here.** Everything in `fmt/` is written by our own writer, but
// an effect command is a byte — if we write the wrong one, the references play
// something obviously different and the error shows. An ENVELOPE is a shape,
// and if our writer encodes the shape wrongly then both references read the
// same wrong shape, agree with each other perfectly, and our replayer reads the
// same file back: the error cancels and the sweep goes green while every real
// module still plays wrong.
//
// So each shape below is chosen to be checkable ARITHMETICALLY from the render
// alone — a ramp whose length in ticks is known in advance — and
// `envelope_shape_test.dart` asserts that against the reference render rather
// than against us. That is the part our writer cannot fake.
//
// Regenerate:  dart run tool/make_envelope_fixtures.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';

const _rows = 32;
const _channels = 4;
const _note = 60;

/// A bright, steady tone. Envelopes shape LEVEL, so the carrier wants a stable
/// spectrum and no decay of its own — anything that fades on its own would be
/// indistinguishable from the envelope under test.
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

/// A volume envelope that RAMPS from silence to full over [attackTicks] and
/// then holds.
///
/// A ramp is the shape to use because its length is a number: at speed 6 an
/// attack of 24 ticks is exactly four rows, so "how long until full volume"
/// can be read off any render and compared against arithmetic. A decay or a
/// curve would only ever be comparable to another render of the same file.
DocEnvelope _rampUp(int attackTicks) => DocEnvelope(
      points: [(0, 0), (attackTicks, 64), (attackTicks + 96, 64)],
      enabled: true,
    );

/// A pan envelope sweeping hard left to hard right over [ticks]. 32 is centre.
DocEnvelope _panSweep(int ticks) => DocEnvelope(
      points: [(0, 0), (ticks, 64), (ticks + 96, 64)],
      enabled: true,
    );

/// [noteRows] carry a fresh note; everything else is empty so the note rings.
ModuleDoc _doc({
  required List<int> noteRows,
  DocEnvelope volume = const DocEnvelope(),
  DocEnvelope pan = const DocEnvelope(),
  int fadeout = 0,
  int keyOffRow = -1,
}) {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'env',
    channelCount: _channels,
    order: const [0],
    samples: [
      DocSample(
        name: 'saw4',
        pcm: wave,
        loopLength: wave.length,
        volumeEnvelope: volume,
        panEnvelope: pan,
      ),
    ],
    // IT keeps envelopes on an instrument record rather than on the sample, so
    // the same intent has to be stated twice. `convertToIt` reads this list;
    // `convertToXm` reads the sample above.
    itInstruments: [
      DocInstrument(
        name: 'saw4',
        volumeEnvelope: volume,
        panEnvelope: pan,
        fadeout: fadeout,
        // IT keymaps are 1-BASED sample numbers; 0 means "no sample", which
        // renders as silence. Caught by checking that the REFERENCE showed the
        // authored shape before comparing anything to us — the whole point of
        // the arithmetic check, since a silent file we also rendered silent
        // would have "agreed" perfectly.
        keymap: List<int>.filled(120, 1),
      ),
    ],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < _rows; r++)
            [
              if (noteRows.contains(r))
                const DocCell(note: _note, instrument: 1, volume: 64)
              else if (r == keyOffRow)
                const DocCell.off()
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
}

void _emit(String name, ModuleDoc doc) {
  for (final entry in {'xm': convertToXm, 'it': convertToIt}.entries) {
    final bytes = entry.value(doc);
    File('test/fixtures/env/$name.${entry.key}').writeAsBytesSync(bytes);
    stdout.writeln('  $name.${entry.key}  ${bytes.length} bytes');
  }
}

void main() {
  Directory('test/fixtures/env').createSync(recursive: true);
  stdout.writeln('envelope fixtures (XM + IT):');

  // The SHAPE, on a single note. 24 ticks = four rows at speed 6.
  _emit('env_vol_ramp', _doc(noteRows: const [0], volume: _rampUp(24)));

  // The same envelope, hit TWICE. This is the fixture the whole set exists for:
  // XM/IT envelopes belong to the INSTRUMENT and restart on every note, but our
  // importer also folds them onto the CHANNEL, and a channel-level envelope has
  // nowhere to put "restart". If the second note does not fade in again, that
  // is what happened. Row 12 is well past the 4-row attack, so a restart is
  // unmistakable rather than a subtlety.
  _emit('env_vol_retrig', _doc(noteRows: const [0, 12], volume: _rampUp(24)));

  // A SHORT attack against the long one above. If the envelope is being applied
  // twice (instrument AND channel) the error grows with the ramp, so two ramp
  // lengths separate a double application from a wrong rate.
  _emit('env_vol_fast', _doc(noteRows: const [0], volume: _rampUp(6)));

  // Pan envelope — invisible to every metric except the pan trajectory, which
  // is exactly why panning went unmeasured until that metric existed.
  _emit('env_pan_sweep', _doc(noteRows: const [0], pan: _panSweep(24)));

  // Fadeout after a key-off. IT's fadeout only runs once the note is released,
  // so this needs the key-off to mean something — and key-off is the command
  // XM's `14h` turned out to be, which the tremor pass fixed.
  _emit(
    'env_fadeout',
    _doc(noteRows: const [0], fadeout: 256, keyOffRow: 8),
  );

  stdout.writeln('done — one note each unless stated, 32 rows, speed 6/125');
}
