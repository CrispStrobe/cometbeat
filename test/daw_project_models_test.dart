// C1 — a saved project keeps its clips EDITABLE, not just audible.
//
// Before this, `projectToJson` baked every clip to PCM, so the "vector, not
// bitmap" timeline survived only until the user pressed Save: reopening turned a
// tracker song into a waveform and closed every editor door behind it. These
// tests pin the round trip per source type, the fallbacks that keep a project
// openable when a model cannot be read, and the v1 compatibility that must not
// regress.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_clip_source_codec.dart';
import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerTiming;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

DawTimeline _timelineWith(ClipSource source) => DawTimeline(
      tracks: [
        DawTrack(name: 'A', clips: [Clip(source: source)]),
      ],
    );

ClipSource _roundTrip(ClipSource source) {
  final json = projectToJson(_timelineWith(source));
  return projectFromJson(json).tracks.single.clips.single.source;
}

DrumRowsPattern _beat() => DrumRowsPattern(
      {
        Drum.kick: [
          for (var i = 0; i < kPatternSteps; i++) i % 4 == 0,
        ],
        Drum.snare: [
          for (var i = 0; i < kPatternSteps; i++) i % 8 == 4,
        ],
      },
      velocities: {
        Drum.kick: [for (var i = 0; i < kPatternSteps; i++) i == 0 ? 1.0 : 0.6],
      },
    );

const _quarter = NoteDuration.quarter;

MultiPartScore _score() => MultiPartScore([
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(const Pitch(Step.c), _quarter),
            NoteElement.note(const Pitch(Step.e), _quarter),
            const RestElement(_quarter),
          ]),
        ],
      ),
    ]);

