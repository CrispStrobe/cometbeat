// lib/core/audio/loop_export_render.dart
//
// Rendering a Loop Studio groove for EXPORT, off the UI isolate.
//
// The worker cannot be handed the live LoopEngine (its caches and the State
// that owns it are not sendable), so it rebuilds an engine from a small value
// and renders that. The value has to carry everything that decides what the
// loop SOUNDS like — and `GrooveSpec` alone does not: it is the share token,
// so it deliberately leaves out the master bus (send, FX chain, filter), which
// are live controls. Rendering from the spec alone exported a different mix
// from the one on the speakers whenever any of them was set.
//
// Audio tracks are the one thing that cannot travel at all (megabytes of PCM,
// and the spec drops them by design), so a groove holding one is rendered on
// the calling isolate instead — see [canRenderGrooveOffThread].
//
// Flutter-free and top-level on purpose: an isolate entry point written as a
// closure inside a State method shares that method's context and drags the
// State into the isolate message ("object is unsendable").

import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';

/// Everything a worker needs to reproduce what [LoopEngine.renderLoop] plays.
/// All fields are plain values, so the record is sendable to an isolate.
typedef GrooveRenderJob = ({
  GrooveSpec spec,
  LoopSend send,
  List<FxSpec> masterFx,
  double masterFilter,
});

/// Snapshot of [engine] for an export render.
GrooveRenderJob grooveRenderJob(LoopEngine engine) => (
      spec: engine.spec,
      send: engine.send,
      masterFx: List<FxSpec>.of(engine.masterFxChain),
      masterFilter: engine.masterFilter,
    );

/// Whether [engine] can be rendered from a [GrooveRenderJob] without losing
/// anything — false while it holds an audio track, whose PCM is not in a spec.
bool canRenderGrooveOffThread(LoopEngine engine) =>
    !engine.tracks.any((t) => engine.isAudioTrack(t.id));

/// The isolate entry point: the loop as a WAV (mono, or stereo when a track
/// is panned — exactly what [LoopEngine.renderLoop] returns).
Uint8List renderGrooveJob(GrooveRenderJob job) {
  final engine = LoopEngine()
    ..applySpec(job.spec)
    ..send = job.send
    ..masterFxChain = List<FxSpec>.of(job.masterFx)
    ..masterFilter = job.masterFilter;
  return engine.renderLoop();
}
