// D2 mixer: AudioService.mixedWavBytes renders each part as a stem and scales it
// by its per-track gain, so a mixer's volume reaches the mix. Pure (no plugin).

import 'dart:typed_data';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The peak absolute PCM16 sample in a mono WAV (44-byte header).
int _peak(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  var peak = 0;
  for (var i = 44; i + 1 < wav.length; i += 2) {
    final s = data.getInt16(i, Endian.little).abs();
    if (s > peak) peak = s;
  }
  return peak;
}

/// The per-channel peak of an INTERLEAVED (L,R,L,R…) stereo WAV.
({int left, int right}) _stereoPeaks(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  var l = 0, r = 0;
  for (var i = 44; i + 3 < wav.length; i += 4) {
    final ls = data.getInt16(i, Endian.little).abs();
    final rs = data.getInt16(i + 2, Endian.little).abs();
    if (ls > l) l = ls;
    if (rs > r) r = rs;
  }
  return (left: l, right: r);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a per-track gain scales that stem in the mix (quieter → lower peak)',
      () {
    final audio = AudioService();
    const part = <(List<int>, int)>[
      ([60, 64, 67], 500),
    ]; // a half-second C-major chord
    final loud = audio.mixedWavBytes([part]); // default gain 1.0
    final soft = audio.mixedWavBytes([part], gains: [0.3]);

    expect(loud, isNotNull);
    expect(soft, isNotNull);
    final loudPeak = _peak(loud!);
    final softPeak = _peak(soft!);
    expect(loudPeak, greaterThan(0));
    expect(softPeak, greaterThan(0));
    expect(softPeak, lessThan(loudPeak));
  });

  test('an all-silent set of parts renders nothing (null)', () {
    final audio = AudioService();
    expect(audio.mixedWavBytes([<(List<int>, int)>[]]), isNull);
  });

  test('a hard-left pan steers the stem to the left channel', () {
    final audio = AudioService();
    const part = <(List<int>, int)>[
      ([60, 64, 67], 500),
    ];
    final wav = audio.mixedWavBytes([part], pans: [-1.0]);
    expect(wav, isNotNull);
    final peaks = _stereoPeaks(wav!);
    expect(peaks.left, greaterThan(0));
    expect(peaks.right, 0); // constant-power hard-left → nothing on the right
  });

  test('a zero pan stays mono (byte-identical to the no-pan path)', () {
    final audio = AudioService();
    const part = <(List<int>, int)>[
      ([60], 200),
    ];
    final mono = audio.mixedWavBytes([part]);
    final zeroPan = audio.mixedWavBytes([part], pans: [0.0]);
    expect(mono, isNotNull);
    expect(zeroPan, equals(mono));
  });

  test('an in-play metronome click changes the mix (baked in, not silent)', () {
    final audio = AudioService();
    const part = <(List<int>, int)>[
      ([60], 1000), // one long note across several beats
    ];
    final plain = audio.mixedWavBytes([part]);
    final clicked = audio.mixedWavBytes([part], clickBeatMs: 250);
    expect(plain, isNotNull);
    expect(clicked, isNotNull);
    expect(clicked, isNot(equals(plain))); // the clicks are in the WAV
    expect(clicked!.length, plain!.length); // same timeline, not longer
  });

  test('a metronome with no music is still a silent no-op', () {
    final audio = AudioService();
    expect(
      audio.mixedWavBytes([<(List<int>, int)>[]], clickBeatMs: 250),
      isNull,
    );
  });
}
