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
import 'package:comet_beat/core/harmony/setlist.dart';
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
  static const _favouritesKey = 'chart_favourites_v1';

  /// The names the player has starred.
  ///
  /// Kept as NAMES rather than as a flag on `SavedChart`, so starring does not
  /// rewrite the chart row — a favourite is a fact about the player, not about
  /// the music, and re-saving the chart must not silently clear it.
  Set<String> favourites() {
    final raw = _prefs.getStringList(_favouritesKey);
    return raw == null ? <String>{} : raw.toSet();
  }

  bool isFavourite(String name) => favourites().contains(name);

  /// Stars or unstars [name]; returns the new set.
  Future<Set<String>> toggleFavourite(String name) async {
    final next = favourites();
    if (!next.remove(name)) next.add(name);
    await _prefs.setStringList(_favouritesKey, next.toList()..sort());
    return next;
  }

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
  Future<List<SavedChart>> remove(String name) async {
    // Drop the star too, or the favourites set grows without bound as names
    // come and go — and a chart the player deleted should not quietly come
    // back starred if they later save something under the same name.
    if (isFavourite(name)) await toggleFavourite(name);
    return _write([
      for (final saved in list())
        if (saved.name != name) saved,
    ]);
  }

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

/// Saved setlists, newest first.
///
/// A separate key and a separate class from [ChartStore], because a setlist
/// REFERENCES charts by name rather than containing them — the two have
/// different lifetimes, and deleting a chart must not silently rewrite every
/// set that mentions it. A set whose chart is gone reports a gap instead (see
/// [SetlistStore.missingCharts]).
class SetlistStore {
  SetlistStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'setlists_v1';
  static const maxSetlists = 40;

  /// Every saved setlist, newest first. Never throws.
  List<({Setlist setlist, int savedAtMs})> list() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <({Setlist setlist, int savedAtMs})>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final setlist = Setlist.fromJson(entry['setlist']);
        if (setlist == null) continue;
        final at = entry['savedAtMs'];
        out.add((setlist: setlist, savedAtMs: at is int ? at : 0));
      }
      out.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Setlist? find(String name) {
    for (final row in list()) {
      if (row.setlist.name == name) return row.setlist;
    }
    return null;
  }

  /// Saves [setlist], replacing any of the same name.
  ///
  /// An EMPTY set is allowed, unlike an empty chart: you build a set by making
  /// it and then adding to it, so refusing the empty one would make it
  /// impossible to start.
  Future<List<({Setlist setlist, int savedAtMs})>> save(
    Setlist setlist, {
    int? nowMs,
  }) async {
    final name = setlist.name.trim();
    if (name.isEmpty) return list();
    final entry = (
      setlist: setlist.copyWith(name: name),
      savedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    final kept = [
      entry,
      for (final row in list())
        if (row.setlist.name != name) row,
    ]..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return _writeSetlists(kept.take(maxSetlists).toList());
  }

  Future<List<({Setlist setlist, int savedAtMs})>> remove(String name) =>
      _writeSetlists([
        for (final row in list())
          if (row.setlist.name != name) row,
      ]);

  /// The entries of [setlist] whose chart no longer exists in [charts].
  ///
  /// Reported rather than pruned: a missing chart on a gig night is something
  /// the player must SEE, and silently dropping the song from the set is the
  /// worst possible response.
  List<SetlistEntry> missingCharts(Setlist setlist, ChartStore charts) {
    final known = {for (final saved in charts.list()) saved.name};
    return [
      for (final entry in setlist.entries)
        if (!known.contains(entry.chartName)) entry,
    ];
  }

  Future<List<({Setlist setlist, int savedAtMs})>> _writeSetlists(
    List<({Setlist setlist, int savedAtMs})> rows,
  ) async {
    await _prefs.setString(
      _key,
      jsonEncode([
        for (final row in rows)
          {'setlist': row.setlist.toJson(), 'savedAtMs': row.savedAtMs},
      ]),
    );
    return rows;
  }
}
