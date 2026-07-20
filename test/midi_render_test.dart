// renderMidiFile — the event-accurate MIDI synth: schedules events on a sample
// clock and voices them through a SoundFont. Uses the shared in-test SF2 fixture
// so no real font/network is needed.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/midi_render.dart';
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

List<int> _v(int n) => n < 128 ? [n] : [((n >> 7) & 0x7f) | 0x80, n & 0x7f];
List<int> _cc(int c, int cc, int val) => [0, 0xB0 | c, cc, val];
List<int> _note(int c, int k, int dur) =>
    [0, 0x90 | c, k, 0x64, ..._v(dur), 0x80 | c, k, 0];
List<int> _mtrk(List<int> body) {
  final b = [...body, 0x00, 0xFF, 0x2F, 0x00];
  return [
    ...'MTrk'.codeUnits,
    (b.length >> 24) & 0xff,
    (b.length >> 16) & 0xff,
    (b.length >> 8) & 0xff,
    b.length & 0xff,
    ...b,
  ];
}

Uint8List _midi(List<int> trackBody) => Uint8List.fromList([
      ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0, //
      ..._mtrk(trackBody),
    ]);

double _peak(Float64List x) {
  var p = 0.0;
  for (final s in x) {
    if (s.abs() > p) p = s.abs();
  }
  return p;
}

