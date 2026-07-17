// Defensive JSON deserialization for the persisted models. ProgressService.load
// round-trips a complete map end-to-end, but the `?? default` fallbacks in
// SriItemData.fromJson / GameProgress.fromJson (for partial or legacy stored
// data) had no direct assertion — a regression there would silently reset a
// child's progress instead of throwing.

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/tuning.dart' show kSm2InitialEasiness;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SriItemData.fromJson', () {
    test('fills defaults for missing count/easiness/repetition keys', () {
      final item = SriItemData.fromJson({
        'id': 'reading.clef',
        'next': DateTime(2026).toIso8601String(),
      });
      expect(item.itemId, 'reading.clef');
      expect(item.successCount, 0);
      expect(item.failureCount, 0);
      expect(item.repetitions, 0);
      expect(item.easinessFactor, kSm2InitialEasiness);
      expect(item.nextReviewDate, DateTime(2026));
    });

    test('round-trips values through toJson', () {
      final original = SriItemData(
        itemId: 'x.y',
        successCount: 4,
        failureCount: 2,
        easinessFactor: 2.36,
        repetitions: 5,
        nextReviewDate: DateTime(2026, 7, 17, 9, 30),
      );
      final restored = SriItemData.fromJson(original.toJson());
      expect(restored.itemId, original.itemId);
      expect(restored.successCount, original.successCount);
      expect(restored.failureCount, original.failureCount);
      expect(restored.easinessFactor, closeTo(original.easinessFactor, 1e-9));
      expect(restored.repetitions, original.repetitions);
      expect(restored.nextReviewDate, original.nextReviewDate);
    });
  });

  group('GameProgress.fromJson', () {
    test('fills all defaults for an empty map', () {
      final p = GameProgress.fromJson(const {});
      expect(p.bestStars, 0);
      expect(p.bestScore, 0);
      expect(p.plays, 0);
      expect(p.bestTimeMs, 0);
    });

    test('round-trips values through toJson', () {
      const original = GameProgress(
        bestStars: 3,
        bestScore: 900,
        plays: 7,
        bestTimeMs: 12345,
      );
      final restored = GameProgress.fromJson(original.toJson());
      expect(restored.bestStars, 3);
      expect(restored.bestScore, 900);
      expect(restored.plays, 7);
      expect(restored.bestTimeMs, 12345);
    });
  });
}
