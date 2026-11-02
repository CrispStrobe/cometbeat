// CrispAsrVoiceRuntime + downloadVoiceFile, with NO libcrispasr: downloads go
// against a local HttpServer (redirects, HTTP errors, short bodies) and
// synthesis through the injected runner seam.
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_voice_runtime.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store whose native lib "loads" — lets speak() reach the synth seam.
class _LoadableStore extends KokoroModelStore {
  _LoadableStore(String dir)
      : super(cacheDirOverride: dir, libPathOverride: '/fake/libcrispasr');
  @override
  String? loadError() => null;
}

void main() {
  late Directory tmp;
  late HttpServer server;
  late String base;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('voice_rt_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.host}:${server.port}';
    server.listen((req) async {
      final r = req.response;
      switch (req.uri.path) {
        case '/ok':
          r.contentLength = 1000;
          r.add(List<int>.filled(1000, 7));
        case '/redirect':
          r.statusCode = HttpStatus.found;
          r.headers.set(HttpHeaders.locationHeader, '$base/ok');
        case '/stall':
          // Promises 1000 bytes, sends 10, then goes silent (never closes).
          r.contentLength = 1000;
          r.add(List<int>.filled(10, 1));
          await r.flush();
          return;
        default:
          r.statusCode = HttpStatus.notFound;
      }
      await r.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  group('downloadVoiceFile', () {
    test('streams to the destination and reports progress', () async {
      final dest = File('${tmp.path}/a.gguf');
      var last = 0;
      await downloadVoiceFile('$base/ok', dest, onProgress: (r, t) => last = r);
      expect(dest.lengthSync(), 1000);
      expect(last, 1000);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('follows redirects (HF → CDN)', () async {
      final dest = File('${tmp.path}/b.gguf');
      await downloadVoiceFile('$base/redirect', dest);
      expect(dest.lengthSync(), 1000);
    });

    test('an HTTP error throws with the status and leaves nothing behind',
        () async {
      final dest = File('${tmp.path}/c.gguf');
      await expectLater(
        downloadVoiceFile('$base/missing', dest),
        throwsA(
          isA<TtsVoiceException>()
              .having((e) => e.kind, 'kind', TtsFailure.downloadFailed)
              .having((e) => e.detail, 'detail', contains('404')),
        ),
      );
      expect(dest.existsSync(), isFalse);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('a stalled transfer times out and is never renamed into place',
        () async {
      final dest = File('${tmp.path}/d.gguf');
      await expectLater(
        downloadVoiceFile(
          '$base/stall',
          dest,
          idleTimeout: const Duration(milliseconds: 400),
        ),
        throwsA(
          isA<TtsVoiceException>()
              .having((e) => e.detail, 'detail', contains('timed out')),
        ),
      );
      expect(dest.existsSync(), isFalse);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('an unreachable host reports a network error', () async {
      final dest = File('${tmp.path}/e.gguf');
      await expectLater(
        downloadVoiceFile('http://127.0.0.1:1/x', dest),
        throwsA(
          isA<TtsVoiceException>()
              .having((e) => e.kind, 'kind', TtsFailure.downloadFailed),
        ),
      );
    });
  });

  group('CrispAsrVoiceRuntime', () {
    final kokoro = neuralVoiceById('kokoro-en-af_heart')!;
    final thorsten = neuralVoiceById('piper-de-thorsten-medium')!;

    CrispAsrVoiceRuntime runtime({
      List<String>? fetched,
      Future<void> Function(Uint8List)? play,
      VoiceSynthRunner? synth,
    }) =>
        CrispAsrVoiceRuntime(
          store: KokoroModelStore(
            cacheDirOverride: tmp.path,
            libPathOverride: '/nonexistent/libcrispasr.dylib',
          ),
          play: play ?? (_) async {},
          synth: synth,
          fetch: (url, dest, {expectedBytes = 0, onProgress}) async {
            fetched?.add(url);
            dest.writeAsBytesSync([1, 2, 3]);
            onProgress?.call(3, 3);
          },
        );

    test('download fetches EVERY file of a voice (Kokoro model + pack)',
        () async {
      final urls = <String>[];
      final rt = runtime(fetched: urls);
      expect(await rt.isInstalled(kokoro), isFalse);
      await rt.download(kokoro);
      expect(urls, [kokoro.model.url, kokoro.voicePack!.url]);
      expect(await rt.isInstalled(kokoro), isTrue);
      // CrispASR's provenance sidecar is written next to each file.
      expect(
        File('${tmp.path}/${kokoro.voicePack!.filename}.src')
            .readAsStringSync(),
        kokoro.voicePack!.url,
      );
    });

    test('a half-installed voice (model only) is NOT installed', () async {
      File('${tmp.path}/${kokoro.model.filename}').writeAsBytesSync([1]);
      final urls = <String>[];
      final rt = runtime(fetched: urls);
      expect(await rt.isInstalled(kokoro), isFalse);
      await rt.download(kokoro);
      expect(urls, [kokoro.voicePack!.url]); // only what was missing
    });

    test('remove deletes the voice files', () async {
      final rt = runtime();
      await rt.download(thorsten);
      await rt.remove(thorsten);
      expect(await rt.isInstalled(thorsten), isFalse);
      expect(
        File('${tmp.path}/${thorsten.model.filename}').existsSync(),
        isFalse,
      );
    });

    test('speak without the engine throws runtimeUnavailable', () async {
      final rt = runtime();
      await rt.download(thorsten);
      await expectLater(
        rt.speak(thorsten, 'Hallo'),
        throwsA(
          isA<TtsVoiceException>()
              .having((e) => e.kind, 'kind', TtsFailure.runtimeUnavailable),
        ),
      );
      expect(await rt.unavailableReason(), isNotNull);
    });

    test(
        'speak synthesises with the voice files and plays a WAV at the '
        'voice rate', () async {
      Uint8List? played;
      VoiceSynthRequest? seen;
      final rt = CrispAsrVoiceRuntime(
        store: _LoadableStore(tmp.path),
        play: (wav) async => played = wav,
        fetch: (url, dest, {expectedBytes = 0, onProgress}) async =>
            dest.writeAsBytesSync([1]),
        synth: (req) async {
          seen = req;
          return VoiceSynthResult(Int16List(2205), 22050);
        },
      );
      await rt.download(thorsten);
      await rt.speak(thorsten, 'Hallo');
      expect(seen!.backend, 'piper');
      expect(seen!.modelPath, endsWith(thorsten.model.filename));
      expect(seen!.lang, 'de');
      expect(String.fromCharCodes(played!.sublist(0, 4)), 'RIFF');
      // Sample rate field of the WAV header (bytes 24..27, little endian).
      expect(
        ByteData.sublistView(played!).getUint32(24, Endian.little),
        22050,
      );
    });

    test('speak never downloads: a missing voice throws notDownloaded',
        () async {
      final rt = CrispAsrVoiceRuntime(
        store: _LoadableStore(tmp.path),
        play: (_) async => fail('must not play'),
        synth: (_) async => fail('must not synthesise'),
      );
      await expectLater(
        rt.speak(thorsten, 'Hallo'),
        throwsA(
          isA<TtsVoiceException>()
              .having((e) => e.kind, 'kind', TtsFailure.notDownloaded),
        ),
      );
    });

    test('a stop during synthesis drops the late result', () async {
      var plays = 0;
      late CrispAsrVoiceRuntime rt;
      rt = CrispAsrVoiceRuntime(
        store: _LoadableStore(tmp.path),
        play: (_) async => plays++,
        fetch: (url, dest, {expectedBytes = 0, onProgress}) async =>
            dest.writeAsBytesSync([1]),
        synth: (req) async {
          await rt.stop(); // user closed the sheet mid-synthesis
          return VoiceSynthResult(Int16List(10), 22050);
        },
      );
      await rt.download(thorsten);
      await rt.speak(thorsten, 'Hallo');
      expect(plays, 0);
    });
  });
}
