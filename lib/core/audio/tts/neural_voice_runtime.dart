// neural_voice_runtime.dart — the seam between TtsService and whatever runs
// the neural voices of the catalog (neural_voice_catalog.dart). Web-safe: pure
// interface + error types. The native implementation is CrispAsrVoiceRuntime
// (libcrispasr over dart:ffi); web and io-less builds get none (null).
//
// Unlike the old fire-and-forget backends, every failure here is an
// exception carrying a [TtsFailure] kind + a human detail, so TtsService can
// fall back to the device voice AND tell the user why.

import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';

/// Why a neural voice could not be used.
enum TtsFailure {
  /// The neural engine (libcrispasr) is not available on this device/build.
  runtimeUnavailable,

  /// The selected voice has not been downloaded.
  notDownloaded,

  /// Downloading a voice failed (network / HTTP / disk).
  downloadFailed,

  /// The engine ran but produced no audio.
  synthFailed,
}

/// A neural-voice failure with a human-readable [detail] (English, technical —
/// shown in a secondary line / error log, the kind itself is localized).
class TtsVoiceException implements Exception {
  const TtsVoiceException(this.kind, this.detail);
  final TtsFailure kind;
  final String detail;

  @override
  String toString() => 'TtsVoiceException(${kind.name}): $detail';
}

/// Download progress callback: [received] of [total] bytes (total may be 0
/// when unknown).
typedef TtsDownloadProgress = void Function(int received, int total);

/// Runs catalog voices. Implementations must never block the UI isolate on
/// synthesis or downloads.
abstract class NeuralVoiceRuntime {
  /// Null when the engine can run here; otherwise why not (e.g. the dlopen
  /// error). Cheap after the first call.
  Future<String?> unavailableReason();

  /// True iff every file of [voice] is present locally.
  Future<bool> isInstalled(NeuralVoice voice);

  /// Fetch every missing file of [voice]. Throws [TtsVoiceException]
  /// ([TtsFailure.downloadFailed]) with the concrete cause on failure; never
  /// leaves a partial file where [isInstalled] would accept it.
  Future<void> download(NeuralVoice voice, {TtsDownloadProgress? onProgress});

  /// Delete [voice]'s files (files shared with another installed voice — the
  /// Kokoro backbone — are kept).
  Future<void> remove(NeuralVoice voice);

  /// Synthesise [text] with [voice] and play it. Never downloads. Throws
  /// [TtsVoiceException] on any failure (nothing is played then).
  Future<void> speak(NeuralVoice voice, String text);

  /// Interrupt playback (and drop any synthesis still in flight).
  Future<void> stop();
}
