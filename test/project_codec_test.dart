// WS-W1 — one document, many track kinds.
//
// The app has five editors, five documents and nothing that can hold more than
// one at a time. `Project` is the container that lets "the tracker pattern in
// bar 9" and "the clip on the timeline" be one object.
//
// The acceptance the ladder asks for, and why each half of it matters:
//
//   A project holding one track of every kind round-trips through the codec
//   with each document INTACT — asserted on the documents, not on the JSON.
//   Asserting on JSON would pass for a codec that writes a perfectly-shaped
//   file and hands back the wrong music.
//
//   An unknown `kind` is preserved VERBATIM rather than dropped, so a newer
//   project opened by an older build loses nothing. This is the assertion that
//   protects against the worst failure mode there is: the file looks fine after
//   the first save and is missing a track after the second.
//
// The registry is the design decision under test throughout. Two of the five
// kinds have no codec today — `tab` has no serialization AT ALL (its only
// persistence is a lossy MusicXML export; see WS-L11) and `audio` needs a PCM
// render callback a pure container should not hold — so "no codec registered"
// and "kind I have never heard of" have to be the same, safe path.

import 'dart:io';

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_codec.dart';
// `hide TempoMap`: crisp_notation_core has one too, and the project's tempo is
// the DAW's — the one `daw_tempo_map.dart` defines and `TransportService`
// (WS-W2) will read.
import 'package:crisp_notation_core/crisp_notation_core.dart' hide TempoMap;
import 'package:flutter_test/flutter_test.dart';

/// A tracker song with something in it worth losing.
TrackerSong _song() {
  final song = TrackerSong(timing: const TrackerTiming(rows: 8));
  song.engine
    ..setCell(0, 0, const TrackerCell(midi: 60, instrument: 1, volume: 48))
    ..setCell(1, 4, const TrackerCell(midi: 67, instrument: 2));
  song.syncCurrent();
  return song;
}

/// A groove using the state that only started travelling recently, so this test
/// also fails if `GrooveSpec` stops carrying it.
GrooveSpec _groove() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass']);
  e
    ..setPan('bass', -0.5)
    ..setTrackFilter('bass', -0.4)
    ..setTrackSteps('drums', 3);
  return e.spec;
}

// Not `const`: MultiPartScore asserts on parts.length, which the const
// evaluator cannot run. Same shape the existing multi-part tests use.
MultiPartScore _score() => MultiPartScore(const [
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch(Step.c)],
              duration: NoteDuration.quarter,
            ),
            NoteElement(
              pitches: [Pitch(Step.e)],
              duration: NoteDuration.quarter,
            ),
          ]),
        ],
      ),
    ]);

Project _everyKind() => Project(
      name: 'All five',
      tempo: TempoMap.constant(96),
      tracks: [
        ProjectTrack(
          id: 'tracker-1',
          kind: AppMode.tracker,
          name: 'Beat',
          document: _song(),
          mix: const ProjectTrackMix(level: 0.8, pan: -0.25),
        ),
        ProjectTrack(
          id: 'loop-1',
          kind: AppMode.loop,
          name: 'Groove',
          document: _groove(),
        ),
        ProjectTrack(
          id: 'score-1',
          kind: AppMode.score,
          name: 'Tune',
          document: _score(),
          mix: const ProjectTrackMix(muted: true),
        ),
        // The two with no codec yet. They must survive as TRACKS even though
        // their music cannot be written — losing the row would be worse than
        // losing the document, because the row is what tells you it is missing.
        ProjectTrack(id: 'tab-1', kind: AppMode.tab, name: 'Riff'),
        ProjectTrack(id: 'audio-1', kind: AppMode.audio, name: 'Vocal'),
      ],
    );

Project _roundTrip(Project p) => projectFromJsonString(projectToJsonString(p))!;

