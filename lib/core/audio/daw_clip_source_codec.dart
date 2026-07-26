// lib/core/audio/daw_clip_source_codec.dart
//
// C1 — what a clip IS, not just what it sounded like.
//
// The DAW's timeline is a "vector, not bitmap" arranger: a clip holds a MODEL
// (a tracker song, a groove spec, a drum grid, engraved music) and the mix is
// rasterized on demand. Saving, however, baked every clip to PCM — so the whole
// design survived exactly until the user pressed Save. Reopen a project and the
// tracker song you spent an hour on is a waveform: it still plays, it can still
// be trimmed and faded, but "Open in Tracker" is gone and so is every other
// editor. That is the single biggest hole in the five-mode interop promise, and
// it is what this file closes.
//
// The approach is deliberately NOT a new serialization format. Every source type
// already has a codec that something else depends on — the Tracker's song JSON,
// the Loop Mixer's `GrooveSpec` (its share token is that JSON), MusicXML for
// engraved music — so this is a dispatch over the codecs that exist, plus a
// `kind` tag to route them back. Nothing here knows how to encode music; it
// knows which encoder owns each kind.
//
// Two rules that keep it honest:
//
//   * **A source that cannot be encoded is not an error.** It simply gets no
//     entry, and the project's baked PCM carries it as before. New source types
//     therefore degrade to the old behaviour instead of breaking saves.
//   * **A source that cannot be DECODED is not an error either.** A project
//     written by a newer build, a corrupt entry, a codec that has moved on — all
//     fall back to the PCM that is still in the file. Losing editability is bad;
//     losing the audio would be much worse.
//
// Pure Dart, no Flutter.

import 'dart:convert';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, GrooveSpec, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_song_codec.dart'
    show trackerSongFromJson, trackerSongToJson;
import 'package:crisp_notation/crisp_notation.dart'
    show multiPartScoreFromMusicXml, multiPartToMusicXml;

/// The tag that routes a stored source back to its codec.
///
/// These strings are an ON-DISK representation: rename one and every project
/// saved before the rename loses its models (silently, falling back to PCM).
/// Add, never rename.
abstract final class ClipSourceKind {
  static const tracker = 'tracker';
  static const groove = 'groove';
  static const drum = 'drum';
  static const score = 'score';
}

/// Encode [source] as a restorable model, or null when it has none.
///
/// Null is the normal answer for a [SampleSource]: a recording or a bounce IS
/// its audio, so the PCM the project already stores is the whole truth and a
/// second copy would be waste.
Map<String, dynamic>? clipSourceToJson(ClipSource source) {
  if (source is TrackerSource) {
    return {
      'kind': ClipSourceKind.tracker,
      'data': trackerSongToJson(source.song),
    };
  }
  if (source is GrooveSource) {
    return {'kind': ClipSourceKind.groove, 'data': source.spec.toJson()};
  }
  if (source is DrumSource) {
    return {
      'kind': ClipSourceKind.drum,
      'data': {
        'rows': {
          for (final entry in source.pattern.rows.entries)
            entry.key.name: entry.value.map((on) => on ? 1 : 0).toList(),
        },
        if (source.pattern.velocities case final velocities?)
          'velocities': {
            for (final entry in velocities.entries) entry.key.name: entry.value,
          },
        'timing': {
          'tempoBpm': source.timing.tempoBpm,
          'swing': source.timing.swing,
          'bars': source.timing.bars,
        },
      },
    };
  }
  if (source is ScoreSource) {
    // MusicXML rather than a private encoding: it is the format the Workshop
    // already reads and writes, so a project's music stays openable by every
    // route that accepts a score — including outside this app.
    return {
      'kind': ClipSourceKind.score,
      'quarterMs': source.quarterMs,
      'data': multiPartToMusicXml(source.score),
    };
  }
  return null;
}

/// Rebuild a source from [raw], or null when it cannot be restored.
///
/// Never throws: a caller has PCM to fall back on, and a project that refuses to
/// open because one clip's model went stale would be a far worse outcome than
/// one clip arriving as audio.
ClipSource? clipSourceFromJson(Object? raw) {
  if (raw is! Map) return null;
  final kind = raw['kind'];
  final data = raw['data'];
  if (kind is! String) return null;
  try {
    switch (kind) {
      case ClipSourceKind.tracker:
        if (data is! Map) return null;
        return TrackerSource(
          trackerSongFromJson(Map<String, dynamic>.from(data)),
        );
      case ClipSourceKind.groove:
        if (data is! Map) return null;
        return GrooveSource(
          GrooveSpec.fromJson(Map<String, dynamic>.from(data)),
        );
      case ClipSourceKind.drum:
        if (data is! Map) return null;
        return _drumFromJson(data);
      case ClipSourceKind.score:
        if (data is! String) return null;
        final quarterMs = raw['quarterMs'];
        return ScoreSource(
          multiPartScoreFromMusicXml(data),
          quarterMs: quarterMs is num ? quarterMs.toInt() : 500,
        );
    }
  } catch (_) {
    // A codec that rejects its own older output, a truncated entry, a format
    // that has moved on — all mean "no model", not "no project".
    return null;
  }
  return null;
}

DrumSource? _drumFromJson(Map<dynamic, dynamic> data) {
  final rowsJson = data['rows'];
  if (rowsJson is! Map) return null;
  final drumsByName = {for (final drum in Drum.values) drum.name: drum};
  final rows = <Drum, List<bool>>{};
  for (final entry in rowsJson.entries) {
    final drum = drumsByName[entry.key];
    final steps = entry.value;
    if (drum == null || steps is! List) continue;
    rows[drum] = [
      for (var i = 0; i < kPatternSteps; i++)
        i < steps.length && steps[i] != 0 && steps[i] != false,
    ];
  }
  if (rows.isEmpty) return null;

  Map<Drum, List<double>>? velocities;
  final velocitiesJson = data['velocities'];
  if (velocitiesJson is Map) {
    velocities = {};
    for (final entry in velocitiesJson.entries) {
      final drum = drumsByName[entry.key];
      final values = entry.value;
      if (drum == null || values is! List) continue;
      velocities[drum] = [
        for (final v in values)
          if (v is num) v.toDouble() else 1.0,
      ];
    }
    if (velocities.isEmpty) velocities = null;
  }

  final timing = data['timing'];
  // 100 BPM is one of the three tempos the loop grid keeps integral in both ms
  // and samples, so a pattern whose timing did not survive still lands on the
  // grid rather than drifting against everything else on the timeline.
  const fallback = LoopTiming(tempoBpm: 100);
  int whole(Object? value, int orElse) =>
      value is num && value.isFinite ? value.toInt() : orElse;
  return DrumSource(
    DrumRowsPattern(rows, velocities: velocities),
    timing is Map
        ? LoopTiming(
            tempoBpm: whole(timing['tempoBpm'], fallback.tempoBpm),
            swing: timing['swing'] is num && (timing['swing'] as num).isFinite
                ? (timing['swing'] as num).toDouble()
                : fallback.swing,
            bars: whole(timing['bars'], fallback.bars),
          )
        : fallback,
  );
}

/// A stable text form of an encoded source, for tests and debugging.
String clipSourceDebugString(ClipSource source) {
  final json = clipSourceToJson(source);
  return json == null ? '${source.runtimeType}(no model)' : jsonEncode(json);
}
