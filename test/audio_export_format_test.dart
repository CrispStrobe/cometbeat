// Headless coverage for the audio-export format seam.
//
// What this file pins down: **web and any plugin-less platform must see
// precisely the format list they saw before Opus/AAC existed.** A regression
// there is a user-visible failure at save time on the one platform nobody
// tests on.
//
// Every test therefore PINS the encoder with debugSetNativeAudioEncoder rather
// than relying on the ambient probe. That is not belt-and-braces: the FFI
// plugin isn't linked into flutter_tester, but loadGlintEncoder()'s last-resort
// candidate is DynamicLibrary.open('libglint.dylib'), and on a machine with
// glint `make install`ed that resolves a system-wide /usr/local/lib/libglint.dylib
// — this suite caught exactly that. Ambient state is not a test fixture.
//
// The encode path is exercised against a FAKE EncodeAudio, so interleaving,
// channel count and parameter hand-off are verified without a codec. The real
// codec round-trip lives in integration_test/glint_encoder_test.dart (live) and
// native/glint/test/encode_roundtrip_test.cpp (native).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encoded_audio.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the export layer hands the native encoder.
class _FakeEncoder {
  Float64List? pcm;
  int? channels;
  int? sampleRate;
  EncodedAudioFormat? format;
  int? bitrateKbps;
  int calls = 0;

  /// Returns bytes that merely identify the call — this fake is about the
  /// arguments, not the codec.
  Uint8List? encode(
    Float64List interleaved, {
    required int channels,
    required int sampleRate,
    required EncodedAudioFormat format,
    int bitrateKbps = 128,
    int vbrQuality = -1,
    int quality = 5,
  }) {
    calls++;
    pcm = interleaved;
    this.channels = channels;
    this.sampleRate = sampleRate;
    this.format = format;
    this.bitrateKbps = bitrateKbps;
    return Uint8List.fromList([0x4F, 0x67, 0x67, 0x53]); // "OggS"
  }
}

Float64List _ramp(int n, {double scale = 1.0}) => Float64List.fromList([
      for (var i = 0; i < n; i++) (i % 100) / 100.0 * scale,
    ]);