void main() {
  setUp(resetProjectDocumentCodecs);

  group('a project holds one track of every kind', () {
    test('every track survives, in order, with its identity', () {
      final back = _roundTrip(_everyKind());
      expect(back.name, 'All five');
      expect(
        back.tracks.map((t) => t.id),
        ['tracker-1', 'loop-1', 'score-1', 'tab-1', 'audio-1'],
      );
      expect(back.tracks.map((t) => t.kind), [
        AppMode.tracker,
        AppMode.loop,
        AppMode.score,
        AppMode.tab,
        AppMode.audio,
      ]);
      expect(back.tracks.map((t) => t.name), [
        'Beat',
        'Groove',
        'Tune',
        'Riff',
        'Vocal',
      ]);
    });

    test('the TRACKER document comes back intact', () {
      // On the document, not the JSON.
      final back = _roundTrip(_everyKind()).track('tracker-1')!;
      final song = back.document as TrackerSong;
      expect(song.rows, 8);
      // Channel-major: cells[channel][row].
      final cells = song.patterns.first.cells;
      expect(cells[0][0].midi, 60);
      expect(cells[0][0].instrument, 1);
      expect(cells[0][0].volume, 48);
      expect(cells[1][4].midi, 67);
      expect(cells[1][4].instrument, 2);
    });

    test('the LOOP document comes back intact', () {
      final back = _roundTrip(_everyKind()).track('loop-1')!;
      final spec = back.document as GrooveSpec;
      expect(spec.cacheKey, _groove().cacheKey);
      expect(spec.pans['bass'], closeTo(-0.5, 0.01));
      expect(spec.filters['bass'], closeTo(-0.4, 0.01));
      expect(spec.trackSteps['drums'], 3);
    });

    test('the SCORE document comes back intact', () {
      final back = _roundTrip(_everyKind()).track('score-1')!;
      final score = back.document as MultiPartScore;
      expect(score.parts.length, 1);
      final notes = [
        for (final e in score.parts.first.measures.first.elements)
          if (e is NoteElement) e.pitches.first.midiNumber,
      ];
      expect(notes, [
        const Pitch(Step.c).midiNumber,
        const Pitch(Step.e).midiNumber,
      ]);
    });

    test('the tempo travels', () {
      expect(_roundTrip(_everyKind()).tempo.changes.first.bpm, 96);
      final varied = Project(
        tempo: TempoMap(const [
          TempoChange(ms: 0, bpm: 100),
          TempoChange(ms: 4000, bpm: 140),
        ]),
      );
      final back = _roundTrip(varied);
      expect(back.tempo.changes.length, 2);
      expect(back.tempo.changes.last.bpm, 140);
    });

    test('the mix travels, and belongs to the TRACK', () {
      // The ladder's warning: mix state must not be inside the documents, or
      // WS-W5 has to unpick it from four places.
      final back = _roundTrip(_everyKind());
      expect(back.track('tracker-1')!.mix.level, closeTo(0.8, 1e-9));
      expect(back.track('tracker-1')!.mix.pan, closeTo(-0.25, 1e-9));
      expect(back.track('score-1')!.mix.muted, isTrue);
      expect(back.track('loop-1')!.mix, const ProjectTrackMix());
    });
  });

  group('a kind with no codec', () {
    test('keeps its track, and says the document is not readable', () {
      final back = _roundTrip(_everyKind());
      final tab = back.track('tab-1')!;
      expect(tab.kind, AppMode.tab);
      expect(tab.name, 'Riff');
      expect(tab.document, isNull);
    });

    test('a caller can tell BEFORE saving that something cannot be written',
        () {
      // The point of the flag: warn while the data still exists, not after.
      final withUnreadable = _roundTrip(
        Project(
          tracks: [
            ProjectTrack(
              id: 'x-1',
              kind: AppMode.tracker,
              unreadable: const {'song': 'not a song'},
            ),
          ],
        ),
      );
      expect(withUnreadable.hasUnreadableTracks, isTrue);
      expect(_roundTrip(_everyKind()).hasUnreadableTracks, isFalse);
    });

    test('registering one makes that kind work, with no change here', () {
      // The registry doing its job: `tab` is not special-cased anywhere, it
      // simply has nothing registered yet.
      registerProjectDocumentCodec(
        ProjectDocumentCodec(
          kind: AppMode.tab,
          encode: (doc) => doc is String ? {'s': doc} : null,
          decode: (json) => json['s'] is String ? json['s'] as String : null,
        ),
      );
      final p = Project(
        tracks: [
          ProjectTrack(id: 'tab-1', kind: AppMode.tab, document: 'EADGBE'),
        ],
      );
      expect(_roundTrip(p).track('tab-1')!.document, 'EADGBE');
    });
  });

  group('an unknown kind is preserved VERBATIM', () {
    // A file from a build that has a mode this one does not.
    const fromTheFuture = '{"v":1,"name":"Newer","tracks":['
        '{"id":"vid-1","kind":"video","name":"Clip",'
        '"mix":{"level":0.5},"doc":{"fps":30,"src":"a.mp4"}},'
        '{"id":"loop-1","kind":"loop","doc":{"groove":{"e":["drums"],"t":100}}}'
        ']}';

    test('the track is kept, not dropped', () {
      final p = projectFromJsonString(fromTheFuture)!;
      expect(p.tracks.length, 2);
      expect(p.tracks.first.id, 'vid-1');
      expect(p.tracks.first.name, 'Clip');
      expect(p.tracks.first.isReadable, isFalse);
      expect(p.hasUnreadableTracks, isTrue);
    });

    test('and writing it back reproduces the file', () {
      // The assertion that matters. An older build must be able to open, save,
      // and hand the file back with the unknown track intact — otherwise the
      // second save is a silent delete.
      final p = projectFromJsonString(fromTheFuture)!;
      final rewritten = projectToJson(p);
      final tracks = rewritten['tracks'] as List;
      expect(tracks.first, {
        'id': 'vid-1',
        'kind': 'video',
        'name': 'Clip',
        'mix': {'level': 0.5},
        'doc': {'fps': 30, 'src': 'a.mp4'},
      });
    });

    test('the tracks it CAN read still work', () {
      final p = projectFromJsonString(fromTheFuture)!;
      final groove = p.track('loop-1')!.document as GrooveSpec;
      expect(groove.enabled, contains('drums'));
      expect(groove.tempoBpm, 100);
    });

    test('a document this build cannot decode is kept too', () {
      // Same rule one level down: the kind is known, the payload is not.
      const stale = '{"v":1,"tracks":['
          '{"id":"t-1","kind":"tracker","doc":{"song":"gibberish"}}]}';
      final p = projectFromJsonString(stale)!;
      expect(p.tracks.single.document, isNull);
      expect(p.tracks.single.isReadable, isFalse);
      expect(
        (projectToJson(p)['tracks'] as List).single,
        {
          'id': 't-1',
          'kind': 'tracker',
          'doc': {'song': 'gibberish'},
        },
      );
    });
  });

  group('it refuses only what is not a project', () {
    test('a wrong shape or an unreadable version is null', () {
      expect(projectFromJson(null), isNull);
      expect(projectFromJson('nope'), isNull);
      expect(projectFromJson(<String, dynamic>{}), isNull);
      expect(projectFromJson({'v': 99, 'tracks': []}), isNull);
      expect(projectFromJsonString('{not json'), isNull);
    });

    test('a malformed TRACK is skipped, the project still opens', () {
      final p = projectFromJson({
        'v': 1,
        'tracks': [
          'not a track',
          {'kind': 'loop'},
          {'id': '', 'kind': 'loop'},
          {'id': 'ok-1', 'kind': 'loop'},
        ],
      })!;
      expect(p.tracks.map((t) => t.id), ['ok-1']);
    });

    test('an absurd mix is clamped rather than trusted', () {
      final p = projectFromJson({
        'v': 1,
        'tracks': [
          {
            'id': 'a',
            'kind': 'loop',
            'mix': {'level': 9.0, 'pan': -8.0},
          },
        ],
      })!;
      expect(p.tracks.single.mix.level, 1.0);
      expect(p.tracks.single.mix.pan, -1.0);
    });
  });

  group('the container stays pure Dart', () {
    // The card specifies "pure Dart, no Flutter", and that is not decoration:
    // it is what lets a CLI, a headless test or a future server hold a project,
    // and it is the reason `AppMode` was moved out of `project_bridge.dart` in
    // the first place. Purity is invisible until it is gone, so it is asserted
    // rather than trusted — one Flutter import anywhere in this chain would
    // otherwise be caught by nothing.
    //
    // `package:crisp_notation/` is named alongside Flutter itself because that
    // barrel DEPENDS on Flutter; the pure half is `crisp_notation_core`, which
    // is what the codec actually imports for MusicXML.
    const pureFiles = [
      'lib/core/project/project.dart',
      'lib/core/project/project_codec.dart',
      'lib/core/interop/app_mode.dart',
    ];

    for (final path in pureFiles) {
      test('$path imports no Flutter', () {
        final source = File(path).readAsStringSync();
        final imports = [
          for (final line in source.split('\n'))
            if (line.trimLeft().startsWith('import ') ||
                line.trimLeft().startsWith('export '))
              line.trim(),
        ];
        for (final line in imports) {
          expect(
            line.contains('package:flutter/') ||
                line.contains('package:crisp_notation/'),
            isFalse,
            reason: '$path pulls in Flutter via: $line',
          );
        }
      });
    }

    test('app_mode.dart has no imports at all', () {
      // The strongest version of the guarantee, for the one file small enough
      // to hold it: a mode is a name, and naming one should cost nothing.
      final source = File('lib/core/interop/app_mode.dart').readAsStringSync();
      expect(source.contains('\nimport '), isFalse);
    });
  });

  group('the container itself', () {
    test('an empty project round-trips and stays small', () {
      final json = projectToJson(Project());
      expect(json.containsKey('name'), isFalse);
      expect(json.containsKey('tempo'), isFalse, reason: 'default tempo');
      expect(_roundTrip(Project()).tracks, isEmpty);
    });

    test('tracks are queryable by id and by kind', () {
      final p = _everyKind();
      expect(p.track('loop-1')!.kind, AppMode.loop);
      expect(p.track('nope'), isNull);
      expect(p.tracksOf(AppMode.tab).single.id, 'tab-1');
      expect(p.tracksOf(AppMode.score).single.id, 'score-1');
    });

    test('a free id never collides', () {
      var p = Project();
      final ids = <String>{};
      for (var i = 0; i < 5; i++) {
        final id = p.freeTrackId(AppMode.loop);
        expect(ids.add(id), isTrue, reason: 'duplicate id $id');
        p = p.withTrack(ProjectTrack(id: id, kind: AppMode.loop));
      }
      expect(p.tracks.length, 5);
    });

    test('add / replace / remove return a NEW project', () {
      final a = Project(
        tracks: [ProjectTrack(id: 'x', kind: AppMode.loop, name: 'one')],
      );
      final b = a.withTrack(ProjectTrack(id: 'y', kind: AppMode.tracker));
      expect(a.tracks.length, 1, reason: 'the original is untouched');
      expect(b.tracks.length, 2);

      final c = b.withTrackReplaced(
        'x',
        ProjectTrack(id: 'x', kind: AppMode.loop, name: 'two'),
      );
      expect(b.track('x')!.name, 'one');
      expect(c.track('x')!.name, 'two');

      expect(c.withoutTrack('x').track('x'), isNull);
      expect(c.withoutTrack('nope').tracks.length, 2);
    });

    test('the track list cannot be mutated behind the project\'s back', () {
      final p = Project(tracks: [ProjectTrack(id: 'x', kind: AppMode.loop)]);
      expect(
        () => p.tracks.add(ProjectTrack(id: 'y', kind: AppMode.loop)),
        throwsUnsupportedError,
      );
    });

    test('replacing a document clears the unreadable copy', () {
      // Otherwise a track could carry a live document AND a stale raw one, and
      // the codec would write the stale one back over the edit.
      final unread = ProjectTrack(
        id: 'x',
        kind: AppMode.tracker,
        unreadable: const {'song': 'gibberish'},
      );
      final fixed = unread.copyWith(document: _song());
      expect(fixed.isReadable, isTrue);
      expect(fixed.unreadable, isNull);
      final json = (projectToJson(Project(tracks: [fixed]))['tracks'] as List)
          .single as Map;
      expect((json['doc'] as Map).containsKey('song'), isTrue);
      expect(json['doc']['song'], isA<Map<String, dynamic>>());
    });
  });
}
