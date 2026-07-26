// Tests for the IT/S3M `S7x` per-voice ENVELOPE TOGGLES (`kFxSetPastNote`
// sub-nibbles 7..C), the completion of the S7x family:
//
//   • S77 / S78 — native VOLUME envelope OFF / ON
//   • S79 / S7A — native PAN    envelope OFF / ON
//   • S7B / S7C — native PITCH/FILTER envelope OFF / ON
//
// Each sets a persistent enable flag on the channel's `ReplayVoice`
// (volEnvEnabled / panEnvEnabled / pitchEnvEnabled, all DEFAULT enabled). When a
// flag is OFF the matching native envelope is SKIPPED for the voice, so the
// sample plays at its base volume / pan / pitch for that dimension — exactly as
// if the instrument carried no such envelope.
//
// Routing: a MultiSampleInstrument with `nativeVoiceSemantics` renders through
// the native tick voices (`_renderNativeTickZoneVoices` → the sample tick
// renderers), which is where the toggles live. A zero-depth vibrato (0x400)
// forces the per-tick native path so every render in a comparison uses the SAME
// path (a MultiSample channel only takes the native tick path when it carries a
// per-tick effect). The S7x command is placed ON the note row so the flag is set
// in the same `armRow` that triggers the note — the envelope is toggled from the
// note's very first sample.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerCell fx(int cmd, int param, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: cmd, fxParam: param);

/// Sum of |sample| over `[a, b)` — a cheap amplitude/energy proxy.
double energy(List<num> pcm, int a, int b) {
  var s = 0.0;
  for (var i = a; i < b && i < pcm.length; i++) {
    s += pcm[i].abs();
  }
  return s;
}

const int _rows = 12;

/// A one-channel, native-voice MultiSampleInstrument song over 12 rows carrying
/// [zone] as its single note-60 sample. [pattern] fills the first rows.
TrackerSong envSong(SampleInstrument zone, List<TrackerCell> pattern) {
  final cells = List<TrackerCell>.filled(_rows, TrackerCell.empty);
  for (var i = 0; i < pattern.length && i < _rows; i++) {
    cells[i] = pattern[i];
  }
  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'env',
        instrument: MultiSampleInstrument(
          'inst',
          {60: zone},
          polyphonic: true,
          nativeVoiceSemantics: true,
        ),
        rows: _rows,
      ),
    ],
    timing: const TrackerTiming(rows: _rows),
    patterns: [
      TrackerPattern(name: '00', cells: [cells]),
    ],
    order: [0],
  );
}

/// A held note-60 at row 0 (optionally carrying [sub] as an S7x on the same row)
/// plus a zero-depth vibrato at row 1 to force the native tick path.
List<TrackerCell> heldNote({int? sub}) => [
      sub == null
          ? const TrackerCell(midi: 60)
          : fx(kFxSetPastNote, sub, midi: 60),
      fx(kFxVibrato, 0x00),
    ];

/// Constant-amplitude looped sample (for the vol / pan tests).
Float64List flatSample() => Float64List(220500)..fillRange(0, 220500, 0.3);

/// A looped low sine (for the pitch test — a pitch shift changes the waveform).
Float64List sineSample() {
  final s = Float64List(44100);
  for (var i = 0; i < s.length; i++) {
    s[i] = 0.3 * sin(2 * pi * 110 * i / 44100.0);
  }
  return s;
}

