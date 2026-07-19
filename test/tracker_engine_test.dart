// TrackerEngine — the Tracker's Flutter-free core. Covers the timing grid, the
// cells->segments note model (sustain-until-next + leading rest), the mixdown
// invariants (silence, no clipping) and the edit/cache behaviour. Mirrors
// loop_engine_test.dart / synth_test.dart: pure Dart, no device audio.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart' show PitchDetector;
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

int _peak(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  var peak = 0;
  for (var i = 44; i + 1 < wav.length; i += 2) {
    final s = data.getInt16(i, Endian.little).abs();
    if (s > peak) peak = s;
  }
  return peak;
}

void main() {
  group('TrackerTiming', () {
    test('a 120 BPM / 16-row / 4-per-beat grid is integral', () {
      const t = TrackerTiming();
      expect(t.stepMs, 125);
      expect(t.totalMs, 2000);
      expect(t.totalSamples, (2000 * kSampleRate) ~/ 1000);
    });
  });

  group('cellsToSegments', () {
    const t = TrackerTiming(rows: 4);
    List<TrackerCell> cells(List<int?> midis) =>
        [for (final m in midis) TrackerCell(midi: m)];

    test('empty cells extend the previous note (let it ring)', () {
      final segs = cellsToSegments(cells([60, null, null, 62]), t);
      // note 60 held for 3 steps, note 62 for 1.
      expect(segs.length, 2);
      expect(segs[0].ms, 3 * t.stepMs);
      expect(segs[0].freqs.single, midiToFrequency(60));
      expect(segs[1].ms, 1 * t.stepMs);
    });

    test('a leading empty is a rest (no freqs)', () {
      final segs = cellsToSegments(cells([null, 60, null, null]), t);
      expect(segs.first.freqs, isEmpty); // rest
      expect(segs.first.ms, t.stepMs);
      expect(segs.last.freqs.single, midiToFrequency(60));
    });

    test('runs always fill the whole pattern', () {
      final segs = cellsToSegments(cells([60, 62, null, 64]), t);
      final total = segs.fold<int>(0, (s, seg) => s + seg.ms);
      expect(total, t.rows * t.stepMs);
    });
  });

  group('TrackerEngine render', () {
    test('an empty pattern is silence of the full loop length', () {
      final e = TrackerEngine();
      final wav = e.renderLoop();
      expect(wav.length, 44 + e.timing.totalSamples * 2);
      expect(_peak(wav), 0);
      expect(e.isEmpty, isTrue);
    });

    test('placing a note breaks the silence', () {
      final e = TrackerEngine();
      e.toggleNote(0, 0, 60);
      expect(e.isEmpty, isFalse);
      expect(_peak(e.renderLoop()), greaterThan(0));
    });

    test('the mixed loop never clips, even fully packed', () {
      final e = TrackerEngine();
      for (var ch = 0; ch < e.channels.length; ch++) {
        for (var row = 0; row < e.rows; row++) {
          e.setCell(ch, row, const TrackerCell(midi: 60));
        }
      }
      expect(_peak(e.renderLoop()), lessThanOrEqualTo(32767));
    });

    test('length is fixed regardless of content', () {
      final e = TrackerEngine();
      final silent = e.renderLoop().length;
      e.toggleNote(1, 5, 67);
      expect(e.renderLoop().length, silent);
    });
  });

  group('TrackerEngine editing + cache', () {
    test('editing a cell changes the bytes; reverting restores them', () {
      final e = TrackerEngine();
      final before = e.renderLoop();
      e.toggleNote(0, 2, 64);
      final edited = e.renderLoop();
      expect(edited, isNot(equals(before)));

      e.toggleNote(0, 2, 64); // same note toggles off
      expect(e.renderLoop(), equals(before));
    });

    test('rendering twice is byte-identical (deterministic + cached)', () {
      final e = TrackerEngine()..toggleNote(2, 0, 60);
      expect(e.renderLoop(), equals(e.renderLoop()));
    });

    test('toggleNote: place, replace, clear', () {
      final e = TrackerEngine();
      expect(e.toggleNote(0, 0, 60), 60); // placed
      expect(e.cellAt(0, 0).midi, 60);
      expect(e.toggleNote(0, 0, 62), 62); // different note replaces
      expect(e.cellAt(0, 0).midi, 62);
      expect(e.toggleNote(0, 0, 62), isNull); // same note clears
      expect(e.cellAt(0, 0).isEmpty, isTrue);
    });

    test('clearAll returns to silence', () {
      final e = TrackerEngine()
        ..toggleNote(0, 0, 60)
        ..toggleNote(3, 8, 48);
      expect(_peak(e.renderLoop()), greaterThan(0));
      e.clearAll();
      expect(e.isEmpty, isTrue);
      expect(_peak(e.renderLoop()), 0);
    });

    test('changing tempo re-renders (different bytes, same length rule)', () {
      final e = TrackerEngine()..toggleNote(0, 0, 60);
      final slow = e.renderLoop();
      e.timing = e.timing.copyWith(tempoBpm: 90);
      final fast = e.renderLoop();
      expect(fast, isNot(equals(slow)));
      expect(fast.length, 44 + e.timing.totalSamples * 2);
    });
  });

  group('SfxrInstrument channel', () {
    TrackerChannel zapChannel(int rows) => TrackerChannel(
          id: 'zap',
          instrument: SfxrInstrument.preset('zap', sfxrZap, seed: 7),
          rows: rows,
        );

    test('renders a full-length buffer; empty is silence', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = zapChannel(timing.rows);
      final silent = ch.instrument.renderChannel(ch.cells, timing);
      expect(silent.length, timing.totalSamples);
      expect(silent.every((v) => v == 0), isTrue);

      ch.cells[0] = const TrackerCell(midi: 72);
      final sounded = ch.instrument.renderChannel(ch.cells, timing);
      expect(sounded.length, timing.totalSamples);
      expect(sounded.any((v) => v != 0), isTrue);
    });

    test('is deterministic (stable stem for the cache)', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = zapChannel(timing.rows)
        ..cells[2] = const TrackerCell(midi: 67);
      final a = ch.instrument.renderChannel(ch.cells, timing);
      final b = ch.instrument.renderChannel(ch.cells, timing);
      expect(a, equals(b));
    });

    test('the bell (FM/LFO) instrument is in the palette and is audible', () {
      final bell = kTrackerInstruments.firstWhere((o) => o.id == 'bell');
      final inst = bell.build();
      expect(inst.id, 'bell');
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = TrackerChannel(id: 'bell', instrument: inst, rows: timing.rows)
        ..cells[0] = const TrackerCell(midi: 72);
      final buf = inst.renderChannel(ch.cells, timing);
      expect(buf.length, timing.totalSamples);
      expect(buf.any((v) => v != 0), isTrue);
    });

    test('the default band mixes additive + sfxr without clipping', () {
      final e =
          TrackerEngine(timing: const TrackerTiming(rows: 8, stepsPerBeat: 2));
      expect(e.channels.map((c) => c.id), contains('zap'));
      final zap = e.channels.indexWhere((c) => c.id == 'zap');
      e.toggleNote(zap, 0, 72);
      e.toggleNote(0, 0, 60); // an additive channel too
      final wav = e.renderLoop();
      var peak = 0;
      for (var i = 44; i + 1 < wav.length; i += 2) {
        final s = (wav[i] | (wav[i + 1] << 8)).toSigned(16).abs();
        if (s > peak) peak = s;
      }
      expect(peak, greaterThan(0));
      expect(peak, lessThanOrEqualTo(32767));
    });
  });

  group('KarplusInstrument channel (plucked string)', () {
    TrackerChannel pluckChannel(int rows) => TrackerChannel(
          id: 'pluck',
          instrument: const KarplusInstrument('pluck'),
          rows: rows,
        );

    test('renders a full-length buffer; empty is silence; deterministic', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = pluckChannel(timing.rows);
      final silent = ch.instrument.renderChannel(ch.cells, timing);
      expect(silent.length, timing.totalSamples);
      expect(silent.every((v) => v == 0), isTrue);

      ch.cells[0] = const TrackerCell(midi: 60);
      final a = ch.instrument.renderChannel(ch.cells, timing);
      final b = ch.instrument.renderChannel(ch.cells, timing);
      expect(a.any((v) => v != 0), isTrue);
      expect(a, equals(b)); // stable stem for the cache
    });

    test('a note is pitched at its frequency (autocorrelation period)', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      List<TrackerCell> one(int midi) => [
            TrackerCell(midi: midi),
            ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
          ];
      const inst = KarplusInstrument('pluck');
      // Fundamental period = the lag (in a plausible range) that maximizes
      // autocorrelation over a settled window — a robust pitch measure for a
      // plucked tone (zero-crossings just track the excitation noise).
      int period(Float64List b) {
        var bestLag = 40;
        var best = -1e18;
        for (var lag = 40; lag <= 800; lag++) {
          var s = 0.0;
          for (var i = 4000; i < 12000; i++) {
            s += b[i] * b[i + lag];
          }
          if (s > best) {
            best = s;
            bestLag = lag;
          }
        }
        return bestLag;
      }

      final low = period(inst.renderChannel(one(48), timing)); // C3 ~130.8 Hz
      final high = period(inst.renderChannel(one(72), timing)); // C5 ~523.3 Hz
      // Detected period ≈ sampleRate / noteFreq, within a couple samples.
      expect((low - kSampleRate / 130.81).abs(), lessThan(3));
      expect((high - kSampleRate / 523.25).abs(), lessThan(3));
      expect(low, greaterThan(high * 2)); // two octaves down ⇒ ~4× the period
    });

    test('a pluck decays within its run (later is quieter than the attack)',
        () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = pluckChannel(timing.rows)
        ..cells[0] = const TrackerCell(midi: 60);
      final buf = ch.instrument.renderChannel(ch.cells, timing);
      double rms(int a, int b) {
        var s = 0.0;
        for (var i = a; i < b; i++) {
          s += buf[i] * buf[i];
        }
        return sqrt(s / (b - a));
      }

      final early = rms(500, 2500); // just after the attack
      final late = rms(20000, 22000); // deep into the decay
      expect(late, lessThan(early));
      expect(early, greaterThan(0));
    });

    test('the sound library groups by category (Song Book-style browsing)', () {
      final byCat = soundLibraryByCategory();
      // Tonal (additive), plucked (KS) and chiptune (sfxr) are all present.
      expect(byCat[SoundCategory.tonal]!.map((o) => o.id), contains('piano'));
      expect(byCat[SoundCategory.plucked]!.map((o) => o.id), contains('harp'));
      expect(byCat[SoundCategory.chiptune]!.map((o) => o.id), contains('zap'));
      // Every catalog entry is classified, none dropped.
      final grouped = byCat.values.fold<int>(0, (n, l) => n + l.length);
      expect(grouped, kTrackerInstruments.length);
      // The plucked group is exactly the three strings.
      expect(
        byCat[SoundCategory.plucked]!.map((o) => o.id).toSet(),
        {'pluck', 'harp', 'pluckBass'},
      );
    });

    test('the plucked strings are in the built-in sound library palette', () {
      final ids = kTrackerInstruments.map((o) => o.id).toSet();
      expect(ids.containsAll({'pluck', 'harp', 'pluckBass'}), isTrue);
      // Each builds an audible instrument.
      for (final o in kTrackerInstruments.where(
        (o) => {'pluck', 'harp', 'pluckBass'}.contains(o.id),
      )) {
        const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
        final cells = [
          const TrackerCell(midi: 62),
          ...List<TrackerCell>.filled(3, TrackerCell.empty),
        ];
        expect(
          o.build().renderChannel(cells, timing).any((v) => v != 0),
          isTrue,
        );
      }
    });
  });

  group('procedural melodic voices (FM + subtractive)', () {
    // Detect the note with the app's own MPM/NSDF pitch detector (built to lock
    // the FUNDAMENTAL of a rich/sustained tone, not a 2× multiple).
    final detector = PitchDetector();
    int detectedMidi(Float64List b) {
      final w = detector.windowSize;
      const start = 3000; // past the attack
      return detector
          .analyze(Float64List.sublistView(b, start, start + w))
          .nearestMidi;
    }

    List<TrackerCell> oneNote(int midi, int rows) => [
          TrackerCell(midi: midi),
          ...List<TrackerCell>.filled(rows - 1, TrackerCell.empty),
        ];

    // Voices whose fundamental sits AT the note frequency. (fmBell/fmBass are
    // deliberately inharmonic / sub-octave — a bell's ambiguous pitch and an
    // FM bass an octave down — so they're audible/deterministic but not
    // pitch-asserted here.)
    const pitchAccurate = {'ePiano', 'pad', 'lead', 'synthBass'};

    for (final o in kTrackerInstruments.where(
      (o) => {'ePiano', 'fmBell', 'fmBass', 'pad', 'lead', 'synthBass'}
          .contains(o.id),
    )) {
      test(
          '${o.id}: audible + deterministic'
          '${pitchAccurate.contains(o.id) ? ' + pitched at the note' : ''}',
          () {
        const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
        final inst = o.build();
        final empty = List<TrackerCell>.filled(timing.rows, TrackerCell.empty);
        expect(
          inst.renderChannel(empty, timing).every((v) => v == 0),
          isTrue,
        );

        final cells = oneNote(60, timing.rows); // C4 = 261.63 Hz
        final a = inst.renderChannel(cells, timing);
        final b = inst.renderChannel(cells, timing);
        expect(a.any((v) => v != 0), isTrue);
        expect(a, equals(b)); // stable stem for the cache
        if (pitchAccurate.contains(o.id)) {
          // The detector reads C4 (midi 60), within a semitone.
          expect((detectedMidi(a) - 60).abs(), lessThanOrEqualTo(1));
        }
      });
    }

    test('FM + subtractive presets are all in the sound library', () {
      final ids = kTrackerInstruments.map((o) => o.id).toSet();
      expect(
        ids.containsAll(
          {'ePiano', 'fmBell', 'fmBass', 'pad', 'lead', 'synthBass'},
        ),
        isTrue,
      );
      // They classify as tonal (grouped with the additive melodic voices).
      final byCat = soundLibraryByCategory();
      final tonalIds = byCat[SoundCategory.tonal]!.map((o) => o.id).toSet();
      expect(tonalIds.containsAll({'ePiano', 'pad'}), isTrue);
    });
  });

  group('PercussionInstrument channel', () {
    test('each non-empty cell is a one-shot drum hit; empty is silence', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = TrackerChannel(
        id: 'drums',
        instrument: const PercussionInstrument('drums'),
        rows: timing.rows,
      );
      final silent = ch.instrument.renderChannel(ch.cells, timing);
      expect(silent.length, timing.totalSamples);
      expect(silent.every((v) => v == 0), isTrue);

      // Kick (Drum.kick.index == 0) on step 0.
      ch.cells[0] = const TrackerCell(midi: 0);
      final hit = ch.instrument.renderChannel(ch.cells, timing);
      expect(hit.any((v) => v != 0), isTrue);
    });

    test('the default band includes a drums channel', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      );
      expect(e.channels.map((c) => c.id), contains('drums'));
      final drums = e.channels.firstWhere((c) => c.id == 'drums');
      expect(drums.instrument, isA<PercussionInstrument>());
    });
  });

  group('per-note dynamics (volume)', () {
    test('a soft note shifts the balance (dynamics are relative in a channel)',
        () {
      // Two notes in one channel: softening one changes the relative levels
      // (a lone note would be normalized back to unit peak — dynamics are
      // relative to the loudest note in the stem).
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )
        ..toggleNote(0, 0, 60)
        ..toggleNote(0, 4, 67);
      final normal = e.renderLoop();
      e.setCellVolume(0, 0, 0.4);
      expect(e.cellAt(0, 0).volume, 0.4);
      final soft = e.renderLoop();
      expect(soft, isNot(equals(normal)));
      expect(soft.length, normal.length);
    });

    test('setCellVolume is a no-op on an empty cell', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..setCellVolume(0, 0, 0.4);
      expect(e.cellAt(0, 0).isEmpty, isTrue);
    });
  });

  group('per-note effects (additive)', () {
    test('an effect changes the additive render', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..toggleNote(0, 0, 60); // melody = additive piano
      final plain = e.renderLoop();
      e.setCellEffect(0, 0, TrackerEffect.vibrato);
      expect(e.cellAt(0, 0).effect, TrackerEffect.vibrato);
      expect(e.renderLoop(), isNot(equals(plain)));
    });

    test('setCellVolume preserves the effect and vice versa', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..toggleNote(0, 0, 60);
      e.setCellEffect(0, 0, TrackerEffect.arpeggio);
      e.setCellVolume(0, 0, 0.5);
      expect(e.cellAt(0, 0).effect, TrackerEffect.arpeggio);
      expect(e.cellAt(0, 0).volume, 0.5);
    });

    test('setCellInstrument sets the column + preserves everything else', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..toggleNote(0, 0, 60);
      e.setCellVolume(0, 0, 0.5);
      e.setCellEffect(0, 0, TrackerEffect.vibrato);
      e.setCellInstrument(0, 0, 3);
      final c = e.cellAt(0, 0);
      expect(c.instrument, 3);
      expect(c.midi, 60);
      expect(c.volume, 0.5);
      expect(c.effect, TrackerEffect.vibrato);
    });

    test('setCellInstrument is a no-op on an empty cell', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..setCellInstrument(0, 0, 2);
      expect(e.cellAt(0, 0).isEmpty, isTrue);
    });
  });

  group('arrangement (renderSong)', () {
    int wavSamples(Uint8List wav) => (wav.length - 44) ~/ 2;

    test('a song is the patterns concatenated (length adds up)', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      );
      final a = e.exportCells();
      e.toggleNote(0, 0, 60);
      final b = e.exportCells();

      final oneBar = e.timing.totalSamples;
      expect(wavSamples(renderSong(e, [a])), oneBar);
      expect(wavSamples(renderSong(e, [a, b])), oneBar * 2);
      expect(wavSamples(renderSong(e, [a, b, a])), oneBar * 3);
    });

    test('rendering a song restores the live pattern (no side effects)', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..toggleNote(0, 0, 67);
      final before = e.renderLoop();
      final empty = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      ).exportCells();
      renderSong(e, [empty, e.exportCells()]);
      expect(e.renderLoop(), equals(before)); // live pattern untouched
    });

    test('an empty order renders nothing', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      );
      expect(wavSamples(renderSong(e, const [])), 0);
    });
  });

  group('instrument palette', () {
    test('every option builds an instrument with a matching id', () {
      expect(kTrackerInstruments, isNotEmpty);
      for (final option in kTrackerInstruments) {
        expect(option.build().id, option.id);
      }
    });

    test('setChannelInstrument re-voices a channel (different bytes)', () {
      final e = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2),
      )..toggleNote(0, 0, 60);
      final before = e.renderLoop();
      final laser = kTrackerInstruments.firstWhere((o) => o.id == 'laser');
      e.setChannelInstrument(0, laser.build());
      expect(e.channels[0].instrument.id, 'laser');
      expect(e.renderLoop(), isNot(equals(before)));
    });
  });

  group('SampleInstrument channel', () {
    Float64List sine(double seconds, double hz) {
      final n = (seconds * kSampleRate).floor();
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        out[i] = sin(2 * pi * hz * i / kSampleRate);
      }
      return out;
    }

    TrackerChannel sampleChannel(int rows, {int baseMidi = 60}) =>
        TrackerChannel(
          id: 'voice',
          instrument:
              SampleInstrument('voice', sine(0.4, 261.63), baseMidi: baseMidi),
          rows: rows,
        );

    test('a note plays the sample; empty is silence; deterministic', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = sampleChannel(timing.rows);
      final silent = ch.instrument.renderChannel(ch.cells, timing);
      expect(silent.length, timing.totalSamples);
      expect(silent.every((v) => v == 0), isTrue);

      ch.cells[0] = const TrackerCell(midi: 60); // base pitch
      final a = ch.instrument.renderChannel(ch.cells, timing);
      final b = ch.instrument.renderChannel(ch.cells, timing);
      expect(a.length, timing.totalSamples);
      expect(a.any((v) => v != 0), isTrue);
      expect(a, equals(b)); // stable stem for the cache
    });

    test('a note starts at its step offset, not before', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final ch = sampleChannel(timing.rows)
        ..cells[4] = const TrackerCell(midi: 60);
      final buf = ch.instrument.renderChannel(ch.cells, timing);
      final startSample = (4 * timing.stepMs * kSampleRate) ~/ 1000;
      expect(buf.sublist(0, startSample).every((v) => v == 0), isTrue);
      expect(buf.sublist(startSample).any((v) => v != 0), isTrue);
    });

    test('9xx sample offset starts the sample at param×256', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      // A rising ramp so the read START position is directly observable.
      final ramp = Float64List(8192);
      for (var i = 0; i < ramp.length; i++) {
        ramp[i] = i / ramp.length;
      }
      final inst = SampleInstrument('r', ramp); // baseMidi 60 → note 60 ratio 1

      List<TrackerCell> col(TrackerCell first) => [
            first,
            ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
          ];

      final plain =
          inst.renderChannel(col(const TrackerCell(midi: 60)), timing);
      final offset = inst.renderChannel(
        // 9x08 → offset 8×256 = 2048 samples into the ramp.
        col(const TrackerCell(midi: 60, fxCmd: 0x9, fxParam: 0x08)),
        timing,
      );
      // Well past the declick attack, the offset read sits higher up the ramp.
      final probe = timing.stepStartSample(0) + 1000;
      expect(plain[probe], greaterThan(0));
      expect(offset[probe], greaterThan(plain[probe]));
    });

    test('a pitch-envelope note glides (differs from a flat-pitch note)', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final s = sine(0.4, 261.63);
      final flat = SampleInstrument('v', s);
      final glided = SampleInstrument(
        'v',
        s,
        envelope: const Envelope(pitchStart: 4), // starts 4 semitones sharp
      );
      final cells = List<TrackerCell>.filled(timing.rows, TrackerCell.empty)
        ..[0] = const TrackerCell(midi: 60);
      final a = flat.renderChannel(cells, timing);
      final b = glided.renderChannel(cells, timing);
      expect(a.length, b.length);
      // The glide reshapes the note's early portion.
      var differs = false;
      for (var i = 0; i < 4000; i++) {
        if ((a[i] - b[i]).abs() > 1e-6) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue);
      expect(b.any((v) => v != 0), isTrue);
    });

    test('a per-cell volume column scales the note (BUG3)', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final inst = SampleInstrument('s', sine(0.4, 261.63));
      List<TrackerCell> col(TrackerCell c) => [
            c,
            ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
          ];
      double peak(Float64List b) => b.fold<double>(
            0,
            (m, v) => v.abs() > m ? v.abs() : m,
          );
      final full = inst.renderChannel(col(const TrackerCell(midi: 60)), timing);
      final quiet = inst.renderChannel(
        col(const TrackerCell(midi: 60, volume: 0.25)),
        timing,
      );
      // A null volume plays full; 0.25 plays at a quarter (not ignored).
      expect(peak(quiet) / peak(full), closeTo(0.25, 0.02));
    });

    test('the recorded factory applies a voice effect', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final inst = SampleInstrument.recorded(
        'voice',
        sine(0.4, 261.63),
        VoiceEffect.robot,
      );
      final ch =
          TrackerChannel(id: 'voice', instrument: inst, rows: timing.rows)
            ..cells[0] = const TrackerCell(midi: 62);
      final buf = inst.renderChannel(ch.cells, timing);
      expect(buf.any((v) => v != 0), isTrue);
    });

    test('a looping sample sustains past its one-shot length', () {
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final short = sine(0.02, 261.63); // ~882 samples, well under the note
      final oneShot = SampleInstrument('v', short); // default loopLength 0
      final looped = SampleInstrument('v', short, loopLength: short.length);
      final cells = List<TrackerCell>.filled(timing.rows, TrackerCell.empty)
        ..[0] = const TrackerCell(midi: 60); // baseMidi 60 → ratio 1
      final a = oneShot.renderChannel(cells, timing);
      final b = looped.renderChannel(cells, timing);
      // Well past the sample's one-shot length: the one-shot has fallen silent…
      final probe = short.length + 20000;
      expect(
        a.sublist(probe, probe + 500).every((v) => v.abs() < 1e-9),
        isTrue,
      );
      // …but the loop is still sounding.
      expect(b.sublist(probe, probe + 500).any((v) => v.abs() > 1e-3), isTrue);
    });

    test('a non-looping sample keeps the one-shot resample path', () {
      // loopLength 0 = no loop → byte-identical to the pre-loop-support render.
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final noLoop = SampleInstrument('v', sine(0.4, 261.63));
      final cells = List<TrackerCell>.filled(timing.rows, TrackerCell.empty)
        ..[0] = const TrackerCell(midi: 60);
      final buf = noLoop.renderChannel(cells, timing);
      expect(noLoop.loops, isFalse);
      expect(buf.any((v) => v != 0), isTrue);
    });
  });

  group('swing', () {
    test('stepOnsetMs delays off-beats only; loop length unchanged', () {
      const straight = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final swung = straight.copyWith(swing: 0.5);
      expect(swung.stepOnsetMs(0), straight.stepOnsetMs(0)); // downbeat
      expect(swung.stepOnsetMs(2), straight.stepOnsetMs(2)); // even step
      expect(swung.stepOnsetMs(1), greaterThan(straight.stepOnsetMs(1)));
      expect(swung.stepOnsetMs(1), closeTo(straight.stepMs * 1.5, 1e-9));
      expect(swung.totalSamples, straight.totalSamples); // total unchanged
    });

    test('a swung render differs from straight for an off-beat note', () {
      final straight =
          TrackerEngine(timing: const TrackerTiming(rows: 8, stepsPerBeat: 2))
            ..setCell(0, 1, const TrackerCell(midi: 60)); // off-beat step
      final dry = straight.renderLoop();
      final swung = TrackerEngine(
        timing: const TrackerTiming(rows: 8, stepsPerBeat: 2, swing: 0.5),
      )..setCell(0, 1, const TrackerCell(midi: 60));
      final swungWav = swung.renderLoop();
      expect(swungWav, isNot(equals(dry)));
      expect(swungWav.length, dry.length); // total loop length preserved
    });
  });

  group('per-channel effect', () {
    test('applyChannelEffect: none is identity; each effect changes the stem',
        () {
      final stem = Float64List(2000);
      for (var i = 0; i < stem.length; i++) {
        stem[i] = 0.6 * sin(2 * pi * 220 * i / kSampleRate);
      }
      expect(applyChannelEffect(stem, TrackerChannelEffect.none), same(stem));
      for (final fx in TrackerChannelEffect.values
          .where((f) => f != TrackerChannelEffect.none)) {
        final out = applyChannelEffect(stem, fx);
        expect(out.length, stem.length);
        var differs = false;
        for (var i = 0; i < stem.length; i++) {
          if ((out[i] - stem[i]).abs() > 1e-6) {
            differs = true;
            break;
          }
        }
        expect(differs, isTrue, reason: '$fx should change the stem');
      }
    });

    test('applyChannelEffects folds a chain; empty chain is dry', () {
      final stem = Float64List(2000);
      for (var i = 0; i < stem.length; i++) {
        stem[i] = 0.6 * sin(2 * pi * 220 * i / kSampleRate);
      }
      expect(applyChannelEffects(stem, const []), same(stem)); // dry
      final chained = applyChannelEffects(
        stem,
        const [TrackerChannelEffect.crunch, TrackerChannelEffect.reverb],
      );
      // A two-effect chain differs from either single effect.
      final onlyCrunch = applyChannelEffect(stem, TrackerChannelEffect.crunch);
      expect(chained.length, stem.length);
      var differs = false;
      for (var i = 0; i < stem.length; i++) {
        if ((chained[i] - onlyCrunch[i]).abs() > 1e-9) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue);
    });

    test(
        'setChannelEffects changes the mix; clearing restores it (cache-aware)',
        () {
      final e =
          TrackerEngine(timing: const TrackerTiming(rows: 8, stepsPerBeat: 2));
      e.setCell(0, 0, const TrackerCell(midi: 60));
      final dry = e.renderLoop();
      e.setChannelEffects(0, const [TrackerChannelEffect.delay]);
      expect(e.renderLoop(), isNot(equals(dry)));
      e.setChannelEffects(0, const []);
      expect(e.renderLoop(), equals(dry));
    });
  });
}
