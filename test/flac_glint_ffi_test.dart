// Pure unit tests for the FLAC seam — no native library, no toolchain, so they
// always run. They cover the value type, the loader's graceful degradation when
// the glint decoder isn't available, and the installer's behaviour around FLAC
// samples it can't decode (skip the region, keep the cached file). The actual
// native decode is proven bit-exact in flac_glint_live_test.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/flac_glint_ffi.dart';
import 'package:comet_beat/features/library/instrument_installer_io.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToWav;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlacPcm', () {
    test('holds mono PCM (no right channel)', () {
      final pcm = FlacPcm(
        left: Float64List.fromList([0.0, 0.5, -0.5]),
        right: null,
        sampleRate: 44100,
      );
      expect(pcm.left, hasLength(3));
      expect(pcm.right, isNull);
      expect(pcm.sampleRate, 44100);
    });

    test('holds stereo PCM (both channels)', () {
      final pcm = FlacPcm(
        left: Float64List.fromList([0.1]),
        right: Float64List.fromList([0.2]),
        sampleRate: 48000,
      );
      expect(pcm.right, isNotNull);
      expect(pcm.right!.first, 0.2);
      expect(pcm.sampleRate, 48000);
    });
  });

  group('loadGlintFlac graceful degradation', () {
    test('a non-existent library path returns null, never throws', () {
      expect(
        loadGlintFlac(libraryPath: '/no/such/lib_xyz.dylib'),
        isNull,
      );
    });

    test('the default loader never throws in a plain test process', () {
      // In `flutter test` the FFI plugin usually isn't linked in, so this
      // returns null; the contract is only that it degrades, not crashes.
      expect(loadGlintFlac, returnsNormally);
    });
  });

  group('installer around an undecodable FLAC sample', () {
    // Non-FLAC bytes so decode always fails, deterministically exercising the
    // skip path whether or not a real glint decoder is present.
    final fakeFlac = Uint8List.fromList(List.filled(2048, 0x37));

    test('a FLAC-only instrument caches the file but builds no voice',
        () async {
      final cache = Directory.systemTemp.createTempSync('flac_only');
      addTearDown(() => cache.deleteSync(recursive: true));

      const sfz = '''
<region>
sample=samples/x.flac
pitch_keycenter=60
lokey=0 hikey=127
''';
      Future<Uint8List> http(Uri url) async {
        final u = url.toString();
        if (u.endsWith('.sfz')) return Uint8List.fromList(sfz.codeUnits);
        if (u.endsWith('samples/x.flac')) return fakeFlac;
        throw Exception('404 $u');
      }

      final installed = await installSfzInstrument(
        sfzUrl: 'https://h/vcsl/OnlyFlac.sfz',
        name: 'Only Flac',
        http: http,
        cacheDirOverride: cache.path,
      );

      // No decodable region → no voice…
      expect(installed, isNull);
      // …but the download IS kept (Downloads manager can free it; a future
      // re-install with a decoder present would then play it).
      expect(
        File('${cache.path}/instruments/Only_Flac/samples/x.flac').existsSync(),
        isTrue,
      );
    });

    test('a mixed WAV+FLAC instrument builds a voice from the WAV region',
        () async {
      final cache = Directory.systemTemp.createTempSync('flac_mixed');
      addTearDown(() => cache.deleteSync(recursive: true));

      final wav = pcmFloatToWav(
        Float64List.fromList(List.generate(2048, (i) => (i % 64 - 32) / 64.0)),
        sampleRate: 22050,
      );
      const sfz = '''
<region>
sample=samples/good.wav
pitch_keycenter=60
lokey=0 hikey=59
<region>
sample=samples/bad.flac
pitch_keycenter=72
lokey=60 hikey=127
''';
      Future<Uint8List> http(Uri url) async {
        final u = url.toString();
        if (u.endsWith('.sfz')) return Uint8List.fromList(sfz.codeUnits);
        if (u.endsWith('samples/good.wav')) return wav;
        if (u.endsWith('samples/bad.flac')) return fakeFlac;
        throw Exception('404 $u');
      }

      final installed = await installSfzInstrument(
        sfzUrl: 'https://h/vcsl/Mixed.sfz',
        name: 'Mixed',
        http: http,
        cacheDirOverride: cache.path,
      );

      // The WAV region yields a voice even though the FLAC region is skipped.
      expect(installed, isNotNull);
      expect(installed!.instrument, isNotNull);
      // Both files are cached (WAV playable, FLAC kept for a future decoder).
      expect(
        File('${cache.path}/instruments/Mixed/samples/good.wav').existsSync(),
        isTrue,
      );
      expect(
        File('${cache.path}/instruments/Mixed/samples/bad.flac').existsSync(),
        isTrue,
      );
    });
  });
}
