@TestOn('browser')
library;

// The WEB half of the codec seam, compiled and executed as web code.
//
// `flutter analyze` and `flutter build web` prove the js_interop compiles;
// neither proves it BEHAVES. This runs the real web variants
// (encode_capability_web.dart / flac_capability_web.dart, selected by the
// conditional exports) in a browser VM.
//
// What it can prove here: the DEGRADATION path. No bootstrap.js runs under
// `flutter test --platform chrome`, so `globalThis.glintCodec` is absent — the
// exact situation of a page that didn't load the shim, or any host embedding
// the app without web/glint. Every seam must then hand back null and every
// pure-Dart format must keep working, rather than the app throwing a
// JS-interop error at the user.
//
// The working path (wasm actually loaded) is covered by
// web/glint/codec_roundtrip_test.mjs, which drives the same shim under node.
//
// Run: flutter test test/web --platform chrome

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encode_capability.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _ramp(int n) =>
    Float64List.fromList([for (var i = 0; i < n; i++) (i % 100) / 100.0]);

void main() {
  group('without the wasm shim on the page', () {
    test('every glint-backed loader declines instead of throwing', () {
      // `globalThis.glintCodec` is undefined here. Reaching into an absent JS
      // object is the classic way interop code explodes; these must be null.
      expect(loadGlintEncoder(), isNull);
      expect(loadOpusFileDecoder(), isNull);
      expect(loadAudioDecoder(), isNull);
    });

    test('readiness resolves false rather than hanging', () async {
      // Every import now awaits this, so a hang here would freeze file import.
      await expectLater(ensureGlintCodecReady(), completion(isFalse));
      await expectLater(ensureAudioDecodersReady(), completes);
    });

    test('the export sheet offers exactly the pure-Dart formats', () async {
      await prepareNativeAudioEncoder();
      expect(availableAudioExportFormats(), [
        AudioExportFormat.wav,
        AudioExportFormat.mp3,
      ]);
    });
  });

  group('pure-Dart codecs work on web regardless', () {
    test('WAV encodes', () {
      final bytes = AudioExportFormat.wav.build(_ramp(1000), 44100);
      expect(bytes.length, 44 + 1000 * 2);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
    });

    test('MP3 encodes', () {
      final bytes = AudioExportFormat.mp3.build(_ramp(4608), 44100);
      expect(bytes.length, greaterThan(100));
      expect(bytes[0], 0xFF, reason: 'MPEG frame sync');
    });

    test('WAV round-trips through import', () async {
      final wav = AudioExportFormat.wav.build(_ramp(2000), 44100);
      final back = await importAudioAsync(wav);
      expect(back, isNotNull);
      expect(back!.sampleRate, 44100);
      expect(back.pcm.length, 2000);
    });
  });

  group('container detection is pure Dart, so it works with no decoder', () {
    test('Ogg-Opus is still recognised', () {
      // Detection must not depend on the shim: the app decides WHICH decoder to
      // ask for before it has one, and a wrong answer here would route an Opus
      // file to the Vorbis decoder.
      final opus = Uint8List.fromList(<int>[
        0x4F,
        0x67,
        0x67,
        0x53,
        0,
        0x02,
        ...List<int>.filled(8, 0),
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        19,
        0x4F,
        0x70,
        0x75,
        0x73,
        0x48,
        0x65,
        0x61,
        0x64,
        1,
        2,
        0x38,
        0x01,
        0x80,
        0xBB,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(isOggOpus(opus), isTrue);
      expect(oggOpusChannels(opus), 2);
    });

    test('an Opus file with no decoder degrades to null, not an exception',
        () async {
      final opus = Uint8List.fromList(<int>[
        0x4F,
        0x67,
        0x67,
        0x53,
        0,
        0x02,
        ...List<int>.filled(8, 0),
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        19,
        0x4F,
        0x70,
        0x75,
        0x73,
        0x48,
        0x65,
        0x61,
        0x64,
        1,
        2,
        0x38,
        0x01,
        0x80,
        0xBB,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(await importAudioAsync(opus), isNull);
    });
  });
}
