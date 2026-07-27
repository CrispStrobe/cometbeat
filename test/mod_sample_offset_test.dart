// `9xx` sample offset past the end of the sample must not silence the note.
//
// ProTracker does not refuse an out-of-range offset — it clamps the play length
// to one word (`pt2_replayer.c` sampleOffset: `else { ch->n_length = 1; }`) and
// on a LOOPING sample Paula's loop then takes over, so the note keeps sounding.
// libopenmpt, libxmp and micromod all agree.
//
// We skipped the whole render block behind `offset < source.length`, so any
// offset at or past the end produced digital silence. The boundary was exact:
// with a 1349-sample buffer, `9x00` (start 0) sounded and `9x01` (start 1350 —
// ONE past the end) was already silent. Measured against the three references
// on `test/fixtures/fx/offset_9xx.mod`: 0.000 → 0.986 spectral (they agree with
// each other at 1.000). See PLAN.md §6 B1.
//
// A one-shot sample has no loop to fall back on, so silence stays correct there
// and the guard still applies — that asymmetry is the point of the fix, not an
// oversight in it.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A short audible buffer.
Float64List _wave(int n) =>
    Float64List.fromList([for (var i = 0; i < n; i++) (i.isEven ? 0.5 : -0.5)]);

int _peakOf(Uint8List wav) {
  final d = ByteData.sublistView(wav);
  var peak = 0;
  for (var i = 44; i + 1 < wav.length; i += 2) {
    final v = d.getInt16(i, Endian.little).abs();
    if (v > peak) peak = v;
  }
  return peak;
}

/// Mean absolute level over a window of the render. [fromFrame]/[frames] pick
/// the window: the START of the note is what reveals WHERE the read pointer
/// began, whereas a peak over the whole render sees every part of a looping
/// sample regardless of the offset (my first attempt at this measured the peak
/// and could not tell two different offsets apart).
double _levelAt(Uint8List wav, {int fromFrame = 0, int frames = 200}) {
  final d = ByteData.sublistView(wav);
  var sum = 0.0;
  var n = 0;
  for (var f = fromFrame; f < fromFrame + frames; f++) {
    final i = 44 + f * 2;
    if (i + 1 >= wav.length) break;
    sum += d.getInt16(i, Endian.little).abs();
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

Uint8List _render(SampleInstrument inst, int fxParam) {
  final song = TrackerSong(
    channels: [TrackerChannel(id: 'c', instrument: inst, rows: 8)],
    timing: const TrackerTiming(rows: 8),
    instruments: [inst],
  );
  song.engine.setCell(
    0,
    0,
    TrackerCell(midi: 60, instrument: 1, fxCmd: 0x9, fxParam: fxParam),
  );
  return song.renderSongWav();
}

int _renderPeak(SampleInstrument inst, int fxParam) {
  return _peakOf(_render(inst, fxParam));
}

void main() {
  group('9xx offset past the sample end', () {
    // 512 samples: `9x01` (256 units) lands inside, `9x04` (1024) is past it.
    SampleInstrument looping() => SampleInstrument(
          'loop',
          _wave(512),
          // loopStart defaults to 0 — the whole buffer loops.
          loopLength: 512,
        );

    test('a looping sample keeps sounding, as the hardware does', () {
      final inst = looping();
      expect(inst.loops, isTrue, reason: 'the fixture must actually loop');
      for (final param in [0x00, 0x01, 0x04, 0x10]) {
        expect(
          _renderPeak(inst, param),
          greaterThan(0),
          reason: '9x${param.toRadixString(16)} went silent; ProTracker clamps '
              'the length and lets the loop take over',
        );
      }
    });

    test('the offset wraps INTO the loop, not to a fixed point', () {
      // Wrapping to the loop start for every out-of-range value would sound
      // plausible and be wrong: `9x04` and `9x08` would then be identical.
      // ProTracker's length clamp leaves Paula reading from the loop at the
      // position it reached, so different offsets stay different.
      final inst = SampleInstrument(
        'loop',
        Float64List.fromList([
          for (var i = 0; i < 512; i++) (i < 256 ? 0.9 : 0.2),
        ]),
        loopLength: 512,
      );
      // Measured at the START of the note, where the read pointer began.
      final a = _levelAt(_render(inst, 0x04)); // 1024 → wraps to 0   (loud)
      final b = _levelAt(_render(inst, 0x05)); // 1280 → wraps to 256 (quiet)
      expect(
        a,
        greaterThan(b * 1.5),
        reason: 'wrapping collapsed distinct offsets: $a vs $b',
      );
    });

    test('a ONE-SHOT sample past its end is still silent', () {
      // No loop to fall back on. ProTracker's `n_length = 1` gives a click at
      // most, and the references agree; inventing sound here would be a
      // different bug.
      final inst = SampleInstrument('once', _wave(512));
      expect(inst.loops, isFalse);
      expect(_renderPeak(inst, 0x10), 0);
    });

    test('an in-range offset is untouched by the fix', () {
      final inst = looping();
      expect(_renderPeak(inst, 0x01), greaterThan(0));
    });
  });
}
