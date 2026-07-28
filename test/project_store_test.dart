// WS-W6 slice 1 — a project that survives the app closing.
//
// `ProjectService` (WS-W1b) could turn the app's project into a string and back
// since the day it landed, and nothing ever called either method — so closing
// the app lost the project. That is the inert-container pattern W1b itself
// described one level down, repeated one level up, and it is what these tests
// are really about: not "the codec works" (that is `project_codec_test`) but
// "the thing a player made is still there tomorrow".
//
// The failure modes worth pinning are the quiet ones. A store that throws on a
// corrupt entry takes the app down at start-up; a rename that silently
// overwrites another save loses work that is only missed much later; a cap that
// drops the NEWEST entry rather than the oldest throws away the thing the
// player just did.

import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Project _project({String name = 'Song', String trackId = 'loop-1'}) => Project(
      name: name,
      tracks: [
        ProjectTrack(
          id: trackId,
          kind: AppMode.loop,
          name: 'Groove',
          document: const GrooveSpec(enabled: {'drums', 'bass'}, tempoBpm: 96),
          mix: const ProjectTrackMix(level: 0.7, pan: -0.3),
        ),
      ],
    );

Future<ProjectStore> _store() async =>
    ProjectStore(await SharedPreferences.getInstance());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a project comes back', () {
    test('saved, then opened, with its tracks intact', () async {
      final store = await _store();
      await store.save('My song', _project());

      final back = store.open('My song')!;
      expect(back.name, 'Song');
      expect(back.tracks.single.id, 'loop-1');
      expect(back.tracks.single.name, 'Groove');
      final groove = back.tracks.single.document! as GrooveSpec;
      expect(groove.tempoBpm, 96);
      expect(groove.enabled, containsAll(['drums', 'bass']));
      expect(back.tracks.single.mix.level, closeTo(0.7, 1e-9));
    });

    test('a fresh store is empty rather than broken', () async {
      final store = await _store();
      expect(store.list(), isEmpty);
      expect(store.open('nothing'), isNull);
      expect(store.find('nothing'), isNull);
    });

    test('the list is newest first', () async {
      final store = await _store();
      await store.save('old', _project(), nowMs: 1000);
      await store.save('new', _project(), nowMs: 3000);
      await store.save('middle', _project(), nowMs: 2000);
      expect(store.list().map((s) => s.name), ['new', 'middle', 'old']);
    });

    test('saving the same name REPLACES rather than duplicating', () async {
      // A project is one document; two entries with one name is a list the
      // player cannot reason about.
      final store = await _store();
      await store.save('Song', _project(name: 'first'), nowMs: 1000);
      await store.save('Song', _project(name: 'second'), nowMs: 2000);
      expect(store.list(), hasLength(1));
      expect(store.open('Song')!.name, 'second');
    });

    test('a blank name saves nothing', () async {
      final store = await _store();
      await store.save('   ', _project());
      expect(store.list(), isEmpty);
    });

    test('names are trimmed, so "Song" and "Song " are one entry', () async {
      final store = await _store();
      await store.save('Song', _project(), nowMs: 1000);
      await store.save(' Song ', _project(), nowMs: 2000);
      expect(store.list(), hasLength(1));
    });
  });

  group('deleting and renaming', () {
    test('delete removes exactly one', () async {
      final store = await _store();
      await store.save('a', _project());
      await store.save('b', _project());
      await store.delete('a');
      expect(store.list().map((s) => s.name), ['b']);
      await store.delete('nothing there');
      expect(store.list(), hasLength(1));
    });

    test('rename keeps the project and its saved-at time', () async {
      final store = await _store();
      await store.save('before', _project(), nowMs: 4242);
      expect(await store.rename('before', 'after'), isTrue);
      expect(store.find('before'), isNull);
      expect(store.find('after')!.savedAtMs, 4242);
      expect(store.open('after')!.tracks.single.id, 'loop-1');
    });

    test('rename REFUSES to overwrite another save', () async {
      // Silently replacing somebody else's project because two names collided
      // is data loss that is only noticed much later.
      final store = await _store();
      await store.save('keep', _project(name: 'keep me'));
      await store.save('other', _project(name: 'other one'));
      expect(await store.rename('other', 'keep'), isFalse);
      expect(store.open('keep')!.name, 'keep me');
      expect(store.find('other'), isNotNull);
    });

    test('rename refuses a blank, a no-op, or a missing source', () async {
      final store = await _store();
      await store.save('a', _project());
      expect(await store.rename('a', '   '), isFalse);
      expect(await store.rename('a', 'a'), isFalse);
      expect(await store.rename('missing', 'b'), isFalse);
      expect(store.list().map((s) => s.name), ['a']);
    });
  });

  group('it degrades instead of throwing', () {
    test('a corrupt store reads as empty, it does not take the app down',
        () async {
      SharedPreferences.setMockInitialValues({
        'projects_v1': 'not json at all',
      });
      final store = await _store();
      expect(store.list(), isEmpty);
      // And it is still writable — the bad value is simply replaced.
      await store.save('fresh', _project());
      expect(store.list(), hasLength(1));
    });

    test('one unreadable entry does not cost the others', () async {
      SharedPreferences.setMockInitialValues({
        'projects_v1':
            '[{"name":"good","at":2,"p":"{\\"v\\":1,\\"tracks\\":[]}"},'
                '{"nonsense":true},'
                '"a string where an object should be"]',
      });
      final store = await _store();
      expect(store.list().map((s) => s.name), ['good']);
    });

    test('an entry this build cannot decode lists but opens as null', () async {
      // Listing has to stay cheap and total; only OPENING decodes, so a
      // project from a newer build is visible and simply will not open.
      SharedPreferences.setMockInitialValues({
        'projects_v1': '[{"name":"future","at":1,"p":"{\\"v\\":999}"}]',
      });
      final store = await _store();
      expect(store.list().single.name, 'future');
      expect(store.open('future'), isNull);
    });
  });

  test('the cap drops the OLDEST, never what was just saved', () async {
    final store = await _store();
    for (var i = 0; i < ProjectStore.maxProjects + 5; i++) {
      await store.save('p$i', _project(), nowMs: 1000 + i);
    }
    final names = store.list().map((s) => s.name).toList();
    expect(names, hasLength(ProjectStore.maxProjects));
    expect(
      names.first,
      'p${ProjectStore.maxProjects + 4}',
      reason: 'the newest survives',
    );
    expect(names, isNot(contains('p0')), reason: 'the oldest went');
  });
}
