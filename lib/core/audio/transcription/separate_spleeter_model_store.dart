// lib/core/audio/transcription/separate_spleeter_model_store.dart
//
// NATIVE model provisioning for the Spleeter separator — the `dart:io` half kept
// OUT of the web-safe `separate_spleeter.dart`. Downloads the MIT Deezer Spleeter
// ONNX stems (~38 MB each) on demand and caches them, mirroring
// `separate_umx_model_store`.
//
// Two configs: 4stems (vocals/drums/bass/other — the full multi-part lever) and
// 2stems (vocals/accompaniment — lighter). Each stem is a separate ONNX; the
// store loads them into a name→model map for `spleeterSeparator`.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separate_spleeter.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Runs ONE stem model (loaded from [path]) on the prepared [input] — the body
/// of each concurrency isolate. Reads the model file inside the isolate (from
/// the OS cache) so the 38 MB weights are NOT copied across the isolate port;
/// only the (shared) input tensor is sent.
Float32List _runStemIsolate(
  ({String path, Float32List input, List<int> shape}) job,
) {
  final model = OnnxModel.fromBytes(File(job.path).readAsBytesSync());
  final out = model.run(
    {spleeterInputName: Tensor.float(job.input, job.shape)},
    const [spleeterOutputName],
  )[spleeterOutputName]!;
  return Float32List.fromList(out.f ?? out.asFloatList());
}

/// Which Spleeter configuration to provision.
enum SpleeterConfig {
  /// vocals / drums / bass / other.
  fourStems,

  /// vocals / accompaniment.
  twoStems,
}

/// Resolves + loads the MIT Spleeter ONNX stems for a [config]. Override the
/// cache location with `COMET_SPLEETER_DIR` (tests use this).
class SpleeterModelStore {
  SpleeterModelStore({
    this.config = SpleeterConfig.fourStems,
    this.cacheDirOverride,
  });

  final SpleeterConfig config;
  final String? cacheDirOverride;

  static const _base =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1';
  static const _minBytes = 10000000; // ~38 MB models; guard partial downloads

  Map<String, OnnxModel>? _cached;

  /// Stem names for this config (also the model-file basenames' stem part).
  List<String> get stemNames =>
      config == SpleeterConfig.fourStems ? spleeter4Stems : spleeter2Stems;

  String get _prefix => config == SpleeterConfig.fourStems
      ? 'spleeter-4stems'
      : 'spleeter-2stems';

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_SPLEETER_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile(String stem) => File('${cacheDir()}/$_prefix-$stem.onnx');

  String _url(String stem) => '$_base/$_prefix-$stem.onnx';

  /// Whether every stem model is already on disk (no network) — the readiness
  /// gate the app checks before offering separation.
  bool isPresent() => stemNames.every((s) {
        final f = modelFile(s);
        return f.existsSync() && f.lengthSync() > _minBytes;
      });

  /// Ensure every stem model is cached, downloading any that are missing.
  /// Returns null if any stem can't be obtained (offline).
  Future<Map<String, File>?> ensureFiles() async {
    final out = <String, File>{};
    Directory(cacheDir()).createSync(recursive: true);
    for (final stem in stemNames) {
      final file = modelFile(stem);
      if (file.existsSync() && file.lengthSync() > _minBytes) {
        out[stem] = file;
        continue;
      }
      try {
        final bytes = await _get(_url(stem));
        if (bytes == null || bytes.length < _minBytes) return null;
        await file.writeAsBytes(bytes);
        out[stem] = file;
      } catch (_) {
        return null;
      }
    }
    return out;
  }

  /// Loads (and memoises) the stem models, downloading if needed. Throws a
  /// [StateError] if they can't be obtained.
  Future<Map<String, OnnxModel>> load() async {
    if (_cached != null) return _cached!;
    final files = await ensureFiles();
    if (files == null) {
      throw StateError('Spleeter ${config.name} models unavailable '
          '(offline?). Expected under ${cacheDir()}');
    }
    return _cached = {
      for (final e in files.entries)
        e.key: OnnxModel.fromBytes(e.value.readAsBytesSync()),
    };
  }

  /// The stems.dart [Separator] backed by these models. By default (native) the
  /// N independent stem models run CONCURRENTLY across isolates (~2× wall-clock
  /// for 4-stem on this hardware — the within-model conv pool gives nothing at
  /// Spleeter's shapes, but the stems are embarrassingly parallel). Set
  /// `COMET_SPLEETER_CONCURRENT=0` (or pass `concurrent: false`) for the
  /// single-isolate path. Falls back to sync if the files can't be provisioned.
  Future<Separator> separator({bool? concurrent}) async {
    final files = await ensureFiles();
    final useConcurrent = concurrent ??
        (Platform.environment['COMET_SPLEETER_CONCURRENT'] != '0');
    if (files == null || !useConcurrent) {
      return spleeterSeparator(await load());
    }
    final paths = {for (final s in stemNames) s: files[s]!.path};
    final names = stemNames;
    return (Float64List mono, int sampleRate) =>
        _separateConcurrent(mono, sampleRate, paths, names);
  }

  /// Prepare → run the stem models in parallel isolates → assemble.
  static Future<Stems> _separateConcurrent(
    Float64List mono,
    int sampleRate,
    Map<String, String> paths,
    List<String> names,
  ) async {
    final prep = spleeterPrepare(mono, sampleRate: sampleRate);
    if (prep.nFrames == 0) {
      return (vocals: null, drums: null, bass: null, other: null);
    }
    final specs = await Future.wait([
      for (final name in names)
        Isolate.run(
          () => _runStemIsolate(
            (path: paths[name]!, input: prep.input, shape: prep.shape),
          ),
        ),
    ]);
    final res = spleeterAssemble(prep, specs, names);
    return (
      vocals: res['vocals'],
      drums: res['drums'],
      bass: res['bass'],
      other: res['other'] ?? res['accompaniment'],
    );
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-spleeter';
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
