// lib/core/services/chart_store.dart
//
// The charts you wrote, kept.
//
// Without this the chart screen is a toy: you type a tune, play it, leave the
// screen and it is gone. `chart_codec.dart` has been able to serialise a
// `Chart` since BB-D2 — nothing ever called it.
//
// Shape borrowed wholesale from `FxPresetStore` (which took it from
// `ProjectStore`): a SharedPreferences list, newest first, capped with the
// OLDEST dropped, and a corrupt row skipped rather than thrown. Three stores of
// the same shape are easier to reason about than three clever ones.
//
// TWO KINDS OF SAVE, and the difference matters:
//   * NAMED     — `save(name, chart)`, an act the user performed.
//   * WORKING   — `saveWorking(chart)`, the chart currently on screen, written
//                 on every edit under its own key. This is what makes leaving
//                 the screen non-destructive, and it is deliberately NOT in the
//                 named list: an autosave that fills your library with
//                 "Untitled 7" is worse than no autosave.
library;

import 'dart:convert';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved chart, with the metadata a browser needs without decoding it.
class SavedChart {
  const SavedChart({
    required this.name,
    required this.json,
    required this.savedAtMs,
  });

  /// What the user called it. Unique within the store — saving again under the
  /// same name replaces.
  final String name;

  /// The chart as `chart_codec` JSON text.
  final String json;

  final int savedAtMs;

  /// The decoded chart, or null when the stored text no longer reads (an older
  /// build, a hand-edited value). Callers must handle null rather than assume.
  Chart? get chart => chartFromJsonString(json);

  Map<String, Object?> toJson() => {
        'name': name,
        'json': json,
        'savedAtMs': savedAtMs,
      };

  /// Null when [raw] is not a chart — a corrupt entry is skipped rather than
  /// throwing, so one bad row cannot cost the whole list.
  static SavedChart? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final json = raw['json'];
    if (name is! String || json is! String || name.isEmpty) return null;
    final savedAt = raw['savedAtMs'];
    return SavedChart(
      name: name,
      json: json,
      savedAtMs: savedAt is int ? savedAt : 0,
    );
  }
}

/// Saved charts, newest first.
class ChartStore {
  ChartStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'charts_v1';
  static const _workingKey = 'chart_working_v1';

  /// How many are kept, oldest dropped. Same reasoning as the sibling stores:
  /// SharedPreferences is not a database, and a list nobody can scroll is not a
  /// browser.
  static const maxCharts = 40;

  /// Every saved chart, newest first. Never throws: a corrupt store reads as
  /// empty, which is recoverable, where a throw at start-up is not.
  List<SavedChart> list() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SavedChart>[
        for (final entry in decoded)
          if (SavedChart.fromJson(entry) case final saved?) saved,
      ];
      out.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// The chart called [name], or null.
  SavedChart? find(String name) {
    for (final saved in list()) {
      if (saved.name == name) return saved;
    }
    return null;
  }

  /// Save [chart] under [name], replacing any chart with that name.
  ///
  /// An EMPTY chart is refused: a library of blank grids is a library you stop
  /// opening. [nowMs] is injected rather than read from the clock so a test can
  /// assert ordering without sleeping.
  Future<List<SavedChart>> save(
    String name,
    Chart chart, {
    int? nowMs,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || chart.isEmpty) return list();
    final entry = SavedChart(
      name: trimmed,
      json: chartToJsonString(chart),
      savedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    final kept = [
      entry,
      for (final saved in list())
        if (saved.name != trimmed) saved,
    ]..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return _write(kept.take(maxCharts).toList());
  }

  /// Forget the chart called [name].
  Future<List<SavedChart>> remove(String name) => _write([
        for (final saved in list())
          if (saved.name != name) saved,
      ]);

  /// The chart that was on screen last time, or null.
  Chart? readWorking() {
    final raw = _prefs.getString(_workingKey);
    if (raw == null || raw.isEmpty) return null;
    return chartFromJsonString(raw);
  }

  /// Remembers the chart currently being edited.
  ///
  /// Separate from the named list on purpose — see the header. An empty chart
  /// CLEARS the slot rather than storing a blank, so "I deleted everything" is
  /// not resurrected on the next visit.
  Future<void> saveWorking(Chart? chart) async {
    if (chart == null || chart.isEmpty) {
      await _prefs.remove(_workingKey);
      return;
    }
    await _prefs.setString(_workingKey, chartToJsonString(chart));
  }

  Future<List<SavedChart>> _write(List<SavedChart> charts) async {
    await _prefs.setString(
      _key,
      jsonEncode([for (final chart in charts) chart.toJson()]),
    );
    return charts;
  }
}
