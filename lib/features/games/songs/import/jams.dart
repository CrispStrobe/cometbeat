// lib/features/games/songs/import/jams.dart
//
// JAMS (JSON Annotated Music Specification, Humphrey et al., ISMIR 2014) import
// + export — the MIR-standard annotation format that ships the big chord/melody/
// beat/key datasets (Isophonics, Billboard, RWC, MedleyDB, …). A JAMS file is
// `{file_metadata, annotations: [{namespace, data: [{time, duration, value,
// confidence}, …]}, …]}`.
//
// This file reads two musical annotations into the app's existing pipelines:
//   • `chord` / `chord_harte` → a ChordPro chord sheet (Harte labels → triads).
//   • `note_midi`             → a melody, rendered to a minimal SMF and fed to
//     the existing MIDI importer. `tempo` sets the SMF tempo (so the rhythm
//     quantizes correctly), `beat` positions infer the time signature, and
//     `key_mode` is surfaced in the title.
//
// It also WRITES JAMS (chordsToJams / notesToJams) so we can produce ground
// truth for automated tests (synthesize → detect → compare against the JAMS).
//
// Pure Dart (no Flutter): unit-testable, and the same converters back the CLI.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// ─────────────────────────── decode + shared helpers ────────────────────────

/// Decodes [json] into a JAMS object, or throws [FormatException].
Map<String, dynamic> _decodeJams(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    throw const FormatException('Not valid JSON — expected a JAMS file.');
  }
  if (root is! Map<String, dynamic>) {
    throw const FormatException('Not a JAMS object.');
  }
  return root;
}

/// The observations of the first annotation in [root] whose namespace is in
/// [namespaces], normalised to `{time, duration, value}` maps. Handles both the
/// modern list-of-observations and the legacy dict-of-parallel-arrays shapes.
List<Map<String, dynamic>> _observations(
  Map<String, dynamic> root,
  Set<String> namespaces,
) {
  final annotations = root['annotations'];
  if (annotations is! List) return const [];
  for (final a in annotations) {
    if (a is! Map) continue;
    if (!namespaces.contains(a['namespace'])) continue;
    final data = a['data'];
    if (data is List) {
      return [
        for (final o in data)
          if (o is Map) {'value': o['value'], ...o.cast<String, dynamic>()},
      ];
    }
    if (data is Map) {
      final values = data['value'];
      if (values is List) {
        final times = data['time'];
        final durs = data['duration'];
        return [
          for (var i = 0; i < values.length; i++)
            {
              'time': times is List && i < times.length ? times[i] : 0,
              'duration': durs is List && i < durs.length ? durs[i] : 0,
              'value': values[i],
            },
        ];
      }
    }
    return const []; // matched the namespace but data shape is unusable
  }
  return const [];
}

