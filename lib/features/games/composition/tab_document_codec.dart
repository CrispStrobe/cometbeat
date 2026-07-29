// lib/features/games/composition/tab_document_codec.dart
//
// WS-L11 — a lossless `TabDocument` ⇄ JSON codec.
//
// Tab was the only mode that could not save what it IS. Its one persistence
// route, `saveToSongBook`, converts to MusicXML — which keeps the pitches and
// throws away the tuning, the strings, the frets and every technique, i.e.
// everything that makes a tab a tab rather than a melody. There was no
// `toJson`/`fromJson` anywhere, `daw_clip_source_codec` had no `tab` kind, and
// a `Project` (WS-W1) could hold a tab track but not its music. This closes all
// three with one encoder.
//
// THE RULE THAT SHAPES EVERY LINE BELOW: this is a SAVE format, so a field that
// is not written is a field the player loses. `TabColumn` has thirty of them
// and grows — B1…B10 and C1 each added some — so the encoder is written to make
// an omission loud rather than quiet:
//
//   * every field is listed in `_columnToJson` in declaration order, so a new
//     one shows up as a gap when the two are read side by side;
//   * `tabColumnFieldKeys` names the keys, and a test asserts a fully-populated
//     column round-trips EQUAL — add a field without touching this file and
//     that test fails rather than silently dropping it.
//
// DEFAULTS ARE OMITTED. A plain quarter-note column with two frets writes four
// keys, not thirty. Tabs are long — a three-minute piece is hundreds of columns
// — and the difference is a file a person can read versus one they cannot.
//
// UNKNOWN ENUM NAMES DEGRADE ONE FIELD, NOT THE FILE. A tab written by a newer
// build with an articulation this one has never heard of loses that
// articulation and keeps the note. The alternative — refusing the document — is
// worse for the same reason it is in `daw_clip_source_codec`: losing
// editability is bad, losing the music is much worse.
//
// This file lives beside `tab_document.dart` rather than in `core/`, because
// `TabDocument` depends on the Flutter `crisp_notation` barrel and
// `core/project/` is deliberately pure Dart. It registers itself into
// `project_codec`'s registry instead — which is exactly why that registry
// exists.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// The version WRITTEN.
const int kTabDocumentCodecVersion = 1;

/// The keys `_columnToJson` may emit, one per [TabColumn] field.
///
/// Exists so a test can assert this list against the constructor's parameters:
/// a field added to `TabColumn` without a key here is a field that would be
/// silently dropped on save, and that is precisely the bug this codec is being
/// written to prevent for the future as well as the present.
const List<String> tabColumnFieldKeys = [
  'frets',
  'duration',
  'techniques',
  'chord',
  'tieToNext',
  'tuplet',
  'startRepeat',
  'endRepeat',
  'volta',
  'navigation',
  'section',
  'tempoChange',
  'bend',
  'whammy',
  'slide',
  'tap',
  'harmonic',
  'palmMute',
  'letRing',
  'articulations',
  'ornament',
  'tremolo',
  'graceMidis',
  'graceStyle',
  'arpeggio',
  'pickStroke',
  'leftFingers',
  'rightFinger',
  'barreFret',
  'barreString',
  'dynamic',
  'hairpin',
];

// --- TabDocument → JSON -----------------------------------------------------

/// [doc] as a JSON map.
Map<String, dynamic> tabDocumentToJson(TabDocument doc) => {
      'v': kTabDocumentCodecVersion,
      'tuning': _tuningToJson(doc.tuning),
      if (doc.timeSignature != TimeSignature.fourFour)
        'time': _timeToJson(doc.timeSignature),
      if (doc.keySignature.fifths != 0 || doc.keySignature.custom != null)
        'key': _keyToJson(doc.keySignature),
      'columns': [for (final c in doc.columns) _columnToJson(c)],
      // Omitted entirely when there is no second voice, which is the ordinary
      // case — an empty list would otherwise appear in every single tab.
      if (doc.voice2.isNotEmpty)
        'voice2': [for (final c in doc.voice2) _columnToJson(c)],
    };

