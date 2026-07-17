// lib/core/services/sri_service.dart
//
// Spaced-repetition (SM-2) engine, generalized from the implementation in
// space_math_academy: items are opaque string IDs instead of MathProblem
// objects, so any minigame can feed it.
//
// ID convention: '<moduleId>.<skillId>.<detail>', e.g.
//   'note_reading.treble.g4'
//   'note_values.rest.quarter'
//   'harmony.function.c_major.dominant'
// The first two segments power the per-module/per-skill progress breakdown.

import 'dart:convert';

import 'package:comet_beat/core/tuning.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SM-2 state for one tracked learning item.
class SriItemData {
  final String itemId;
  int successCount;
  int failureCount;
  double easinessFactor;
  int repetitions;
  DateTime nextReviewDate;

  SriItemData({
    required this.itemId,
    this.successCount = 0,
    this.failureCount = 0,
    this.easinessFactor = kSm2InitialEasiness,
    this.repetitions = 0,
    required this.nextReviewDate,
  });

  String get moduleId => itemId.split('.').first;

  String get skillId {
    final parts = itemId.split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  Map<String, dynamic> toJson() => {
        'id': itemId,
        's': successCount,
        'f': failureCount,
        'ef': easinessFactor,
        'r': repetitions,
        'next': nextReviewDate.toIso8601String(),
      };

  factory SriItemData.fromJson(Map<String, dynamic> json) => SriItemData(
        itemId: json['id'] as String,
        successCount: (json['s'] as int?) ?? 0,
        failureCount: (json['f'] as int?) ?? 0,
        easinessFactor:
            ((json['ef'] as num?) ?? kSm2InitialEasiness).toDouble(),
        repetitions: (json['r'] as int?) ?? 0,
        nextReviewDate: DateTime.parse(json['next'] as String),
      );
}

/// Aggregated progress for a module or skill bucket.
class SkillStat {
  final int tracked;
  final int mastered;
  final double averageEasiness;
  double get masteryPercent => tracked > 0 ? mastered / tracked : 0.0;

  const SkillStat({
    this.tracked = 0,
    this.mastered = 0,
    this.averageEasiness = kSm2InitialEasiness,
  });
}

class SriService with ChangeNotifier {
  static const _sriStorageKey = 'sri_database';

  Map<String, SriItemData> _sriDatabase = {};

  /// Injectable clock for deterministic testing. Defaults to [DateTime.now].
  final DateTime Function() getNow;

  final Set<String> _alreadyReturnedThisSession = {};
  DateTime? _sessionStartTime;

  SriService({DateTime Function()? getNow}) : getNow = getNow ?? DateTime.now;

  void _log(String message) {
    if (kDebugMode) debugPrint('[SRI_SERVICE] 🧠 $message');
  }

  void resetSession() {
    _alreadyReturnedThisSession.clear();
    _sessionStartTime = getNow();
    _log('Session reset. Clearing returned items cache.');
  }

  void _checkSessionExpiry() {
    if (_sessionStartTime == null ||
        getNow().difference(_sessionStartTime!).inMinutes > 10) {
      resetSession();
    }
  }

  bool isItemMastered(String itemId) {
    final data = _sriDatabase[itemId];
    if (data == null) return false;
    return data.repetitions >= kSm2MinimumRepetitionsForMastery &&
        data.easinessFactor > kSm2MasteryEasinessThreshold &&
        data.failureCount <= kSm2MaxFailuresForMastery;
  }

  /// SM-2 retention for a namespace: the mean per-item mastery over tracked
  /// items whose id starts with [prefix] — 1.0 for a mastered item, otherwise
  /// its progress toward the mastery repetition count. Null when nothing under
  /// [prefix] has been practised yet, so callers can treat it as "no signal".
  double? masteryUnder(String prefix) {
    final items = _sriDatabase.values.where((d) => d.itemId.startsWith(prefix));
    if (items.isEmpty) return null;
    var total = 0.0;
    var count = 0;
    for (final d in items) {
      count++;
      total += isItemMastered(d.itemId)
          ? 1.0
          : (d.repetitions / kSm2MinimumRepetitionsForMastery).clamp(0.0, 1.0);
    }
    return total / count;
  }

  Future<void> loadSriData() async {
    _log('Loading SRI database from storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_sriStorageKey);
      if (jsonString != null) {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        _sriDatabase = jsonMap.map(
          (key, value) => MapEntry(
            key,
            SriItemData.fromJson(value as Map<String, dynamic>),
          ),
        );
        _log('✅ Loaded ${_sriDatabase.length} SRI records.');
      } else {
        _log('No SRI data found. Starting with a fresh database.');
      }
    } catch (e) {
      _log('❌ Error loading SRI data: $e. Using an empty database.');
      _sriDatabase = {};
    }

    resetSession();
    notifyListeners();
  }