String? _titleOf(Map<String, dynamic> root) {
  final meta = root['file_metadata'];
  if (meta is Map && meta['title'] is String) {
    final t = (meta['title'] as String).trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

/// The JAMS `file_metadata.title`, or null.
String? jamsTitle(String json) {
  try {
    return _titleOf(_decodeJams(json));
  } catch (_) {
    return null;
  }
}

// ───────────────────────────────── chords ───────────────────────────────────

/// Whether [json] has a chord annotation with at least one real chord.
bool jamsHasChords(String json) {
  try {
    return _chordNames(_decodeJams(json)).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Distinct-run chord names from the first chord annotation (repeats collapsed,
/// a no-chord `N`/`X` breaking the run).
List<String> _chordNames(Map<String, dynamic> root) {
  final out = <String>[];
  String? last;
  for (final o in _observations(root, const {'chord', 'chord_harte'})) {
    final v = o['value'];
    if (v is! String) continue;
    final name = harteToChordName(v);
    if (name == null) {
      last = null;
      continue;
    }
    if (name == last) continue;
    out.add(name);
    last = name;
  }
  return out;
}

/// Converts a JAMS chord annotation into ChordPro source text (reused by the
/// existing chord-sheet pipeline). Throws [FormatException] with no usable
/// chords.
String jamsToChordPro(String json) {
  final root = _decodeJams(json);
  final chords = _chordNames(root);
  if (chords.isEmpty) {
    throw const FormatException('No chord annotation found in the JAMS file.');
  }
  final title = _titleOf(root) ?? 'JAMS chords';
  final buffer = StringBuffer('{title: $title}\n\n');
  for (var i = 0; i < chords.length; i += 4) {
    buffer.writeln(chords.skip(i).take(4).map((c) => '[$c]·').join('  '));
  }
  return buffer.toString();
}

/// Maps a Harte chord [label] to a plain chord name (`C`, `Am`, `F#`, `Bbm`),
/// or null for a no-chord / unparseable label. The app renders triads, so only
/// the root + major/minor survive; extensions and slash-bass are dropped;
/// dim/hdim → minor.
String? harteToChordName(String label) {
  final s = label.trim();
  if (s.isEmpty || s == 'N' || s == 'X') return null;
  final m = RegExp(r'^([A-G])([#b]*)').firstMatch(s);
  if (m == null) return null;
  final root = '${m.group(1)}${m.group(2)}';
  final colon = s.indexOf(':');
  var quality = '';
  if (colon >= 0) {
    quality = s.substring(colon + 1);
    final slash = quality.indexOf('/');
    if (slash >= 0) quality = quality.substring(0, slash);
    quality = quality.trim();
  }
  final isMinor = quality.startsWith('min') ||
      quality.startsWith('dim') ||
      quality.startsWith('hdim');
  return isMinor ? '${root}m' : root;
}

// ───────────────────────────────── melody ───────────────────────────────────

/// One note from a `note_midi` annotation.
typedef JamsNote = ({double time, double duration, int midi});

/// The notes of the first `note_midi` annotation in [json], time-sorted.
/// Fractional MIDI values are rounded to the nearest semitone; non-positive
/// durations and out-of-range pitches are skipped.
List<JamsNote> jamsMelodyNotes(String json) {
  final root = _decodeJams(json);
  final out = <JamsNote>[];
  for (final o in _observations(root, const {'note_midi'})) {
    final t = o['time'];
    final d = o['duration'];
    final v = o['value'];
    if (t is! num || v is! num) continue;
    final dur = d is num ? d.toDouble() : 0.0;
    final midi = v.round();
    if (dur <= 0 || midi < 0 || midi > 127) continue;
    out.add((time: t.toDouble(), duration: dur, midi: midi));
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// The tempo (BPM) from the first `tempo` annotation, or null.
double? jamsTempo(String json) {
  try {
    for (final o in _observations(_decodeJams(json), const {'tempo'})) {
      final v = o['value'];
      if (v is num && v > 0) return v.toDouble();
    }
  } catch (_) {}
  return null;
}

/// The beats-per-bar inferred from a `beat` annotation's max position value
/// (JAMS beats carry the in-bar position 1..N), or null. Clamped to 2..12.
int? jamsBeatsPerBar(String json) {
  try {
    var maxPos = 0;
    for (final o in _observations(_decodeJams(json), const {'beat'})) {
      final v = o['value'];
      if (v is num) maxPos = math.max(maxPos, v.round());
    }
    if (maxPos >= 2) return maxPos.clamp(2, 12);
  } catch (_) {}
  return null;
}

/// A human key label ("A minor", "Eb major") from the first `key_mode`
/// annotation, or null. JAMS values look like `C:major`, `Eb:minor`, or `N`.
String? jamsKey(String json) {
  try {
    for (final o in _observations(_decodeJams(json), const {'key_mode'})) {
      final v = o['value'];
      if (v is! String) continue;
      final s = v.trim();
      if (s.isEmpty || s == 'N') continue;
      // Split "TONIC:MODE" (or "TONIC MODE"); default mode = major.
      final sep = s.contains(':') ? ':' : ' ';
      final parts = s.split(sep);
      final tonic = parts.first.trim();
      final mode = parts.length > 1 ? parts[1].trim().toLowerCase() : 'major';
      if (tonic.isEmpty) continue;
      return '$tonic ${mode.isEmpty ? 'major' : mode}';
    }
  } catch (_) {}
  return null;
}

/// Renders the `note_midi` melody of [json] to a minimal Standard MIDI File
/// (format 0), so it can be fed to the app's MIDI importer. The `tempo`
/// annotation (or 120 BPM) drives the seconds→ticks mapping so the rhythm
/// quantizes correctly; a `beat`-derived meter sets the time signature.
///
/// Throws [FormatException] when there is no usable `note_midi` annotation.
Uint8List jamsToMidi(String json) {
  final notes = jamsMelodyNotes(json);
  if (notes.isEmpty) {
    throw const FormatException(
      'No melody (note_midi) annotation found in the JAMS file.',
    );
  }
  const tpq = 480;
  final bpm = jamsTempo(json) ?? 120.0;
  final ticksPerSec = tpq * bpm / 60.0;
  int tick(double sec) => (sec * ticksPerSec).round();

  // (tick, isOn, midi) events; note-offs sort before note-ons at the same tick.
  final events = <(int, bool, int)>[];
  for (final n in notes) {
    final on = tick(n.time);
    final off = math.max(on + 1, tick(n.time + n.duration));
    events.add((on, true, n.midi));
    events.add((off, false, n.midi));
  }
  events.sort((a, b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    return (a.$2 ? 1 : 0).compareTo(b.$2 ? 1 : 0);
  });

  final track = <int>[];
  // Tempo meta (µs per quarter).
  final usPerQuarter = (60000000 / bpm).round();
  track.addAll([
    0x00, 0xFF, 0x51, 0x03, //
    (usPerQuarter >> 16) & 0xFF,
    (usPerQuarter >> 8) & 0xFF,
    usPerQuarter & 0xFF,
  ]);
  // Time-signature meta (nn/2^dd), inferred from the beat annotation.
  final numerator = jamsBeatsPerBar(json) ?? 4;
  track.addAll([0x00, 0xFF, 0x58, 0x04, numerator, 2, 24, 8]);

  var cur = 0;
  for (final (t, isOn, m) in events) {
    _writeVlq(track, t - cur);
    cur = t;
    track.addAll(isOn ? [0x90, m, 80] : [0x80, m, 0]);
  }
  track.addAll([0x00, 0xFF, 0x2F, 0x00]); // end of track

  return Uint8List.fromList([
    ...'MThd'.codeUnits,
    0, 0, 0, 6, 0, 0, 0, 1, (tpq >> 8) & 0xFF, tpq & 0xFF, //
    ...'MTrk'.codeUnits,
    (track.length >> 24) & 0xFF,
    (track.length >> 16) & 0xFF,
    (track.length >> 8) & 0xFF,
    track.length & 0xFF,
    ...track,
  ]);
}

/// Appends [value] as a MIDI variable-length quantity to [out].
void _writeVlq(List<int> out, int value) {
  var v = value < 0 ? 0 : value;
  final buf = <int>[v & 0x7F];
  v >>= 7;
  while (v > 0) {
    buf.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addAll(buf.reversed);
}

// ───────────────────────────── JAMS writers ─────────────────────────────────
// Emit JAMS so tests can generate ground truth (and reader↔writer round-trips).

Map<String, dynamic> _obs(num time, num duration, Object? value) =>
    {'time': time, 'duration': duration, 'value': value, 'confidence': 1.0};

/// A JAMS document (JSON string) with a `chord` annotation for [chords] — one
/// per bar of [barSeconds]. Names are written as Harte labels (`Am` → `A:min`).
String chordsToJams(
  List<String> chords, {
  String? title,
  double barSeconds = 2.0,
}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {
          'namespace': 'chord',
          'data': [
            for (var i = 0; i < chords.length; i++)
              _obs(i * barSeconds, barSeconds, _nameToHarte(chords[i])),
          ],
        },
      ],
    });

/// A JAMS document (JSON string) with a `note_midi` annotation for [notes]
/// (plus an optional `tempo` annotation).
String notesToJams(List<JamsNote> notes, {String? title, double? tempo}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {
          'namespace': 'note_midi',
          'data': [for (final n in notes) _obs(n.time, n.duration, n.midi)],
        },
        if (tempo != null)
          {
            'namespace': 'tempo',
            'data': [_obs(0, 0, tempo)],
          },
      ],
    });

/// The plain chord name (`Am`, `C#`) → a Harte label (`A:min`, `C#:maj`).
String _nameToHarte(String name) {
  final m = RegExp(r'^([A-G][#b]*)(m(?!aj))?').firstMatch(name.trim());
  if (m == null) return 'N';
  final root = m.group(1)!;
  return m.group(2) != null ? '$root:min' : '$root:maj';
}