void main() {
  // Every test decides its own encoder state; never leak it between tests.
  tearDown(() => debugSetNativeAudioEncoder(null, probed: false));

  group('format metadata', () {
    test('extensions and native mapping', () {
      expect(AudioExportFormat.wav.ext, 'wav');
      expect(AudioExportFormat.mp3.ext, 'mp3');
      expect(AudioExportFormat.opus.ext, 'opus');
      // AAC is written into an .m4a container by convention.
      expect(AudioExportFormat.aac.ext, 'm4a');

      expect(AudioExportFormat.wav.nativeFormat, isNull);
      expect(AudioExportFormat.mp3.nativeFormat, isNull);
      expect(AudioExportFormat.opus.nativeFormat, EncodedAudioFormat.opus);
      expect(AudioExportFormat.aac.nativeFormat, EncodedAudioFormat.aac);
    });

    test('only wav is uncompressed', () {
      expect(AudioExportFormat.wav.isCompressed, isFalse);
      for (final f in AudioExportFormat.values.where(
        (f) => f != AudioExportFormat.wav,
      )) {
        expect(f.isCompressed, isTrue, reason: '$f');
      }
    });

    test('enum order is append-only', () {
      // Nothing persists this today, but the export UI and any future project
      // field are both happier if new values are appended. Pin the prefix.
      expect(AudioExportFormat.values.take(2).toList(), [
        AudioExportFormat.wav,
        AudioExportFormat.mp3,
      ]);
      expect(AudioExportFormat.wav.index, 0);
      expect(AudioExportFormat.mp3.index, 1);
    });
  });

  group('availability gating', () {
    test('without a native encoder, only the pure-Dart formats are offered',
        () {
      debugSetNativeAudioEncoder(null);
      expect(availableAudioExportFormats(), [
        AudioExportFormat.wav,
        AudioExportFormat.mp3,
      ]);
    });

    test('with a native encoder, all four are offered in enum order', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      expect(availableAudioExportFormats(), AudioExportFormat.values);
    });

    test('an explicitly passed encoder overrides the ambient one', () {
      debugSetNativeAudioEncoder(null);
      final fake = _FakeEncoder();
      expect(
        availableAudioExportFormats(encoder: fake.encode),
        AudioExportFormat.values,
      );
    });

    test('the ambient probe is cached, so it is pinnable', () {
      // Deliberately NOT asserting that nativeAudioEncoder() is null here.
      // loadGlintEncoder()'s last resort is DynamicLibrary.open('libglint.dylib'),
      // which on a machine with glint `make install`ed resolves a system-wide
      // /usr/local/lib/libglint.dylib even under `flutter test` — this suite
      // found exactly that. Environment facts don't belong in assertions; what
      // matters is that the probe runs once and can be pinned, which is what
      // lets the tests above prove both branches deterministically.
      var probes = 0;
      Uint8List? counting(
        Float64List pcm, {
        required int channels,
        required int sampleRate,
        required EncodedAudioFormat format,
        int bitrateKbps = 128,
        int vbrQuality = -1,
        int quality = 5,
      }) {
        probes++;
        return Uint8List.fromList([1]);
      }

      debugSetNativeAudioEncoder(counting);
      expect(identical(nativeAudioEncoder(), counting), isTrue);
      expect(
        identical(nativeAudioEncoder(), counting),
        isTrue,
        reason: 'second call must not re-probe',
      );
      expect(probes, 0, reason: 'probing must not encode anything');
    });

    test('needsNativeEncoder matches nativeFormat, for every value', () {
      for (final f in AudioExportFormat.values) {
        expect(
          f.needsNativeEncoder,
          f.nativeFormat != null,
          reason: '$f disagrees with itself',
        );
      }
    });
  });

  group('pure-Dart formats still work with no encoder present', () {
    test('wav builds', () {
      debugSetNativeAudioEncoder(null);
      final bytes = AudioExportFormat.wav.build(_ramp(1000), 44100);
      expect(bytes.length, 44 + 1000 * 2);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
    });

    test('mp3 builds', () {
      debugSetNativeAudioEncoder(null);
      final bytes = AudioExportFormat.mp3.build(_ramp(4608), 44100);
      expect(bytes.length, greaterThan(100));
      expect(bytes[0], 0xFF, reason: 'MPEG frame sync');
    });
  });

  _mp3EncoderChoice();

  group('native formats route to the encoder', () {
    test('mono: PCM passes through unchanged, 1 channel', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      final pcm = _ramp(500);

      final bytes = AudioExportFormat.opus.build(pcm, 48000, bitrate: 96);

      expect(fake.calls, 1);
      expect(fake.channels, 1);
      expect(fake.sampleRate, 48000);
      expect(fake.format, EncodedAudioFormat.opus);
      expect(fake.bitrateKbps, 96);
      expect(fake.pcm!.length, 500);
      expect(fake.pcm![7], pcm[7]);
      expect(String.fromCharCodes(bytes), 'OggS');
    });

    test('stereo: channels are interleaved L,R,L,R', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      final left = _ramp(200);
      final right = _ramp(200, scale: -1.0);

      AudioExportFormat.aac.build(left, 44100, right: right);

      expect(fake.channels, 2);
      expect(fake.format, EncodedAudioFormat.aac);
      expect(fake.pcm!.length, 400);
      for (var i = 0; i < 200; i++) {
        expect(fake.pcm![i * 2], left[i], reason: 'left at frame $i');
        expect(fake.pcm![i * 2 + 1], right[i], reason: 'right at frame $i');
      }
    });

    test('a shorter channel is zero-padded, not truncated', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      final left = _ramp(300);
      final right = _ramp(100);

      AudioExportFormat.opus.build(left, 48000, right: right);

      expect(fake.pcm!.length, 600, reason: 'frames = max(len), not min');
      expect(fake.pcm![299 * 2], left[299]);
      expect(fake.pcm![299 * 2 + 1], 0.0);
    });

    test('exportSampleRate resamples before handing over', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);

      AudioExportFormat.opus.build(
        _ramp(4410),
        44100,
        exportSampleRate: 22050,
      );

      expect(fake.sampleRate, 22050);
      // Half the rate over the same duration => about half the frames.
      expect(fake.pcm!.length, closeTo(2205, 5));
    });

    test('an encoder that returns null throws, so no truncated file is written',
        () {
      debugSetNativeAudioEncoder(
        (
          Float64List pcm, {
          required int channels,
          required int sampleRate,
          required EncodedAudioFormat format,
          int bitrateKbps = 128,
          int vbrQuality = -1,
          int quality = 5,
        }) =>
            null,
      );
      expect(
        () => AudioExportFormat.opus.build(_ramp(500), 48000),
        throwsA(isA<StateError>()),
      );
    });

    test('an encoder that returns empty bytes throws too', () {
      debugSetNativeAudioEncoder(
        (
          Float64List pcm, {
          required int channels,
          required int sampleRate,
          required EncodedAudioFormat format,
          int bitrateKbps = 128,
          int vbrQuality = -1,
          int quality = 5,
        }) =>
            Uint8List(0),
      );
      expect(
        () => AudioExportFormat.aac.build(_ramp(500), 48000),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'picking a native format with no encoder throws rather than silently '
        'writing something else', () {
      debugSetNativeAudioEncoder(null);
      expect(
        () => AudioExportFormat.opus.build(_ramp(500), 48000),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// MP3 has TWO encoders — our pure-Dart port and glint's C one. This pins which
/// one each request actually reaches, because the failure mode is silent: the
/// wrong encoder still produces a valid MP3, just different bytes (or, on a
/// platform without glint, no file at all if we refused instead of falling
/// back).
void _mp3EncoderChoice() {
  group('MP3 encoder selection', () {
    test('the default is the pure-Dart encoder', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      final bytes = AudioExportFormat.mp3.build(_ramp(4608), 44100);
      expect(fake.calls, 0, reason: 'must NOT reach glint by default');
      expect(bytes[0], 0xFF, reason: 'a real MP3 from the Dart writer');
    });

    test('asking for native routes to glint as MP3', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      AudioExportFormat.mp3.build(
        _ramp(4608),
        44100,
        mp3Encoder: Mp3Encoder.native,
      );
      expect(fake.calls, 1);
      expect(fake.format, EncodedAudioFormat.mp3,
          reason: 'not opus/aac by accident');
    });

    test('native MP3 falls back to Dart when glint is absent', () {
      // Unlike Opus/AAC, MP3 always has a working path, so refusing would be
      // gratuitous — a user picking "native" on web must still get a file.
      debugSetNativeAudioEncoder(null);
      final bytes = AudioExportFormat.mp3.build(
        _ramp(4608),
        44100,
        mp3Encoder: Mp3Encoder.native,
      );
      expect(bytes.length, greaterThan(100));
      expect(bytes[0], 0xFF);
    });

    test('the choice does not leak into the other formats', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      // WAV stays pure Dart whatever the MP3 setting says.
      final wav = AudioExportFormat.wav.build(
        _ramp(500),
        44100,
        mp3Encoder: Mp3Encoder.native,
      );
      expect(String.fromCharCodes(wav.take(4)), 'RIFF');
      expect(fake.calls, 0);
      // Opus is always native, and Mp3Encoder.dart must not divert it.
      AudioExportFormat.opus.build(
        _ramp(500),
        48000,
        mp3Encoder: Mp3Encoder.dart,
      );
      expect(fake.calls, 1);
      expect(fake.format, EncodedAudioFormat.opus);
    });

    test('bitrate reaches whichever encoder was chosen', () {
      final fake = _FakeEncoder();
      debugSetNativeAudioEncoder(fake.encode);
      AudioExportFormat.mp3.build(
        _ramp(4608),
        44100,
        bitrate: 320,
        mp3Encoder: Mp3Encoder.native,
      );
      expect(fake.bitrateKbps, 320);
    });

    test('both encoders are labelled for the picker', () {
      expect(Mp3Encoder.values.length, 2);
      for (final e in Mp3Encoder.values) {
        expect(e.label, isNotEmpty);
      }
      expect(Mp3Encoder.dart.index, 0, reason: 'default first');
    });
  });
}
