// Project persistence for the DAW: a portable JSON snapshot of a [DawTimeline].
//
// The DAW is a "vector, not bitmap" arranger, but its sources span very
// different models (a groove spec, an engraved score, a whole tracker song, a
// raw sample). Rather than a fragile per-type serializer for each, a saved
// project BAKES every clip to PCM — the one thing every [ClipSource] can
// produce — and stores it alongside the clip's placement. This is the same
// "freeze to a fixed take" verb the DAW already offers, applied to the whole
// arrangement: uniform, robust across every current and future source type,
// and a natural fit for an offline-render-then-play app.
//
// C1 (2026-07-26) — that is no longer the whole story. A clip now ALSO stores
// its model when it has one (`daw_clip_source_codec.dart`), so a tracker song,
// a groove, a drum grid or engraved music comes back as itself and can be
// reopened in its editor. The baked PCM stays alongside it, for three reasons:
// it is what a source WITHOUT a model (a recording, a bounce) has always been;
// it is the fallback when a model cannot be decoded, so a stale entry costs
// editability rather than audio; and it primes the render cache on load, so
// reopening a heavy arrangement does not re-render every clip before the first
// sample plays.
//
// The residual trade-off is narrower and still worth stating: a source type with
// no codec yet still reopens as audio only.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_clip_source_codec.dart';
import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';

/// Renders a source to PCM — injectable so the service can render through its
/// per-source cache instead of re-rendering on save.
typedef SourceRender = Float64List Function(ClipSource source);

/// The version WRITTEN. Version 2 adds the per-clip `source` model (C1).
const int _kProjectVersion = 2;

/// Versions that can be READ. A v1 project has no models and its clips come
/// back as audio, exactly as they always did.
const Set<int> _kReadableProjectVersions = {1, 2};

/// Serializes [timeline] to a JSON string: every audible clip baked to PCM plus
/// its placement. [render] defaults to a direct `source.render`.
String projectToJson(
  DawTimeline timeline, {
  int sampleRate = kDawSampleRate,
  SourceRender? render,
  TempoMap? tempoMap,
}) {
  final r = render ?? (s) => s.render(sampleRate);
  return jsonEncode({
    'v': _kProjectVersion,
    'sampleRate': sampleRate,
    if (timeline.effects.isNotEmpty)
      'effects': [for (final fx in timeline.effects) fx.toJson()],
    if (timeline.markers.isNotEmpty)
      'markers': [for (final m in timeline.markers) m.toJson()],
    // Only written when the tempo actually varies: a constant-tempo project
    // has nothing to say here that the app's own default does not cover, and
    // an absent key reads identically on an older build.
    if (tempoMap != null && !tempoMap.isConstant) 'tempo': tempoMap.toJson(),
    if (timeline.buses.isNotEmpty)
      'buses': [
        for (final bus in timeline.buses)
          {
            'name': bus.name,
            if (bus.effects.isNotEmpty)
              'effects': [for (final fx in bus.effects) fx.toJson()],
          },
      ],
    'tracks': [
      for (final track in timeline.tracks)
        {
          'name': track.name,
          'gain': track.gain,
          if (track.pan != 0) 'pan': track.pan,
          'muted': track.muted,
          'soloed': track.soloed,
          if (track.busIndex != null) 'busIndex': track.busIndex,
          if (track.busSends.isNotEmpty)
            'busSends': {
              for (final send in track.busSends.entries)
                if (send.value > 0) '${send.key}': send.value,
            },
          'effect': track.effect.name,
          if (track.effects.isNotEmpty)
            'effects': [for (final fx in track.effects) fx.toJson()],
          if (track.gainAutomation.isNotEmpty)
            'gainAutomation': [
              for (final point in track.gainAutomation) point.toJson(),
            ],
          'clips': [
            for (final clip in track.clips)
              {
                'startMs': clip.startMs,
                'gain': clip.gain,
                if (clip.pan != 0) 'pan': clip.pan,
                if (clip.width != 1) 'width': clip.width,
                'muted': clip.muted,
                'fadeInMs': clip.fadeInMs,
                'fadeOutMs': clip.fadeOutMs,
                'fadeInCurve': clip.fadeInCurve.name,
                'fadeOutCurve': clip.fadeOutCurve.name,
                'trimStartMs': clip.trimStartMs,
                'trimEndMs': clip.trimEndMs,
                if (clip.effects.isNotEmpty)
                  'effects': [for (final fx in clip.effects) fx.toJson()],
                if (clip.gainAutomation.isNotEmpty)
                  'gainAutomation': [
                    for (final point in clip.gainAutomation) point.toJson(),
                  ],
                // Licence obligations must survive save/load: one that vanishes
                // on reload is worse than none, because it looks discharged.
                if (clip.provenance != null)
                  'provenance': _provenanceToJson(clip.provenance!),
                // The model, when the source has one — what makes the clip
                // editable again rather than merely audible.
                if (clipSourceToJson(clip.source) case final source?)
                  'source': source,
                'pcm': base64Encode(_floatToInt16(r(clip.source))),
                if (clip.source is StereoSampleSource)
                  'rightPcm': base64Encode(
                    _floatToInt16((clip.source as StereoSampleSource).right),
                  ),
              },
          ],
        },
    ],
  });
}

