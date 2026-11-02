// crispasr_voice_runtime.dart — NATIVE runtime for the neural voice catalog:
// Piper (VITS) and Kokoro voices, both executed by libcrispasr through the
// pure-Dart `crispasr` FFI package. dart:io + ffi + isolates → native only;
// web gets no runtime (tts_neural_stub.dart).
//
// Three jobs, each fixing a defect of the old Kokoro-only backend:
//
//  1. DOWNLOAD in Dart (HttpClient), not through CrispASR's C downloader.
//     The C side shells out to `curl` via system() (libcrispasr is built
//     without libcurl), which reports NOTHING back — no progress, no HTTP
//     status, no reason — and does not exist at all on iOS/Android. Here a
//     download streams to `<file>.part`, follows the HF → CDN redirects, checks
//     the status + byte count, times out a stalled connection, renames into
//     place atomically and writes CrispASR's `.src` sidecar, so the file is
//     indistinguishable from one CrispASR fetched itself (same cache dir, same
//     name, same provenance record). A failure throws with the concrete cause.
//
//  2. Download EVERY file a voice needs. The old job returned right after the
//     Kokoro model and never fetched the voice pack, so synthesis then ran
//     without a voice and failed ("kokoro synthesis failed … check that a voice
//     pack is loaded") — silently.
//
//  3. Synthesise in ONE long-lived worker isolate that keeps the last session
//     open, so only the first sentence pays the model load; a failure comes
//     back as an exception (with libcrispasr's own error text) instead of an
//     empty result that played nothing.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';
import 'package:crispasr/crispasr.dart';

/// One synthesis request for the worker (plain fields → sendable).
class VoiceSynthRequest {
  const VoiceSynthRequest({
    required this.libPath,
    required this.backend,
    required this.modelPath,
    required this.text,
    required this.lang,
    this.voicePackPath,
    this.speakerId,
  });

  final String libPath;
  final String backend; // 'piper' | 'kokoro'
  final String modelPath;
  final String? voicePackPath;
  final int? speakerId;
  final String lang;
  final String text;
}

/// Synthesised audio: PCM16 mono at [sampleRate].
class VoiceSynthResult {
  const VoiceSynthResult(this.pcm, this.sampleRate);
  final Int16List pcm;
  final int sampleRate;
}

/// Runs a [VoiceSynthRequest]; throws [TtsVoiceException] on failure.
typedef VoiceSynthRunner = Future<VoiceSynthResult> Function(
  VoiceSynthRequest req,
);

/// Downloads [url] to [dest]; throws [TtsVoiceException] on failure.
typedef VoiceFileFetcher = Future<void> Function(
  String url,
  File dest, {
  int expectedBytes,
  void Function(int received, int total)? onProgress,
});

class CrispAsrVoiceRuntime implements NeuralVoiceRuntime {
  CrispAsrVoiceRuntime({
    required this.play,
    this.stopPlayback,
    KokoroModelStore? store,
    VoiceSynthRunner? synth,
    VoiceFileFetcher? fetch,
  })  : store = store ?? KokoroModelStore(),
        _synthOverride = synth,
        _fetch = fetch ?? downloadVoiceFile;

  /// Lib-path + cache-dir resolution (shared with the transcription paths).
  final KokoroModelStore store;

  /// Plays a finished WAV (AudioService.playWavBytes in the app).
  final Future<void> Function(Uint8List wav) play;
  final Future<void> Function()? stopPlayback;

  final VoiceSynthRunner? _synthOverride;
  final VoiceFileFetcher _fetch;
  _SynthWorker? _worker;

  /// Bumped by [stop] so a synthesis that finishes after a stop isn't played.
  int _generation = 0;

  String? _reason;
  bool _probed = false;

  @override
  Future<String?> unavailableReason() async {
    if (!_probed) {
      _probed = true;
      _reason = store.loadError();
    }
    return _reason;
  }

  String _dir() {
    final d = store.cacheDirPath();
    if (d == null) {
      throw const TtsVoiceException(
        TtsFailure.downloadFailed,
        'no cache directory (HOME is not set)',
      );
    }
    return d;
  }

  File _file(NeuralVoiceFile f) => File('${_dir()}/${f.filename}');