Map<String, dynamic> _columnToJson(TabColumn c) => {
      // Fret maps are keyed by string index; JSON object keys must be strings.
      if (c.frets.isNotEmpty)
        'frets': {for (final e in c.frets.entries) '${e.key}': e.value},
      if (c.duration != NoteDuration.quarter)
        'duration': _durationToJson(c.duration),
      if (c.techniques.isNotEmpty)
        'techniques': [for (final t in c.techniques) t.name],
      if (c.chord case final chord?) 'chord': _chordToJson(chord),
      if (c.tieToNext) 'tieToNext': true,
      if (c.tuplet case final t?) 'tuplet': [t.$1, t.$2],
      if (c.startRepeat) 'startRepeat': true,
      if (c.endRepeat) 'endRepeat': true,
      if (c.volta case final v?) 'volta': v,
      if (c.navigation case final n?) 'navigation': n.name,
      if (c.section case final s?) 'section': s,
      if (c.tempoChange case final t?) 'tempoChange': t,
      if (c.bend case final b?) 'bend': [for (final p in b) _bendToJson(p)],
      if (c.whammy case final w?) 'whammy': [for (final p in w) _bendToJson(p)],
      if (c.slide case final s?) 'slide': s.name,
      if (c.tap) 'tap': true,
      if (c.harmonic case final h?) 'harmonic': h.name,
      if (c.palmMute) 'palmMute': true,
      if (c.letRing) 'letRing': true,
      if (c.articulations.isNotEmpty)
        'articulations': [for (final a in c.articulations) a.name],
      if (c.ornament case final o?) 'ornament': o.name,
      if (c.tremolo case final t?) 'tremolo': t,
      if (c.graceMidis case final g?) 'graceMidis': g,
      // Only meaningful with grace notes, so only written with them — otherwise
      // every column would carry a style for notes it does not have.
      if (c.graceMidis != null && c.graceStyle != GraceStyle.acciaccatura)
        'graceStyle': c.graceStyle.name,
      if (c.arpeggio case final a?) 'arpeggio': a.name,
      if (c.pickStroke case final p?) 'pickStroke': p,
      if (c.leftFingers case final f?) 'leftFingers': f,
      if (c.rightFinger case final f?) 'rightFinger': f.name,
      // A barre is a DISTINCT fact from the fingering, not a summary of it —
      // the digits of a barre chord already read 1,1,1 — so it has to be
      // written separately or a saved barre is simply gone.
      if (c.barreFret case final f?) 'barreFret': f,
      if (c.barreString case final b?) 'barreString': b,
      if (c.dynamic case final d?) 'dynamic': d.name,
      if (c.hairpin case final h?) 'hairpin': h.name,
    };

Map<String, dynamic> _tuningToJson(Tuning tuning) => {
      'strings': [for (final p in tuning.strings) _pitchToJson(p)],
      if (tuning.name case final n?) 'name': n,
    };

Map<String, dynamic> _pitchToJson(Pitch p) => {
      'step': p.step.name,
      if (p.alter != 0) 'alter': p.alter,
      if (p.octave != 4) 'octave': p.octave,
      if (p.microtone case final m?) 'microtone': m.name,
    };

Map<String, dynamic> _timeToJson(TimeSignature t) => {
      'beats': t.beats,
      'beatUnit': t.beatUnit,
      if (t.symbol != TimeSymbol.numeric) 'symbol': t.symbol.name,
      if (t.components case final c?) 'components': c,
      if (t.alternate case final a?) 'alternate': _timeToJson(a),
    };

Map<String, dynamic> _keyToJson(KeySignature k) => {
      'fifths': k.fifths,
      if (k.custom case final custom?)
        'custom': [
          for (final a in custom) {'step': a.step.name, 'alter': a.alter},
        ],
    };

Map<String, dynamic> _durationToJson(NoteDuration d) => {
      'base': d.base.name,
      if (d.dots != 0) 'dots': d.dots,
    };

Map<String, dynamic> _chordToJson(ChordDiagram c) => {
      'frets': c.frets,
      if (c.name case final n?) 'name': n,
      if (c.fingers case final f?) 'fingers': f,
      if (c.baseFret != 1) 'baseFret': c.baseFret,
      if (c.fretSpan != 4) 'fretSpan': c.fretSpan,
      if (c.barreFret case final b?) 'barreFret': b,
    };

List<double> _bendToJson(BendPoint p) => [p.offset, p.steps];

// --- JSON → TabDocument -----------------------------------------------------

