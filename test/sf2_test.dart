// SoundFont 2 reading: sample extraction + the GM preset→zone graph. Uses the
// shared in-test SF2 fixture writer (test/sf2_fixture.dart) — no external asset.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

void main() {
  group('SF2 sample extraction', () {
    test('parses one sample with its rate, root key and loop', () {
      final pcm = sineI16(880, 20);
      final sf = Sf2SoundFont.parse(
        oneSampleSf2(
          pcm: pcm,
          sampleRate: 22050,
          rootKey: 60,
          loopStart: 44,
          loopEnd: 836,
        ),
      );
      expect(sf.samples.length, 1);
      final s = sf.samples.single;
      expect(s.name, 'Tone');
      expect(s.sampleRate, 22050);
      expect(s.originalPitch, 60);
      expect(s.pcm.length, 880);
      expect(s.loops, isTrue);
    });

    test('builds a looping, pitched SampleInstrument', () {
      final pcm = sineI16(880, 20);
      final s = Sf2SoundFont.parse(
        oneSampleSf2(
          pcm: pcm,
          sampleRate: 22050,
          rootKey: 60,
          loopStart: 44,
          loopEnd: 836,
        ),
      ).samples.single;
      final inst = sampleInstrumentFromSf2(s, id: 'sf2tone');
      expect(inst.baseMidi, 60);
      expect(inst.loops, isTrue);
      expect(soundCategoryOf(inst), SoundCategory.recorded);

      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
      ];
      final buf = inst.renderChannel(cells, timing);
      final probe = inst.sample.length + 20000;
      expect(
        buf.sublist(probe, probe + 500).any((v) => v.abs() > 1e-3),
        isTrue,
      );
    });

    test('rejects a non-SoundFont buffer', () {
      expect(
        () => Sf2SoundFont.parse(Uint8List.fromList('not an sf2!!'.codeUnits)),
        throwsFormatException,
      );
    });

    test('.sf3: extracts each Ogg stream + decodes via the injected seam', () {
      // A fake "Ogg stream": OggS magic + a marker byte the fake decoder maps to
      // a known PCM length, so we prove the byte-range extraction + decode wiring.
      final ogg = Uint8List.fromList([...'OggS'.codeUnits, 0, 42, 7]);
      final bytes = compressedSf3(
        oggStream: ogg,
        loopStart: 4,
        loopEnd: 20, // decoded-frame positions (NOT byte offsets)
      );
      expect(sf2IsCompressed(bytes), isTrue);

      Uint8List? seen;
      Float64List fake(Uint8List stream) {
        seen = stream;
        return Float64List(24)..[10] = 0.5; // stand-in decoded PCM
      }

      final sf = Sf2SoundFont.parse(bytes, vorbis: fake);
      // The decoder received EXACTLY the sample's Ogg byte range.
      expect(seen, equals(ogg));
      expect(sf.samples.length, 1);
      final s = sf.samples.single;
      expect(s.pcm.length, 24); // the decoded PCM, not the compressed bytes
      // .sf3 loop points are decoded-frame positions, used as-is (no `-start`).
      expect(s.loopStart, 4);
      expect(s.loopEnd, 20);
      expect(s.loops, isTrue);
      // The preset graph still resolves over the decoded sample.
      expect(sf.presets.single.zones.single.sampleIndex, 0);
    });

    test('detects + rejects a compressed .sf3 (OGG samples)', () {
      // A soundfont whose smpl data starts with the "OggS" magic = .sf3.
      // 'OggS' as two little-endian int16 words: 0x674F, 0x5367.
      final oggPcm = Int16List.fromList([0x674F, 0x5367, 0, 0, 0, 0]);
      final bytes = oneSampleSf2(
        pcm: oggPcm,
        sampleRate: 44100,
        rootKey: 60,
        loopStart: 0,
        loopEnd: 0,
      );
      // A normal .sf2 is not compressed; this crafted one is.
      expect(
        sf2IsCompressed(
          oneSampleSf2(
            pcm: sineI16(64, 4),
            sampleRate: 44100,
            rootKey: 60,
            loopStart: 0,
            loopEnd: 0,
          ),
        ),
        isFalse,
      );
      expect(sf2IsCompressed(bytes), isTrue);
      expect(sf2IsCompressed(Uint8List.fromList('nope'.codeUnits)), isFalse);
      // parse throws a clear, catchable error mentioning .sf3.
      expect(
        () => Sf2SoundFont.parse(bytes),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('.sf3'),
          ),
        ),
      );
    });

    test('reads chPitchCorrection and bakes it into the resample', () {
      final pcm = sineI16(880, 20);
      Sf2SoundFont build(int corr) => Sf2SoundFont.parse(
            oneSampleSf2(
              pcm: pcm,
              sampleRate: 44100,
              rootKey: 60,
              loopStart: 0,
              loopEnd: 0,
              pitchCorrection: corr,
            ),
          );

      // The signed correction is parsed off shdr byte 41.
      expect(build(0).samples.single.pitchCorrection, 0);
      expect(build(30).samples.single.pitchCorrection, 30);
      expect(build(-30).samples.single.pitchCorrection, -30);

      // A non-zero correction stretches the sample (baked tuning) → the built
      // instrument's buffer differs in length from the uncorrected one; zero
      // correction at the engine rate leaves it exactly the sample length.
      final none = sampleInstrumentFromSf2(build(0).samples.single, id: 'a');
      final corrected =
          sampleInstrumentFromSf2(build(50).samples.single, id: 'b');
      expect(none.sample.length, pcm.length); // 44.1kHz, no correction → as-is
      expect(corrected.sample.length, isNot(pcm.length));
    });
  });

  group('SF2 GM preset → zone mapping', () {
    test('resolves a preset with its bank/program + a full-range zone', () {
      final sf = Sf2SoundFont.parse(
        oneSampleSf2(
          pcm: sineI16(880, 20),
          sampleRate: 44100,
          rootKey: 60,
          loopStart: 0,
          loopEnd: 0,
        ),
      );
      expect(sf.presets.length, 1);
      final p = sf.presets.single;
      expect(p.name, 'GMTest');
      expect(p.bank, 0);
      expect(p.program, 0);
      expect(p.zones.length, 1);
      expect(p.zones.single.keyLo, 0);
      expect(p.zones.single.keyHi, 127);
      expect(p.zones.single.sampleIndex, 0);
    });

    test('a key-split preset picks the RIGHT sample per note', () {
      // Sample A = low buzz (few periods), B = high buzz (many periods): a
      // note in each range should read a clearly different pitch.
      final a = sineI16(2000, 8); // ~8 cycles over 2000 → low
      final b = sineI16(2000, 64); // ~64 cycles over 2000 → high
      final sf = Sf2SoundFont.parse(twoZoneSf2(a, b));
      expect(sf.presets.single.zones.length, 2);

      final inst = sf2InstrumentFromPreset(sf, sf.presets.single, id: 'split');
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      List<TrackerCell> one(int midi) => [
            TrackerCell(midi: midi),
            ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
          ];

      // Zone A plays at its root (48); zone B at its root (72). Count zero
      // crossings over the note's start — the high sample crosses far more.
      int crossings(Float64List buf) {
        var c = 0;
        for (var i = 1; i < 3000; i++) {
          if ((buf[i - 1] < 0) != (buf[i] < 0)) c++;
        }
        return c;
      }

      final low = inst.renderChannel(one(48), timing); // → zone A (root 48)
      final high = inst.renderChannel(one(72), timing); // → zone B (root 72)
      expect(low.any((v) => v != 0), isTrue);
      expect(high.any((v) => v != 0), isTrue);
      // Different zones → clearly different pitch content.
      expect(crossings(high), greaterThan(crossings(low) * 2));
    });

    test('per-zone initialAttenuation (gen 48) lowers the level', () {
      final pcm = sineI16(880, 20);
      Sf2SoundFont build(int cb) => Sf2SoundFont.parse(
            oneSampleSf2(
              pcm: pcm,
              sampleRate: 44100,
              rootKey: 60,
              loopStart: 0,
              loopEnd: 0,
              attenuationCb: cb,
            ),
          );
      // The zone carries the attenuation…
      expect(build(0).presets.single.zones.single.attenuationCb, 0);
      expect(build(100).presets.single.zones.single.attenuationCb, 100);
      expect(build(100).presets.single.zones.single.gain, closeTo(0.316, 0.02));

      // …and the render is quieter (100 cB = 10 dB ≈ 0.316× peak).
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(3, TrackerCell.empty),
      ];
      double peak(Sf2SoundFont sf) => sf2InstrumentFromPreset(
            sf,
            sf.presets.single,
            id: 'a',
          ).renderChannel(cells, timing).fold<double>(
                0,
                (m, v) => v.abs() > m ? v.abs() : m,
              );
      final loud = peak(build(0));
      final quiet = peak(build(100));
      expect(quiet, lessThan(loud * 0.5));
    });

    test('per-zone fine/coarse tune (gen 51/52) is baked into the pitch', () {
      final pcm = sineI16(880, 20);
      // A looping sample so the tone sustains across the measurement window.
      Sf2SoundFont build({int coarse = 0, int fine = 0}) => Sf2SoundFont.parse(
            oneSampleSf2(
              pcm: pcm,
              sampleRate: 44100,
              rootKey: 60,
              loopStart: 0,
              loopEnd: pcm.length,
              coarseTune: coarse,
              fineTune: fine,
            ),
          );
      final z = build(coarse: 2, fine: -14).presets.single.zones.single;
      expect(z.coarseTune, 2);
      expect(z.fineTune, -14);

      // Play the SAME note through untuned vs +12-semitone (octave up) zones: the
      // octave-up render has roughly double the zero-crossing rate (higher pitch).
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(3, TrackerCell.empty),
      ];
      Float64List render(Sf2SoundFont sf) =>
          sf2InstrumentFromPreset(sf, sf.presets.single, id: 'x')
              .renderChannel(cells, timing);
      int crossings(Float64List b) {
        var c = 0;
        for (var i = 1001; i < 5000; i++) {
          if ((b[i - 1] < 0) != (b[i] < 0)) c++;
        }
        return c;
      }

      final base = crossings(render(build()));
      final up = crossings(render(build(coarse: 12)));
      expect(up, greaterThan(base * 1.7)); // ~2× the pitch
    });

    test('an Sf2Instrument is a renderable tracker instrument', () {
      final sf =
          Sf2SoundFont.parse(twoZoneSf2(sineI16(1000, 8), sineI16(1000, 32)));
      final inst = sf2InstrumentFromPreset(sf, sf.presets.single, id: 'x');
      expect(inst, isA<TrackerInstrument>());
      expect(inst.id, 'x');
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 55),
        ...List<TrackerCell>.filled(3, TrackerCell.empty),
      ];
      expect(inst.renderChannel(cells, timing).any((v) => v != 0), isTrue);
    });
  });
}