  @override
  Future<bool> isInstalled(NeuralVoice voice) async {
    try {
      return voice.files.every((f) {
        final file = _file(f);
        return file.existsSync() && file.lengthSync() > 0;
      });
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> download(
    NeuralVoice voice, {
    TtsDownloadProgress? onProgress,
  }) async {
    final missing = <NeuralVoiceFile>[];
    for (final f in voice.files) {
      final file = _file(f);
      if (!(file.existsSync() && file.lengthSync() > 0)) missing.add(f);
    }
    final total = missing.fold<int>(0, (s, f) => s + f.bytes);
    var done = 0;
    for (final f in missing) {
      final base = done;
      await _fetch(
        f.url,
        _file(f),
        expectedBytes: f.bytes,
        onProgress: (r, _) => onProgress?.call(base + r, total),
      );
      done += f.bytes;
      // CrispASR's provenance sidecar: its own cache then accepts the file as
      // coming from this URL instead of re-downloading (issue #250 logic).
      try {
        File('${_file(f).path}.src').writeAsStringSync(f.url);
      } catch (_) {
        // A missing sidecar only means CrispASR trusts the file as-is.
      }
    }
    onProgress?.call(total, total);
  }

  @override
  Future<void> remove(NeuralVoice voice) async {
    // Keep files another INSTALLED voice still needs (the Kokoro backbone).
    final keep = <String>{};
    for (final other in kNeuralVoices) {
      if (other.id == voice.id) continue;
      if (await isInstalled(other)) {
        keep.addAll(other.files.map((f) => f.filename));
      }
    }
    for (final f in voice.files) {
      if (keep.contains(f.filename)) continue;
      for (final p in [_file(f).path, '${_file(f).path}.src']) {
        try {
          final file = File(p);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {
          // best effort
        }
      }
    }
  }

  @override
  Future<void> speak(NeuralVoice voice, String text) async {
    if (text.trim().isEmpty) return;
    final reason = await unavailableReason();
    if (reason != null) {
      throw TtsVoiceException(TtsFailure.runtimeUnavailable, reason);
    }
    if (!await isInstalled(voice)) {
      throw TtsVoiceException(
        TtsFailure.notDownloaded,
        '${voice.name} is not downloaded',
      );
    }
    final gen = ++_generation;
    final req = VoiceSynthRequest(
      libPath: store.libPath(),
      backend: voice.engine.name,
      modelPath: _file(voice.model).path,
      voicePackPath:
          voice.voicePack == null ? null : _file(voice.voicePack!).path,
      speakerId: voice.speakerId,
      lang: voice.lang,
      text: text,
    );
    final runner = _synthOverride ?? (_worker ??= _SynthWorker()).run;
    final result = await runner(req);
    if (gen != _generation) return; // stopped meanwhile — don't talk over
    if (result.pcm.isEmpty) {
      throw const TtsVoiceException(TtsFailure.synthFailed, 'empty audio');
    }
    await play(wavBytes(result.pcm, sampleRate: result.sampleRate));
  }

  @override
  Future<void> stop() async {
    _generation++;
    await stopPlayback?.call();
  }

  /// Shut the worker isolate down (app teardown / tests).
  void dispose() {
    _worker?.close();
    _worker = null;
  }
}

// ── Download ────────────────────────────────────────────────────────────────

/// Stream [url] into [dest] atomically. Follows redirects (HF answers with a
/// 302 to its CDN), fails on a non-200 status, a stalled connection (no bytes
/// for [idleTimeout]) or a short body, and only renames the `.part` file into
/// place once it is complete. Throws [TtsVoiceException] with the cause.
Future<void> downloadVoiceFile(
  String url,
  File dest, {
  int expectedBytes = 0,
  void Function(int received, int total)? onProgress,
  Duration idleTimeout = const Duration(seconds: 45),
  HttpClient? client,
}) async {
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'CometBeat (crispasr voices)';
  final part = File('${dest.path}.part');
  IOSink? sink;
  try {
    dest.parent.createSync(recursive: true);
    final req = await http.getUrl(Uri.parse(url));
    req.followRedirects = true;
    req.maxRedirects = 10;
    final resp = await req.close().timeout(idleTimeout);
    if (resp.statusCode != HttpStatus.ok) {
      await resp.drain<void>().catchError((_) {});
      throw TtsVoiceException(
        TtsFailure.downloadFailed,
        'HTTP ${resp.statusCode} for $url',
      );
    }
    final total = resp.contentLength > 0 ? resp.contentLength : expectedBytes;
    sink = part.openWrite();
    var received = 0;
    await for (final chunk in resp.timeout(
      idleTimeout,
      onTimeout: (s) => s.addError(
        TimeoutException('no data for ${idleTimeout.inSeconds} s'),
      ),
    )) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    if (received == 0 || (total > 0 && received != total)) {
      throw TtsVoiceException(
        TtsFailure.downloadFailed,
        'incomplete download ($received of $total bytes)',
      );
    }
    part.renameSync(dest.path);
  } on TtsVoiceException {
    rethrow;
  } on SocketException catch (e) {
    throw TtsVoiceException(
      TtsFailure.downloadFailed,
      'network error: ${e.message}${e.osError == null ? '' : ' (${e.osError!.message})'}',
    );
  } on HandshakeException catch (e) {
    throw TtsVoiceException(TtsFailure.downloadFailed, 'TLS error: $e');
  } on TimeoutException catch (e) {
    throw TtsVoiceException(
      TtsFailure.downloadFailed,
      'timed out: ${e.message ?? 'no response'}',
    );
  } on FileSystemException catch (e) {
    throw TtsVoiceException(
      TtsFailure.downloadFailed,
      'cannot write ${e.path}: ${e.osError?.message ?? e.message}',
    );
  } catch (e) {
    throw TtsVoiceException(TtsFailure.downloadFailed, '$e');
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
    if (client == null) http.close(force: true);
  }
}

// ── Synthesis worker ────────────────────────────────────────────────────────

/// A long-lived isolate that owns the CrispASR session (model stays loaded
/// between sentences). Requests are serialised.
class _SynthWorker {
  Future<SendPort>? _port;
  Isolate? _isolate;
  Future<void> _queue = Future.value();

  Future<SendPort> _start() async {
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_workerMain, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    return port;
  }

  Future<VoiceSynthResult> run(VoiceSynthRequest req) {
    final job = _queue.then((_) async {
      final port = await (_port ??= _start());
      final reply = ReceivePort();
      port.send([req, reply.sendPort]);
      final msg = await reply.first;
      reply.close();
      if (msg is List && msg.length == 2 && msg[0] is TransferableTypedData) {
        final bytes = (msg[0] as TransferableTypedData).materialize();
        return VoiceSynthResult(bytes.asInt16List(), msg[1] as int);
      }
      throw TtsVoiceException(TtsFailure.synthFailed, '$msg');
    });
    _queue = job.then((_) {}, onError: (_) {});
    return job;
  }

  void close() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
  }
}

void _workerMain(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  CrispasrSession? session;
  String? key;
  inbox.listen((dynamic msg) {
    final req = (msg as List)[0] as VoiceSynthRequest;
    final reply = msg[1] as SendPort;
    try {
      final k = '${req.libPath}|${req.backend}|${req.modelPath}|'
          '${req.voicePackPath}|${req.speakerId}';
      if (session == null || key != k) {
        session?.close();
        session = null;
        // Opening validates the lib on THIS isolate too (a dlopen failure
        // surfaces here as the reason).
        DynamicLibrary.open(req.libPath);
        // Piper runs on the CPU: it is as fast there as on Metal for these
        // small VITS graphs, and opening it on Metal costs 5–20 s (shader
        // pipeline build) — measured ~50 s for the first sentence in the
        // sandboxed app. Kokoro keeps the GPU: on CPU it is ~8x slower.
        final s = CrispasrSession.openWithParams(
          req.modelPath,
          backend: req.backend,
          libPath: req.libPath,
          useGpu: req.backend != 'piper',
        );
        if (req.backend == 'kokoro') {
          final vp = req.voicePackPath;
          if (vp == null) throw StateError('kokoro needs a voice pack');
          s.setVoice(vp);
          // Output language for kokoro's phonemizer (en-us by default).
          try {
            s.setSourceLanguage(req.lang == 'en' ? 'en-us' : req.lang);
          } catch (_) {}
        } else if (req.speakerId != null) {
          s.setSpeakerID(req.speakerId!);
        }
        session = s;
        key = k;
      }
      final s = session!;
      final pcm = s.synthesize(req.text);
      final sr = s.outputSampleRate > 0
          ? s.outputSampleRate
          : (req.backend == 'piper' ? 22050 : 24000);
      final out = Int16List(pcm.length);
      for (var i = 0; i < pcm.length; i++) {
        final v = pcm[i];
        if (v.isNaN) throw StateError('NaN in synthesised audio');
        out[i] = (v * 32767.0).round().clamp(-32768, 32767);
      }
      reply.send([
        TransferableTypedData.fromList([out]),
        sr,
      ]);
    } catch (e) {
      // A broken session must not poison the next request.
      try {
        session?.close();
      } catch (_) {}
      session = null;
      key = null;
      reply.send('$e');
    }
  });
}