void main() {
  group('a clip comes back as its model', () {
    test('a tracker song', () {
      final song = TrackerSong(
        timing: const TrackerTiming(tempoBpm: 132, rows: 32),
      );
      final back = _roundTrip(TrackerSource(song));
      expect(back, isA<TrackerSource>());
      expect((back as TrackerSource).song.timing.tempoBpm, 132);
      expect(back.song.timing.rows, 32);
    });

    test('a groove spec', () {
      const spec = GrooveSpec(swing: 0.15, key: 3);
      final back = _roundTrip(GrooveSource(spec));
      expect(back, isA<GrooveSource>());
      // The spec's own cache key is its canonical JSON, so equal keys mean the
      // groove came back byte-for-byte.
      expect((back as GrooveSource).spec.cacheKey, spec.cacheKey);
      expect(back.spec.swing, closeTo(0.15, 1e-9));
      expect(back.spec.key, 3);
    });

    test('a drum beat, with its grid, its ghost notes and its timing', () {
      const timing = LoopTiming(tempoBpm: 120, swing: 0.2);
      final back = _roundTrip(DrumSource(_beat(), timing));
      expect(back, isA<DrumSource>());
      final drum = back as DrumSource;
      expect(drum.timing.tempoBpm, 120);
      expect(drum.timing.swing, closeTo(0.2, 1e-9));
      expect(drum.timing.bars, 2);
      expect(drum.pattern.rows[Drum.kick]!.take(8), [
        true, false, false, false, true, false, false, false, //
      ]);
      expect(drum.pattern.rows[Drum.snare]![4], isTrue);
      // The ghost-note dynamics are half the reason a beat sounds like itself.
      expect(drum.pattern.velocities?[Drum.kick]?[0], closeTo(1, 1e-9));
      expect(drum.pattern.velocities?[Drum.kick]?[1], closeTo(0.6, 1e-9));
    });

    test('engraved music, note for note', () {
      final back = _roundTrip(ScoreSource(_score(), quarterMs: 400));
      expect(back, isA<ScoreSource>());
      final score = back as ScoreSource;
      expect(score.quarterMs, 400);
      final measure = score.score.parts.single.measures.single;
      final notes = measure.elements.whereType<NoteElement>().toList();
      expect(notes, hasLength(2));
      const c = Pitch(Step.c);
      const e = Pitch(Step.e);
      expect(notes[0].pitches.single.midiNumber, c.midiNumber);
      expect(notes[1].pitches.single.midiNumber, e.midiNumber);
      expect(measure.elements.whereType<RestElement>(), hasLength(1));
    });

    test('the whole arrangement survives together', () {
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            name: 'A',
            clips: [
              Clip(
                source: DrumSource(_beat(), const LoopTiming(tempoBpm: 100)),
              ),
              Clip(source: ScoreSource(_score()), startMs: 2000),
            ],
          ),
          DawTrack(
            name: 'B',
            clips: [Clip(source: TrackerSource(TrackerSong()))],
          ),
        ],
      );
      final back = projectFromJson(projectToJson(timeline));
      expect(
        back.tracks.first.clips.map((c) => c.source.runtimeType).toList(),
        [DrumSource, ScoreSource],
      );
      expect(back.tracks.last.clips.single.source, isA<TrackerSource>());
    });
  });

  group('placement still survives, exactly as before', () {
    test('a restored model keeps its clip settings', () {
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(
                source: DrumSource(_beat(), const LoopTiming(tempoBpm: 100)),
                startMs: 1500,
                gain: 0.5,
                pan: -0.25,
                fadeInMs: 20,
                fadeOutMs: 30,
                trimStartMs: 10,
                trimEndMs: 900,
                effects: [defaultDawClipEffect(DawClipEffectType.reverb)],
              ),
            ],
          ),
        ],
      );
      final clip =
          projectFromJson(projectToJson(timeline)).tracks.single.clips.single;
      expect(clip.source, isA<DrumSource>());
      expect(clip.startMs, 1500);
      expect(clip.gain, 0.5);
      expect(clip.pan, -0.25);
      expect(clip.fadeInMs, 20);
      expect(clip.fadeOutMs, 30);
      expect(clip.trimStartMs, 10);
      expect(clip.trimEndMs, 900);
      expect(clip.effects.single.type, DawClipEffectType.reverb);
    });

    test('a licence obligation still rides along with the model', () {
      // Provenance travelling with the clip is what lets an export know what it
      // owes; a model that arrived licensed must not come back unencumbered.
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(
                source: DrumSource(_beat(), const LoopTiming(tempoBpm: 100)),
                provenance: const LicensedWork(
                  title: 'Borrowed beat',
                  license: 'CC-BY-4.0',
                  creator: 'Someone',
                ),
              ),
            ],
          ),
        ],
      );
      final clip =
          projectFromJson(projectToJson(timeline)).tracks.single.clips.single;
      expect(clip.source, isA<DrumSource>());
      expect(clip.provenance?.license, 'CC-BY-4.0');
      expect(clip.provenance?.creator, 'Someone');
    });
  });

  group('audio still works where there is no model', () {
    test('a recorded sample round-trips as audio', () {
      final pcm = Float64List.fromList([0.0, 0.5, -0.5, 0.25]);
      final back = _roundTrip(SampleSource(pcm));
      expect(back, isA<SampleSource>());
      expect((back as SampleSource).pcm.length, 4);
      expect(back.pcm[1], closeTo(0.5, 1e-4));
    });

    test('a stereo sample keeps both sides', () {
      final left = Float64List.fromList([0.5, 0.5]);
      final right = Float64List.fromList([-0.5, -0.5]);
      final back = _roundTrip(StereoSampleSource(left, right));
      expect(back, isA<StereoSampleSource>());
      expect((back as StereoSampleSource).right[0], closeTo(-0.5, 1e-4));
    });

    test('a source with no codec saves and loads as audio, not as an error',
        () {
      // The degradation path for a source type added later: no model entry, and
      // the bake carries it exactly as it always did.
      expect(clipSourceToJson(SampleSource(Float64List(4))), isNull);
    });
  });

  group('robustness — a bad model costs editability, never the project', () {
    test('an unreadable model falls back to the baked audio', () {
      final json = jsonDecode(
        projectToJson(
          _timelineWith(DrumSource(_beat(), const LoopTiming(tempoBpm: 100))),
        ),
      ) as Map<String, dynamic>;
      // Corrupt the model but leave the PCM intact.
      (json['tracks'][0]['clips'][0] as Map)['source'] = {
        'kind': 'drum',
        'data': {'rows': 'not a map'},
      };
      final clip = projectFromJson(jsonEncode(json)).tracks.single.clips.single;
      expect(clip.source, isA<SampleSource>());
      expect((clip.source as SampleSource).pcm, isNotEmpty);
    });

    test('an unknown source kind falls back too', () {
      expect(clipSourceFromJson({'kind': 'holographic', 'data': 42}), isNull);
    });

    test('malformed entries never throw', () {
      for (final raw in [
        null,
        42,
        'nope',
        <String, dynamic>{},
        {'kind': 'tracker'},
        {'kind': 'tracker', 'data': 'not a map'},
        {'kind': 'groove', 'data': <String, dynamic>{}},
        {'kind': 'score', 'data': '<not really xml'},
        {'kind': 'drum', 'data': <String, dynamic>{}},
      ]) {
        expect(() => clipSourceFromJson(raw), returnsNormally, reason: '$raw');
      }
    });
  });

  group('file format', () {
    test('a v1 project still opens, as audio', () {
      // Written by the pre-C1 build: version 1, one clip, PCM only.
      final v1 = jsonEncode({
        'v': 1,
        'sampleRate': kDawSampleRate,
        'tracks': [
          {
            'name': 'A',
            'gain': 1.0,
            'muted': false,
            'soloed': false,
            'effect': 'none',
            'clips': [
              {
                'startMs': 500.0,
                'gain': 0.8,
                'muted': false,
                'fadeInMs': 0.0,
                'fadeOutMs': 0.0,
                'fadeInCurve': 'linear',
                'fadeOutCurve': 'linear',
                'trimStartMs': 0.0,
                'trimEndMs': 0.0,
                'pcm': base64Encode(Uint8List.fromList([0, 0, 0, 64])),
              },
            ],
          },
        ],
      });
      final clip = projectFromJson(v1).tracks.single.clips.single;
      expect(clip.source, isA<SampleSource>());
      expect(clip.startMs, 500);
      expect(clip.gain, 0.8);
    });

    test('an unrecognised version is still rejected', () {
      expect(
        () => projectFromJson(jsonEncode({'v': 99, 'tracks': []})),
        throwsFormatException,
      );
      expect(() => projectFromJson('{'), throwsFormatException);
    });

    test('the source kinds are the on-disk names and must not drift', () {
      // Renaming one silently strands every project saved before the rename.
      expect(ClipSourceKind.tracker, 'tracker');
      expect(ClipSourceKind.groove, 'groove');
      expect(ClipSourceKind.drum, 'drum');
      expect(ClipSourceKind.score, 'score');
    });
  });

  test('the baked audio primes the render cache under the restored key', () {
    // Without this a reopened arrangement re-renders every tracker song and
    // groove before the first sample plays.
    final source = DrumSource(_beat(), const LoopTiming(tempoBpm: 100));
    final json = projectToJson(_timelineWith(source));
    final warm = <Object, Float64List>{};
    final timeline = projectFromJson(json, warmCache: warm);
    final restored = timeline.tracks.single.clips.single.source;
    expect(warm.keys, contains(restored.cacheKey));
    expect(warm[restored.cacheKey], isNotEmpty);
  });
}