void main() {
  final font = loadSoundFont(velSplitSf2(sineI16(2000, 8), sineI16(2000, 64)));

  test('renders a MIDI to non-silent stereo', () {
    final smf = _midi([
      for (final k in [60, 64, 67]) ..._note(0, k, 240),
    ]);
    final (left, right) = renderMidiFile(smf, font);
    expect(left, isNotEmpty);
    expect(right.length, left.length);
    expect(_peak(left) + _peak(right), greaterThan(0.0));
  });

  test('CC10 pan places a note in the stereo field', () {
    // Hard left (CC10 = 0) → louder on the left; hard right (127) → the reverse.
    final leftSmf = _midi([..._cc(0, 10, 0), ..._note(0, 60, 480)]);
    final rightSmf = _midi([..._cc(0, 10, 127), ..._note(0, 60, 480)]);
    final (l0, r0) = renderMidiFile(leftSmf, font);
    final (l1, r1) = renderMidiFile(rightSmf, font);
    expect(_peak(l0), greaterThan(_peak(r0)));
    expect(_peak(r1), greaterThan(_peak(l1)));
  });

  test('velocity → cutoff: a soft note is duller than a loud note', () {
    List<int> note(int vel) => [0, 0x90, 60, vel, 0x83, 0x60, 0x80, 60, 0];
    // A crude high-frequency proxy: mean |x[n] − x[n−1]| relative to level.
    double brightnessOf(Float64List x) {
      var hf = 0.0, energy = 0.0;
      for (var i = 1; i < x.length; i++) {
        hf += (x[i] - x[i - 1]).abs();
        energy += x[i].abs();
      }
      return energy == 0 ? 0 : hf / energy;
    }

    final (soft, _) = renderMidiFile(_midi(note(24)), font);
    final (loud, _) = renderMidiFile(_midi(note(120)), font);
    expect(
      brightnessOf(loud),
      greaterThan(brightnessOf(soft)),
      reason: 'the louder note keeps more high frequencies',
    );
  });

  test('pitch bend raises the note pitch (more zero-crossings)', () {
    // Zero-crossings over the sounding head — a monotone proxy for pitch. (The
    // fixture sample is short + non-looping, so the sound lives at the start.)
    int zc(Float64List x) {
      final n = x.length < 2000 ? x.length : 2000;
      var z = 0;
      for (var i = 1; i < n; i++) {
        if ((x[i] >= 0) != (x[i - 1] >= 0)) z++;
      }
      return z;
    }

    final plain = _midi(_note(0, 60, 496));
    // Pitch bend to +2 semitones at tick 0, then the same note.
    final bent = _midi([
      0, 0xE0, 0x00, 0x7F, // pitch bend ≈ max (+2 st) at tick 0
      ..._note(0, 60, 496),
    ]);
    final (pl, _) = renderMidiFile(plain, font);
    final (bt, _) = renderMidiFile(bent, font);
    expect(bt, isNot(pl), reason: 'the bend changes the audio');
    expect(zc(bt), greaterThan(zc(pl)), reason: 'bent up → higher pitch');
  });

  test('reverb send (CC91) wets the output when a master mix is set', () {
    final smf = _midi([..._cc(0, 91, 127), ..._note(0, 60, 240)]);
    final (dry, _) = renderMidiFile(smf, font); // reverbMix 0 → dry
    final (wet, _) = renderMidiFile(smf, font, reverbMix: 0.6);
    expect(wet, isNot(dry));
    double energy(Float64List x) {
      var s = 0.0;
      for (final v in x) {
        s += v * v;
      }
      return s;
    }

    expect(energy(wet), greaterThan(energy(dry)), reason: 'reverb adds energy');
  });

  test('soft pedal (CC67) makes a note quieter', () {
    final loud = _midi([..._note(0, 60, 240)]);
    final soft = _midi([..._cc(0, 67, 127), ..._note(0, 60, 240)]);
    final (l, _) = renderMidiFile(loud, font);
    final (s, _) = renderMidiFile(soft, font);
    expect(_peak(s), lessThan(_peak(l)));
  });

  test('XG drum bank (CC0=127) + a GS rhythm-part SysEx render without error',
      () {
    final smf = _midi([
      // GS "use part-block 1 (ch0) for rhythm map 2": F0 41 10 42 12 40 11 15
      // 02 00 F7 (10 data bytes).
      0, 0xF0, 0x0A, //
      0x41, 0x10, 0x42, 0x12, 0x40, 0x11, 0x15, 0x02, 0x00, 0xF7,
      ..._cc(0, 0, 127), // XG drum bank MSB
      ..._note(0, 38, 240), // a snare on the (now drum) channel 0
    ]);
    final (l, _) = renderMidiFile(smf, font);
    expect(l, isNotEmpty);
    expect(_peak(l), greaterThan(0.0));
  });

  test('channel aftertouch (0xD0) adds vibrato to a sounding note', () {
    final plain = _midi(_note(0, 60, 480));
    // Full channel pressure set at the note-on → continuous vibrato.
    final at = _midi([0, 0xD0, 127, ..._note(0, 60, 480)]);
    final (p, _) = renderMidiFile(plain, font);
    final (a, _) = renderMidiFile(at, font);
    expect(a, isNot(p), reason: 'aftertouch modulates the pitch (vibrato)');
  });

  test('sostenuto (CC66) holds notes down at press, not ones played after', () {
    // A looping font so a *held* note keeps sounding (a one-shot would stop at
    // the sample end regardless of how long it is held).
    final loopFont = loadSoundFont(
      oneSampleSf2(
        pcm: sineI16(400, 8),
        sampleRate: 44100,
        rootKey: 60,
        loopStart: 0,
        loopEnd: 400,
        sampleModes: 1, // gen 54 = loop
      ),
    );
    // The last output sample above a small threshold — how long sound lasts.
    int lastSound(Float64List x) {
      for (var i = x.length - 1; i >= 0; i--) {
        if (x[i].abs() > 0.01) return i;
      }
      return 0;
    }

    // Baseline: note off at tick 120, no pedal → stops shortly after.
    final base = _midi([0, 0x90, 60, 0x64, 0x81, 0x00, 0x80, 60, 0]);
    // Captured: press CC66 while the note sounds, THEN note off → held to the end.
    final captured = _midi([
      0, 0x90, 60, 0x64, // note on
      ..._cc(0, 66, 127), // sostenuto down (captures the sounding note)
      0x81, 0x00, 0x80, 60, 0, // note off at tick 128
    ]);
    // After-pedal: press CC66 FIRST, then play → not captured → stops normally.
    final afterPedal = _midi([
      ..._cc(0, 66, 127), // sostenuto down (nothing sounding yet)
      0, 0x90, 60, 0x64, //
      0x81, 0x00, 0x80, 60, 0,
    ]);

    final (b, _) = renderMidiFile(base, loopFont);
    final (c, _) = renderMidiFile(captured, loopFont);
    final (ap, _) = renderMidiFile(afterPedal, loopFont);
    expect(
      lastSound(c),
      greaterThan(lastSound(b) + 8000),
      reason: 'a captured note is held well past its note-off',
    );
    expect(
      lastSound(ap),
      lessThan(lastSound(c) - 8000),
      reason: 'a note played after the pedal is NOT held',
    );
  });

  test('GS NRPN 18h retunes a single drum key (per-drum pitch)', () {
    // Zero-crossings over a fixed early window: a higher pitch = more crossings.
    int zc(Float64List x, int n) {
      final m = x.length < n ? x.length : n;
      var z = 0;
      for (var i = 1; i < m; i++) {
        if ((x[i] >= 0) != (x[i - 1] >= 0)) z++;
      }
      return z;
    }

    final plain = _midi([..._note(9, 60, 240)]); // drum ch, key 60
    // NRPN 18h/key 60, data 0x40+12 → +12 semitones (an octave up).
    final tuned = _midi([
      ..._cc(9, 99, 0x18), // NRPN MSB = drum pitch coarse
      ..._cc(9, 98, 60), // NRPN LSB = drum key 60
      ..._cc(9, 6, 64 + 12), // data entry = centre + 12 st
      ..._note(9, 60, 240),
    ]);
    final (p, _) = renderMidiFile(plain, font);
    final (t, _) = renderMidiFile(tuned, font);
    expect(
      zc(t, 800),
      greaterThan(zc(p, 800) + 10),
      reason: 'the retuned drum plays an octave higher',
    );
  });

  test('scaleTuning 0 (drums): different keys play at the SAME pitch', () {
    // A normal font transposes with the key; an untuned (drum) font must not —
    // the key only selects which sample, never its pitch.
    int zc(Float64List x) {
      final n = x.length < 1500 ? x.length : 1500;
      var z = 0;
      for (var i = 1; i < n; i++) {
        if ((x[i] >= 0) != (x[i - 1] >= 0)) z++;
      }
      return z;
    }

    final normal = loadSoundFont(
      oneSampleSf2(
        pcm: sineI16(4000, 80), // long enough that +12 keys doesn't run out
        sampleRate: 44100,
        rootKey: 60,
        loopStart: 0,
        loopEnd: 0,
      ),
    );
    final drum = loadSoundFont(
      oneSampleSf2(
        pcm: sineI16(4000, 80), // long enough that +12 keys doesn't run out
        sampleRate: 44100,
        rootKey: 60,
        loopStart: 0,
        loopEnd: 0,
        scaleTuning: 0,
      ),
    );
    final low = _midi(_note(0, 60, 240));
    final high = _midi(_note(0, 72, 240)); // an octave up
    // Normal: +12 keys transposes up an octave, so the non-looping sample's
    // cycles pack into fewer output samples → clearly more zero-crossings in the
    // fixed 1500-sample window (measured ~78 vs ~59). Margin kept off the
    // knife-edge (the exact count rounds near +20, so assert a solid +10).
    expect(
      zc(renderMidiFile(high, normal).$1),
      greaterThan(zc(renderMidiFile(low, normal).$1) + 10),
    );
    // Drum (scaleTuning 0): both keys sound at the sample's native pitch.
    final dLow = zc(renderMidiFile(low, drum).$1);
    final dHigh = zc(renderMidiFile(high, drum).$1);
    expect((dHigh - dLow).abs(), lessThan(8), reason: 'key must not transpose');
  });

  test('empty / non-MIDI input yields empty output', () {
    final (l, r) = renderMidiFile(Uint8List.fromList([1, 2, 3]), font);
    expect(l, isEmpty);
    expect(r, isEmpty);
  });
}