void main() {
  const timing = TrackerTiming(rows: _rows);
  final rowStart = [for (var r = 0; r <= _rows; r++) timing.stepStartSample(r)];

  group('S77 / S78 — volume envelope toggle', () {
    // A clearly DECAYING volume envelope: 1.0 at onset → ~0 by ~2.2 s.
    SampleInstrument volInst() => SampleInstrument(
          'vol',
          flatSample(),
          normalize: false,
          loopLength: 220500,
          nativeVolumeEnvelope: const VolumeEnvelope([
            (ms: 0, level: 1.0),
            (ms: 2200, level: 0.02),
          ]),
        );

    // Compare an EARLY window (rows 1–3) against a LATE window (rows 8–10).
    double early(List<num> pcm) => energy(pcm, rowStart[1], rowStart[4]);
    double late(List<num> pcm) => energy(pcm, rowStart[8], rowStart[11]);

    test('baseline follows the envelope (decays); S77 flattens it', () {
      final base = replaySong(envSong(volInst(), heldNote())).pcm;
      final off = replaySong(envSong(volInst(), heldNote(sub: 0x7))).pcm; // S77

      // Baseline: the decaying envelope shapes the note — late ≪ early.
      expect(
        late(base),
        lessThan(early(base) * 0.6),
        reason: 'the volume envelope must clearly decay the baseline note',
      );

      // S77: the envelope is skipped — the note plays at flat base volume, so
      // the amplitude no longer follows the (decaying) envelope: late ≈ early.
      expect(
        late(off),
        closeTo(early(off), early(off) * 0.1),
        reason: 'S77 removes the envelope shaping → flat amplitude',
      );
      // And the late (formerly decayed) region is now much louder than baseline.
      expect(late(off), greaterThan(late(base) * 1.4));
    });

    test('S78 re-enables the volume envelope (decays again)', () {
      final on = replaySong(envSong(volInst(), heldNote(sub: 0x8))).pcm; // S78
      expect(
        late(on),
        lessThan(early(on) * 0.6),
        reason: 'S78 restores the envelope → the note decays again',
      );
    });
  });

  group('S79 / S7A — pan envelope toggle (stereo path)', () {
    // Pan sweeps hard LEFT → hard RIGHT over the first 0.8 s, then holds RIGHT.
    SampleInstrument panInst() => SampleInstrument(
          'pan',
          flatSample(),
          normalize: false,
          loopLength: 220500,
          nativePanEnvelope: const PanEnvelope([
            (ms: 0, pan: -1.0),
            (ms: 800, pan: 1.0),
          ]),
        );

    // Late window (rows 8–10): the pan envelope holds hard RIGHT there.
    double sideBias(List<double> l, List<double> r) =>
        energy(r, rowStart[8], rowStart[11]) -
        energy(l, rowStart[8], rowStart[11]);

    test('baseline pans right; S79 centres it; S7A restores', () {
      final base = songStereoFloat(envSong(panInst(), heldNote()));
      final off =
          songStereoFloat(envSong(panInst(), heldNote(sub: 0x9))); // S79
      final on = songStereoFloat(envSong(panInst(), heldNote(sub: 0xA))); // S7A

      final baseR = energy(base.right, rowStart[8], rowStart[11]);
      final baseL = energy(base.left, rowStart[8], rowStart[11]);
      expect(
        baseR,
        greaterThan(baseL * 4),
        reason: 'the pan envelope drives the late note hard right',
      );

      // S79: no pan envelope → the mono sample sits centred, L == R.
      final offR = energy(off.right, rowStart[8], rowStart[11]);
      final offL = energy(off.left, rowStart[8], rowStart[11]);
      expect(
        offR,
        closeTo(offL, offL * 0.02 + 1e-9),
        reason: 'S79 removes the pan envelope → centred (L == R)',
      );
      expect(
        sideBias(off.left, off.right),
        lessThan(sideBias(base.left, base.right) * 0.1),
        reason: 'S79 collapses the right-side bias the envelope created',
      );

      // S7A: the pan envelope is back → hard right again.
      expect(
        energy(on.right, rowStart[8], rowStart[11]),
        greaterThan(energy(on.left, rowStart[8], rowStart[11]) * 4),
        reason: 'S7A restores the pan envelope',
      );
    });
  });

  group('S7B / S7C — pitch envelope toggle', () {
    // A constant +7-semitone pitch offset — an audible, immediate pitch shift.
    SampleInstrument pitchInst({bool withEnv = true}) => SampleInstrument(
          'pitch',
          sineSample(),
          normalize: false,
          loopLength: 44100,
          nativePitchEnvelope:
              withEnv ? const PitchEnvelope([(ms: 0, semitones: 7.0)]) : null,
        );

    bool samePcm(Int16List a, Int16List b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    test('S7B off == no pitch envelope, and differs from the shifted note', () {
      final shifted = replaySong(envSong(pitchInst(), heldNote())).pcm;
      final off =
          replaySong(envSong(pitchInst(), heldNote(sub: 0xB))).pcm; // S7B
      final noEnv =
          replaySong(envSong(pitchInst(withEnv: false), heldNote())).pcm;

      // Skipping the pitch envelope reproduces the un-shifted note exactly.
      expect(
        samePcm(off, noEnv),
        isTrue,
        reason: 'S7B (pitch env off) == an instrument with no pitch envelope',
      );
      // And it is audibly different from the +7-semitone shifted baseline.
      expect(
        samePcm(off, shifted),
        isFalse,
        reason: 'the pitch envelope shifts the note; S7B removes that shift',
      );
    });

    test('S7C re-enables the pitch envelope (matches the shifted note)', () {
      final shifted = replaySong(envSong(pitchInst(), heldNote())).pcm;
      final on =
          replaySong(envSong(pitchInst(), heldNote(sub: 0xC))).pcm; // S7C
      expect(
        samePcm(on, shifted),
        isTrue,
        reason: 'S7C restores the pitch envelope',
      );
    });
  });

  group('byte-identity — the toggles are inert without an S7x', () {
    test('a no-S7x render is deterministic through the S7x code path', () {
      final inst = SampleInstrument(
        'x',
        flatSample(),
        normalize: false,
        loopLength: 220500,
        nativeVolumeEnvelope: const VolumeEnvelope([
          (ms: 0, level: 1.0),
          (ms: 2200, level: 0.2),
        ]),
      );
      final a = replaySong(envSong(inst, heldNote())).pcm;
      final b = replaySong(envSong(inst, heldNote())).pcm;
      expect(a.length, b.length);
      var same = true;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          same = false;
          break;
        }
      }
      expect(same, isTrue, reason: 'no-S7x render must be byte-stable');
    });
  });

  group('regression — S70..S76 (past-note / set-NNA) still work', () {
    // Adding the 7..C toggle handling to armRow must not disturb the 0..6
    // note-run passes. A two-note NNA=cut channel: S74 (set NNA=continue) keeps
    // the predecessor ringing where S73 (set NNA=cut) removes it.
    TrackerSong nnaSong(int sub) {
      final cells = List<TrackerCell>.filled(_rows, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 60);
      cells[2] = fx(kFxSetPastNote, sub); // set-NNA + forces the tick path
      cells[4] = const TrackerCell(midi: 60);
      return TrackerSong.fromParts(
        channels: [
          TrackerChannel(
            id: 'nna',
            instrument: MultiSampleInstrument(
              'inst',
              {
                60: SampleInstrument(
                  'zone',
                  flatSample(),
                  normalize: false,
                  // Instrument default NNA (0) = cut.
                  nativeFadeout: 8,
                  loopLength: 220500,
                ),
              },
              polyphonic: true,
              nativeVoiceSemantics: true,
            ),
            rows: _rows,
          ),
        ],
        timing: const TrackerTiming(rows: _rows),
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );
    }

    test('S74 (continue) keeps both voices ringing where S73 (cut) leaves one',
        () {
      final s74 = replaySong(nnaSong(0x4)).pcm; // set NNA = continue
      final s73 = replaySong(nnaSong(0x3)).pcm; // set NNA = cut
      final a = rowStart[6], b = rowStart[8];
      expect(
        energy(s74, a, b),
        greaterThan(energy(s73, a, b) * 1.3),
        reason: 'S73..S76 must still drive the NNA override after the change',
      );
    });
  });
}
