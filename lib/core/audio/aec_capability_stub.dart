// lib/core/audio/aec_capability_stub.dart
//
// The `dart:ffi`-free fallback used on platforms without FFI (the web). No
// native AEC engine here — the caller falls back to the `record` capture path.
// See aec_capability.dart.

import 'package:comet_beat/core/audio/aec_engine.dart';

/// No native engine on this platform.
AecEngine? createNativeAecEngine() => null;
