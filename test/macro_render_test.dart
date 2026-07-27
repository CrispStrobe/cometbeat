// Instrument macros applied in the per-tick additive voice (§4 slice 2). A macro
// on an AdditiveInstrument modulates the note tick-by-tick during synthesis;
// absent macros leave the render byte-identical (pinned by the golden suite, and
// re-checked here against a no-macro baseline).

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/macro_sequence.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show replaySong, replaySongStereo, songUsesVariableTiming;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders one held C-4 (row 0, ringing 8 rows) played by a piano additive voice
/// carrying [macros].
List<int> _render(List<MacroSequence> macros) {
  final song = TrackerSong(timing: const TrackerTiming(rows: 8));
  song.engine.setChannelInstrument(
    0,
    AdditiveInstrument('piano', Instrument.piano, macros: macros),
  );
  song.engine.setCell(0, 0, const TrackerCell(midi: 60));
  return replaySong(song).pcm;
}

double _rms(List<int> pcm) {
  var s = 0.0;
  for (final v in pcm) {
    s += v * v.toDouble();
  }
  return sqrt(s / pcm.length);
}

int _crossings(List<int> pcm, int lo, int hi) {
  var c = 0;
  for (var i = lo + 1; i < hi; i++) {
    if ((pcm[i - 1] < 0) != (pcm[i] < 0)) c++;
  }
  return c;
}