  Future<void> saveSriData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(
        _sriDatabase.map((key, value) => MapEntry(key, value.toJson())),
      );
      await prefs.setString(_sriStorageKey, jsonString);
    } catch (e) {
      _log('❌ Error saving SRI data: $e');
    }
  }

  /// Record a right/wrong response for [itemId] and reschedule it (SM-2).
  void recordResponse(String itemId, bool wasCorrect) {
    _log('Recording response for "$itemId": '
        '${wasCorrect ? "Correct" : "Incorrect"}');

    final data = _sriDatabase[itemId] ??
        SriItemData(itemId: itemId, nextReviewDate: getNow());

    if (wasCorrect) {
      data.successCount++;
    } else {
      data.failureCount++;
    }

    final q = wasCorrect ? 5 : 1;

    if (q < 3) {
      data.repetitions = 0;
    } else {
      data.repetitions++;
    }

    data.easinessFactor =
        data.easinessFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (data.easinessFactor < kSm2MinimumEasiness) {
      data.easinessFactor = kSm2MinimumEasiness;
    }

    int intervalInDays;
    if (data.repetitions <= 1) {
      intervalInDays = 1;
    } else if (data.repetitions == 2) {
      intervalInDays = 6;
    } else {
      intervalInDays = (data.repetitions - 1) * data.easinessFactor.round();
    }

    data.nextReviewDate = getNow().add(Duration(days: intervalInDays));

    _sriDatabase[itemId] = data;
    _log('Updated "$itemId": EF=${data.easinessFactor.toStringAsFixed(2)}, '
        'Reps=${data.repetitions}');

    notifyListeners();
    saveSriData();
  }

  /// IDs due for review, hardest (lowest easiness) first. Items already
  /// handed out this session are excluded; [moduleId] filters to one module.
  List<String> getItemsForReview({
    int limit = 5,
    Set<String>? excludeIds,
    String? moduleId,
    bool resetSessionFirst = false,
  }) {
    if (resetSessionFirst) {
      resetSession();
    } else {
      _checkSessionExpiry();
    }

    final now = getNow();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    final reviewable = _sriDatabase.values
        .where(
          (data) =>
              data.nextReviewDate.isBefore(now) &&
              !allExcluded.contains(data.itemId) &&
              !isItemMastered(data.itemId) &&
              (moduleId == null || data.moduleId == moduleId),
        )
        .toList();

    reviewable.sort((a, b) {
      final efComparison = a.easinessFactor.compareTo(b.easinessFactor);
      if (efComparison != 0) return efComparison;
      return a.nextReviewDate.compareTo(b.nextReviewDate);
    });

    final itemIds = reviewable.map((data) => data.itemId).take(limit).toList();
    _alreadyReturnedThisSession.addAll(itemIds);

    _log('Found ${itemIds.length} items due for review.');
    return itemIds;
  }

  int getAvailableReviewCount({Set<String>? excludeIds, String? moduleId}) {
    _checkSessionExpiry();

    final now = getNow();
    final allExcluded = <String>{
      ..._alreadyReturnedThisSession,
      ...?excludeIds,
    };

    return _sriDatabase.values
        .where(
          (data) =>
              data.nextReviewDate.isBefore(now) &&
              !allExcluded.contains(data.itemId) &&
              !isItemMastered(data.itemId) &&
              (moduleId == null || data.moduleId == moduleId),
        )
        .length;
  }

  // --- Statistics ---

  int get totalTrackedItems => _sriDatabase.length;

  int get masteredItemCount => _sriDatabase.keys.where(isItemMastered).length;

  int get learningItemCount => totalTrackedItems - masteredItemCount;

  /// Progress aggregated by module, then by skill (from the ID convention).
  Map<String, Map<String, SkillStat>> getDetailedBreakdown() {
    final buckets = <String, Map<String, List<SriItemData>>>{};
    for (final data in _sriDatabase.values) {
      buckets
          .putIfAbsent(data.moduleId, () => {})
          .putIfAbsent(data.skillId, () => [])
          .add(data);
    }

    return buckets.map((moduleId, skills) {
      return MapEntry(
        moduleId,
        skills.map((skillId, items) {
          final mastered = items.where((d) => isItemMastered(d.itemId)).length;
          final totalEf =
              items.fold<double>(0, (sum, d) => sum + d.easinessFactor);
          return MapEntry(
            skillId,
            SkillStat(
              tracked: items.length,
              mastered: mastered,
              averageEasiness: items.isNotEmpty
                  ? totalEf / items.length
                  : kSm2InitialEasiness,
            ),
          );
        }),
      );
    });
  }

  List<SriItemData> getMostDifficultItems({int limit = 5}) {
    final items = _sriDatabase.values.toList()
      ..sort((a, b) => a.easinessFactor.compareTo(b.easinessFactor));
    return items.take(limit).toList();
  }

  /// The learner's "tricky notes": items they have actually missed and not yet
  /// mastered, hardest first (most misses, then lowest easiness). SM-2 already
  /// re-drills these in review; this surfaces them so the child sees them.
  List<SriItemData> weakestItems({int limit = 5}) {
    final struggled = _sriDatabase.values
        .where((d) => d.failureCount > 0 && !isItemMastered(d.itemId))
        .toList()
      ..sort((a, b) {
        final byFails = b.failureCount.compareTo(a.failureCount);
        if (byFails != 0) return byFails;
        return a.easinessFactor.compareTo(b.easinessFactor);
      });
    return struggled.take(limit).toList();
  }

  // ============== Karteikasten (Leitner-style) projection ==============
  //
  // Maps the SM-2 state onto 5 boxes for a flashcard-box UI, identical to
  // the projection in space_math_academy. 1 = Neu, 5 = Gemeistert.

  int getBoxFor(SriItemData d) {
    if (isItemMastered(d.itemId)) return 5;
    if (d.repetitions == 0) return 1;
    if (d.repetitions == 1) return 2;
    if (d.repetitions == 2) return 3;
    return 4;
  }

  List<SriItemData> getItemsInBox(int box) {
    return _sriDatabase.values.where((d) => getBoxFor(d) == box).toList();
  }

  Map<int, int> getBoxCounts() {
    final counts = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
    for (final d in _sriDatabase.values) {
      final b = getBoxFor(d);
      counts[b] = (counts[b] ?? 0) + 1;
    }
    return counts;
  }
}
