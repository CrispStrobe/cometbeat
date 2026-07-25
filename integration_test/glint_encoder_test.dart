// LIVE test for the native glint encoder, on a real app build.
//
// Headless `flutter test` cannot prove this: the FFI plugin isn't linked into
// flutter_tester, so what `loadGlintEncoder()` finds there is at best a
// system-wide libglint.dylib that happens to be installed — not the library the
// app actually ships. This test runs against a real build, where the plugin IS
// linked, and proves the shipped path end to end.
//
// Run:
//   flutter test integration_test/glint_encoder_test.dart -d macos
//
// The app's convention is render -> decode -> assert, not "it compiled", so the
// core assertion is that a 440 Hz tone survives encode + decode with its PITCH
// intact. Opus resamples to 48 kHz internally, so we assert the pitch, NEVER
// the sample rate.
//
// Unlike the other integration suites this does NOT skip itself when the
// encoder is missing: on a real build a null encoder IS the bug this file
// exists to catch.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encode_capability.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const int _kRate = 48000;

Float64List _tone(
  double freq,
  double seconds, {
  int rate = _kRate,
  double amp = 0.5,
}) {
  final n = (rate * seconds).round();
  final pcm = Float64List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = amp * math.sin(2 * math.pi * freq * i / rate);
  }
  return pcm;
}

/// Autocorrelation pitch estimate over one channel of interleaved PCM.
///
/// Same two traps as the native version of this test: every lag must correlate
/// the SAME number of terms (otherwise long lags are inflated and an 880 Hz
/// tone reads as 80 Hz), and a periodic signal correlates just as well at 2T
/// as at T — so take the first strong peak, not the global max. Parabolic
/// interpolation matters too: an 880 Hz period is 54.5 samples at 48 kHz.
double _estimatePitch(Float64List pcm, int channels, int channel, int rate) {
  final frames = pcm.length ~/ channels;
  final skip = math.min(frames ~/ 4, rate ~/ 4);
  final n = math.min(frames - skip, rate ~/ 2);
  if (n < 2048) return 0;
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    x[i] = pcm[(skip + i) * channels + channel];
  }

  final minLag = rate ~/ 2000;
  var maxLag = rate ~/ 50;
  if (maxLag >= n ~/ 2) maxLag = n ~/ 2 - 1;
  if (maxLag <= minLag) return 0;
  final terms = n - maxLag;

  final r = Float64List(maxLag + 1);
  var peak = 0.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    var s = 0.0;
    for (var i = 0; i < terms; i++) {
      s += x[i] * x[i + lag];
    }
    r[lag] = s;
    if (s > peak) peak = s;
  }
  if (peak <= 0) return 0;

  var best = 0;
  for (var lag = minLag + 1; lag < maxLag; lag++) {
    if (r[lag] >= 0.85 * peak && r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1]) {
      best = lag;
      break;
    }
  }
  if (best <= 0) return 0;
  final y0 = r[best - 1], y1 = r[best], y2 = r[best + 1];
  final denom = 2 * (2 * y1 - y0 - y2);
  final refined = denom != 0 ? best + (y2 - y0) / denom : best.toDouble();
  return refined > 0 ? rate / refined : 0.0;
}

