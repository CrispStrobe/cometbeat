// Web / no-dart:io fallback: no CLI, so no CrispASR separator.
// Signature must match crispasr_separate_io.dart.

import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;

/// Always null on web — no process/filesystem. [binary]/[model] are accepted for
/// a matching signature.
Separator? crispasrCliSeparator({
  required String binary,
  required String model,
  String? workDir,
}) =>
    null;
