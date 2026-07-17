// lib/core/audio/aec_capability_ffi.dart
//
// The FFI-backed factory, compiled only where `dart:ffi` exists (native
// platforms). It adapts the `aec_fullduplex` plugin's NativeAecEngine to the
// app-owned [AecEngine] contract (identical shape, different declaring package),
// so nothing above MicrophonePitchService depends on the plugin directly.
//
// Constructing the engine does NOT load the native library — that happens lazily
// on start() — so this is safe to call during app startup / tests; it just makes
// the capability available. See aec_capability.dart.

import 'dart:typed_data';

import 'package:aec_fullduplex/aec_engine.dart' as plugin;
import 'package:comet_beat/core/audio/aec_engine.dart' as app;

/// A native full-duplex AEC engine for this platform.
app.AecEngine? createNativeAecEngine() => _NativeAecAdapter();

class _NativeAecAdapter implements app.AecEngine {
  final plugin.NativeAecEngine _engine = plugin.NativeAecEngine();

  @override
  Future<void> start({int sampleRate = 44100, int frame = 256}) =>
      _engine.start(sampleRate: sampleRate, frame: frame);

  @override
  void reference(Uint8List pcm16) => _engine.reference(pcm16);

  @override
  Stream<Uint8List> get cleaned => _engine.cleaned;

  @override
  Future<void> stop() => _engine.stop();
}
