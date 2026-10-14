// Learner profiles + progress backup: each learner has their own stars and
// review data, an existing install becomes the default learner untouched, and
// a backup restores as a new learner.
import 'dart:convert';

import 'package:comet_beat/core/services/learner_scope.dart';
import 'package:comet_beat/core/services/profile_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/project_store.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App {
  _App() {
    profiles
      ..addReloader(sri.loadSriData)
      ..addReloader(progress.load);
  }

  final profiles = ProfileService();
  final sri = SriService();
  final progress = ProgressService();

  Future<void> start() async {
    await profiles.load();
    await sri.loadSriData();
    await progress.load();
  }
}

/// Lets the stores' fire-and-forget saves land.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setLearnerScope(kDefaultLearnerId);
  });
  tearDown(() => setLearnerScope(kDefaultLearnerId));

  test('an install from before profiles is the default learner, as it was',
      () async {
    SharedPreferences.setMockInitialValues({
      'game_progress': json.encode({
        'note_value_quiz': {'stars': 3, 'score': 300, 'plays': 1},
      }),
    });
    final app = _App();
    await app.start();
    expect(app.profiles.profiles, hasLength(1));
    expect(app.profiles.active.id, kDefaultLearnerId);
    expect(app.progress.progressFor('note_value_quiz').plays, greaterThan(0));
  });

  test('each learner has their own stars and review items', () async {
    final app = _App();
    await app.start();
    app.progress.recordResult('note_value_quiz', score: 300, stars: 3);
    app.sri.recordResponse('note_values.symbol.whole_note', true);
    await _settle();

    final mia = await app.profiles.add('Mia');
    expect(app.profiles.active.id, mia.id);
    expect(app.progress.starsFor('note_value_quiz'), 0);
    expect(app.sri.totalTrackedItems, 0);

    app.progress.recordResult('beat_sort', score: 100, stars: 1);
    await _settle();

    await app.profiles.switchTo(kDefaultLearnerId);
    expect(app.progress.starsFor('note_value_quiz'), 3);
    expect(app.progress.starsFor('beat_sort'), 0);
    expect(app.sri.totalTrackedItems, 1);

    await app.profiles.switchTo(mia.id);
    expect(app.progress.starsFor('beat_sort'), 1);
  });

  test('the active learner survives a restart', () async {
    final app = _App();
    await app.start();
    final mia = await app.profiles.add('Mia');
    app.progress.recordResult('beat_sort', score: 100, stars: 2);
    await _settle();

    final again = _App();
    await again.start();
    expect(again.profiles.active.id, mia.id);
    expect(again.profiles.active.name, 'Mia');
    expect(again.progress.starsFor('beat_sort'), 2);
  });

  test('deleting a learner removes their data and falls back to the default',
      () async {
    final app = _App();
    await app.start();
    final mia = await app.profiles.add('Mia');
    app.progress.recordResult('beat_sort', score: 100, stars: 2);
    await _settle();

    expect(app.profiles.canDelete(kDefaultLearnerId), isFalse);
    await app.profiles.delete(mia.id);
    expect(app.profiles.profiles, hasLength(1));
    expect(app.profiles.active.id, kDefaultLearnerId);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('p.${mia.id}.')), isEmpty);
  });

  test('a backup restores as a new learner with the same progress', () async {
    final app = _App();
    await app.start();
    app.progress.recordResult('note_value_quiz', score: 300, stars: 3);
    app.sri.recordResponse('note_values.symbol.whole_note', true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_seen_note_value_quiz', true);
    await _settle();

    final document = await app.profiles.exportActive(displayName: 'Player 1');
    final decoded = json.decode(document) as Map<String, dynamic>;
    expect(decoded['format'], ProfileService.backupFormat);
    expect(decoded['name'], 'Player 1');

    // Onto a different, empty device.
    SharedPreferences.setMockInitialValues({});
    setLearnerScope(kDefaultLearnerId);
    final other = _App();
    await other.start();
    final restored = await other.profiles.importAsNew(document);

    expect(other.profiles.profiles, hasLength(2));
    expect(other.profiles.active.id, restored.id);
    expect(restored.name, 'Player 1');
    expect(other.progress.starsFor('note_value_quiz'), 3);
    expect(other.sri.totalTrackedItems, 1);
    final otherPrefs = await SharedPreferences.getInstance();
    expect(
      otherPrefs.getBool(learnerKey('tutorial_seen_note_value_quiz')),
      isTrue,
    );
    // Nothing of the device's own default learner was touched.
    await other.profiles.switchTo(kDefaultLearnerId);
    expect(other.progress.starsFor('note_value_quiz'), 0);
  });

  test('imported songs belong to the learner, and travel in the backup',
      () async {
    final profiles = ProfileService();
    final songs = UserSongsService();
    profiles.addReloader(songs.load);
    await profiles.load();
    await songs.load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_songs', json.encode({'songs': [], 'x': 1}));
    final document = await profiles.exportActive();
    expect(
      (json.decode(document) as Map)['data']['songs'],
      containsPair('x', 1),
    );

    await profiles.add('Mia');
    expect(prefs.getString(learnerKey('user_songs')), isNull);
    expect(songs.songs, isEmpty);

    final restored = await profiles.importAsNew(document);
    expect(
      json.decode(prefs.getString(learnerKeyFor(restored.id, 'user_songs'))!),
      containsPair('x', 1),
    );
  });

  test('saved projects belong to the learner, and travel in the backup',
      () async {
    final profiles = ProfileService();
    await profiles.load();
    final prefs = await SharedPreferences.getInstance();
    final store = ProjectStore(prefs);
    // Saved before profiles existed: the default learner's, untouched.
    await prefs.setString(
      'projects_v1',
      json.encode([
        {'name': 'Old song', 'at': 1, 'p': '{}'},
      ]),
    );
    expect(store.list().single.name, 'Old song');
    final document = await profiles.exportActive();

    await profiles.add('Mia');
    expect(store.list(), isEmpty, reason: 'a new learner starts empty');

    final restored = await profiles.importAsNew(document);
    expect(profiles.active.id, restored.id);
    expect(store.list().single.name, 'Old song');
    await profiles.switchTo(kDefaultLearnerId);
    expect(store.list().single.name, 'Old song');
  });

  test('a file that is not a backup is refused and writes nothing', () async {
    final app = _App();
    await app.start();
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getKeys().toSet();
    for (final bad in [
      'not json at all',
      '[]',
      '{"format":"something-else","version":1,"data":{}}',
      '{"format":"cometbeat-learner","version":99,"data":{}}',
      '{"format":"cometbeat-learner","version":1,"data":{"sri":[],'
          '"progress":{},"practiceDays":[],"tutorialsSeen":[]}}',
    ]) {
      await expectLater(
        app.profiles.importAsNew(bad),
        throwsFormatException,
        reason: bad,
      );
    }
    expect(app.profiles.profiles, hasLength(1));
    expect(prefs.getKeys().toSet(), before);
  });
}
