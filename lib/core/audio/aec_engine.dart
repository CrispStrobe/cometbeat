// lib/core/audio/aec_engine.dart
//
// The app-side CONTRACT for a native full-duplex acoustic echo canceller (AEC
// Tier 3b). This interface lives in the app deliberately: MicrophonePitchService
// depends on it, but NOT on any native plugin, so the app compiles and CI stays
// green with no native code present. A concrete engine (the `aec_fullduplex`
// package's NativeAecEngine, via a thin adapter) is injected only when the
// platform plugin is actually available — otherwise the service falls back to
// the ordinary `record` capture path (AEC tiers 0/1). See docs/AEC_TIER3B.md.
//
// Contract: hand the engine the reference PCM you are about to play (the same
// synth/backing PCM), the engine plays it AND uses it as the AEC far-end, and
// emits the cleaned near-end (mic minus echo) on [cleaned] — sample-aligned on a
// single hardware clock, which is the thing Flutter's separate playback/capture
// plugins can't provide.

import 'dart:typed_data';

/// A full-duplex echo-cancelling capture engine. PCM is mono, little-endian
/// PCM16 throughout, matching the rest of the audio pipeline.
abstract class AecEngine {
  /// Open the duplex device and begin playback+capture. [frame] is the AEC
  /// block size (a power of two).
  Future<void> start({int sampleRate = 44100, int frame = 256});

  /// Queue reference PCM16 to be played AND cancelled (what the backing plays).
  void reference(Uint8List pcm16);

  /// Cleaned near-end (mic minus echo), delivered in chunks as they're ready —
  /// the same PCM16 shape MicrophonePitchService already consumes from `record`.
  Stream<Uint8List> get cleaned;

  /// Stop the device and end [cleaned]. Safe to call more than once.
  Future<void> stop();
}
