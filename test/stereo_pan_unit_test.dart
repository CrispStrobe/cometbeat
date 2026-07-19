// Unit tests for Feature C (stereo + panning) internals — complements the
// orchestrator's stereo_pan_acceptance_test.dart. Owned by the feature agent.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

Float64List _tone({int n = 2000, double hz = 220}) => Float64List.fromList([
      for (var i = 0; i < n; i++) sin(2 * pi * hz * i / kSampleRate),
    ]);

double _energyOf(Uint8List wav, {required int channel}) {
  final data = ByteData.sublistView(wav);
  var e = 0.0;
  final off = channel == 0 ? 44 : 46; // L at 44, R at 46 in each 4-byte frame
  for (var i = off; i + 1 < wav.length; i += 4) {
    e += data.getInt16(i, Endian.little).abs();
  }
  return e;
}

void main() {
  group('synth stereo primitives', () {
    test('mixStemsStereo: constant-power centre keeps ~equal total power', () {
      final sig = _tone();
      final mix = mixStemsStereo(
        [(samples: sig, gain: 0.8, pan: 0.0)],
        totalSamples: sig.length,
      );
      // Centre = cos(pi/4)=sin(pi/4): each side is the same non-zero signal.
      var any = false;
      for (var i = 0; i < sig.length; i++) {
        expect(mix[i * 2], mix[i * 2 + 1]);
        if (mix[i * 2] != 0) any = true;
      }
      expect(any, isTrue);
    });

    test('mixStemsStereo: empty stems = interleaved silence', () {
      final mix = mixStemsStereo(const [], totalSamples: 10);
      expect(mix.length, 20);
      expect(mix.every((s) => s == 0), isTrue);
    });

    test('mixStemsStereo: a non-panned song equals mono mix duplicated', () {
      final sig = _tone();
      final stereo = mixStemsStereo(
        [(samples: sig, gain: 0.8, pan: 0.0)],
        totalSamples: sig.length,
      );
      // The mono mix scales by 1.0 per side; centre pan scales each by ~0.707,
      // so they are NOT identical — but L and R must mirror each other exactly.
      for (var i = 0; i < sig.length; i++) {
        expect(stereo[i * 2], stereo[i * 2 + 1]);
      }
    });

    test('wavBytesStereo: odd length asserts', () {
      expect(
        () => wavBytesStereo(Int16List.fromList([1, 2, 3])),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('channel pan (offline engine path)', () {
    test('setChannelPan invalidates + renders stereo', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.engine.setChannelPan(0, 1.0); // hard right
      s.syncCurrent();
      expect(s.usesPan, isTrue);
      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 2);
      expect(
        _energyOf(wav, channel: 1),
        greaterThan(_energyOf(wav, channel: 0) * 4),
      );
    });

    test('usesPan false → mono, and toggling pan back to 0 is mono again', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.engine.setChannelPan(0, -1.0);
      s.engine.setChannelPan(0, 0.0);
      s.syncCurrent();
      expect(s.usesPan, isFalse);
      expect(_u16(s.renderCurrentPatternWav(), 22), 1);
    });
  });

  group('8xx pan command (replayer path)', () {
    test('8x00 pans a note hard left; usesPan flips true', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(
        0,
        0,
        const TrackerCell(midi: 60, fxCmd: kFxSetPan), // param 0x00 = hard left
      );
      s.syncCurrent();
      expect(s.usesPan, isTrue);
      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 2);
      expect(
        _energyOf(wav, channel: 0),
        greaterThan(_energyOf(wav, channel: 1) * 4),
      );
    });

    test('8xFF pans a note hard right', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(
        0,
        0,
        const TrackerCell(midi: 60, fxCmd: kFxSetPan, fxParam: 0xFF),
      );
      s.syncCurrent();
      final wav = s.renderCurrentPatternWav();
      expect(
        _energyOf(wav, channel: 1),
        greaterThan(_energyOf(wav, channel: 0) * 4),
      );
    });
  });

  group('Pxy pan slide (replayer path)', () {
    // Energy of [channel] over the last quarter of a stereo WAV's frames.
    double tailEnergy(Uint8List wav, {required int channel}) {
      final data = ByteData.sublistView(wav);
      final frames = (wav.length - 44) ~/ 4;
      var e = 0.0;
      for (var f = (frames * 3) ~/ 4; f < frames; f++) {
        final i = 44 + f * 4 + (channel == 0 ? 0 : 2);
        e += data.getInt16(i, Endian.little).abs();
      }
      return e;
    }

    test('PF0 slides the pan right over the pattern; usesPan flips true', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 8));
      // Retrigger a note each row and slide the pan hard right (PF0).
      for (var r = 0; r < 8; r++) {
        s.engine.setCell(
          0,
          r,
          const TrackerCell(midi: 60, fxCmd: kFxPanSlide, fxParam: 0xF0),
        );
      }
      s.syncCurrent();
      expect(s.usesPan, isTrue); // Pxy arms the stereo render
      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 2); // stereo
      // By the tail the pan has slid hard right → right louder than left.
      expect(
        tailEnergy(wav, channel: 1),
        greaterThan(tailEnergy(wav, channel: 0)),
      );
    });

    test('PxY (leftward) is the mirror; a plain song stays mono', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 8));
      for (var r = 0; r < 8; r++) {
        s.engine.setCell(
          0,
          r,
          const TrackerCell(midi: 60, fxCmd: kFxPanSlide, fxParam: 0x0F),
        );
      }
      s.syncCurrent();
      final wav = s.renderCurrentPatternWav();
      expect(
        tailEnergy(wav, channel: 0),
        greaterThan(tailEnergy(wav, channel: 1)),
      );

      // No pan command anywhere → mono, byte-cheap.
      final plain = TrackerSong(timing: const TrackerTiming(rows: 4));
      plain.engine.setCell(0, 0, const TrackerCell(midi: 60));
      plain.syncCurrent();
      expect(plain.usesPan, isFalse);
    });

    test('a variable-timing panned song still slides the pan (Pxy)', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 6));
      for (var r = 0; r < 6; r++) {
        s.engine.setCell(
          0,
          r,
          const TrackerCell(midi: 60, fxCmd: kFxPanSlide, fxParam: 0xF0),
        );
      }
      // A mid-song tempo change forces the variable-timing stereo path.
      s.engine
          .setCell(1, 2, const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x50));
      s.syncCurrent();
      expect(s.usesPan, isTrue);
      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 2);
      expect(
        tailEnergy(wav, channel: 1),
        greaterThan(tailEnergy(wav, channel: 0)),
      );
    });
  });

  group('global volume on the stereo path', () {
    int wavPeak(Uint8List wav) {
      final d = ByteData.sublistView(wav);
      var p = 0;
      for (var i = 44; i + 1 < wav.length; i += 2) {
        final v = d.getInt16(i, Endian.little).abs();
        if (v > p) p = v;
      }
      return p;
    }

    test('G00 silences a panned (stereo) song', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      // A note + G00 on ch0; an 8xx on ch1 arms the stereo render.
      s.engine.setCell(
        0,
        0,
        const TrackerCell(midi: 60, fxCmd: kFxSetGlobalVolume),
      ); // G00
      s.engine.setCell(1, 0, const TrackerCell(fxCmd: kFxSetPan)); // 8x00 left
      s.syncCurrent();
      expect(s.usesPan, isTrue);
      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 2); // stereo
      expect(wavPeak(wav), 0); // global volume 0 → silent
    });
  });

  group('mono regression (byte-identity)', () {
    test('a plain song renders byte-identical with the feature added', () {
      Uint8List render() {
        final s = TrackerSong(timing: const TrackerTiming(rows: 8));
        s.engine.setCell(0, 0, const TrackerCell(midi: 60));
        s.engine.setCell(0, 4, const TrackerCell(midi: 64));
        s.syncCurrent();
        return s.renderSongWav();
      }

      final a = render();
      final b = render();
      expect(a, equals(b));
      expect(_u16(a, 22), 1); // still mono
    });
  });
}
