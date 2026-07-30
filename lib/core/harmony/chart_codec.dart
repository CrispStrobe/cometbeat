// lib/core/harmony/chart_codec.dart
//
// BB-D2 — the chart's codec, versioned from day one.
//
// CHORDS ARE STORED AS SYMBOLS, and that is exact rather than merely tidy.
// `ChordSpec` documents the invariant this rests on: *"`parse(format(x)) == x`
// holds even where `format(parse(s)) != s`"* — formatting is canonical, so a
// spec survives the round trip even though two different spellings collapse to
// one spec on the way in. So a chart file says `"Cmaj7"` and not eleven fields,
// which matters because a chart is the kind of file someone opens in a text
// editor.
//
// ⚠️ BUT IT IS VERIFIED, NOT TRUSTED. The encoder re-parses every symbol it
// writes and falls back to a STRUCTURAL form for any chord that does not come
// back identical. That costs one parse per chord on save and removes an entire
// class of silent corruption — a construct BB-D1's formatter cannot express
// would otherwise be saved as a *different chord*, which is far worse than a
// verbose file. `chart_codec_test` asserts the fallback is never needed today;
// if it ever fires, the file is still right and the test says so.
//
// UNKNOWN KEYS SURVIVE. Anything this build does not recognise is kept in
// `extra` and written back unchanged. Same rule as `ProjectTrack.unreadable`,
// and the same reason: a newer build's chart, opened and re-saved by an older
// one, must not come back with its form quietly deleted.

import 'dart:convert';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Pitch, Step, TimeSignature;

/// Bumped when the shape changes in a way an older reader cannot handle.
const int kChartCodecVersion = 1;

/// The keys this build owns at each level, so everything else is `extra`.
const _chartKeys = {
  'v',
  'title',
  'composer',
  'fifths',
  'minor',
  'meter',
  'tempo',
  'style',
  'sections',
  'pickup',
};
const _sectionKeys = {
  'label',
  'bars',
  'repeat',
  'feel',
  'tempoScale',
  'intensity',
};
const _barKeys = {'chords', 'meter', 'barline', 'ending', 'nav'};
const _chordKeys = {'c', 'spec', 'beat', 'beats'};

// ── encode ──────────────────────────────────────────────────────────────────

Map<String, dynamic> chartToJson(Chart chart) => {
      'v': kChartCodecVersion,
      if (chart.title.isNotEmpty) 'title': chart.title,
      if (chart.composer != null) 'composer': chart.composer,
      if (chart.keyFifths != 0) 'fifths': chart.keyFifths,
      if (chart.minor) 'minor': true,
      'meter': _meterToJson(chart.meter),
      'tempo': chart.tempoBpm,
      if (chart.styleId != null) 'style': chart.styleId,
      if (chart.pickupBeats != 0) 'pickup': chart.pickupBeats,
      'sections': [for (final s in chart.sections) _sectionToJson(s)],
      ...?_extraFor(chart.extra, _chartKeys),
    };

String chartToJsonString(Chart chart) => jsonEncode(chartToJson(chart));

Map<String, dynamic> _sectionToJson(ChartSection s) => {
      if (s.label.isNotEmpty) 'label': s.label,
      if (s.repeatCount != 1) 'repeat': s.repeatCount,
      if (s.feel != null) 'feel': s.feel,
      if (s.tempoScale != null) 'tempoScale': s.tempoScale,
      if (s.intensity != null) 'intensity': s.intensity,
      'bars': [for (final b in s.bars) _barToJson(b)],
      ...?_extraFor(s.extra, _sectionKeys),
    };

Map<String, dynamic> _barToJson(ChartBar b) => {
      if (b.chords.isNotEmpty)
        'chords': [for (final c in b.chords) _chordToJson(c)],
      if (b.meterChange != null) 'meter': _meterToJson(b.meterChange!),
      if (b.barline != ChartBarline.plain) 'barline': b.barline.name,
      if (b.endingNumber != null) 'ending': b.endingNumber,
      if (b.navigation != null) 'nav': b.navigation!.name,
      ...?_extraFor(b.extra, _barKeys),
    };

Map<String, dynamic> _chordToJson(ChartBeatChord c) {
  final symbol = c.chord.text;
  // Verified, not trusted — see the header.
  final exact = parseChordSpec(symbol) == c.chord;
  return {
    if (exact) 'c': symbol else 'spec': _specToJson(c.chord),
    if (c.beat != 0) 'beat': c.beat,
    if (c.beats != 1) 'beats': c.beats,
    ...?_extraFor(c.extra, _chordKeys),
  };
}

/// The structural fallback. Only written for a chord whose symbol does not
/// re-parse to itself, which no chord does today.
Map<String, dynamic> _specToJson(ChordSpec s) => {
      'root': _pitchToJson(s.root),
      'triad': s.triad.name,
      if (s.seventh != ChordSeventh.none) 'seventh': s.seventh.name,
      if (s.extension != 0) 'ext': s.extension,
      if (s.alterations.isNotEmpty)
        'alt': [for (final a in s.alterations) a.name],
      if (s.added.isNotEmpty) 'add': s.added.toList()..sort(),
      if (s.omitted.isNotEmpty) 'omit': s.omitted.toList()..sort(),
      if (s.bass != null) 'bass': _pitchToJson(s.bass!),
    };

