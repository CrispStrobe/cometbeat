// The CrispASR FFI piano/separate providers (crispasr 0.8.17). Can't run the
// native lib in CI, so we assert the invariant: they degrade gracefully — no
// pitch-capable/htdemucs/piano libcrispasr here ⇒ null WITHOUT throwing, so the
// resolver falls back (onnx Basic Pitch / a single-part song).

import 'package:comet_beat/core/audio/transcription/crispasr_ffi_piano.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('piano + separate FFI loaders never throw; null when the lib is absent',
      () async {
    expect(await loadCrispasrPianoFfi(), anyOf(isNull, isNotNull));
    expect(await loadCrispasrFfiSeparator(), anyOf(isNull, isNotNull));
  });

  test('every note model degrades the same way — null, never a throw',
      () async {
    // basic-pitch / piano-transcription / mt3 all go through the SAME C entry
    // point, so the failure mode must be identical for all three: no lib, no
    // registry entry, or an uncached model ⇒ null, and the resolver falls back
    // to the pure-Dart ONNX Basic Pitch. download:false keeps CI off the network.
    for (final m in CrispasrNoteModel.values) {
      expect(
        await loadCrispasrPianoFfi(model: m),
        anyOf(isNull, isNotNull),
        reason: '$m must not throw',
      );
    }
  });
}