/// Rebuilds a [TabDocument] from [raw], or null when it is not one.
///
/// Null is reserved for "this is not a tab": a wrong shape, or a version this
/// build cannot read. Everything inside degrades instead — a malformed column
/// becomes an empty one so the columns after it stay where they were, and an
/// unknown enum name loses that one field.
TabDocument? tabDocumentFromJson(Object? raw) {
  if (raw is! Map) return null;
  final version = raw['v'];
  if (version is! num || version.toInt() > kTabDocumentCodecVersion) {
    return null;
  }
  final tuning = _tuningFromJson(raw['tuning']);
  if (tuning == null) return null;
  final columns = raw['columns'];
  final voice2 = raw['voice2'];
  return TabDocument(
    tuning: tuning,
    columns: [
      if (columns is List)
        for (final c in columns) _columnFromJson(c),
    ],
    timeSignature: _timeFromJson(raw['time']) ?? TimeSignature.fourFour,
    keySignature: _keyFromJson(raw['key']) ?? const KeySignature(0),
    voice2: [
      if (voice2 is List)
        for (final c in voice2) _columnFromJson(c),
    ],
  );
}

/// Never null: a column that cannot be read becomes an EMPTY column rather than
/// disappearing. Dropping it would shift every column after it by one, turning
/// one unreadable note into a rhythm that is wrong from there to the end.
TabColumn _columnFromJson(Object? raw) {
  if (raw is! Map) return const TabColumn();
  final frets = <int, int>{};
  final fretsRaw = raw['frets'];
  if (fretsRaw is Map) {
    for (final e in fretsRaw.entries) {
      final string = int.tryParse('${e.key}');
      final fret = e.value;
      if (string != null && fret is num) frets[string] = fret.toInt();
    }
  }
  final tuplet = raw['tuplet'];
  return TabColumn(
    frets: frets,
    duration: _durationFromJson(raw['duration']) ?? NoteDuration.quarter,
    techniques: _enumSet(TabTechnique.values, raw['techniques']),
    chord: _chordFromJson(raw['chord']),
    tieToNext: raw['tieToNext'] == true,
    tuplet: tuplet is List &&
            tuplet.length == 2 &&
            tuplet[0] is num &&
            tuplet[1] is num
        ? ((tuplet[0] as num).toInt(), (tuplet[1] as num).toInt())
        : null,
    startRepeat: raw['startRepeat'] == true,
    endRepeat: raw['endRepeat'] == true,
    volta: _int(raw['volta']),
    navigation: _enumByName(NavigationMark.values, raw['navigation']),
    section: raw['section'] is String ? raw['section'] as String : null,
    tempoChange: _double(raw['tempoChange']),
    bend: _bendsFromJson(raw['bend']),
    whammy: _bendsFromJson(raw['whammy']),
    slide: _enumByName(SlideInOut.values, raw['slide']),
    tap: raw['tap'] == true,
    harmonic: _enumByName(TabNoteStyle.values, raw['harmonic']),
    palmMute: raw['palmMute'] == true,
    letRing: raw['letRing'] == true,
    articulations: _enumSet(Articulation.values, raw['articulations']),
    ornament: _enumByName(Ornament.values, raw['ornament']),
    tremolo: _int(raw['tremolo']),
    graceMidis: _intList(raw['graceMidis']),
    graceStyle: _enumByName(GraceStyle.values, raw['graceStyle']) ??
        GraceStyle.acciaccatura,
    arpeggio: _enumByName(Arpeggio.values, raw['arpeggio']),
    pickStroke: raw['pickStroke'] is bool ? raw['pickStroke'] as bool : null,
    leftFingers: _intList(raw['leftFingers']),
    rightFinger: _enumByName(RightHandFinger.values, raw['rightFinger']),
    barreFret: _int(raw['barreFret']),
    barreString: _int(raw['barreString']),
    dynamic: _enumByName(DynamicLevel.values, raw['dynamic']),
    hairpin: _enumByName(HairpinType.values, raw['hairpin']),
  );
}

Tuning? _tuningFromJson(Object? raw) {
  if (raw is! Map) return null;
  final strings = raw['strings'];
  if (strings is! List || strings.isEmpty) return null;
  final pitches = <Pitch>[];
  for (final s in strings) {
    final pitch = _pitchFromJson(s);
    // One unreadable string would renumber every string after it, so the whole
    // tuning is refused instead — and a tab without a tuning is not a tab.
    if (pitch == null) return null;
    pitches.add(pitch);
  }
  final name = raw['name'];
  return Tuning(pitches, name: name is String ? name : null);
}

Pitch? _pitchFromJson(Object? raw) {
  if (raw is! Map) return null;
  final step = _enumByName(Step.values, raw['step']);
  if (step == null) return null;
  return Pitch(
    step,
    alter: _int(raw['alter']) ?? 0,
    octave: _int(raw['octave']) ?? 4,
    microtone: _enumByName(MicrotonalAccidental.values, raw['microtone']),
  );
}

