// lib/core/audio/transcription/piano_model_store.dart
//
// NATIVE model provisioning for the Kong piano-transcription model — the
// `dart:io` half kept OUT of the web-safe `piano.dart`. Downloads the MIT
// ByteDance/Kong note ONNX (~99 MB) on demand and caches it, mirroring
// `separate_umx_model_store` / `rmvpe_model_store`.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart'
    show NoteEvent;
import 'package:comet_beat/core/audio/transcription/piano.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A loaded Kong piano model.
typedef OnnxPianoModel = ({OnnxModel model});

/// Runs ONE piano segment (model loaded from [path] inside the isolate) → the
/// four head rows — the body of each segment-concurrency isolate.
List<Float32List> _runSegmentIsolate(
  ({String path, Float32List seg}) job,
) {
  final model = OnnxModel.fromBytes(File(job.path).readAsBytesSync());
  return pianoRunSegment(model, job.seg);
}

/// Resolves + loads the MIT Kong piano ONNX. Override the cache location with
/// `COMET_PIANO_DIR` (tests use this).
class PianoModelStore {
  PianoModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _modelUrl =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/piano.onnx';
  static const _minBytes = 50000000; // ~99 MB; guard partial downloads

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_PIANO_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/piano.onnx');

  /// Whether the model is already on disk (no network) — the readiness gate.
  bool isPresent() {
    final f = modelFile();
    return f.existsSync() && f.lengthSync() > _minBytes;
  }

  /// The cached model file, downloading it on first use. Returns null if absent
  /// and the download fails (offline).
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (isPresent()) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < _minBytes) return null;
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads (and memoises) the model, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<OnnxPianoModel> load() async {
    if (_cached != null) return (model: _cached!);
    final file = await ensureFile();
    if (file == null) {
      throw StateError('Kong piano model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    _cached = OnnxModel.fromBytes(file.readAsBytesSync());
    return (model: _cached!);
  }

  /// The route.dart [NeuralTranscriber] backed by this model. By default
  /// (native) the independent 10 s segments of a LONG recording run
  /// CONCURRENTLY across isolates (~2× wall-clock for multi-segment audio; the
  /// model is GRU-bound, so the within-model conv pool gives nothing, but the
  /// segments are independent). Peak memory is `workers`×99 MB (each isolate
  /// loads the model), so concurrency is capped — [workers] (default 4, or
  /// `COMET_PIANO_WORKERS`). Single-segment (≤10 s) audio has no extra segments
  /// to parallelise and runs as one isolate. Set `COMET_PIANO_CONCURRENT=0` (or
  /// `concurrent: false`) for the single preloaded-model path.
  Future<NeuralTranscriber> transcriber({
    bool? concurrent,
    int? workers,
  }) async {
    final file = await ensureFile();
    final useConcurrent =
        concurrent ?? (Platform.environment['COMET_PIANO_CONCURRENT'] != '0');
    if (file == null || !useConcurrent) {
      return pianoTranscriber((await load()).model);
    }
    final path = file.path;
    final w = workers ??
        (int.tryParse(Platform.environment['COMET_PIANO_WORKERS'] ?? '') ?? 4);
    return (Float64List mono, int sampleRate) =>
        _transcribeConcurrent(mono, sampleRate, path, math.max(1, w));
  }

  /// Enframe → run segments in parallel isolate batches of [workers] → deframe →
  /// decode. Each isolate loads the model from [path] (peak `workers`×99 MB).
  static Future<List<NoteEvent>> _transcribeConcurrent(
    Float64List mono,
    int sampleRate,
    String path,
    int workers,
  ) async {
    final audio = sampleRate == pianoSampleRate
        ? mono
        : resampleLinear(mono, sampleRate / pianoSampleRate);
    if (audio.isEmpty) return const [];
    final segs = pianoEnframe(audio);
    final perSeg = List<List<Float32List>>.filled(segs.length, const []);
    for (var i = 0; i < segs.length; i += workers) {
      final end = math.min(i + workers, segs.length);
      final batch = await Future.wait([
        for (var j = i; j < end; j++)
          Isolate.run(
            () => _runSegmentIsolate((path: path, seg: segs[j])),
          ),
      ]);
      for (var j = i; j < end; j++) {
        perSeg[j] = batch[j - i];
      }
    }
    return decodePianoHeads(pianoDeframeSegments(perSeg));
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-piano';
      var uri = Uri.parse(url);
      for (var hop = 0; hop < 5; hop++) {
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final b = BytesBuilder(copy: false);
          await for (final chunk in resp) {
            b.add(chunk);
          }
          return b.takeBytes();
        }
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (resp.isRedirect && loc != null) {
          uri = Uri.parse(loc);
          continue;
        }
        return null;
      }
      return null;
    } finally {
      client.close();
    }
  }
}
