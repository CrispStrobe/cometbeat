// lib/core/project/project_render.dart
//
// WS-W5b — the project mix, made audible.
//
// `WS-W5` shipped a mixer whose level, pan, mute and solo **no render path
// honoured**, so it was a settings screen you could not hear. That is the same
// inert-feature shape as the shared count-in, `Project` itself and
// `ProjectTrackMix` — the fourth time on this ladder — and this closes it.
//
// IT DOES NOT WRITE A SECOND RENDERER, deliberately. `core/audio/daw_sources.dart`
// already turns every kind into PCM: `TrackerSource`, `GrooveSource` and
// `ScoreSource` each implement `ClipSource.render(sampleRate)`, complete with
// their own caching. A project mixdown is therefore nothing more than *map each
// track's document to the source that already renders it, apply the track's
// mix, sum* — no new DSP, no new per-kind knowledge, and no existing render
// path modified, which is what makes the byte-identical guard hold by
// construction rather than by testing.
//
// IT REPORTS WHAT IT COULD NOT RENDER. A tab has no direct PCM source (it is
// notation plus fingering, and turning it into sound means choosing an
// instrument — a decision that belongs to a caller, not to a mixdown), and an
// audio track needs a clip that the project does not carry yet. Those tracks
// are named in [ProjectMixdown.skipped] rather than quietly omitted: a mix that
// silently drops a part is worse than one that says which part it dropped.
//
// THE PAN LAW MATCHES THE REST OF THE APP — constant power, pan −1..1 mapped to
// an angle 0..π/2 with cos/sin gains, the same shaping `panPartsToStereo` uses
// in `score_instrument_render.dart`. A mixer whose centre was louder than the
// app's other panners would be a bug nobody could name.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart'
    show ClipSource, kDawSampleRate;
import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:crisp_notation/crisp_notation.dart' show MultiPartScore;

/// A track the mixdown could not turn into sound, and why.
class SkippedTrack {
  const SkippedTrack(this.trackId, this.reason);

  final String trackId;

  /// Plain enough to show a user — "this track has no sound yet" is a thing a
  /// person can act on; a type name is not.
  final String reason;

  @override
  String toString() => 'SkippedTrack($trackId: $reason)';
}

/// The summed project, in stereo, plus an honest account of what is missing.
class ProjectMixdown {
  const ProjectMixdown({
    required this.left,
    required this.right,
    required this.sampleRate,
    this.skipped = const [],
  });

  final Float64List left;
  final Float64List right;
  final int sampleRate;

  /// Tracks that contributed nothing, and why. Empty is the happy case.
  final List<SkippedTrack> skipped;

  /// Length in samples (both channels are the same length by construction).
  int get lengthInSamples => left.length;

  double get durationMs =>
      sampleRate <= 0 ? 0 : left.length * 1000 / sampleRate;

  /// Whether anything at all was rendered — false for an empty project, a
  /// fully-muted one, or one where nothing could be rendered.
  bool get isSilent => left.isEmpty;
}

/// Renders [project] to a stereo mix, honouring each track's
/// [ProjectTrackMix].
///
/// Solo wins over mute in the usual way: if ANY track is soloed, only soloed
/// tracks are heard, and a soloed track that is also muted stays silent —
/// muting something you soloed is a deliberate act, not a contradiction to
/// resolve in the user's favour.
///
/// Tracks are summed from sample 0; a shorter track simply stops. No
/// normalisation is applied, because a mixdown that quietly changed the level
/// the user set would make the fader a lie.
ProjectMixdown renderProject(
  Project project, {
  int sampleRate = kDawSampleRate,
}) {
  final skipped = <SkippedTrack>[];
  final rendered = <(Float64List, ProjectTrackMix)>[];

  final anySolo = project.tracks.any((t) => t.mix.soloed);

  for (final track in project.tracks) {
    if (anySolo && !track.mix.soloed) continue;
    if (track.mix.muted) continue;
    if (track.mix.level <= 0) continue;

    final source = _sourceFor(track);
    if (source == null) {
      skipped.add(SkippedTrack(track.id, _whyNoSound(track)));
      continue;
    }
    final pcm = source.render(sampleRate);
    if (pcm.isEmpty) continue;
    rendered.add((pcm, track.mix));
  }

  if (rendered.isEmpty) {
    return ProjectMixdown(
      left: Float64List(0),
      right: Float64List(0),
      sampleRate: sampleRate,
      skipped: skipped,
    );
  }

  var length = 0;
  for (final (pcm, _) in rendered) {
    if (pcm.length > length) length = pcm.length;
  }
  final left = Float64List(length);
  final right = Float64List(length);

  for (final (pcm, mix) in rendered) {
    // pan −1..1 → angle 0..π/2; cos/sin give the L/R gains, equal at centre.
    final theta = (mix.pan.clamp(-1.0, 1.0) + 1) * 0.25 * math.pi;
    final lg = math.cos(theta) * mix.level;
    final rg = math.sin(theta) * mix.level;
    for (var i = 0; i < pcm.length; i++) {
      left[i] += pcm[i] * lg;
      right[i] += pcm[i] * rg;
    }
  }

  return ProjectMixdown(
    left: left,
    right: right,
    sampleRate: sampleRate,
    skipped: skipped,
  );
}

/// The already-existing source that renders this track's document, or null
/// when there is none.
ClipSource? _sourceFor(ProjectTrack track) {
  final doc = track.document;
  if (doc == null || !track.isReadable) return null;
  return switch (track.kind) {
    AppMode.tracker => doc is TrackerSong ? TrackerSource(doc) : null,
    AppMode.loop => doc is GrooveSpec ? GrooveSource(doc) : null,
    AppMode.score => doc is MultiPartScore ? ScoreSource(doc) : null,
    // Tab and audio have no direct PCM source — see the header.
    AppMode.tab || AppMode.audio => null,
  };
}

String _whyNoSound(ProjectTrack track) {
  if (!track.isReadable) {
    return 'made by a newer version and kept as-is';
  }
  if (track.document == null) {
    return 'no document to play';
  }
  return switch (track.kind) {
    AppMode.tab => 'a tab needs an instrument chosen before it can sound',
    AppMode.audio => 'audio tracks are not carried in the project yet',
    _ => 'the document is not the type this kind renders',
  };
}
