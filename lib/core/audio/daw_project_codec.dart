// lib/core/audio/daw_project_codec.dart
//
// WS-W1c — audio becomes a real project kind.
//
// WHY THIS IS A REGISTRATION AND NOT A BUILT-IN. `project_codec.dart` carries
// codecs for the three kinds whose documents are pure Dart, and offers a
// REGISTRY for the rest. Audio is the clearest case for that registry:
// `projectToJson` needs a `SourceRender` callback to bake each clip, and a pure
// container has no business holding one. `tab` registers for the same class of
// reason (its document reaches Flutter through `crisp_notation`), so this is the
// established pattern rather than a special case.
//
// ⚠️ `daw_project.dart` is imported with a PREFIX: both it and
// `project_codec.dart` export a `projectFromJson`, one for a `.cbdaw` timeline
// and one for a `Project`. Same name, different documents — the prefix is what
// keeps the next reader from assuming they are the same function.
//
// IT WRITES NO NEW CODEC. `daw_project.dart` already serialises a `DawTimeline`
// — it is what `.cbdaw` is — so this wraps the existing pair. The same
// reuse-don't-rewrite shape that made the project mixdown cheap.
//
// ⚠️ THE ONE REAL MISMATCH, and it is a contract difference rather than a bug:
// `projectFromJson` THROWS on anything it cannot read, while
// `ProjectDocumentCodec.decode` must RETURN NULL — the registry's rule is that a
// codec which has moved on costs editability, never the file. An unreadable
// audio track has to come back as `unreadable` and be written out verbatim, not
// take the whole project down with it. Hence the catch.

import 'package:comet_beat/core/audio/daw_project.dart' as daw;
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project_codec.dart';

/// Teaches [Project] to carry an Audio Editor timeline.
///
/// Call once at start-up, next to `registerTabProjectCodec()`.
void registerAudioProjectCodec() {
  registerProjectDocumentCodec(
    ProjectDocumentCodec(
      kind: AppMode.audio,
      encode: (doc) {
        if (doc is! DawTimeline) return null;
        try {
          return {'daw': daw.projectToJson(doc)};
        } on Object {
          // A clip whose source cannot bake must not lose the whole project;
          // returning null carries the track verbatim instead.
          return null;
        }
      },
      decode: (json) {
        final raw = json['daw'];
        if (raw is! String) return null;
        try {
          return daw.projectFromJson(raw);
        } on Object {
          return null;
        }
      },
    ),
  );
}
