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
// Trade-off (documented, deliberate): a reopened project is a set of audio
// takes, not re-editable source models — reopening a saved groove gives you
// its audio, not the groove spec. The clip's placement, gain, fades and
// (non-destructive) trim all survive and stay editable.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';

/// Renders a source to PCM — injectable so the service can render through its
/// per-source cache instead of re-rendering on save.
typedef SourceRender = Float64List Function(ClipSource source);

const int _kProjectVersion = 1;

/// Serializes [timeline] to a JSON string: every audible clip baked to PCM plus
/// its placement. [render] defaults to a direct `source.render`.
String projectToJson(
  DawTimeline timeline, {
  int sampleRate = kDawSampleRate,
  SourceRender? render,
}) {
  final r = render ?? (s) => s.render(sampleRate);
  return jsonEncode({
    'v': _kProjectVersion,
    'sampleRate': sampleRate,
    'tracks': [
      for (final track in timeline.tracks)
        {
          'name': track.name,
          'gain': track.gain,
          'muted': track.muted,
          'soloed': track.soloed,
          'clips': [
            for (final clip in track.clips)
              {
                'startMs': clip.startMs,
                'gain': clip.gain,
                'muted': clip.muted,
                'fadeInMs': clip.fadeInMs,
                'fadeOutMs': clip.fadeOutMs,
                'trimStartMs': clip.trimStartMs,
                'trimEndMs': clip.trimEndMs,
                if (clip.effects.isNotEmpty)
                  'effects': [for (final fx in clip.effects) fx.toJson()],
                'pcm': base64Encode(_floatToInt16(r(clip.source))),
              },
          ],
        },
    ],
  });
}

/// Rebuilds a [DawTimeline] from [json]. Every clip comes back as a
/// [SampleSource] of its baked PCM. Throws [FormatException] on malformed input
/// — callers catch it to report a bad/corrupt project file.
DawTimeline projectFromJson(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    throw const FormatException('Not a valid project file');
  }
  if (decoded is! Map || decoded['v'] != _kProjectVersion) {
    throw const FormatException('Unrecognized project format');
  }
  final tracksJson = decoded['tracks'];
  if (tracksJson is! List) {
    throw const FormatException('Project has no tracks');
  }

  double num_(Object? v) => v is num ? v.toDouble() : 0.0;

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
        try {
          pcm = _int16ToFloat(base64Decode(pcmB64));
        } catch (_) {
          continue; // skip an unreadable clip rather than fail the whole load
        }
        clips.add(
          Clip(
            source: SampleSource(pcm),
            startMs: num_(c['startMs']),
            gain: c['gain'] is num ? num_(c['gain']) : 1.0,
            muted: c['muted'] == true,
            fadeInMs: num_(c['fadeInMs']),
            fadeOutMs: num_(c['fadeOutMs']),
            trimStartMs: num_(c['trimStartMs']),
            trimEndMs: num_(c['trimEndMs']),
            effects: [
              if (c['effects'] case final effects? when effects is List)
                for (final fx in effects)
                  if (DawClipEffect.fromJson(fx) case final parsed?) parsed,
            ],
          ),
        );
      }
    }
    tracks.add(
      DawTrack(
        name: t['name'] is String ? t['name'] as String : '',
        gain: t['gain'] is num ? num_(t['gain']) : 1.0,
        muted: t['muted'] == true,
        soloed: t['soloed'] == true,
        clips: clips,
      ),
    );
  }
  return DawTimeline(tracks: tracks);
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
