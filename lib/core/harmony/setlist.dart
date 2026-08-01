// lib/core/harmony/setlist.dart
//
// BB-U4 — setlists: an ordered set of charts, with the per-song overrides in
// the SET rather than in the chart.
//
// 🔴 THAT PLACEMENT IS THE WHOLE DESIGN, not a detail. The same tune sits in
// two bands' sets at two different keys, and the singer's key is a property of
// the GIG, not of the song. Writing the key onto the chart would mean the
// second set silently re-keys the first — and worse, that opening a chart from
// one set and saving it would corrupt the other. So a `Setlist` never mutates a
// chart; it carries what to do TO one, and resolution happens at play time.
//
// The same reasoning already shaped `ChartTransposition` (a capo belongs to the
// player, not the tune). This is that rule one level up.
library;

import 'dart:convert';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_transpose.dart';

/// One song in a set: which chart, and what this gig does to it.
class SetlistEntry {
  const SetlistEntry({
    required this.chartName,
    this.transposeSemitones = 0,
    this.tempoBpm,
    this.note,
  });

  /// The saved chart's name — a reference, never a copy. A set that embedded
  /// the chart would drift from the one you edit.
  final String chartName;

  /// This gig's key, relative to the chart's own.
  final int transposeSemitones;

  /// This gig's tempo, or null to use the chart's.
  final int? tempoBpm;

  /// A cue for the player: "capo 3", "straight in from the last tune".
  final String? note;

  bool get isPlain =>
      transposeSemitones == 0 && tempoBpm == null && (note?.isEmpty ?? true);

  SetlistEntry copyWith({
    String? chartName,
    int? transposeSemitones,
    int? tempoBpm,
    String? note,
    bool clearTempo = false,
  }) =>
      SetlistEntry(
        chartName: chartName ?? this.chartName,
        transposeSemitones: transposeSemitones ?? this.transposeSemitones,
        tempoBpm: clearTempo ? null : (tempoBpm ?? this.tempoBpm),
        note: note ?? this.note,
      );

  Map<String, Object?> toJson() => {
        'chart': chartName,
        if (transposeSemitones != 0) 'transpose': transposeSemitones,
        if (tempoBpm != null) 'tempo': tempoBpm,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  /// Null when [raw] is not an entry — one bad row must not cost the set.
  static SetlistEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['chart'];
    if (name is! String || name.isEmpty) return null;
    final transpose = raw['transpose'];
    final tempo = raw['tempo'];
    final note = raw['note'];
    return SetlistEntry(
      chartName: name,
      transposeSemitones: transpose is int ? transpose : 0,
      tempoBpm: tempo is int && tempo > 0 ? tempo : null,
      note: note is String ? note : null,
    );
  }

  @override
  String toString() => 'SetlistEntry($chartName, +$transposeSemitones)';
}

/// An ordered set of songs.
class Setlist {
  const Setlist({required this.name, this.entries = const []});

  final String name;
  final List<SetlistEntry> entries;

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;

  Setlist copyWith({String? name, List<SetlistEntry>? entries}) =>
      Setlist(name: name ?? this.name, entries: entries ?? this.entries);

  /// [entry] appended.
  Setlist add(SetlistEntry entry) => copyWith(entries: [...entries, entry]);

  /// The entry at [index] removed; out of range is a no-op rather than a throw,
  /// because a stale index from a list widget must not crash a gig.
  Setlist removeAt(int index) => index < 0 || index >= entries.length
      ? this
      : copyWith(entries: [...entries]..removeAt(index));

  /// [from] moved to [to]. Out-of-range is a no-op, for the same reason.
  Setlist reorder(int from, int to) {
    if (from < 0 || from >= entries.length) return this;
    if (to < 0 || to >= entries.length) return this;
    final next = [...entries];
    next.insert(to, next.removeAt(from));
    return copyWith(entries: next);
  }

  Setlist replaceAt(int index, SetlistEntry entry) =>
      index < 0 || index >= entries.length
          ? this
          : copyWith(entries: [...entries]..[index] = entry);

  Map<String, Object?> toJson() => {
        'v': kSetlistCodecVersion,
        'name': name,
        'entries': [for (final e in entries) e.toJson()],
      };

  static Setlist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String) return null;
    final entries = raw['entries'];
    return Setlist(
      name: name,
      entries: entries is! List
          ? const []
          : [
              for (final e in entries)
                if (SetlistEntry.fromJson(e) case final entry?) entry,
            ],
    );
  }
}

const int kSetlistCodecVersion = 1;

String setlistToJsonString(Setlist setlist) => jsonEncode(setlist.toJson());

/// Null on anything unreadable — never throws, so a corrupt file cannot take
/// the screen down mid-gig.
Setlist? setlistFromJsonString(String source) {
  try {
    return Setlist.fromJson(jsonDecode(source));
  } catch (_) {
    return null;
  }
}

/// [chart] as this [entry] asks for it.
///
/// ⚠️ Returns a NEW chart and never touches the stored one. That is the
/// invariant the whole file exists for: the same chart in two sets at two keys
/// plays at each set's key, and the file on disk is unchanged by either.
Chart resolveEntry(Chart chart, SetlistEntry entry) {
  var out = chart;
  if (entry.transposeSemitones != 0) {
    out = transposeChartBySemitones(out, entry.transposeSemitones);
  }
  if (entry.tempoBpm != null && entry.tempoBpm! > 0) {
    out = Chart(
      title: out.title,
      composer: out.composer,
      keyFifths: out.keyFifths,
      minor: out.minor,
      meter: out.meter,
      tempoBpm: entry.tempoBpm!,
      styleId: out.styleId,
      sections: out.sections,
      pickupBeats: out.pickupBeats,
      extra: out.extra,
    );
  }
  return out;
}
