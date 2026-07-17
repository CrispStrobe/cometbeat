import 'package:comet_beat/core/services/progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records results, keeps the best, counts plays, persists', () async {
    final progress = ProgressService();
    await progress.load();

    expect(progress.starsFor('note_value_quiz'), 0);

    progress.recordResult('note_value_quiz', score: 700, stars: 2);
    progress.recordResult('note_value_quiz', score: 500, stars: 1);
    progress.recordResult('scale_builder', score: 600, stars: 3);

    final p = progress.progressFor('note_value_quiz');
    expect(p.bestStars, 2); // the later, worse run doesn't downgrade
    expect(p.bestScore, 700);
    expect(p.plays, 2);
    expect(progress.totalStars, 5);

    // Allow the async save to land, then reload from storage.
    await Future<void>.delayed(Duration.zero);
    final reloaded = ProgressService();
    await reloaded.load();
    expect(reloaded.starsFor('note_value_quiz'), 2);
    expect(reloaded.starsFor('scale_builder'), 3);
    expect(reloaded.progressFor('scale_builder').plays, 1);
  });
}
