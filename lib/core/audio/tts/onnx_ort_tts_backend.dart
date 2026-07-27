// onnx_ort_tts_backend.dart — the `onnxFfi` TtsEngine's backend: Piper VITS over
// NATIVE ONNX Runtime. The ORT analogue of `crispasr_tts_backend.dart`: given a
// downloaded CC0 Piper voice (via `piper/piper_voice_store.dart`), it phonemizes
// text with OUR g2p (`piper/piper_phonemes.dart`), runs the graph through
// [OnnxOrtTtsSynth] (native ORT), wraps the PCM as a WAV (`synth.dart` wavBytes)
// and hands it to the injected [play] sink — exactly the CrispAsr backend flow.
//
// NATIVE ONLY: it reads model bytes (dart:io) and opens libonnxruntime, so it is
// instantiated solely by the native factory (`onnx_ort_tts_io.dart`); web gets
// the null stub. Everything is defensive — no native ORT / no cached model ⇒
// probes report unavailable and [speak] is a silent no-op, so TtsService falls
// back to the platform voice and never crashes.
//
// A [synthesize] seam (default: real ORT) + an [ortAvailable] seam make the whole
// speak→WAV→play path unit-testable without libonnxruntime (see the tests).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/onnx_ort_session.dart';
import 'package:comet_beat/core/audio/tts/onnx_ort_tts.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_phonemes.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_voice_store.dart';
import 'package:comet_beat/core/services/tts_service.dart';

/// A resolved-paths synthesis request handed to the [OnnxOrtTtsBackend.synthesize]
/// seam: the cached model path, its config json text, the text, and the base
/// language. Plain fields so a fake seam is trivial in tests.
class OnnxTtsRequest {
  const OnnxTtsRequest({
    required this.modelPath,
    required this.configJson,
    required this.text,
    required this.lang,
  });

  final String modelPath;
  final String configJson;
  final String text;
  final String lang;
}

/// The synthesized PCM plus the voice's sample rate (needed to wrap the WAV).
class OnnxTtsResult {
  const OnnxTtsResult(this.pcm, this.sampleRate);
  final Float32List pcm;
  final int sampleRate;
}

/// Default synthesis: parse the voice config → phoneme-id map + sample rate,
/// build Piper ids with OUR g2p, load the model bytes, run the graph through
/// native ORT ([OnnxOrtTtsSynth]). Native-only; null on any failure (missing lib,
/// empty ids, bad decode) so the backend stays silent. Top-level + pure so it can
/// be swapped by a fake in tests.
OnnxTtsResult? defaultOnnxTtsSynthesize(OnnxTtsRequest req) {
  try {
    final map = phonemeIdMapFromJson(req.configJson);
    final sr = sampleRateFromJson(req.configJson);
    final ids = piperPhonemeIds(req.text, lang: req.lang, phonemeIdMap: map);
    if (ids.isEmpty) return null;
    final bytes = File(req.modelPath).readAsBytesSync();
    final session = OrtFfiSession.fromBytes(bytes);
    if (session == null) return null; // no native ORT here
    try {
      final pcm = OnnxOrtTtsSynth(session, sampleRate: sr).synthesize(ids);
      if (pcm.isEmpty) return null;
      return OnnxTtsResult(pcm, sr);
    } finally {
      session.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Neural TtsBackend over Piper VITS + native ONNX Runtime.
class OnnxOrtTtsBackend implements TtsBackend {
  OnnxOrtTtsBackend({
    required this.store,
    required this.play,
    this.stopPlayback,
    OnnxTtsResult? Function(OnnxTtsRequest req)? synthesize,
    bool Function()? ortAvailable,
  })  : _synthesize = synthesize ?? defaultOnnxTtsSynthesize,
        _ortAvailable = ortAvailable ?? OrtFfiSession.available;

  final PiperVoiceStore store;

  /// Plays the finished WAV (AudioService.playWavBytes); honours the sound switch.
  final Future<void> Function(Uint8List wav) play;

  /// Interrupts current playback when narration is cancelled.
  final Future<void> Function()? stopPlayback;

  final OnnxTtsResult? Function(OnnxTtsRequest req) _synthesize;
  final bool Function() _ortAvailable;

  static String _lang(String langCode) =>
      langCode.toLowerCase().split(RegExp('[-_]')).first;

  bool _cached(String lang) =>
      store.modelFile(lang).existsSync() && store.configFile(lang).existsSync();

  /// True iff synthesis can run right now: native ORT loadable AND the voice's
  /// model + config are already cached (no download triggered).
  Future<bool> isAvailable() async {
    if (!_ortAvailable()) return false;
    // The app ships de + en; ready means at least one voice is on disk.
    return _cached('en') || _cached('de');
  }

  /// True iff the native ORT runtime is loadable on this platform (a voice may
  /// still need [download]).
  Future<bool> supported() async => _ortAvailable();

  @override
  Future<void> speak(String text, {required String langCode}) async {
    if (text.trim().isEmpty) return;
    if (!_ortAvailable()) return; // no native ORT → let TtsService fall back
    final lang = _lang(langCode);
    // speak NEVER downloads — synthesize only from an already-cached voice.
    if (!_cached(lang)) return;
    final result = _synthesize(
      OnnxTtsRequest(
        modelPath: store.modelFile(lang).path,
        configJson: store.configFile(lang).readAsStringSync(),
        text: text,
        lang: lang,
      ),
    );
    if (result == null || result.pcm.isEmpty) return;
    await play(wavBytes(_toPcm16(result.pcm), sampleRate: result.sampleRate));
  }

  /// Explicit opt-in download of the [langCode] voice (a settings action). Returns
  /// true once the runtime is loadable and the voice is cached.
  Future<bool> download(String langCode) async {
    await store.ensureModel(_lang(langCode));
    return isAvailable();
  }

  @override
  Future<void> stop() async {
    await stopPlayback?.call();
  }

  /// Float32 [-1,1] PCM → PCM16, NaN-guarded (a bad decode yields silence).
  static Int16List _toPcm16(Float32List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      final v = pcm[i];
      if (v.isNaN) return Int16List(0);
      out[i] = (v * 32767.0).round().clamp(-32768, 32767);
    }
    return out;
  }
}