/// Rebuilds a [DawTimeline] from [json].
///
/// A clip that stored a MODEL comes back as that model (a [TrackerSource],
/// [GrooveSource], [DrumSource] or [ScoreSource]) and is editable again; one
/// that did not — a recording, a bounce, or a v1 project — comes back as a
/// [SampleSource] of its baked PCM, as before.
///
/// Pass [warmCache] (the caller's render cache) to have the baked audio primed
/// against each restored source's key, so a reopened project plays immediately
/// instead of re-rendering every model first.
///
/// Throws [FormatException] on malformed input — callers catch it to report a
/// bad/corrupt project file.
/// The tempo map a project carried, or null when it had none (a constant-tempo
/// project, or one written before D6). Read separately from the timeline
/// because tempo lives on the SERVICE, not on the arrangement.
TempoMap? projectTempoFromJson(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final tempo = decoded['tempo'];
    return tempo is List ? TempoMap.fromJson(tempo) : null;
  } catch (_) {
    return null;
  }
}

DawTimeline projectFromJson(
  String json, {
  Map<Object, Float64List>? warmCache,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    throw const FormatException('Not a valid project file');
  }
  if (decoded is! Map || !_kReadableProjectVersions.contains(decoded['v'])) {
    throw const FormatException('Unrecognized project format');
  }
  final tracksJson = decoded['tracks'];
  if (tracksJson is! List) {
    throw const FormatException('Project has no tracks');
  }

  double num_(Object? v) => v is num ? v.toDouble() : 0.0;
  TrackEffect effect_(Object? v) {
    if (v is String) {
      for (final effect in TrackEffect.values) {
        if (effect.name == v) return effect;
      }
    }
    return TrackEffect.none;
  }

  DawFadeCurve fadeCurve_(Object? v) {
    if (v is String) {
      for (final curve in DawFadeCurve.values) {
        if (curve.name == v) return curve;
      }
    }
    return DawFadeCurve.linear;
  }

  final timelineEffects = [
    if (decoded['effects'] case final effects? when effects is List)
      for (final fx in effects)
        if (DawClipEffect.fromJson(fx) case final parsed?) parsed,
  ];
  final buses = [
    if (decoded['buses'] case final busesJson? when busesJson is List)
      for (final b in busesJson)
        if (b is Map)
          DawBus(
            name: b['name'] is String ? b['name'] as String : '',
            effects: [
              if (b['effects'] case final effects? when effects is List)
                for (final fx in effects)
                  if (DawClipEffect.fromJson(fx) case final parsed?) parsed,
            ],
          ),
  ];
  final tracks = <DawTrack>[];
  for (final t in tracksJson) {
    if (t is! Map) continue;
    final clipsJson = t['clips'];
    final clips = <Clip>[];
    if (clipsJson is List) {
      for (final c in clipsJson) {
        if (c is! Map) continue;
        final pcmB64 = c['pcm'];
        if (pcmB64 is! String) continue;
        final Float64List pcm;
        Float64List? right;
        try {
          pcm = _int16ToFloat(base64Decode(pcmB64));
          final rightB64 = c['rightPcm'];
          if (rightB64 is String) {
            right = _int16ToFloat(base64Decode(rightB64));
          }
        } catch (_) {
          continue; // skip an unreadable clip rather than fail the whole load
        }
        // Prefer the stored MODEL; fall back to the baked audio. A clip that
        // cannot decode its model is still a clip — it just arrives as a take.
        final restored = clipSourceFromJson(c['source']);
        if (restored != null) {
          // Prime the render cache with what was baked, so opening a project
          // does not re-render every tracker song and groove up front. The key
          // is the RESTORED source's own cacheKey, so a later edit to the model
          // invalidates it exactly as an edit made in this session would.
          warmCache?[restored.cacheKey] = pcm;
        }
        clips.add(
          Clip(
            source: restored ??
                (right == null
                    ? SampleSource(pcm)
                    : StereoSampleSource(pcm, right)),
            startMs: num_(c['startMs']),
            gain: c['gain'] is num ? num_(c['gain']) : 1.0,
            pan: c['pan'] is num ? num_(c['pan']).clamp(-1.0, 1.0) : 0.0,
            width: c['width'] is num ? num_(c['width']).clamp(0.0, 2.0) : 1.0,
            muted: c['muted'] == true,
            fadeInMs: num_(c['fadeInMs']),
            fadeOutMs: num_(c['fadeOutMs']),
            fadeInCurve: fadeCurve_(c['fadeInCurve']),
            fadeOutCurve: fadeCurve_(c['fadeOutCurve']),
            trimStartMs: num_(c['trimStartMs']),
            trimEndMs: num_(c['trimEndMs']),
            provenance: _provenanceFromJson(c['provenance']),
            effects: [
              if (c['effects'] case final effects? when effects is List)
                for (final fx in effects)
                  if (DawClipEffect.fromJson(fx) case final parsed?) parsed,
            ],
            gainAutomation: [
              if (c['gainAutomation'] case final points? when points is List)
                for (final point in points)
                  if (DawAutomationPoint.fromJson(point) case final parsed?)
                    parsed,
            ]..sort((a, b) => a.ms.compareTo(b.ms)),
          ),
        );
      }
    }
    tracks.add(
      () {
        final legacyEffect = effect_(t['effect']);
        final effects = [
          if (t['effects'] case final trackEffects? when trackEffects is List)
            for (final fx in trackEffects)
              if (DawClipEffect.fromJson(fx) case final parsed?) parsed,
        ];
        return DawTrack(
          name: t['name'] is String ? t['name'] as String : '',
          gain: t['gain'] is num ? num_(t['gain']) : 1.0,
          pan: t['pan'] is num ? num_(t['pan']).clamp(-1.0, 1.0) : 0.0,
          muted: t['muted'] == true,
          soloed: t['soloed'] == true,
          busIndex:
              t['busIndex'] is num ? (t['busIndex'] as num).toInt() : null,
          busSends: _parseBusSends(t['busSends']),
          effect: legacyEffect,
          effects: effects.isNotEmpty
              ? effects
              : trackEffectChainForLegacy(legacyEffect),
          gainAutomation: [
            if (t['gainAutomation'] case final points? when points is List)
              for (final point in points)
                if (DawAutomationPoint.fromJson(point) case final parsed?)
                  parsed,
          ]..sort((a, b) => a.ms.compareTo(b.ms)),
          clips: clips,
        );
      }(),
    );
  }
  return DawTimeline(
    tracks: tracks,
    buses: buses,
    effects: timelineEffects,
    markers: [
      if (decoded['markers'] case final list? when list is List)
        for (final m in list)
          if (DawMarker.fromJson(m) case final parsed?) parsed,
    ]..sort((a, b) => a.ms.compareTo(b.ms)),
  );
}

