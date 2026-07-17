// Additional SRI engine coverage: session expiry, statistics ordering,
// breakdown math.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late SriService sri;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 7, 11, 9);
    sri = SriService(getNow: () => now);
  });

  test('session cache expires after 10 minutes', () {
    const id = 'note_values.symbol.half_note';
    sri.recordResponse(id, false);
    now = now.add(const Duration(days: 2));

    // First fetch hands the item out and caches it for the session.
    expect(sri.getItemsForReview(), contains(id));
    expect(sri.getItemsForReview(), isNot(contains(id)));

    // 11 minutes later the session has expired; the item is offered again.
    now = now.add(const Duration(minutes: 11));
    expect(sri.getItemsForReview(), contains(id));
  });

  test('review queue is ordered hardest (lowest easiness) first', () {
    // 'hard' fails three times, 'easy' once — hard has lower easiness.
    for (var i = 0; i < 3; i++) {
      sri.recordResponse('scales.spot.c_major', false);
    }
    sri.recordResponse('scales.spot.g_major', false);
    now = now.add(const Duration(days: 2));

    final due = sri.getItemsForReview(resetSessionFirst: true);
    expect(due.first, 'scales.spot.c_major');

    final difficult = sri.getMostDifficultItems(limit: 2);
    expect(difficult.first.itemId, 'scales.spot.c_major');
    expect(
      difficult.first.easinessFactor,
      lessThan(difficult.last.easinessFactor),
    );
  });

  test('breakdown averages easiness within a skill bucket', () {
    sri.recordResponse('chords.triad.c_major', true); // EF 2.6
    sri.recordResponse('chords.triad.g_major', false); // EF 1.96

    final stat = sri.getDetailedBreakdown()['chords']!['triad']!;
    expect(stat.tracked, 2);
    expect(stat.mastered, 0);
    expect(stat.averageEasiness, closeTo((2.6 + 1.96) / 2, 0.001));
    expect(stat.masteryPercent, 0.0);
  });

  test('module filter isolates review counts', () {
    sri.recordResponse('keyboard.find.g4', false);
    sri.recordResponse('cello.string.d3', false);
    now = now.add(const Duration(days: 2));

    expect(sri.getAvailableReviewCount(moduleId: 'keyboard'), 1);
    expect(sri.getAvailableReviewCount(moduleId: 'cello'), 1);
    expect(sri.getAvailableReviewCount(moduleId: 'harmony'), 0);
    expect(sri.getAvailableReviewCount(), 2);
  });
}
