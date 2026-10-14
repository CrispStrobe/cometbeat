// The review router: every skill that records spaced-repetition items can be
// reviewed — re-asked item by item where a quiz supports it, otherwise by a
// round of the game that drills it.
import 'dart:io';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/review/review_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An SRI service whose [ids] were all answered wrong and have come due.
SriService _due(List<String> ids) {
  var now = DateTime(2026, 1, 15);
  final sri = SriService(getNow: () => now);
  for (final id in ids) {
    sri.recordResponse(id, false);
  }
  now = DateTime(2026, 3, 15);
  return sri;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every fallback route names a registered game', () {
    for (final entry in kReviewGameBySkill.entries) {
      expect(
        gameInfoById(entry.value),
        isNotNull,
        reason: '${entry.key} → ${entry.value} is not in the registry',
      );
    }
  });

  test('every SRI namespace a game records under has a review route', () {
    // Scan the game sources for '<module>.<skill>.' item-id literals. A game
    // added under a new namespace must be routed, or its due items would be
    // counted on the home button and never offered.
    final modules = kGamesByModule.keys.toSet()..addAll(['key_sig']);
    final literal = RegExp(r"'([a-z_]+)\.([a-z_0-9]+)\.");
    final unrouted = <String>{};
    for (final file in Directory('lib/features/games')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m in literal.allMatches(file.readAsStringSync())) {
        if (!modules.contains(m[1])) continue;
        // A stand-in detail segment: only the namespace is under test.
        final id = '${m[1]}.${m[2]}.x';
        if (reviewPrefixFor(id) == null) unrouted.add('${m[1]}.${m[2]}.');
      }
    }
    expect(unrouted, isEmpty);
  });

  test('the longest prefix claims an item', () {
    expect(reviewPrefixFor('note_reading.treble.c4'), 'note_reading.treble.');
    expect(
      reviewPrefixFor('note_reading.place_treble.c'),
      'note_reading.place_treble.',
    );
    expect(reviewPrefixFor('key_sig.g'), 'key_sig.');
    expect(reviewPrefixFor('nonsense.thing.x'), isNull);
  });

  test('time signatures, key names and key signatures re-ask their items', () {
    for (final (id, prefix) in [
      ('measures.timesig.3_4', 'measures.timesig.'),
      ('keyboard.name.c', 'keyboard.name.'),
      ('key_sig.g', 'key_sig.'),
      ('measures.meter.3_4', 'measures.meter.'),
      ('keyboard.find.c4', 'keyboard.find.'),
      ('note_values.rhythm.p2', 'note_values.rhythm.'),
    ]) {
      final plan = planReview(_due([id]))!;
      expect(plan.prefix, prefix);
      expect(plan.dedicated, isTrue, reason: id);
    }
  });

  test('nothing due → no plan', () {
    expect(planReview(SriService(getNow: () => DateTime(2026))), isNull);
  });

  test('the biggest bucket wins, and a quiz re-asks its exact items', () {
    final sri = _due([
      'note_values.symbol.whole_note',
      'note_values.symbol.half_note',
      'note_values.symbol.quarter_note',
      'measures.upbeat.a',
    ]);
    final plan = planReview(sri)!;
    expect(plan.prefix, 'note_values.symbol.');
    expect(plan.dedicated, isTrue);
    expect(plan.itemIds, hasLength(3));
  });

  test('a skill with no quiz runner opens its game, then rotates on', () {
    final sri = _due([
      'measures.upbeat.a',
      'measures.upbeat.b',
      'guitar.capo.c',
    ]);
    final first = planReview(sri)!;
    expect(first.dedicated, isFalse);
    expect(first.game!.id, 'spot_upbeat');
    expect(sri.getAvailableReviewCount(), 3);

    // Opening it hands the bucket out: the count drops and the next review is
    // a different skill, not the same game again.
    first.open(sri);
    expect(sri.getAvailableReviewCount(), 1);
    final second = planReview(sri)!;
    expect(second.game!.id, 'capo_match');

    second.open(sri);
    expect(planReview(sri), isNull);
  });

  test('planning is a read: it hands nothing out', () {
    final sri = _due(['measures.upbeat.a']);
    planReview(sri);
    planReview(sri);
    expect(sri.handedOutThisSession, isEmpty);
    expect(sri.getAvailableReviewCount(), 1);
  });
}
