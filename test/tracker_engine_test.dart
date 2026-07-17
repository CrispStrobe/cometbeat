// TrackerEngine — the Tracker's Flutter-free core. Covers the timing grid, the
// cells->segments note model (sustain-until-next + leading rest), the mixdown
// invariants (silence, no clipping) and the edit/cache behaviour. Mirrors
// loop_engine_test.dart / synth_test.dart: pure Dart, no device audio.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
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
  });

  group('per-channel effect', () {
    test('applyChannelEffect: none is identity; each effect changes the stem',
        () {
      final stem = Float64List(2000);
      for (var i = 0; i < stem.length; i++) {
        stem[i] = 0.6 * sin(2 * pi * 220 * i / kSampleRate);
      }
      expect(applyChannelEffect(stem, TrackerChannelEffect.none), same(stem));
      for (final fx in const [
        TrackerChannelEffect.delay,
        TrackerChannelEffect.chorus,
        TrackerChannelEffect.flanger,
        TrackerChannelEffect.reverb,
      ]) {
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

    test('setChannelEffect changes the mix; none restores it (cache-aware)',
        () {
      final e =
          TrackerEngine(timing: const TrackerTiming(rows: 8, stepsPerBeat: 2));
      e.setCell(0, 0, const TrackerCell(midi: 60));
      final dry = e.renderLoop();
      e.setChannelEffect(0, TrackerChannelEffect.delay);
      expect(e.renderLoop(), isNot(equals(dry)));
      e.setChannelEffect(0, TrackerChannelEffect.none);
      expect(e.renderLoop(), equals(dry));
    });
  });
}