double _rms(Float64List pcm, int channels, int channel) {
  final frames = pcm.length ~/ channels;
  if (frames == 0) return 0;
  var s = 0.0;
  for (var i = 0; i < frames; i++) {
    final v = pcm[i * channels + channel];
    s += v * v;
  }
  return math.sqrt(s / frames);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late EncodeAudio encode;
  late OpusFileDecode decodeOpus;

  setUpAll(() {
    final loaded = loadGlintEncoder();
    expect(
      loaded,
      isNotNull,
      reason: 'the glint FFI plugin must be linked into a real app build — '
          'if this is null, native/glint is not in the build',
    );
    encode = loaded!;
    final dec = loadOpusFileDecoder();
    expect(dec, isNotNull, reason: 'cometbeat_opus_file_decode must resolve');
    decodeOpus = dec!;
  });

  testWidgets('the calibration signal is what we think it is', (_) async {
    // Measure the instrument before measuring the codec with it.
    for (final f in [110.0, 440.0, 880.0]) {
      expect(_estimatePitch(_tone(f, 1.0), 1, 0, _kRate), closeTo(f, 1.0));
    }
  });

  testWidgets('a 440 Hz tone survives Opus encode + decode', (_) async {
    // 44.1 kHz in — Opus must resample it and still come back in tune.
    final pcm = _tone(440, 2.0, rate: 44100);
    final bytes = encode(
      pcm,
      channels: 1,
      sampleRate: 44100,
      format: EncodedAudioFormat.opus,
      bitrateKbps: 96,
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), 'OggS');

    final decoded = decodeOpus(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.channels, 1);
    expect(decoded.sampleRate, 48000, reason: 'Opus always decodes at 48 kHz');
    final seconds = decoded.frames / 48000;
    expect(seconds, closeTo(2.0, 0.3));

    // The assertion that matters: pitch, not sample rate.
    expect(
      _estimatePitch(decoded.pcm, 1, 0, decoded.sampleRate),
      closeTo(440.0, 3.0),
    );
  });

  testWidgets('hard-panned stereo does not collapse or swap', (_) async {
    final left = _tone(440, 2.0);
    final right = _tone(880, 2.0);
    final interleaved = Float64List(left.length * 2);
    for (var i = 0; i < left.length; i++) {
      interleaved[i * 2] = left[i];
      interleaved[i * 2 + 1] = right[i];
    }

    final bytes = encode(
      interleaved,
      channels: 2,
      sampleRate: _kRate,
      format: EncodedAudioFormat.opus,
      bitrateKbps: 128,
    );
    expect(bytes, isNotNull);
    final decoded = decodeOpus(bytes!);
    expect(decoded, isNotNull);
    expect(decoded!.channels, 2, reason: 'must stay stereo');

    final l = _estimatePitch(decoded.pcm, 2, 0, decoded.sampleRate);
    final r = _estimatePitch(decoded.pcm, 2, 1, decoded.sampleRate);
    expect(l, closeTo(440.0, 4.0), reason: 'left channel');
    expect(r, closeTo(880.0, 6.0), reason: 'right channel — a swap reads 440');
  });

  testWidgets('a silent channel stays silent', (_) async {
    final left = _tone(440, 1.5);
    final interleaved = Float64List(left.length * 2);
    for (var i = 0; i < left.length; i++) {
      interleaved[i * 2] = left[i];
    }
    final bytes = encode(
      interleaved,
      channels: 2,
      sampleRate: _kRate,
      format: EncodedAudioFormat.opus,
      bitrateKbps: 128,
    );
    final decoded = decodeOpus(bytes!);
    expect(decoded, isNotNull);
    final l = _rms(decoded!.pcm, 2, 0);
    final r = _rms(decoded.pcm, 2, 1);
    expect(l, greaterThan(0.2));
    expect(r, lessThan(l * 0.1), reason: 'right must not pick up the tone');
  });

  testWidgets('MP3 and AAC produce structurally valid streams', (_) async {
    final pcm = _tone(440, 1.0, rate: 44100);
    for (final (format, name) in [
      (EncodedAudioFormat.mp3, 'MP3'),
      (EncodedAudioFormat.aac, 'AAC'),
    ]) {
      final bytes = encode(
        pcm,
        channels: 1,
        sampleRate: 44100,
        format: format,
        bitrateKbps: 128,
      );
      expect(bytes, isNotNull, reason: name);
      expect(bytes!.length, greaterThan(1000), reason: name);
      expect(bytes[0], 0xFF, reason: '$name frame sync');
      if (format == EncodedAudioFormat.aac) {
        // ADTS: 12-bit sync, layer bits 00.
        expect(bytes[1] & 0xF6, 0xF0, reason: 'ADTS header');
      } else {
        expect(bytes[1] & 0xE0, 0xE0, reason: 'MPEG header');
        expect(bytes[1] & 0xF6, isNot(0xF0), reason: 'MP3 is not ADTS');
      }
    }
  });

  testWidgets('the export layer offers the native formats here', (_) async {
    // On a real build, availableAudioExportFormats() must include Opus/AAC —
    // this is the user-visible half of "the symbol resolved".
    debugSetNativeAudioEncoder(null, probed: false); // force a fresh probe
    expect(availableAudioExportFormats(), AudioExportFormat.values);

    // And the export path itself must produce a playable Opus file.
    final bytes = AudioExportFormat.opus.build(
      _tone(440, 1.0, rate: 44100),
      44100,
      bitrate: 96,
    );
    final decoded = decodeOpus(bytes);
    expect(decoded, isNotNull);
    expect(
      _estimatePitch(decoded!.pcm, decoded.channels, 0, decoded.sampleRate),
      closeTo(440.0, 3.0),
    );
  });

  testWidgets('repeated encoding does not leak or degrade', (_) async {
    // A wrong glint_free shows up here, not in a single-shot smoke test.
    final pcm = _tone(440, 0.25);
    for (var i = 0; i < 200; i++) {
      final bytes = encode(
        pcm,
        channels: 1,
        sampleRate: _kRate,
        format: EncodedAudioFormat.opus,
        bitrateKbps: 96,
      );
      expect(bytes, isNotNull, reason: 'iteration $i');
      expect(bytes!.length, greaterThan(200), reason: 'iteration $i');
    }
    // Still correct after 200 rounds — a corrupted heap would show up as a
    // crash above or as garbage here.
    final decoded = decodeOpus(
      encode(
        _tone(440, 1.0),
        channels: 1,
        sampleRate: _kRate,
        format: EncodedAudioFormat.opus,
        bitrateKbps: 96,
      )!,
    );
    expect(decoded, isNotNull);
    expect(
      _estimatePitch(decoded!.pcm, 1, 0, decoded.sampleRate),
      closeTo(440.0, 3.0),
    );
  });
}
