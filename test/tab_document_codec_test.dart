// WS-L11 — a lossless TabDocument codec.
//
// Tab was the only mode that could not save what it IS. `saveToSongBook` goes
// through MusicXML, which keeps the pitches and drops the tuning, the strings,
// the frets and every technique — so a saved tab came back as a melody. There
// was no `toJson`/`fromJson` anywhere, and `daw_clip_source_codec` had no `tab`
// kind, so a tab could not live in a Project or be a DAW clip model either.
//
// The failure mode this file is built around is NOT "the codec is wrong". It is
// "the codec is a year old and TabColumn grew four fields". That is what
// actually happens to save formats, it is silent, and the loss only shows up
// when a player reopens their work. So the central test populates EVERY field
// and asserts the whole column round-trips equal, and a second test asserts the
// codec's own key list matches `TabColumn`'s constructor — add a field without
// touching the codec and this suite fails instead of the file quietly shrinking.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_document_codec.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A column with EVERY field set to something non-default.
///
/// The point of this fixture is to be exhaustive rather than realistic — no
/// player writes a note that is simultaneously tapped, palm-muted and a
/// harmonic. Realism would leave fields at their defaults, and a default is
/// exactly what a dropped field looks like.
const _loaded = TabColumn(
  frets: {0: 3, 1: 5, 2: 7},
  duration: NoteDuration(DurationBase.eighth, dots: 1),
  techniques: {TabTechnique.hammer, TabTechnique.vibrato},
  chord: ChordDiagram(
    [3, 2, 0, 0, 0, 3],
    name: 'G',
    fingers: [3, 2, null, null, null, 4],
    baseFret: 2,
    fretSpan: 5,
    barreFret: 3,
  ),
  tieToNext: true,
  tuplet: (3, 2),
  startRepeat: true,
  endRepeat: true,
  volta: 2,
  navigation: NavigationMark.dalSegno,
  section: 'Chorus',
  tempoChange: 132.5,
  bend: [BendPoint(0, 0), BendPoint(0.5, 2), BendPoint(1, 0)],
  whammy: [BendPoint(0, 0), BendPoint(1, -2)],
  slide: SlideInOut.inFromBelow,
  tap: true,
  harmonic: TabNoteStyle.artificialHarmonic,
  palmMute: true,
  letRing: true,
  articulations: {Articulation.staccato, Articulation.accent},
  ornament: Ornament.mordent,
  tremolo: 2,
  graceMidis: [58, 59],
  graceStyle: GraceStyle.appoggiatura,
  arpeggio: Arpeggio.up,
  pickStroke: true,
  leftFingers: [1, 3, 4],
  rightFinger: RightHandFinger.middle,
  // ⚠️ COLUMN-level barre, which is NOT the `barreFret` inside the TabChord
  // above — that one is part of the chord shape. These two were declared on
  // TabColumn, listed in `tabColumnFieldKeys`, and never written by the codec:
  // a saved barre was silently dropped. The completeness test below caught the
  // missing KEY, but nothing could catch the missing WRITE, because the
  // round-trip test asserts field by field and nobody added these two lines.
  barreFret: 5,
  barreString: 4,
  dynamic: DynamicLevel.ff,
  hairpin: HairpinType.crescendo,
);

TabDocument _doc() => TabDocument(
      tuning: Tuning.standardGuitar,
      columns: [
        _loaded,
        const TabColumn(frets: {0: 0}),
        const TabColumn(),
      ],
      timeSignature: const TimeSignature(7, 8),
      keySignature: const KeySignature(-3),
      voice2: [
        const TabColumn(frets: {5: 3}),
      ],
    );

TabDocument _roundTrip(TabDocument doc) =>
    tabDocumentFromJson(jsonDecode(jsonEncode(tabDocumentToJson(doc))))!;

