// moduleDocFromSong — the PCM-preserving TrackerSong -> ModuleDoc export. Unlike
// the Score->module path, a SampleInstrument keeps its REAL waveform and the
// effect column survives. Pure Dart, no device audio.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertToIt, convertToXm, parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart'
    show DocCell, DocPattern, DocSample, ModuleDoc, ModuleFormat;
import 'package:comet_beat/core/audio/mod/xm_module.dart' show XmCell;
import 'package:comet_beat/core/audio/synth.dart' show Instrument, kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A recognizable sample buffer (a square-ish buzz, ±0.6, at the engine rate).
  Float64List buzz(int n) {
    final s = Float64List(n);
    for (var i = 0; i < n; i++) {
      s[i] = i % 40 < 20 ? 0.6 : -0.6;
    }
    return s;
  }

  TrackerSong sampleSong(Float64List pcm) {
    final ch = TrackerChannel(
      id: 's',
      instrument: SampleInstrument('rec', pcm),
      rows: 8,
    );
    final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
    cells[0] = const TrackerCell(midi: 60); // a note that uses the sample
    cells[4] = const TrackerCell(
      midi: 62,
      fxCmd: 0x1, // porta-up, param 4 — an authored effect
      fxParam: 0x04,
    );
    return TrackerSong.fromParts(
      channels: [ch],
      timing: const TrackerTiming(rows: 8),
      patterns: [
        TrackerPattern(name: '00', cells: [cells]),
      ],
      order: [0],
    );
  }

  group('moduleDocFromSong (PCM-preserving)', () {
    test('native XM and IT exports retain edited multi-sample keymaps', () {
      final low = SampleInstrument(
        'low',
        Float64List.fromList(List<double>.filled(500, 0.25)),
      );
      final high = SampleInstrument(
        'high',
        Float64List.fromList(List<double>.filled(500, -0.25)),
      );
      final kit = MultiSampleInstrument('kit', {60: low, 72: high});
      final cells = List<TrackerCell>.filled(4, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 60);
      cells[1] = const TrackerCell(midi: 72);
      final song = TrackerSong.fromParts(
        channels: [TrackerChannel(id: 'kit', instrument: kit, rows: 4)],
        instruments: [kit],
        timing: const TrackerTiming(rows: 4),
        patterns: [
          TrackerPattern(name: '00', cells: [cells])
        ],
        order: [0],
      );

      final xm = parseAnyModule(
        convertToXm(moduleDocFromSong(song, targetFormat: ModuleFormat.xm)),
      );
      expect(xm.xmInstruments.single.samples, hasLength(2));
      expect(xm.xmInstruments.single.keymap[49], 0); // C-4 / MIDI 60
      expect(xm.xmInstruments.single.keymap[61], 1); // C-5 / MIDI 72

      final it = parseAnyModule(
        convertToIt(moduleDocFromSong(song, targetFormat: ModuleFormat.it)),
      );
      expect(it.itInstruments.single.keymap[60], 1);
      expect(it.itInstruments.single.keymap[72], 2);
      expect(it.samples, hasLength(2));
    });

    test('explicit key-off cells survive native XM and IT export', () {
      final sample = SampleInstrument(
        'sample',
        Float64List.fromList(List<double>.filled(500, 0.2)),
      );
      final cells = [
        const TrackerCell(midi: 60),
        TrackerCell.noteCut,
      ];
      final song = TrackerSong.fromParts(
        channels: [TrackerChannel(id: 'sample', instrument: sample, rows: 2)],
        instruments: [sample],
        timing: const TrackerTiming(rows: 2),
        patterns: [
          TrackerPattern(name: '00', cells: [cells])
        ],
        order: [0],
      );
      final xm = parseAnyModule(
        convertToXm(moduleDocFromSong(song, targetFormat: ModuleFormat.xm)),
      );
      expect(xm.xmPatterns.single.rows[1].single.note, XmCell.noteOff);
      final it = parseAnyModule(
        convertToIt(moduleDocFromSong(song, targetFormat: ModuleFormat.it)),
      );
      expect(it.patterns.single.rows[1].single.noteOff, isTrue);
    });

    test('same-format native command bytes survive the song bridge', () {
      final pcm = Float64List.fromList(List<double>.filled(300, 0.2));
      final source = ModuleDoc(
        sourceFormat: ModuleFormat.xm,
        channelCount: 1,
        order: const [0],
        patterns: [
          const DocPattern([
            [
              DocCell(
                note: 60,
                nativeNote: 49,
                instrument: 1,
                nativeInstrument: 1,
                nativeInstrumentSet: true,
                effect: 0x4,
                effectParam: 0x12,
                nativeEffect: 0xA,
                nativeEffectParam: 0x34,
              ),
            ],
          ], 1),
        ],
        samples: [DocSample(pcm: pcm)],
      );
      final song = songFromModuleDoc(source);
      final exported = parseAnyModule(
        convertToXm(moduleDocFromSong(song, targetFormat: ModuleFormat.xm)),
      );
      final cell = exported.xmPatterns.single.rows.first.single;
      expect(cell.effect, 0xA);
      expect(cell.effectParam, 0x34);
      expect(cell.note, 49);
    });

    test('a SampleInstrument keeps its real PCM in the doc', () {
      final pcm = buzz(400);
      final doc = moduleDocFromSong(sampleSong(pcm));
      expect(doc.samples, isNotEmpty);
      final s = doc.samples.first;
      // The waveform is the SAME samples (not a re-synthesized timbre).
      expect(s.pcm.length, pcm.length);
      for (var i = 0; i < pcm.length; i++) {
        expect(s.pcm[i], closeTo(pcm[i], 1e-12), reason: 'sample $i');
      }
      // baseMidi 60 -> c5speed is the engine rate (no tuning shift).
      expect(s.c5speed, closeTo(kSampleRate, 1));
    });

    test('the note + instrument + effect column survive into the doc', () {
      final doc = moduleDocFromSong(sampleSong(buzz(200)));
      final p = doc.patterns.single;
      // Row 0: the note plays the (1-based) sample.
      expect(p.rows[0][0].note, 60);
      expect(p.rows[0][0].instrument, 1);
      // Row 4: the authored porta effect rode through 1:1.
      expect(p.rows[4][0].note, 62);
      expect(p.rows[4][0].effect, 0x1);
      expect(p.rows[4][0].effectParam, 0x04);
    });

    test('round-trips through a writer (XM) preserving the real waveform', () {
      // The DOC preserves PCM exactly (test above); a full write+read keeps the
      // waveform to the format's sample bit-depth (the writer quantises) — still
      // the REAL recording, not a re-synthesized timbre.
      final pcm = buzz(400);
      final bytes = convertToXm(moduleDocFromSong(sampleSong(pcm)));
      final back = parseAnyModule(bytes);
      final s = back.usedSamples.first;
      expect(s.pcm.length, pcm.length);
      var maxErr = 0.0;
      for (var i = 0; i < pcm.length; i++) {
        final e = (s.pcm[i] - pcm[i]).abs();
        if (e > maxErr) maxErr = e;
      }
      // Within a sample-quantisation step (writer bit-depth), not a timbre swap.
      expect(maxErr, lessThan(0.02), reason: 'sample quantisation error');
    });

    test('a re-imported song plays the note that used the sample', () {
      // Full loop: song -> doc -> XM -> song -> render is non-silent at the note.
      final bytes = convertToXm(moduleDocFromSong(sampleSong(buzz(600))));
      final reimported = songFromModuleBytes(bytes);
      final wav = reimported.renderSongWav();
      expect(wav.length, greaterThan(44)); // more than a bare WAV header
    });

    test('sixteenBit toggle controls the exported sample bit-depth', () {
      final song = sampleSong(buzz(400));
      // Default: 16-bit (higher quality) for the app export path.
      expect(moduleDocFromSong(song).samples.first.sixteenBit, isTrue);
      // Opting out yields 8-bit samples (smaller files) — e.g. for a MOD
      // export where 16-bit is meaningless anyway.
      final eightBit = moduleDocFromSong(song, sixteenBit: false);
      expect(eightBit.samples.first.sixteenBit, isFalse);
      // The waveform is preserved in the doc regardless of the flag (the writer
      // is what quantises to the on-disk bit-depth).
      expect(eightBit.samples.first.pcm.length, 400);
    });

    test('a procedural voice is rendered to a non-empty sample', () {
      final ch = TrackerChannel(
        id: 'p',
        instrument: const AdditiveInstrument('piano', Instrument.piano),
        rows: 8,
      );
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 60);
      final song = TrackerSong.fromParts(
        channels: [ch],
        timing: const TrackerTiming(rows: 8),
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );
      final doc = moduleDocFromSong(song);
      // No PCM to preserve, so it renders a base-note one-shot (non-empty).
      expect(doc.samples.first.pcm, isNotEmpty);
      expect(doc.samples.first.pcm.any((v) => v != 0), isTrue);
    });

    test('a channel volume envelope exports onto the doc sample', () {
      final ch = TrackerChannel(
        id: 's',
        instrument: SampleInstrument('rec', buzz(400)),
        rows: 8,
        volumeEnvelope: const VolumeEnvelope([
          (ms: 0, level: 1),
          (ms: 100, level: 0),
        ]),
      );
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 60);
      final song = TrackerSong.fromParts(
        channels: [ch],
        timing: const TrackerTiming(tempoBpm: 125, rows: 8), // tick = 20 ms
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );

      final env = moduleDocFromSong(song).samples.first.volumeEnvelope;
      expect(env.enabled, isTrue);
      expect(env.points, [(0, 64), (5, 0)]); // 100 ms → 5 ticks; 1.0 → 64
    });

    test('a channel pan exports onto the doc sample', () {
      final ch = TrackerChannel(
        id: 's',
        instrument: SampleInstrument('rec', buzz(200)),
        rows: 8,
        pan: 0.5, // right of centre
      );
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 60);
      final song = TrackerSong.fromParts(
        channels: [ch],
        timing: const TrackerTiming(rows: 8),
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );
      // 0.5 → 0.5 × 128 + 128 = 192.
      expect(moduleDocFromSong(song).samples.first.pan, 192);
    });

    test('a channel envelope survives a full song → XM → song round-trip', () {
      final ch = TrackerChannel(
        id: 's',
        instrument: SampleInstrument('rec', buzz(400)),
        rows: 8,
        volumeEnvelope: const VolumeEnvelope([
          (ms: 0, level: 1),
          (ms: 120, level: 0),
        ]),
      );
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 60);
      final song = TrackerSong.fromParts(
        channels: [ch],
        timing: const TrackerTiming(tempoBpm: 125, rows: 8),
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );

      // song → XM bytes → re-imported song: the channel keeps its envelope.
      final back = songFromModuleBytes(convertToXm(moduleDocFromSong(song)));
      final env = back.channels.first.volumeEnvelope;
      expect(env, isNotNull);
      expect(env!.points.first.level, closeTo(1.0, 1e-9));
      expect(env.points.last.level, closeTo(0.0, 1e-9));
      // 120 ms → 6 ticks → back to 6 × 20 ms = 120 ms at the same tempo.
      expect(env.points.last.ms, 120);
    });

    test('native IT pitch envelope survives the song round-trip', () {
      final instrument = SampleInstrument(
        'it-pitch',
        buzz(2000),
        nativePitchEnvelope: const PitchEnvelope([
          (ms: 0, semitones: 12),
          (ms: 100, semitones: 0),
        ]),
      );
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty)
        ..[0] = const TrackerCell(midi: 60);
      final song = TrackerSong.fromParts(
        channels: [
          TrackerChannel(id: 'it', instrument: instrument, rows: 8),
        ],
        timing: const TrackerTiming(tempoBpm: 125, rows: 8),
        patterns: [
          TrackerPattern(name: '00', cells: [cells])
        ],
        order: [0],
      );

      final doc = moduleDocFromSong(song, targetFormat: ModuleFormat.it);
      final exported = doc.itInstruments.firstWhere(
        (instrument) => instrument.pitchEnvelope.enabled,
      );
      expect(exported.pitchEnvelope.points, [(0, 12), (5, 0)]);

      final back = songFromModuleBytes(convertToIt(doc));
      final multi = back.instruments.firstWhere(
        (instrument) =>
            instrument is MultiSampleInstrument &&
            instrument.zones.values.any(
              (zone) =>
                  zone is SampleInstrument && zone.nativePitchEnvelope != null,
            ),
      ) as MultiSampleInstrument;
      final zone = multi.zones[60]! as SampleInstrument;
      expect(zone.nativePitchEnvelope!.semitonesAt(0), 12);
      expect(zone.nativePitchEnvelope!.semitonesAt(1000), 0);
    });
  });
}
