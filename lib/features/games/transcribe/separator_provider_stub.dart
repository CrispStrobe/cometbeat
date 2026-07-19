// Web / no-dart:io fallback: no separator, so transcribeSong makes a single part.
// Signature must match separator_provider_io.dart.

import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;

/// Always null on web — no ONNX. [download] is accepted for a matching signature.
Future<Separator?> loadSeparator({bool download = false}) async => null;

/// The model is never present on web.
bool separatorModelPresent() => false;