void main() {
  setUp(resetProjectDocumentCodecs);

  group('the whole document survives', () {
    test('tuning, meter, key and both voices', () {
      final back = _roundTrip(_doc());
      expect(back.tuning.strings.length, 6);
      expect(
        back.tuning.strings.map((p) => p.midiNumber),
        Tuning.standardGuitar.strings.map((p) => p.midiNumber),
      );
      expect(back.tuning.name, Tuning.standardGuitar.name);
      expect(back.timeSignature.beats, 7);
      expect(back.timeSignature.beatUnit, 8);
      expect(back.keySignature.fifths, -3);
      expect(back.columns.length, 3);
      expect(back.voice2.length, 1);
      expect(back.voice2.single.frets, {5: 3});
    });

    test('a scordatura tuning survives, which MusicXML never did', () {
      // The concrete thing that was lost before: drop-D is a different
      // instrument, and the old save route could not say so.
      const dropD = Tuning(
        [
          Pitch(Step.e),
          Pitch(Step.b, octave: 3),
          Pitch(Step.g, octave: 3),
          Pitch(Step.d, octave: 3),
          Pitch(Step.a, octave: 2),
          Pitch(Step.d, octave: 2),
        ],
        name: 'Drop D',
      );
      final back = _roundTrip(
        TabDocument(
          tuning: dropD,
          columns: [
            const TabColumn(frets: {5: 0}),
          ],
        ),
      );
      expect(back.tuning.name, 'Drop D');
      expect(
        back.tuning.strings.last.midiNumber,
        const Pitch(Step.d, octave: 2).midiNumber,
      );
    });

    test('the FRETS survive — not just the pitches', () {
      // The same note can be played in several places, and which one is the
      // whole content of a tab. MusicXML kept the pitch and lost the choice.
      final back = _roundTrip(
        TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            const TabColumn(frets: {2: 9}),
          ],
        ),
      );
      expect(back.columns.single.frets, {2: 9});
    });
  });

  group('every TabColumn field round-trips', () {
    // One test per field would be thirty tests that all pass while a thirty-
    // first field is dropped. This asserts the object.
    test('a fully-populated column comes back EQUAL', () {
      final back = _roundTrip(_doc()).columns.first;
      expect(back.frets, _loaded.frets);
      expect(back.duration.base, _loaded.duration.base);
      expect(back.duration.dots, _loaded.duration.dots);
      expect(back.techniques, _loaded.techniques);
      expect(back.chord, _loaded.chord);
      expect(back.tieToNext, isTrue);
      expect(back.tuplet, (3, 2));
      expect(back.startRepeat, isTrue);
      expect(back.endRepeat, isTrue);
      expect(back.volta, 2);
      expect(back.navigation, NavigationMark.dalSegno);
      expect(back.section, 'Chorus');
      expect(back.tempoChange, 132.5);
      expect(back.bend?.length, 3);
      expect(back.bend?[1].offset, 0.5);
      expect(back.bend?[1].steps, 2);
      expect(back.whammy?.last.steps, -2);
      expect(back.slide, SlideInOut.inFromBelow);
      expect(back.tap, isTrue);
      expect(back.harmonic, TabNoteStyle.artificialHarmonic);
      expect(back.palmMute, isTrue);
      expect(back.letRing, isTrue);
      expect(back.articulations, _loaded.articulations);
      expect(back.ornament, Ornament.mordent);
      expect(back.tremolo, 2);
      expect(back.graceMidis, [58, 59]);
      expect(back.graceStyle, GraceStyle.appoggiatura);
      expect(back.arpeggio, Arpeggio.up);
      expect(back.pickStroke, isTrue);
      expect(back.leftFingers, [1, 3, 4]);
      expect(back.rightFinger, RightHandFinger.middle);
      expect(back.dynamic, DynamicLevel.ff);
      expect(back.hairpin, HairpinType.crescendo);
      // The two that were missing. This assertion is the ONLY thing standing
      // between a declared field and a silent data loss on save: the key-list
      // check above proves the codec KNOWS about a field, not that it writes
      // one. Remove either line below and dropping the codec entry goes
      // unnoticed again.
      expect(back.barreFret, 5, reason: 'a saved barre must survive');
      expect(back.barreString, 4);
    });

    test('the codec knows about every field TabColumn declares', () {
      // The guard against the real failure mode: TabColumn grows, the codec
      // does not, and saves start losing the new field silently. Read the
      // constructor's named parameters out of the source and compare.
      final source = File(
        'lib/features/games/composition/tab_document.dart',
      ).readAsStringSync();
      final start = source.indexOf('  const TabColumn({');
      expect(start, greaterThan(0), reason: 'TabColumn constructor moved');
      final end = source.indexOf('});', start);
      final params = <String>[];
      for (final line in source.substring(start, end).split('\n')) {
        final match = RegExp(r'this\.(\w+)').firstMatch(line);
        if (match != null) params.add(match.group(1)!);
      }
      expect(params.length, greaterThan(25), reason: 'parse failed');
      expect(
        params.toSet().difference(tabColumnFieldKeys.toSet()),
        isEmpty,
        reason: 'TabColumn gained a field the codec does not write — a save '
            'would silently drop it. Add it to _columnToJson, '
            '_columnFromJson and tabColumnFieldKeys.',
      );
      expect(
        tabColumnFieldKeys.toSet().difference(params.toSet()),
        isEmpty,
        reason: 'the codec writes a key TabColumn no longer has',
      );
    });
  });

  group('defaults stay out of the file', () {
    test('an empty column writes nothing at all', () {
      final json = tabDocumentToJson(
        TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [const TabColumn()],
        ),
      );
      expect((json['columns'] as List).single, isEmpty);
    });

    test('a plain note writes only what it is', () {
      final json = tabDocumentToJson(
        TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            const TabColumn(frets: {0: 3}),
          ],
        ),
      );
      expect((json['columns'] as List).single, {
        'frets': {'0': 3},
      });
      expect(json.containsKey('time'), isFalse, reason: '4/4 is the default');
      expect(json.containsKey('key'), isFalse, reason: 'C is the default');
      expect(json.containsKey('voice2'), isFalse);
    });

    test('a long tab stays small', () {
      // The reason defaults are omitted at all: a three-minute piece is
      // hundreds of columns, and thirty keys each would be unreadable.
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          for (var i = 0; i < 200; i++) TabColumn(frets: {i % 6: i % 12}),
        ],
      );
      expect(jsonEncode(tabDocumentToJson(doc)).length, lessThan(6000));
    });
  });

  group('a damaged or foreign file degrades, it does not explode', () {
    test('a non-document is refused', () {
      expect(tabDocumentFromJson(null), isNull);
      expect(tabDocumentFromJson('nope'), isNull);
      expect(tabDocumentFromJson(<String, dynamic>{}), isNull);
      expect(
        tabDocumentFromJson({'v': 1, 'columns': []}),
        isNull,
        reason: 'a tab without a tuning is not a tab',
      );
      expect(
        tabDocumentFromJson({'v': 99, 'tuning': _tuningJson()}),
        isNull,
        reason: 'a version this build cannot read',
      );
    });

    test('an unreadable column becomes an EMPTY one, not a missing one', () {
      // Dropping it would shift every column after it, turning one bad note
      // into a rhythm that is wrong from there to the end.
      final doc = tabDocumentFromJson({
        'v': 1,
        'tuning': _tuningJson(),
        'columns': [
          {
            'frets': {'0': 1},
          },
          'not a column',
          {
            'frets': {'0': 3},
          },
        ],
      })!;
      expect(doc.columns.length, 3);
      expect(doc.columns[0].frets, {0: 1});
      expect(doc.columns[1].frets, isEmpty);
      expect(doc.columns[2].frets, {0: 3});
    });

    test('an unknown enum name loses that FIELD, not the note', () {
      final doc = tabDocumentFromJson({
        'v': 1,
        'tuning': _tuningJson(),
        'columns': [
          {
            'frets': {'0': 5},
            'ornament': 'quintuple-backflip',
            'articulations': ['staccato', 'from-the-future'],
            'dynamic': 'fortississississimo',
          },
        ],
      })!;
      final c = doc.columns.single;
      expect(c.frets, {0: 5}, reason: 'the note survived');
      expect(c.ornament, isNull);
      expect(c.dynamic, isNull);
      expect(c.articulations, {Articulation.staccato});
    });

    test('an impossible time signature is refused rather than asserted on', () {
      // TimeSignature asserts on both fields, and an assert is a crash in
      // debug — a hand-edited file must not be able to take the app down.
      for (final time in [
        {'beats': 0, 'beatUnit': 4},
        {'beats': 4, 'beatUnit': 5},
        {'beats': 4, 'beatUnit': 0},
        {'beats': 4, 'beatUnit': 32},
      ]) {
        final doc = tabDocumentFromJson({
          'v': 1,
          'tuning': _tuningJson(),
          'columns': [],
          'time': time,
        })!;
        expect(doc.timeSignature, TimeSignature.fourFour, reason: '$time');
      }
    });

    test('an out-of-range key signature falls back to C', () {
      final doc = tabDocumentFromJson({
        'v': 1,
        'tuning': _tuningJson(),
        'columns': [],
        'key': {'fifths': 40},
      })!;
      expect(doc.keySignature.fifths, 0);
    });

    test('an empty bend list is no curve, not a curve with no points', () {
      final doc = tabDocumentFromJson({
        'v': 1,
        'tuning': _tuningJson(),
        'columns': [
          {'bend': <dynamic>[]},
        ],
      })!;
      expect(doc.columns.single.bend, isNull);
    });
  });

  group('it teaches Project how to carry a tab', () {
    test('a tab track round-trips inside a project', () {
      // The gap WS-W1 left open, closed. Before this the track survived with
      // its name and mix and no music at all.
      registerTabProjectCodec();
      final project = Project(
        name: 'With a tab',
        tracks: [
          ProjectTrack(
            id: 'tab-1',
            kind: AppMode.tab,
            name: 'Riff',
            document: _doc(),
          ),
        ],
      );
      final back = projectFromJsonString(projectToJsonString(project))!;
      final track = back.track('tab-1')!;
      expect(track.isReadable, isTrue);
      final doc = track.document as TabDocument;
      expect(doc.columns.first.frets, _loaded.frets);
      expect(doc.tuning.strings.length, 6);
      expect(doc.timeSignature.beats, 7);
    });

    test('without registering, the track still survives as unreadable', () {
      // The registry's promise, stated from the other side: a project written
      // by a build that HAS the tab codec, opened by one that does not.
      final project = Project(
        tracks: [ProjectTrack(id: 'tab-1', kind: AppMode.tab, name: 'Riff')],
      );
      final back = projectFromJsonString(projectToJsonString(project))!;
      expect(back.track('tab-1')!.name, 'Riff');
      expect(back.track('tab-1')!.document, isNull);
    });
  });
}

Map<String, dynamic> _tuningJson() => {
      'strings': [
        for (final p in Tuning.standardGuitar.strings)
          {
            'step': p.step.name,
            if (p.alter != 0) 'alter': p.alter,
            if (p.octave != 4) 'octave': p.octave,
          },
      ],
    };
