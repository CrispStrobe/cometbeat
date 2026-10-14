// lib/core/services/progress_service.dart
//
// Per-game progression, persisted in SharedPreferences: best stars, best
// score, play count. Drives the stars shown on game tiles and the
// star-based difficulty scaling inside games (docs/PLAN.md).

import 'dart:convert';

import 'package:comet_beat/core/services/learner_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameProgress {
  final int bestStars; // 0..3
  final int bestScore;
  final int plays;
  final int bestTimeMs; // fastest completion, 0 = never timed

  const GameProgress({
    this.bestStars = 0,
    this.bestScore = 0,
    this.plays = 0,
    this.bestTimeMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'stars': bestStars,
        'score': bestScore,
        'plays': plays,
        'time': bestTimeMs,
      };

  factory GameProgress.fromJson(Map<String, dynamic> json) => GameProgress(
        bestStars: (json['stars'] as int?) ?? 0,
        bestScore: (json['score'] as int?) ?? 0,
        plays: (json['plays'] as int?) ?? 0,
        bestTimeMs: (json['time'] as int?) ?? 0,
      );
}

class ProgressService with ChangeNotifier {
  ProgressService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _storageKey = 'game_progress';
  static const _daysKey = 'practice_days';

  /// Clock, injectable for tests.
  final DateTime Function() _now;

  Map<String, GameProgress> _byGame = {};

  /// Days on which at least one game was finished, as `YYYY-MM-DD` keys.
  Set<String> _practiceDays = {};

  Future<void> _lastSave = Future<void>.value();

  // The most recently recorded timed run, for the result screen.
  int _lastElapsedMs = 0;
  int _lastBestMs = 0;
  bool _lastWasBest = false;

  /// This run's completion time in ms (0 if the last game wasn't timed).
  int get lastElapsedMs => _lastElapsedMs;

  /// Best time for the game just finished, in ms.
  int get lastBestMs => _lastBestMs;

  /// Whether the run just finished set a new personal best.
  bool get lastWasBest => _lastWasBest;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Start from empty every time: a load also runs on a learner switch, and
      // a learner with nothing stored must not inherit the previous one's.
      final jsonString = prefs.getString(learnerKey(_storageKey));
      final jsonMap = jsonString == null
          ? const <String, dynamic>{}
          : json.decode(jsonString) as Map<String, dynamic>;
      _byGame = jsonMap.map(
        (key, value) => MapEntry(
          key,
          GameProgress.fromJson(value as Map<String, dynamic>),
        ),
      );
      _practiceDays =
          (prefs.getStringList(learnerKey(_daysKey)) ?? const []).toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[PROGRESS] load failed: $e');
      _byGame = {};
      _practiceDays = {};
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      // Snapshot keys AND data before the first await: a learner switch
      // landing in that gap must not send one learner's stars to the other.
      final storageKey = learnerKey(_storageKey);
      final daysKey = learnerKey(_daysKey);
      final encoded =
          json.encode(_byGame.map((key, v) => MapEntry(key, v.toJson())));
      final days = _practiceDays.toList();
      // Chained, so writes land in call order (see UserSongsService._save).
      _lastSave = _lastSave.then((_) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(storageKey, encoded);
        await prefs.setStringList(daysKey, days);
      }).catchError((Object e) {
        // Caught on the chain itself, so one failed write cannot stall every
        // later one.
        if (kDebugMode) debugPrint('[PROGRESS] save failed: $e');
      });
      await _lastSave;
    } catch (e) {
      if (kDebugMode) debugPrint('[PROGRESS] save failed: $e');
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Records a finished game; keeps the best stars/score, counts plays, tracks
  /// the fastest completion (when [elapsedMs] is given), and marks today as a
  /// practice day (feeds the streak).
  void recordResult(
    String gameId, {
    required int score,
    required int stars,
    int? elapsedMs,
  }) {
    final old = _byGame[gameId] ?? const GameProgress();
    final timed = elapsedMs != null && elapsedMs > 0;
    final isBest = timed && (old.bestTimeMs == 0 || elapsedMs < old.bestTimeMs);
    final newBest = isBest ? elapsedMs : old.bestTimeMs;
    _byGame[gameId] = GameProgress(
      bestStars: stars > old.bestStars ? stars : old.bestStars,
      bestScore: score > old.bestScore ? score : old.bestScore,
      plays: old.plays + 1,
      bestTimeMs: newBest,
    );
    if (timed) {
      _lastElapsedMs = elapsedMs;
      _lastBestMs = newBest;
      _lastWasBest = isBest;
    }
    _practiceDays.add(_dayKey(_now()));
    notifyListeners();
    _save();
  }

  /// Whether a game was finished on [day].
  bool practicedOn(DateTime day) => _practiceDays.contains(_dayKey(day));

  /// Date-only "today" per the injected clock (used for streak + calendar).
  DateTime get today => DateTime(_now().year, _now().month, _now().day);

  /// Consecutive practice days ending today (or yesterday, so the streak
  /// doesn't read as broken before today's first session).
  int get currentStreak {
    // Walk back by CALENDAR days, not `subtract(Duration(days: 1))`. A Duration
    // is 24 h of absolute time, but the day after a spring-forward DST change
    // only had 23 h — subtracting 24 h overshoots to 23:00 of the day-before,
    // whose date-key skips the intervening day and the streak silently breaks
    // (undercounts, and loses the "practiced yesterday" grace). The audience is
    // German (CET/CEST), so this bites every spring. DateTime(y, m, d-1)
    // normalizes (day 0 → previous month) and stays on the local calendar.
    DateTime prevDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);
    var day = practicedOn(today) ? today : prevDay(today);
    var streak = 0;
    while (practicedOn(day)) {
      streak++;
      day = prevDay(day);
    }
    return streak;
  }

  GameProgress progressFor(String gameId) =>
      _byGame[gameId] ?? const GameProgress();

  /// Best stars for [gameId] (0 if never finished).
  int starsFor(String gameId) => progressFor(gameId).bestStars;

  int get totalStars => _byGame.values.fold(0, (sum, p) => sum + p.bestStars);
}