Uint8List _floatToInt16(Float64List pcm) {
  final bytes = Uint8List(pcm.length * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < pcm.length; i++) {
    view.setInt16(
      i * 2,
      (pcm[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}

Float64List _int16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, n * 2);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

Map<int, double> _parseBusSends(Object? value) {
  final sends = <int, double>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = int.tryParse('${entry.key}');
      final gain = entry.value;
      if (key != null && gain is num && gain > 0) {
        sends[key] = gain.toDouble();
      }
    }
  }
  return sends;
}

/// A clip's licence provenance, as stored in the project.
Map<String, dynamic> _provenanceToJson(LicensedWork w) => {
      'title': w.title,
      'license': w.license,
      if (w.creator != null) 'creator': w.creator,
      if (w.source != null) 'source': w.source,
      if (w.url != null) 'url': w.url,
    };

/// Read a clip's provenance. A malformed or absent entry yields null (the clip
/// simply carries no obligation) rather than failing the load — but a present
/// one MUST keep its licence, so an entry without one is discarded instead of
/// being resurrected as licence-free.
LicensedWork? _provenanceFromJson(Object? raw) {
  if (raw is! Map) return null;
  final title = raw['title'];
  final license = raw['license'];
  if (title is! String || license is! String || license.trim().isEmpty) {
    return null;
  }
  String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
  return LicensedWork(
    title: title,
    license: license,
    creator: str(raw['creator']),
    source: str(raw['source']),
    url: str(raw['url']),
  );
}
