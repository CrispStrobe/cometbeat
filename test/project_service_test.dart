// WS-W1b — the service that makes `Project` reachable.
//
// The point of this slice is that WS-W1's container was inert: nothing in the
// app ever constructed a Project, and `registerTabProjectCodec()` — whose own
// comment says "call once at start-up" — was never called. So the tests that
// matter most here are the reachability ones at the bottom, not the CRUD.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/features/games/composition/tab_document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ownership and mutation', () {
    test('starts with an empty, named project', () {
      final service = ProjectService();
      expect(service.tracks, isEmpty);
      expect(service.name, 'Untitled');
    });

    test('addTrack returns the id the caller needs immediately', () {
      final service = ProjectService();
      final id = service.addTrack(kind: AppMode.tracker, document: null);
      expect(id, isNotEmpty);
      expect(service.track(id), isNotNull);
      expect(service.track(id)!.kind, AppMode.tracker);
    });

    test('ids do not collide across kinds or repeats', () {
      final service = ProjectService();
      final ids = {
        for (var i = 0; i < 3; i++)
          service.addTrack(kind: AppMode.loop, document: null),
        service.addTrack(kind: AppMode.tracker, document: null),
      };
      expect(ids.length, 4);
    });

    test('tracksOf filters by kind', () {
      final service = ProjectService()
        ..addTrack(kind: AppMode.loop, document: null)
        ..addTrack(kind: AppMode.tracker, document: null)
        ..addTrack(kind: AppMode.loop, document: null);
      expect(service.tracksOf(AppMode.loop).length, 2);
      expect(service.tracksOf(AppMode.score), isEmpty);
    });

    test('updateDocument keeps id, name and MIX — the WS-X1 seam', () {
      // A live link that reset the level and pan on return would be worse than
      // the copy it replaces, so this is the assertion that matters.
      final service = ProjectService();
      final id = service.addTrack(
        kind: AppMode.tracker,
        document: 'before',
        name: 'Drums',
      );
      service.updateTrack(
        id,
        service.track(id)!.copyWith(
              mix: const ProjectTrackMix(level: 0.3, pan: -0.5, muted: true),
            ),
      );

      expect(service.updateDocument(id, 'after'), isTrue);
      final track = service.track(id)!;
      expect(track.document, 'after');
      expect(track.name, 'Drums');
      expect(track.mix.level, 0.3);
      expect(track.mix.pan, -0.5);
      expect(track.mix.muted, isTrue);
    });

    test('updateDocument CAN clear a document', () {
      // `ProjectTrack.copyWith` resolves `document ?? this.document` and so
      // cannot clear one; the service builds the track directly for exactly
      // this case, and this test is what stops someone "simplifying" it back.
      final service = ProjectService();
      final id = service.addTrack(kind: AppMode.loop, document: 'something');
      expect(service.updateDocument(id, null), isTrue);
      expect(service.track(id)!.document, isNull);
    });

    test('mutating an unknown id reports false and changes nothing', () {
      final service = ProjectService()
        ..addTrack(kind: AppMode.loop, document: null);
      expect(service.updateDocument('nope', 'x'), isFalse);
      expect(service.removeTrack('nope'), isFalse);
      expect(service.tracks.length, 1);
    });

    test('removeTrack removes exactly one', () {
      final service = ProjectService();
      final keep = service.addTrack(kind: AppMode.loop, document: null);
      final drop = service.addTrack(kind: AppMode.loop, document: null);
      expect(service.removeTrack(drop), isTrue);
      expect(service.tracks.map((t) => t.id), [keep]);
    });

    test('every real change notifies; a no-op does not', () {
      final service = ProjectService();
      var notifications = 0;
      service.addListener(() => notifications++);

      service.addTrack(kind: AppMode.loop, document: null);
      expect(notifications, 1);

      service.rename('Untitled');
      expect(notifications, 1, reason: 'already the name');

      service.rename('Song');
      expect(notifications, 2);

      service.removeTrack('nope');
      expect(notifications, 2, reason: 'nothing was removed');
    });
  });

  group('persistence', () {
    test('a bad file leaves the open project alone', () {
      // Losing the open project to a bad file would be the worst possible
      // response to one.
      final service = ProjectService();
      final id = service.addTrack(kind: AppMode.loop, document: null);
      expect(service.loadJsonString('not json at all'), isFalse);
      expect(service.track(id), isNotNull);
    });

    test('round-trips through JSON', () {
      final service = ProjectService()..rename('Song');
      service.addTrack(kind: AppMode.tracker, document: null, name: 'Lead');

      final reopened = ProjectService();
      expect(reopened.loadJsonString(service.toJsonString()), isTrue);
      expect(reopened.name, 'Song');
      expect(reopened.tracks.single.name, 'Lead');
      expect(reopened.tracks.single.kind, AppMode.tracker);
    });
  });

  group('reachability — the whole point of this slice', () {
    setUp(resetProjectDocumentCodecs);

    test('the three pure kinds have codecs out of the box', () {
      for (final kind in [AppMode.tracker, AppMode.loop, AppMode.score]) {
        expect(
          projectDocumentCodecFor(kind),
          isNotNull,
          reason: '$kind should be readable without any registration',
        );
      }
    });

    test('tab has NO codec until it is registered — the bug this fixes', () {
      // `registerTabProjectCodec()` documents "call once at start-up" and was
      // never called, so a tab track was carried as `unreadable` despite a
      // working codec existing. main() now calls it; this pins both halves.
      expect(projectDocumentCodecFor(AppMode.tab), isNull);
      registerTabProjectCodec();
      expect(projectDocumentCodecFor(AppMode.tab), isNotNull);
    });
  });
}
