// An XM channel is monophonic: a new note replaces what the channel was
// playing.
//
// PLAN.md §6 X8. Our XM importer built each instrument as a
// `MultiSampleInstrument(polyphonic: true)` — the flag whose own doc comment
// reads "notes are not choked by subsequent notes on the channel (drum kit
// mode)". Every note in every XM therefore rang on forever and SUMMED with its
// successors. FastTracker II has no NNA; that is Impulse Tracker's addition,
// which is why the IT pool sets `nativeVoiceSemantics` alongside `polyphonic`
// and the XM pool has no business claiming either.
//
// Found by writing ONE song into all four formats and rendering each: MOD, S3M
// and IT sat at 0.999 spectral against libopenmpt and libxmp while the XM sat
// at 0.731 with the SAME duration — so not a flow bug, a content one. Our XM
// render measured 3.4x the RMS of our own MOD render of the same song and 6x
// libopenmpt's, saturating the limiter hard enough that the envelope
// correlation against both was 0.09. Removing the flag took the XM to 0.999.
//
// ⚠️ The obvious test — "the same song in two formats must render at the same
// LEVEL" — is not a real invariant, and writing it first was a mistake worth
// recording. Per-format mixing volume is implementation-defined and the
// reference players disagree with each other about it substantially: for one
// song, libopenmpt renders S3M at 0.493 of the MOD level and libxmp at 0.353;
// XM is 0.676 against 0.901. There is no bar to hold there. What IS invariant
// is that repeated notes on one channel must not ACCUMULATE, which is what
// these tests measure and what was actually broken.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// A short looped saw, so notes SUSTAIN and stacking has something to stack.
/// With a one-shot sample the bug would be invisible.
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

/// One sounding channel, a new note every four rows, walking up a scale.
///
/// The notes must DIFFER. Repeating the same note every four rows does not
/// reproduce the bug — the channel walker appears to fold consecutive identical
/// triggers into a single run, so there is only ever one voice to stack. A test
/// built on a repeated note passed cheerfully with the defect in place.
ModuleDoc _retriggeredNote() {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'monophony',
    channelCount: 4,
    order: const [0],
    samples: [DocSample(name: 'saw4', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < 64; r++)
            [
              if (r % 4 == 0)
                DocCell(note: 48 + (r ~/ 4) % 12, instrument: 1)
              else
                DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        4,
      ),
    ],
  );
}

/// Mono RMS over the fraction of the render between [from] and [to] (0..1).
double _rmsWindow(Uint8List wav, double from, double to) {
  final data = ByteData.sublistView(wav);
  final total = (wav.length - 44) ~/ 2;
  final start = (total * from).floor();
  final end = (total * to).floor();
  var sum = 0.0;
  var n = 0;
  for (var i = start; i < end; i++) {
    final v = data.getInt16(44 + i * 2, Endian.little) / 32768.0;
    sum += v * v;
    n++;
  }
  return n == 0 ? 0 : math.sqrt(sum / n);
}

void main() {
  /// The level at the END of the pattern over the level at the START.
  ///
  /// One voice at a time keeps this near 1: every window holds the same note at
  /// the same volume. Voices that are never choked make it climb, because the
  /// sixteenth note is sounding on top of fifteen predecessors.
  double growth(Uint8List module) {
    final wav = songFromModuleBytes(module).renderSongWav();
    final first = _rmsWindow(wav, 0.02, 0.12);
    final last = _rmsWindow(wav, 0.85, 0.95);
    expect(first, greaterThan(0.005), reason: 'the fixture must sound');
    return last / first;
  }

  test('XM: a retriggered note does not pile up on itself', () {
    expect(
      growth(convertToXm(_retriggeredNote())),
      lessThan(1.5),
      reason: 'the sixteenth trigger is sounding on top of its predecessors — '
          'the XM instrument pool is polyphonic again',
    );
  });

  test('and neither do MOD, S3M or IT', () {
    // Controls. They were never affected, and they keep this test honest: if a
    // change ever makes EVERY format accumulate, the XM assertion alone would
    // not tell you the cause is shared.
    final doc = _retriggeredNote();
    for (final entry in {
      'mod': convertToMod(doc),
      's3m': convertToS3m(doc),
      'it': convertToIt(doc),
    }.entries) {
      expect(
        growth(entry.value),
        lessThan(1.5),
        reason: '${entry.key} accumulated voices',
      );
    }
  });
}