TimeSignature? _timeFromJson(Object? raw) {
  if (raw is! Map) return null;
  final beats = _int(raw['beats']);
  final unit = _int(raw['beatUnit']);
  if (beats == null || unit == null) return null;
  // The constructor asserts on both, and an assert is a crash in debug: a
  // hand-edited file must not be able to take the app down.
  if (beats < 1 || unit < 1 || unit > 16 || (unit & (unit - 1)) != 0) {
    return null;
  }
  return TimeSignature(
    beats,
    unit,
    symbol: _enumByName(TimeSymbol.values, raw['symbol']) ?? TimeSymbol.numeric,
    components: _intList(raw['components']),
    alternate: _timeFromJson(raw['alternate']),
  );
}

KeySignature? _keyFromJson(Object? raw) {
  if (raw is! Map) return null;
  final custom = raw['custom'];
  if (custom is List && custom.isNotEmpty) {
    final accidentals = <KeyAccidental>[];
    for (final entry in custom) {
      if (entry is! Map) continue;
      final step = _enumByName(Step.values, entry['step']);
      final alter = _int(entry['alter']);
      if (step != null && alter != null) {
        accidentals.add(KeyAccidental(step, alter));
      }
    }
    if (accidentals.isNotEmpty) return KeySignature.custom(accidentals);
  }
  final fifths = _int(raw['fifths']);
  if (fifths == null || fifths < -7 || fifths > 7) return null;
  return KeySignature(fifths);
}

NoteDuration? _durationFromJson(Object? raw) {
  if (raw is! Map) return null;
  final base = _enumByName(DurationBase.values, raw['base']);
  if (base == null) return null;
  final dots = _int(raw['dots']) ?? 0;
  return NoteDuration(base, dots: dots < 0 || dots > 3 ? 0 : dots);
}

ChordDiagram? _chordFromJson(Object? raw) {
  if (raw is! Map) return null;
  final frets = _intList(raw['frets']);
  if (frets == null) return null;
  final fingersRaw = raw['fingers'];
  final name = raw['name'];
  return ChordDiagram(
    frets,
    name: name is String ? name : null,
    fingers: fingersRaw is List
        ? [for (final f in fingersRaw) f is num ? f.toInt() : null]
        : null,
    baseFret: _int(raw['baseFret']) ?? 1,
    fretSpan: _int(raw['fretSpan']) ?? 4,
    barreFret: _int(raw['barreFret']),
  );
}

List<BendPoint>? _bendsFromJson(Object? raw) {
  if (raw is! List) return null;
  final points = <BendPoint>[];
  for (final entry in raw) {
    if (entry is! List || entry.length != 2) continue;
    final offset = entry[0];
    final steps = entry[1];
    if (offset is! num || steps is! num) continue;
    points.add(BendPoint(offset.toDouble(), steps.toDouble()));
  }
  // An empty list is NOT the same as no curve: `bend: []` would mean "a curve
  // with no points", which the renderer would treat differently from "none".
  return points.isEmpty ? null : points;
}

// --- Small readers ----------------------------------------------------------

int? _int(Object? raw) => raw is num ? raw.toInt() : null;
double? _double(Object? raw) => raw is num ? raw.toDouble() : null;

List<int>? _intList(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final v in raw)
      if (v is num) v.toInt(),
  ];
}

/// The value of [values] whose `name` is [raw], or null.
///
/// Null for an unknown name is the whole degrade-one-field rule in one place: a
/// tab from a newer build loses the articulation it names and keeps the note.
T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

Set<T> _enumSet<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! List) return <T>{};
  return {
    for (final entry in raw)
      if (_enumByName(values, entry) case final v?) v,
  };
}

// --- Registration -----------------------------------------------------------

/// Teaches [Project] how to carry a tab.
///
/// Call once at start-up. It is a registration rather than a hardcoded case in
/// `project_codec.dart` because `TabDocument` reaches Flutter through
/// `crisp_notation`, and the project container is deliberately pure Dart.
void registerTabProjectCodec() {
  registerProjectDocumentCodec(
    ProjectDocumentCodec(
      kind: AppMode.tab,
      encode: (doc) =>
          doc is TabDocument ? {'tab': tabDocumentToJson(doc)} : null,
      decode: (json) {
        final tab = json['tab'];
        return tab is Map ? tabDocumentFromJson(tab) : null;
      },
    ),
  );
}