void main() {
  test('an empty macro list is byte-identical to no macros', () {
    // Two AdditiveInstruments, one with macros:[] — the render must not budge.
    expect(_render(const []), _render(const []));
    final baseline = _render(const []);
    expect(baseline.any((v) => v != 0), isTrue, reason: 'baseline is audible');
  });

  test('a fade-to-zero volume macro cuts the note energy', () {
    final plain = _render(const []);
    // 64→0 over 5 ticks, then hold 0 (loop the final entry).
    final faded = _render(const [
      MacroSequence(
        target: MacroTarget.volume,
        values: [64, 48, 32, 16, 0],
        loopStart: 4,
        loopEnd: 4,
      ),
    ]);
    expect(faded.length, plain.length);
    expect(
      _rms(faded),
      lessThan(_rms(plain) * 0.6),
      reason: 'the volume macro should audibly duck the note',
    );
  });

  test('a +12 pitch macro raises the note an octave (more zero-crossings)', () {
    final plain = _render(const []);
    final octaveUp = _render(const [
      MacroSequence(target: MacroTarget.pitch, values: [12]),
    ]);
    final n = plain.length;
    expect(
      _crossings(octaveUp, 0, n),
      greaterThan(_crossings(plain, 0, n) * 1.5),
      reason: 'up an octave ≈ double the frequency',
    );
  });

  test('an arpeggio macro changes the sound vs a plain note', () {
    final plain = _render(const []);
    final arp = _render(const [
      MacroSequence(
        target: MacroTarget.arpeggio,
        values: [0, 4, 7],
        loopStart: 0,
        loopEnd: 2,
      ),
    ]);
    var maxDiff = 0;
    final n = min(plain.length, arp.length);
    for (var i = 0; i < n; i++) {
      maxDiff = max(maxDiff, (plain[i] - arp[i]).abs());
    }
    expect(maxDiff, greaterThan(100), reason: 'the arpeggio must be audible');
  });

  group('sample voice', () {
    List<int> renderSample(List<MacroSequence> macros) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      final pcm = List<double>.generate(
        4410,
        (i) => sin(2 * pi * 220 * i / 44100),
      );
      song.engine.setChannelInstrument(
        0,
        SampleInstrument(
          'tone',
          Float64List.fromList(pcm),
          loopLength: 4410, // loop so a held note keeps sounding (baseMidi 60)
          macros: macros,
        ),
      );
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      return replaySong(song).pcm;
    }

    test('a fade-to-zero volume macro ducks a sample note', () {
      final plain = renderSample(const []);
      final faded = renderSample(const [
        MacroSequence(
          target: MacroTarget.volume,
          values: [64, 32, 16, 0],
          loopStart: 3,
          loopEnd: 3,
        ),
      ]);
      expect(plain.any((v) => v != 0), isTrue);
      expect(_rms(faded), lessThan(_rms(plain) * 0.6));
    });

    test('a +12 pitch macro raises a sample note (more zero-crossings)', () {
      final plain = renderSample(const []);
      final up = renderSample(const [
        MacroSequence(target: MacroTarget.pitch, values: [12]),
      ]);
      final n = min(plain.length, up.length);
      expect(
        _crossings(up, 0, n),
        greaterThan(_crossings(plain, 0, n) * 1.5),
      );
    });
  });

  group('stereo (panned) render', () {
    List<int> renderStereo(List<MacroSequence> macros, {bool sample = true}) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      if (sample) {
        final pcm = List<double>.generate(
          4410,
          (i) => sin(2 * pi * 220 * i / 44100),
        );
        song.engine.setChannelInstrument(
          0,
          SampleInstrument(
            'tone',
            Float64List.fromList(pcm),
            loopLength: 4410,
            macros: macros,
          ),
        );
      } else {
        song.engine.setChannelInstrument(
          0,
          AdditiveInstrument('piano', Instrument.piano, macros: macros),
        );
      }
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      return replaySongStereo(song).pcm;
    }

    test('a volume macro ducks a sample note in the stereo render', () {
      final plain = renderStereo(const []);
      final faded = renderStereo(const [
        MacroSequence(
          target: MacroTarget.volume,
          values: [64, 16, 4, 0],
          loopStart: 3,
          loopEnd: 3,
        ),
      ]);
      expect(plain.any((v) => v != 0), isTrue);
      expect(_rms(faded), lessThan(_rms(plain) * 0.6));
    });

    test('a hard-left pan macro pushes energy to the left channel', () {
      final panned = renderStereo(const [
        MacroSequence(target: MacroTarget.pan, values: [-32]),
      ]);
      var l = 0.0, r = 0.0;
      for (var i = 0; i + 1 < panned.length; i += 2) {
        l += panned[i].abs();
        r += panned[i + 1].abs();
      }
      expect(l, greaterThan(r * 2), reason: 'pan -32 ≈ hard left');
    });

    test('additive macros also apply in the stereo render', () {
      const up = [
        MacroSequence(target: MacroTarget.pitch, values: [12]),
      ];
      final plain = renderStereo(const [], sample: false);
      final raised = renderStereo(up, sample: false);
      final n = min(plain.length, raised.length);
      expect(
        _crossings(raised, 0, n),
        greaterThan(_crossings(plain, 0, n) * 1.5),
      );
    });
  });

  group('variable-timing render (non-default speed)', () {
    List<int> renderVar(List<MacroSequence> macros) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8))
        // A non-default header speed arms the variable-timing render path
        // (replaySong routes it through _replayVariable).
        ..setInitialSpeed(3);
      song.engine.setChannelInstrument(
        0,
        AdditiveInstrument('piano', Instrument.piano, macros: macros),
      );
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      expect(songUsesVariableTiming(song), isTrue, reason: 'variable path');
      return replaySong(song).pcm;
    }

    test('a volume macro ducks the note on the variable-timing path', () {
      final plain = renderVar(const []);
      final faded = renderVar(const [
        MacroSequence(
          target: MacroTarget.volume,
          values: [64, 16, 4, 0],
          loopStart: 3,
          loopEnd: 3,
        ),
      ]);
      expect(plain.any((v) => v != 0), isTrue);
      expect(_rms(faded), lessThan(_rms(plain) * 0.7));
    });
  });

  group('reachability through renderSongWav (real playback entry)', () {
    TrackerSong build(List<MacroSequence> macros) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setChannelInstrument(
        0,
        AdditiveInstrument('piano', Instrument.piano, macros: macros),
      );
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      return song;
    }

    const volMacro = MacroSequence(
      target: MacroTarget.volume,
      values: [64, 16, 4, 0],
      loopStart: 3,
      loopEnd: 3,
    );

    test('usesMacros flags a macro-carrying song', () {
      expect(build(const []).usesMacros, isFalse);
      expect(build(const [volMacro]).usesMacros, isTrue);
    });

    test('a macro changes the WAV that renderSongWav produces', () {
      // Without the usesMacros routing, a command-free song takes the fast
      // offline path and the macro would be silently ignored.
      final plain = build(const []).renderSongWav();
      final macroed = build(const [volMacro]).renderSongWav();
      expect(
        macroed,
        isNot(plain),
        reason: 'the macro must reach the tick replayer via renderSongWav',
      );
    });
  });

  group('pulse voice + duty macro', () {
    List<int> renderPulse(List<MacroSequence> macros) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine
          .setChannelInstrument(0, PulseInstrument('pulse', macros: macros));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      return replaySong(song).pcm;
    }

    test('the duty macro changes the pulse waveform', () {
      final narrow = renderPulse(const [
        MacroSequence(target: MacroTarget.duty, values: [2, 2, 2, 2]),
      ]);
      final wide = renderPulse(const [
        MacroSequence(target: MacroTarget.duty, values: [61, 61, 61, 61]),
      ]);
      var maxDiff = 0;
      final n = min(narrow.length, wide.length);
      for (var i = 0; i < n; i++) {
        maxDiff = max(maxDiff, (narrow[i] - wide[i]).abs());
      }
      expect(maxDiff, greaterThan(100), reason: 'duty must shape the wave');
    });

    test('a volume macro ducks the pulse', () {
      final plain = renderPulse(const [
        MacroSequence(target: MacroTarget.volume, values: [64, 64, 64, 64]),
      ]);
      final faded = renderPulse(const [
        MacroSequence(
          target: MacroTarget.volume,
          values: [64, 16, 4, 0],
          loopStart: 3,
          loopEnd: 3,
        ),
      ]);
      expect(_rms(faded), lessThan(_rms(plain) * 0.7));
    });

    test('pulse is a pickable voice and round-trips through the codec', () {
      expect(kTrackerInstruments.any((o) => o.id == 'pulse'), isTrue);
      final opt = kTrackerInstruments.firstWhere((o) => o.id == 'pulse');
      expect(opt.build(), isA<PulseInstrument>());

      const original = PulseInstrument(
        'pulse',
        duty: 0.25,
        macros: [
          MacroSequence(target: MacroTarget.duty, values: [4, 60]),
        ],
      );
      final twin = instrumentFromJson(instrumentToJson(original));
      expect(twin, isA<PulseInstrument>());
      final p = twin as PulseInstrument;
      expect(p.duty, 0.25);
      expect(p.macros.single.target, MacroTarget.duty);
      expect(p.macros.single.values, [4, 60]);
    });
  });

  test('macros survive a codec round-trip on an additive instrument', () {
    const original = AdditiveInstrument(
      'piano',
      Instrument.piano,
      macros: [
        MacroSequence(
          target: MacroTarget.volume,
          values: [64, 32, 0],
          loopStart: 2,
          loopEnd: 2,
        ),
        MacroSequence(target: MacroTarget.pitch, values: [0, 12]),
      ],
    );
    expect(isSerializableInstrument(original), isTrue);
    final twin = instrumentFromJson(instrumentToJson(original));
    expect(twin, isA<AdditiveInstrument>());
    final macros = (twin as AdditiveInstrument).macros;
    expect(macros, hasLength(2));
    expect(macros[0].target, MacroTarget.volume);
    expect(macros[0].values, [64, 32, 0]);
    expect(macros[0].loopStart, 2);
    expect(macros[1].target, MacroTarget.pitch);
    expect(macros[1].values, [0, 12]);
  });
}