Map<String, dynamic> _pitchToJson(Pitch p) => {
      'step': p.step.name,
      if (p.alter != 0) 'alter': p.alter,
      'octave': p.octave,
    };

Map<String, dynamic> _meterToJson(TimeSignature t) => {
      'beats': t.beats,
      'unit': t.beatUnit,
    };

/// The unrecognised keys, minus any this build owns — so a key that was unknown
/// when the file was written and is understood now is not written twice.
Map<String, dynamic>? _extraFor(
  Map<String, dynamic>? extra,
  Set<String> owned,
) {
  if (extra == null || extra.isEmpty) return null;
  final out = {
    for (final e in extra.entries)
      if (!owned.contains(e.key)) e.key: e.value,
  };
  return out.isEmpty ? null : out;
}

// ── decode ──────────────────────────────────────────────────────────────────

/// Reads a chart. Null only for input that is not a chart object at all —
/// anything merely unfamiliar INSIDE it is preserved rather than rejected.
Chart? chartFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final sections = json['sections'];
  return Chart(
    title: _str(json['title']) ?? '',
    composer: _str(json['composer']),
    keyFifths: _int(json['fifths']) ?? 0,
    minor: json['minor'] == true,
    meter: _meterFromJson(json['meter']) ?? const TimeSignature(4, 4),
    tempoBpm: _int(json['tempo']) ?? 120,
    styleId: _str(json['style']),
    pickupBeats: _num(json['pickup']) ?? 0,
    sections: [
      if (sections is List)
        for (final s in sections)
          if (_sectionFromJson(s) case final parsed?) parsed,
    ],
    extra: _unknown(json, _chartKeys),
  );
}

Chart? chartFromJsonString(String source) {
  try {
    return chartFromJson(jsonDecode(source));
  } catch (_) {
    // A corrupt string reads as "not a chart", which a caller can recover from;
    // a throw out of a decoder cannot be recovered from at the call site.
    return null;
  }
}

ChartSection? _sectionFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final bars = json['bars'];
  return ChartSection(
    label: _str(json['label']) ?? '',
    repeatCount: _int(json['repeat']) ?? 1,
    feel: _str(json['feel']),
    tempoScale: _num(json['tempoScale']),
    intensity: _num(json['intensity']),
    bars: [
      if (bars is List)
        for (final b in bars)
          if (_barFromJson(b) case final parsed?) parsed,
    ],
    extra: _unknown(json, _sectionKeys),
  );
}

ChartBar? _barFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final chords = json['chords'];
  return ChartBar(
    chords: [
      if (chords is List)
        for (final c in chords)
          if (_chordFromJson(c) case final parsed?) parsed,
    ],
    meterChange: _meterFromJson(json['meter']),
    barline:
        _enumByName(ChartBarline.values, json['barline']) ?? ChartBarline.plain,
    endingNumber: _int(json['ending']),
    navigation: _enumByName(ChartNavigation.values, json['nav']),
    extra: _unknown(json, _barKeys),
  );
}

ChartBeatChord? _chordFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final spec = json['c'] is String
      ? parseChordSpec(json['c'] as String)
      : _specFromJson(json['spec']);
  // A chord whose symbol this build cannot read is DROPPED rather than guessed
  // at — but the bar around it survives, so the chart still opens and the loss
  // is one chord rather than the file. Guessing would put a wrong chord in a
  // document someone plays from.
  if (spec == null) return null;
  return ChartBeatChord(
    chord: spec,
    beat: _num(json['beat']) ?? 0,
    beats: _num(json['beats']) ?? 1,
    extra: _unknown(json, _chordKeys),
  );
}

ChordSpec? _specFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final root = _pitchFromJson(json['root']);
  if (root == null) return null;
  return ChordSpec(
    root: root,
    triad: _enumByName(ChordTriad.values, json['triad']) ?? ChordTriad.major,
    seventh:
        _enumByName(ChordSeventh.values, json['seventh']) ?? ChordSeventh.none,
    extension: _int(json['ext']) ?? 0,
    alterations: {
      for (final a in (json['alt'] is List ? json['alt'] as List : const []))
        if (_enumByName(ChordAlteration.values, a) case final parsed?) parsed,
    },
    added: _intSet(json['add']),
    omitted: _intSet(json['omit']),
    bass: _pitchFromJson(json['bass']),
  );
}

Pitch? _pitchFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final step = _enumByName(Step.values, json['step']);
  if (step == null) return null;
  return Pitch(
    step,
    alter: _int(json['alter']) ?? 0,
    octave: _int(json['octave']) ?? 4,
  );
}

TimeSignature? _meterFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, dynamic>();
  final beats = _int(json['beats']);
  final unit = _int(json['unit']);
  if (beats == null || unit == null || beats < 1 || unit < 1) return null;
  return TimeSignature(beats, unit);
}

/// Everything in [json] this build does not own, or null when there is nothing.
Map<String, dynamic>? _unknown(Map<String, dynamic> json, Set<String> owned) {
  final out = {
    for (final e in json.entries)
      if (!owned.contains(e.key)) e.key: e.value,
  };
  return out.isEmpty ? null : out;
}

T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
int? _int(Object? v) => v is num ? v.toInt() : null;
double? _num(Object? v) => v is num ? v.toDouble() : null;

Set<int> _intSet(Object? v) => {
      if (v is List)
        for (final e in v)
          if (e is num) e.toInt(),
    };
