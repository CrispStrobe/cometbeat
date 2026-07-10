import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late SriService sri;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 7, 10);
    sri = SriService(getNow: () => now);
  });

  test('correct answers grow the review interval (SM-2)', () {
    const id = 'note_reading.treble.g4';

    sri.recordResponse(id, true);
    now = now.add(const Duration(days: 2));
    expect(sri.getItemsForReview(resetSessionFirst: true), contains(id));

    sri.recordResponse(id, true); // repetitions = 2 -> 6 days
    now = now.add(const Duration(days: 2));
    expect(sri.getItemsForReview(resetSessionFirst: true), isNot(contains(id)));

    now = now.add(const Duration(days: 5));
    expect(sri.getItemsForReview(resetSessionFirst: true), contains(id));
  });

  test('a failure resets repetitions and schedules for tomorrow', () {
    const id = 'note_values.rest.quarter';

    sri.recordResponse(id, true);
    sri.recordResponse(id, true);
    sri.recordResponse(id, false);

    now = now.add(const Duration(days: 2));
    final due = sri.getItemsForReview(resetSessionFirst: true);
    expect(due, contains(id));
  });

  test('items become mastered and drop out of review', () {
    const id = 'scales.major.c';

    // EF grows +0.1 per correct answer from 2.5; mastery needs EF > 4.0.
    for (var i = 0; i < 16; i++) {
      sri.recordResponse(id, true);
      now = now.add(const Duration(days: 60));
    }

    expect(sri.isItemMastered(id), isTrue);
    expect(sri.getItemsForReview(resetSessionFirst: true), isNot(contains(id)));
    expect(sri.masteredItemCount, 1);
  });

  test('breakdown buckets by module and skill from the ID convention', () {
    sri.recordResponse('note_reading.treble.g4', true);
    sri.recordResponse('note_reading.treble.a4', false);
    sri.recordResponse('note_reading.bass.f3', true);
    sri.recordResponse('harmony.function.c_major.dominant', true);

    final breakdown = sri.getDetailedBreakdown();
    expect(breakdown['note_reading']!['treble']!.tracked, 2);
    expect(breakdown['note_reading']!['bass']!.tracked, 1);
    expect(breakdown['harmony']!['function']!.tracked, 1);
  });

  test('session cache does not return the same item twice', () {
    const id = 'measures.fill.4_4';
    sri.recordResponse(id, false);
    now = now.add(const Duration(days: 2));

    expect(sri.getItemsForReview(), contains(id));
    expect(sri.getItemsForReview(), isNot(contains(id)));
  });

  test('Karteikasten box projection covers new to mastered', () {
    sri.recordResponse('chords.triad.c_major', false); // box 1 (reps reset)
    expect(sri.getBoxCounts()[1], 1);

    for (var i = 0; i < 16; i++) {
      sri.recordResponse('scales.major.g', true);
      now = now.add(const Duration(days: 60));
    }
    expect(sri.getBoxCounts()[5], 1);
  });
}
