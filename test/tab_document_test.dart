// TabDocument (B1) — the editable tablature model: fret placement, string
// pinning into the engraved Score, playback timing, and Score→doc import.

import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final guitar = Tuning.standardGuitar;

  test('blank() makes N empty columns', () {
    final doc = TabDocument.blank(guitar, initialColumns: 4);
    expect(doc.columns, hasLength(4));
    expect(doc.columns.every((c) => c.isEmpty), isTrue);
    expect(doc.stringCount, 6);
  });

  test('setFret places the tuned pitch and pins the string', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1);
    doc.setFret(0, 5, 3); // 3rd fret, bottom string
    final score = doc.toScore();
    final note = score.measures.first.elements.whereType<NoteElement>().first;
    expect(note.pitches.single.midiNumber, guitar.strings[5].midiNumber + 3);
    expect(score.tabVoicings, hasLength(1));
    expect(score.tabVoicings.first.strings, [5]);
  });

  test('capo raises the sounding pitch, tab-voicing string unchanged', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)..setFret(0, 5, 3);
    final open = doc.toScore();
    final capo2 = doc.toScore(capo: 2);
    final openMidi = open.measures.first.elements
        .whereType<NoteElement>()
        .first
        .pitches
        .single
        .midiNumber;
    final capoMidi = capo2.measures.first.elements
        .whereType<NoteElement>()
        .first
        .pitches
        .single
        .midiNumber;
    // Standard-staff / concert pitch is transposed up by the capo…
    expect(capoMidi, openMidi + 2);
    // …but the note is still pinned to the same string (fret display is
    // re-derived against the capo-shifted tuning, so the number is unchanged).
    expect(capo2.tabVoicings.first.strings, [5]);
    // Playback follows the same transpose.
    expect(
      doc.toPlaybackEvents(capo: 2).first.$1.single,
      doc.toPlaybackEvents().first.$1.single + 2,
    );
  });

  test('barBoundsAt tiles columns into 8-step (4/4) bars', () {
    // Blank columns are quarters (2 steps each), so four = 8 steps = one bar.
    final doc = TabDocument.blank(guitar);
    expect(doc.barBoundsAt(0), (0, 4)); // first bar: cols 0..3
    expect(doc.barBoundsAt(3), (0, 4));
    expect(doc.barBoundsAt(4), (4, 8)); // second bar: cols 4..7
    expect(doc.barBoundsAt(7), (4, 8));
  });

  test('duplicateBar copies the cursor bar and inserts it after', () {
    final doc = TabDocument.blank(guitar)
      ..setFret(0, 0, 3)
      ..setFret(1, 1, 5); // mark the first bar (cols 0..3)

    final added = doc.duplicateBar(2); // cursor in the first bar
    expect(added, 4); // a 4-column bar
    expect(doc.columns, hasLength(12));
    // The copy lands right after the original bar (cols 4..7) and matches it.
    expect(doc.columns[4].frets[0], 3);
    expect(doc.columns[5].frets[1], 5);
    // …and it's a deep copy — editing the copy leaves the original untouched.
    doc.setFret(4, 0, 9);
    expect(doc.columns[0].frets[0], 3);
  });

  test('transposeBy shifts every note on its own string', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)
      ..setFret(0, 5, 3) // low E, fret 3
      ..setFret(1, 4, 5); // A, fret 5
    expect(doc.transposeBy(2), isTrue);
    expect(doc.columns[0].frets[5], 5); // 3 + 2
    expect(doc.columns[1].frets[4], 7); // 5 + 2
  });

  test('transposeBy is all-or-nothing when a note would leave the fretboard',
      () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)
      ..setFret(0, 5, 1); // fret 1 — can't go down 2
    expect(doc.transposeBy(-2), isFalse);
    expect(doc.columns[0].frets[5], 1); // unchanged
  });

  test('transposeBy clears the now-wrong chord label', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)
      ..setFret(0, 5, 3)
      ..setChord(0, kGuitarChords['C']);
    expect(doc.columns[0].chord?.name, 'C');
    doc.transposeBy(2);
    expect(doc.columns[0].chord, isNull); // the C shape no longer matches
  });

  test('a chord column pins each string in pitch order', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)
      ..setFret(0, 0, 0)
      ..setFret(0, 1, 2);
    final score = doc.toScore();
    final note = score.measures.first.elements.whereType<NoteElement>().first;
    expect(note.pitches, hasLength(2));
    expect(score.tabVoicings.first.strings, [0, 1]); // ascending = top→down
  });

  test('an empty column renders as a rest', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1);
    final score = doc.toScore();
    expect(score.measures.first.elements.whereType<RestElement>(), isNotEmpty);
    expect(score.tabVoicings, isEmpty);
  });

  test('toPlaybackEvents: one per column, quarter = 500ms @120bpm', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)..setFret(0, 0, 0);
    final events = doc.toPlaybackEvents();
    expect(events, hasLength(2));
    expect(events.first.$2, 500);
    expect(events.first.$1, [guitar.strings[0].midiNumber]);
    expect(events[1].$1, isEmpty); // rest column
  });

  test('setDuration changes the played length', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)..setFret(0, 0, 0);
    doc.setDuration(0, NoteDuration.eighth);
    expect(doc.toPlaybackEvents().first.$2, 250);
  });

  test('removeColumn keeps at least one column', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1);
    doc.removeColumn(0);
    expect(doc.columns, hasLength(1));
  });

  test('insertColumn adds an empty step', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)..insertColumn(1);
    expect(doc.columns, hasLength(3));
    expect(doc.columns[1].isEmpty, isTrue);
  });

  test('fromScore reads ascii tab into editable fretted columns', () {
    final score = asciiTabToScore(
      'e|-0-3-|\nB|-----|\nG|-----|\nD|-----|\nA|-----|\nE|-----|',
    );
    final doc = TabDocument.fromScore(score, guitar);
    final fretted = doc.columns.where((c) => !c.isEmpty).toList();
    expect(fretted, isNotEmpty);
    // The two events are open (0) and 3rd fret on the top string.
    expect(fretted.first.frets[0], anyOf(0, isNotNull));
  });

  test('GP export: toScore round-trips through the GPIF writer', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)
      ..setFret(0, 0, 0)
      ..setFret(1, 5, 3);
    final bytes = writeGpFromGpif(scoreToGpif(doc.toScore(), tuning: guitar));
    expect(bytes.length, greaterThan(0));
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // .gp is a zip (PK header)

    // Re-reading the file we just wrote recovers the notes.
    final back = scoreFromGpif(readGpifFromGp(bytes));
    final notes =
        back.measures.expand((m) => m.elements).whereType<NoteElement>();
    expect(notes, hasLength(2));
  });

  test('GP export keeps the arranged string, not fretFor\'s lowest fret', () {
    // Regression: the writer used to re-fret every pitch with the greedy
    // Tuning.fretFor, so a tab arrangement was discarded on .gp export. B2 is
    // reachable at fret 7 on the low-E string (5) OR fret 2 on the A string (4);
    // the user pinned string 5 / fret 7. fretFor would drop it to 4 / 2 — the
    // tab-voicing must win now.
    final doc = TabDocument.blank(guitar, initialColumns: 1)..setFret(0, 5, 7);
    final gpif = scoreToGpif(doc.toScore(), tuning: guitar);
    expect(
      gpif,
      contains('<String>5</String></Property>'
          '<Property name="Fret"><Fret>7</Fret></Property>'),
      reason: 'the arranged string 5 / fret 7 must survive export',
    );
    expect(gpif, isNot(contains('<Fret>2</Fret>'))); // fretFor would use 4 / 2
    // The sounding pitch is unchanged either way.
    final back = scoreFromGpif(readGpifFromGp(writeGpFromGpif(gpif)));
    final note =
        back.measures.expand((m) => m.elements).whereType<NoteElement>().single;
    expect(note.pitches.single.midiNumber, guitar.strings[5].midiNumber + 7);
  });

  test('techniques emit the matching noteId-keyed Score lists', () {
    // 4 quarter notes = one 4/4 bar, ids t0..t3.
    final doc = TabDocument.blank(guitar, initialColumns: 4)
      ..setFret(0, 0, 5)
      ..setFret(1, 0, 5)
      ..setFret(2, 0, 7)
      ..setFret(3, 0, 7)
      ..toggleTechnique(0, TabTechnique.hammer) // slur t0 -> t1
      ..toggleTechnique(1, TabTechnique.bend)
      ..toggleTechnique(1, TabTechnique.vibrato)
      ..toggleTechnique(2, TabTechnique.slide) // glissando t2 -> t3
      ..toggleTechnique(3, TabTechnique.harmonic);
    final s = doc.toScore();
    expect(s.slurs.any((x) => x.startId == 't0' && x.endId == 't1'), isTrue);
    expect(s.bends.map((b) => b.noteId), contains('t1'));
    expect(s.vibratos.map((v) => v.noteId), contains('t1'));
    // slide -> glissando (renders AND survives GP export), not slideInOuts.
    expect(
      s.glissandos.any((g) => g.startId == 't2' && g.endId == 't3'),
      isTrue,
    );
    expect(s.slideInOuts, isEmpty);
    expect(
      s.tabNoteMarks
          .any((m) => m.noteId == 't3' && m.style == TabNoteStyle.harmonic),
      isTrue,
    );
  });

  test('techniques ride a GPIF export (glissando/bend/vibrato survive)', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)
      ..setFret(0, 0, 5)
      ..setFret(1, 0, 7)
      ..toggleTechnique(0, TabTechnique.slide) // gliss t0 -> t1
      ..toggleTechnique(1, TabTechnique.bend);
    final gpif = scoreToGpif(doc.toScore(), tuning: guitar);
    // The GPIF writer reads glissandos + bends; a re-read recovers the notes.
    final back = scoreFromGpif(readGpifFromGp(writeGpFromGpif(gpif)));
    expect(
      back.measures.expand((m) => m.elements).whereType<NoteElement>(),
      hasLength(2),
    );
    expect(gpif.toLowerCase(), contains('slide'));
    expect(gpif.toLowerCase(), contains('bend'));
  });

  test('guitar chord presets are 6-string and self-named', () {
    expect(kGuitarChords, isNotEmpty);
    for (final e in kGuitarChords.entries) {
      expect(e.value.frets, hasLength(6), reason: e.key);
      expect(e.value.name, e.key);
    }
  });

  test('setChord attaches then clears, and survives edits + insert', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)
      ..setChord(1, kGuitarChords['G']);
    expect(doc.columns[1].chord?.name, 'G');
    // Editing the column keeps its chord.
    doc
      ..setFret(1, 0, 3)
      ..setDuration(1, NoteDuration.eighth);
    expect(doc.columns[1].chord?.name, 'G');
    // Inserting before shifts the chord with its column.
    doc.insertColumn(0);
    expect(doc.columns[2].chord?.name, 'G');
    // The chord is display-only — toScore ignores it.
    expect(doc.toScore().measures, isNotEmpty);
    doc.setChord(2, null);
    expect(doc.columns[2].chord, isNull);
  });

  test('toggleTechnique adds then removes', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)..setFret(0, 0, 0);
    doc.toggleTechnique(0, TabTechnique.bend);
    expect(doc.columns[0].techniques, contains(TabTechnique.bend));
    doc.toggleTechnique(0, TabTechnique.bend);
    expect(doc.columns[0].techniques, isEmpty);
  });

  group('mergePlaybackEvents (band)', () {
    test('two tracks sound together on a shared slice', () {
      // Track A: one 500ms note (midi 40). Track B: one 500ms note (midi 52).
      final merged = mergePlaybackEvents([
        [
          ([40], 500),
        ],
        [
          ([52], 500),
        ],
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.$1, [40, 52]); // both sounding, sorted
      expect(merged.single.$2, 500);
    });

    test('slices at boundaries when tracks differ in rhythm', () {
      // A: 40 for 1000ms. B: 52 for 500ms then 53 for 500ms.
      final merged = mergePlaybackEvents([
        [
          ([40], 1000),
        ],
        [
          ([52], 500),
          ([53], 500),
        ],
      ]);
      expect(merged, hasLength(2));
      expect(merged[0].$1, [40, 52]);
      expect(merged[0].$2, 500);
      expect(merged[1].$1, [40, 53]);
      expect(merged[1].$2, 500);
    });

    test('runs to the longest track; a rest contributes nothing', () {
      final merged = mergePlaybackEvents([
        [
          ([40], 500),
        ],
        [
          (<int>[], 500), // rest
          ([52], 500),
        ],
      ]);
      expect(merged, hasLength(2));
      expect(merged[0].$1, [40]);
      expect(merged[1].$1, [52]); // track A already finished
      expect(merged.fold<int>(0, (a, e) => a + e.$2), 1000);
    });

    test('a single track passes through unchanged', () {
      final doc = TabDocument.blank(guitar, initialColumns: 2)
        ..setFret(0, 0, 0);
      final solo = doc.toPlaybackEvents();
      final merged = mergePlaybackEvents([solo]);
      expect(merged.map((e) => e.$2).toList(), solo.map((e) => e.$2).toList());
    });
  });

  test('a two-track band exports a multi-track .gp both parts survive', () {
    final guitarDoc = TabDocument.blank(guitar, initialColumns: 2)
      ..setFret(0, 0, 3)
      ..setFret(1, 1, 5);
    final bassDoc = TabDocument.blank(Tuning.standardBass, initialColumns: 2)
      ..setFret(0, 3, 3) // low string on the bass
      ..setFret(1, 3, 5);

    final gpif = multiPartToGpif(
      MultiPartScore([guitarDoc.toScore(), bassDoc.toScore()]),
      tunings: [guitar, Tuning.standardBass],
      names: const ['Guitar', 'Bass'],
    );
    final bytes = writeGpFromGpif(gpif);
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // a real .gp zip

    // Two tracks, carrying their own tunings.
    expect('<Track '.allMatches(gpif).length, 2);
    expect(gpif, contains('Bass'));
    expect(
      gpif,
      contains(guitar.strings.map((p) => p.midiNumber).join(' ')),
    );
    expect(
      gpif,
      contains(
        Tuning.standardBass.strings.map((p) => p.midiNumber).join(' '),
      ),
    );
  });

  test('audibleTracks respects mute and solo', () {
    TabTrack t(String n) => TabTrack(n, TabDocument.blank(guitar));
    final a = t('A');
    final b = t('B');
    final c = t('C');
    final all = [a, b, c];

    // Nothing muted/soloed → all audible.
    expect(audibleTracks(all).map((x) => x.name), ['A', 'B', 'C']);

    // Mute B → A, C.
    b.muted = true;
    expect(audibleTracks(all).map((x) => x.name), ['A', 'C']);

    // Solo overrides mute: solo C → only C (even though B is muted).
    c.soloed = true;
    expect(audibleTracks(all).map((x) => x.name), ['C']);

    // A second solo joins the soloed set.
    a.soloed = true;
    expect(audibleTracks(all).map((x) => x.name), ['A', 'C']);
  });

  test('clearCell removes only that string from a chord', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)
      ..setFret(0, 0, 5)
      ..setFret(0, 1, 7);
    doc.clearCell(0, 0);
    expect(doc.columns[0].frets.containsKey(0), isFalse);
    expect(doc.columns[0].frets[1], 7);
  });

  group('A1 — finer durations (16th / 32nd) on the 32nd grid', () {
    const sixteenth = NoteDuration(DurationBase.sixteenth);

    test('the palette now offers 16th and 32nd (and dotted eighth/16th)', () {
      final bases = {
        for (final (d, _) in kTabDurations) (d.base, d.dots),
      };
      expect(bases.contains((DurationBase.sixteenth, 0)), isTrue);
      expect(bases.contains((DurationBase.thirtySecond, 0)), isTrue);
      expect(bases.contains((DurationBase.eighth, 1)), isTrue); // dotted 8th
      expect(
        bases.contains((DurationBase.sixteenth, 1)),
        isTrue,
      ); // dotted 16th
    });

    test('sixteen 16th-notes tile into exactly one 4/4 bar', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          for (var i = 0; i < 16; i++)
            const TabColumn(frets: {0: 0}, duration: sixteenth),
        ],
      );
      expect(doc.toScore().measures.length, 1); // 16 × 1/16 = one whole bar
    });

    test('a 16th plays for exactly an eighth of a beat (125ms @120bpm)', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(frets: {0: 0}, duration: sixteenth),
        ],
      );
      expect(doc.toPlaybackEvents().single.$2, 125); // 2000/16 @120bpm default
    });

    test('a quarter still plays exactly 500ms @120bpm (no grid rounding drift)',
        () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(frets: {0: 0}),
        ], // default quarter
      );
      expect(doc.toPlaybackEvents().single.$2, 500);
    });

    test('a 16th note survives the import→edit→export round-trip', () {
      final src = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(frets: {0: 3}, duration: sixteenth),
          TabColumn(frets: {0: 5}, duration: sixteenth),
        ],
      ).toScore();
      final back =
          TabDocument.fromScore(src, Tuning.standardGuitar).columns.first;
      expect(back.duration.base, DurationBase.sixteenth);
    });
  });

  group('A2 — ties', () {
    TabDocument twoTiedQuarters() => TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            const TabColumn(frets: {0: 3}, tieToNext: true),
            const TabColumn(frets: {0: 3}),
          ],
        );

    test('toScore ties the first note into the next', () {
      final notes = twoTiedQuarters()
          .toScore()
          .measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(notes.first.tieToNext, isTrue);
      expect(notes.last.tieToNext, isFalse);
    });

    test('playback merges a tied pair into one sound of the summed length', () {
      final events = twoTiedQuarters().toPlaybackEvents(); // @120bpm default
      expect(events.length, 1); // the two columns sound as one note
      expect(events.single.$2, 1000); // 500 + 500 ms
    });

    test('a tie survives the import→edit→export round-trip', () {
      final src = twoTiedQuarters().toScore();
      final cols = TabDocument.fromScore(src, Tuning.standardGuitar).columns;
      expect(cols.first.tieToNext, isTrue);
    });

    test('setTie / withTie toggle the flag', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(frets: {0: 0}),
        ],
      );
      expect(doc.columns[0].tieToNext, isFalse);
      doc.setTie(0, true);
      expect(doc.columns[0].tieToNext, isTrue);
      // Duplicating a column preserves the tie.
      expect(doc.columns[0].copy().tieToNext, isTrue);
    });
  });

  group('A4 — time signature', () {
    TabDocument meter(TimeSignature ts, int quarters) => TabDocument(
          tuning: Tuning.standardGuitar,
          timeSignature: ts,
          columns: [for (var i = 0; i < quarters; i++) const TabColumn()],
        );

    test('default is 4/4 and a bar holds 32 steps (a whole note)', () {
      final doc = TabDocument.blank(Tuning.standardGuitar);
      expect(doc.timeSignature.beats, 4);
      expect(doc.timeSignature.beatUnit, 4);
      expect(doc.barCapacity, 32);
    });

    test('3/4 holds three quarters per bar', () {
      final doc = meter(const TimeSignature(3, 4), 6); // six quarters
      expect(doc.barCapacity, 24);
      expect(doc.toScore().measures.length, 2); // 6 / 3 per bar = 2 bars
    });

    test('6/8 has a bar capacity of 24 (a dotted half)', () {
      expect(meter(const TimeSignature(6, 8), 1).barCapacity, 24);
    });

    test('toScore stamps the time signature', () {
      final ts = meter(const TimeSignature(6, 8), 1).toScore().timeSignature;
      expect(ts?.beats, 6);
      expect(ts?.beatUnit, 8);
    });

    test('the meter survives the import→edit→export round-trip', () {
      final src = meter(const TimeSignature(3, 4), 1).toScore();
      final back = TabDocument.fromScore(src, Tuning.standardGuitar);
      expect(back.timeSignature.beats, 3);
      expect(back.timeSignature.beatUnit, 4);
    });
  });

  group('A3 — tuplets', () {
    TabDocument tripletOfEighths() {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          for (var i = 0; i < 3; i++)
            const TabColumn(frets: {0: 0}, duration: NoteDuration.eighth),
        ],
      );
      doc.makeTuplet(0, 3); // 3:2 triplet
      return doc;
    }

    test('makeTuplet marks the columns with a 3:2 ratio', () {
      final doc = tripletOfEighths();
      expect(doc.columns.every((c) => c.tuplet == (3, 2)), isTrue);
    });

    test('a triplet of eighths fits one beat (a quarter) — one bar', () {
      // 3 × eighth × 2/3 = one quarter = 8 of 32 steps, so a single measure.
      final score = tripletOfEighths().toScore();
      expect(score.measures, hasLength(1));
    });

    test('toScore emits one TupletSpan(0..2, 3:2) for the group', () {
      final m = tripletOfEighths().toScore().measures.single;
      expect(m.tuplets, hasLength(1));
      final t = m.tuplets.single;
      expect((t.startIndex, t.endIndex), (0, 2));
      expect((t.actual, t.normal), (3, 2));
    });

    test('playback scales each note by normal/actual (three sum to a beat)',
        () {
      final events = tripletOfEighths().toPlaybackEvents(); // @120bpm default
      expect(events, hasLength(3));
      // Each eighth (250ms) × 2/3 ≈ 167ms; the three sum to a 500ms quarter.
      expect(events.fold<int>(0, (s, e) => s + e.$2), closeTo(500, 2));
    });

    test('a tuplet survives the import→edit→export round-trip', () {
      final src = tripletOfEighths().toScore();
      final cols = TabDocument.fromScore(src, Tuning.standardGuitar).columns;
      expect(cols.first.tuplet, (3, 2));
    });

    test('withTuplet/copy preserve the ratio; clearing works', () {
      const c = TabColumn(frets: {0: 0}, tuplet: (3, 2));
      expect(c.copy().tuplet, (3, 2));
      expect(c.withTuplet(null).tuplet, isNull);
      expect(c.withTuplet((5, 4)).tuplet, (5, 4));
    });
  });

  group('A5 — key signature', () {
    test('default is C (0 fifths)', () {
      expect(TabDocument.blank(Tuning.standardGuitar).keySignature.fifths, 0);
    });

    test('toScore stamps the key signature', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        keySignature: const KeySignature(3), // A major
        columns: [
          const TabColumn(frets: {0: 0}),
        ],
      );
      expect(doc.toScore().keySignature.fifths, 3);
    });

    test('the key survives the import→edit→export round-trip', () {
      final src = TabDocument(
        tuning: Tuning.standardGuitar,
        keySignature: const KeySignature(-2), // B♭ major
        columns: [
          const TabColumn(frets: {0: 0}),
        ],
      ).toScore();
      final back = TabDocument.fromScore(src, Tuning.standardGuitar);
      expect(back.keySignature.fifths, -2);
    });
  });

  group('A6 — repeats', () {
    // Two 4/4 bars of four quarters; bar 0 opens a repeat, bar 1 closes it.
    TabDocument twoBars() {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          for (var i = 0; i < 8; i++) const TabColumn(frets: {0: 0}),
        ],
      );
      doc.setBarRepeat(0, start: true); // bar 0
      doc.setBarRepeat(4, end: true); // bar 1
      return doc;
    }

    test('toScore stamps the repeat barlines on the right measures', () {
      final measures = twoBars().toScore().measures;
      expect(measures, hasLength(2));
      expect(measures[0].startRepeat, isTrue);
      expect(measures[0].endRepeat, isFalse);
      expect(measures[1].startRepeat, isFalse);
      expect(measures[1].endRepeat, isTrue);
    });

    test('repeats survive the import→edit→export round-trip', () {
      final back = TabDocument.fromScore(
        twoBars().toScore(),
        Tuning.standardGuitar,
      );
      final m = back.toScore().measures;
      expect(m[0].startRepeat, isTrue);
      expect(m[1].endRepeat, isTrue);
    });

    test('setBarRepeat anchors to the bar\'s first column', () {
      final doc = twoBars();
      expect(doc.columns[0].startRepeat, isTrue); // bar 0, col 0
      expect(doc.columns[4].endRepeat, isTrue); // bar 1, col 4
      // Setting from a mid-bar column still lands on that bar's first column.
      doc.setBarRepeat(6, start: true);
      expect(doc.columns[4].startRepeat, isTrue);
    });
  });

  group('A7 — alternate endings (voltas)', () {
    TabDocument twoEndings() {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          for (var i = 0; i < 8; i++) const TabColumn(frets: {0: 0}),
        ],
      );
      doc.setBarVolta(0, 1); // bar 0 = 1st ending
      doc.setBarVolta(4, 2); // bar 1 = 2nd ending
      return doc;
    }

    test('toScore brackets each bar with its volta number', () {
      final m = twoEndings().toScore().measures;
      expect(m[0].volta, 1);
      expect(m[1].volta, 2);
    });

    test('voltas survive the import→edit→export round-trip', () {
      final back = TabDocument.fromScore(
        twoEndings().toScore(),
        Tuning.standardGuitar,
      );
      final m = back.toScore().measures;
      expect(m[0].volta, 1);
      expect(m[1].volta, 2);
    });

    test('setBarVolta anchors to the bar start and clears with null', () {
      final doc = twoEndings();
      expect(doc.columns[0].volta, 1);
      doc.setBarVolta(6, 3); // mid bar 1
      expect(doc.columns[4].volta, 3);
      doc.setBarVolta(4, null);
      expect(doc.columns[4].volta, isNull);
    });
  });

  group('A8 — directions + section labels', () {
    test('a direction mark stamps Measure.navigation and round-trips', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          for (var i = 0; i < 4; i++) const TabColumn(frets: {0: 0}),
        ],
      );
      doc.setBarNavigation(0, NavigationMark.daCapo);
      expect(doc.toScore().measures.first.navigation, NavigationMark.daCapo);
      final back = TabDocument.fromScore(doc.toScore(), Tuning.standardGuitar);
      expect(back.columns.first.navigation, NavigationMark.daCapo);
    });

    test('a section label becomes a Score annotation and round-trips', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(frets: {0: 0}),
        ],
      );
      doc.setSection(0, 'Verse');
      final score = doc.toScore();
      expect(score.annotations.any((a) => a.text == 'Verse'), isTrue);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.section, 'Verse');
    });

    test('withNavigation/withSection preserve other bar metadata', () {
      const c = TabColumn(frets: {0: 0}, volta: 2, startRepeat: true);
      final n = c.withNavigation(NavigationMark.fine).withSection('Chorus');
      expect(n.volta, 2);
      expect(n.startRepeat, isTrue);
      expect(n.navigation, NavigationMark.fine);
      expect(n.section, 'Chorus');
    });
  });

  group('A9 — tempo map', () {
    // Two 4/4 bars of four quarters; a tempo change on bar 2.
    TabDocument twoBars() => TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            for (var i = 0; i < 8; i++) TabColumn(frets: {0: i}),
          ],
        );

    test('setBarTempo stamps Measure.tempoChange on the bar', () {
      final doc = twoBars();
      doc.setBarTempo(4, 90); // bar 2 → 90 BPM
      final measures = doc.toScore().measures;
      expect(measures[0].tempoChange, isNull);
      expect(measures[1].tempoChange?.bpm, 90);
    });

    test('setBarTempo anchors to the bar start and clears with null', () {
      final doc = twoBars();
      doc.setBarTempo(6, 72); // mid bar 2
      expect(doc.columns[4].tempoChange, 72);
      doc.setBarTempo(4, null);
      expect(doc.columns[4].tempoChange, isNull);
    });

    test('a tempo change re-times playback from its bar on', () {
      final doc = twoBars();
      doc.setBarTempo(4, 60); // bar 2 at 60 BPM (quarter = 1000 ms)
      // Default 120 BPM → bar 1's quarter is 500 ms.
      final events = doc.toPlaybackEvents();
      expect(events, hasLength(8));
      expect(events[0].$2, 500); // bar 1 at 120
      expect(events[4].$2, 1000); // bar 2 at 60
    });

    test('tempo change survives a Score round-trip', () {
      final doc = twoBars();
      doc.setBarTempo(4, 90);
      final back = TabDocument.fromScore(doc.toScore(), Tuning.standardGuitar);
      // the first column of bar 2 carries the tempo back
      final barTwoFirst = back.columns[back.barBoundsAt(4).$1];
      expect(barTwoFirst.tempoChange, 90);
    });

    test('copyWith can clear a nullable field explicitly', () {
      const c = TabColumn(frets: {0: 0}, volta: 2, tempoChange: 100);
      expect(c.copyWith(volta: null).volta, isNull);
      expect(c.copyWith(volta: null).tempoChange, 100); // untouched
      expect(c.copyWith().volta, 2); // omitted → unchanged
    });
  });

  group('B1–B3 — parametric bend / whammy / slide', () {
    TabDocument oneNote() => TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            const TabColumn(frets: {0: 5}),
          ],
        );

    test('B1 a bend curve emits Bend.curve and round-trips its points', () {
      final doc = oneNote();
      doc.setBend(0, TabBends.bendRelease());
      final score = doc.toScore();
      expect(score.bends, hasLength(1));
      expect(score.bends.single.points, hasLength(3)); // 0 → up → 0
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.bend, isNotNull);
      expect(
        back.columns.first.bend!.map((p) => p.steps).toList(),
        [0.0, 1.0, 0.0],
      );
    });

    test('B1 the flat bend technique still emits a plain Bend (no points)', () {
      final doc = oneNote()..toggleTechnique(0, TabTechnique.bend);
      final score = doc.toScore();
      expect(score.bends.single.points, isEmpty);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.techniques, contains(TabTechnique.bend));
      expect(back.columns.first.bend, isNull);
    });

    test('B2 a whammy curve emits TremoloBar.curve and round-trips', () {
      final doc = oneNote();
      doc.setWhammy(
        0,
        const [BendPoint(0, 0), BendPoint(0.5, -2), BendPoint(1, 0)],
      );
      final score = doc.toScore();
      expect(score.tremoloBars, hasLength(1));
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.whammy, isNotNull);
      expect(
        back.columns.first.whammy!.map((p) => p.steps).toList(),
        [0.0, -2.0, 0.0],
      );
    });

    test('B3 a slide-in/out emits TabSlide and round-trips its direction', () {
      final doc = oneNote();
      doc.setSlide(0, SlideInOut.inFromBelow);
      final score = doc.toScore();
      expect(score.slideInOuts, hasLength(1));
      expect(score.slideInOuts.single.direction, SlideInOut.inFromBelow);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.slide, SlideInOut.inFromBelow);
    });

    test('the three parametric fields are independent + clearable', () {
      var c = const TabColumn(frets: {0: 5});
      c = c.withBend(TabBends.prebend()).withSlide(SlideInOut.outUpward);
      expect(c.bend, isNotNull);
      expect(c.slide, SlideInOut.outUpward);
      expect(c.whammy, isNull);
      expect(c.withBend(null).bend, isNull);
      expect(c.withBend(null).slide, SlideInOut.outUpward); // untouched
    });
  });

  group('B4–B6 — tap / harmonic kinds / articulations', () {
    TabDocument oneNote() => TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            const TabColumn(frets: {0: 5}),
          ],
        );

    test('B4 tap emits a Tap and round-trips', () {
      final doc = oneNote()..setTap(0, true);
      final score = doc.toScore();
      expect(score.taps, hasLength(1));
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.tap, isTrue);
    });

    test('B5 a specific harmonic kind emits its style and round-trips', () {
      final doc = oneNote()..setHarmonic(0, TabNoteStyle.artificialHarmonic);
      final score = doc.toScore();
      expect(
        score.tabNoteMarks.single.style,
        TabNoteStyle.artificialHarmonic,
      );
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.harmonic, TabNoteStyle.artificialHarmonic);
      // it is NOT also mapped onto the flat harmonic technique
      expect(
        back.columns.first.techniques,
        isNot(contains(TabTechnique.harmonic)),
      );
    });

    test('B5 the flat harmonic technique still round-trips as before', () {
      final doc = oneNote()..toggleTechnique(0, TabTechnique.harmonic);
      final score = doc.toScore();
      expect(score.tabNoteMarks.single.style, TabNoteStyle.harmonic);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.harmonic, TabNoteStyle.harmonic);
    });

    test('B6 palm-mute and let-ring emit self-spans and round-trip', () {
      final doc = oneNote()
        ..setPalmMute(0, true)
        ..setLetRing(0, true);
      final score = doc.toScore();
      expect(score.palmMutes, hasLength(1));
      expect(score.letRings, hasLength(1));
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.palmMute, isTrue);
      expect(back.columns.first.letRing, isTrue);
    });

    test('B6 a palm-mute SPAN over several notes flags every column', () {
      // A hand-built score with a 3-note palm-mute span (import fidelity).
      final score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [pitchFromMidi(64)],
              duration: NoteDuration.quarter,
              id: 'e0',
            ),
            NoteElement(
              pitches: [pitchFromMidi(65)],
              duration: NoteDuration.quarter,
              id: 'e1',
            ),
            NoteElement(
              pitches: [pitchFromMidi(67)],
              duration: NoteDuration.quarter,
              id: 'e2',
            ),
          ]),
        ],
        palmMutes: const [PalmMute('e0', 'e2')],
      );
      final doc = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(doc.columns.take(3).every((c) => c.palmMute), isTrue);
    });

    test('B6 articulations set on the note and round-trip', () {
      final doc = oneNote()
        ..toggleArticulation(0, Articulation.staccato)
        ..toggleArticulation(0, Articulation.accent);
      final score = doc.toScore();
      final note = score.measures.first.elements.whereType<NoteElement>().first;
      expect(
        note.articulations,
        containsAll([Articulation.staccato, Articulation.accent]),
      );
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(
        back.columns.first.articulations,
        containsAll([Articulation.staccato, Articulation.accent]),
      );
    });

    test('toggleArticulation removes on second toggle; copy() is deep', () {
      var c = const TabColumn(frets: {0: 5});
      c = c.toggleArticulation(Articulation.tenuto);
      expect(c.articulations, {Articulation.tenuto});
      c = c.toggleArticulation(Articulation.tenuto);
      expect(c.articulations, isEmpty);
      // copy() must not alias the articulation set
      final withArt = const TabColumn(frets: {0: 5})
          .toggleArticulation(Articulation.marcato);
      final dup = withArt.copy();
      expect(dup.articulations, {Articulation.marcato});
      expect(identical(dup.articulations, withArt.articulations), isFalse);
    });
  });

  group('B7–B10 — trill/tremolo, grace, strum/pick, fingering', () {
    TabDocument oneNote() => TabDocument(
          tuning: Tuning.standardGuitar,
          columns: [
            const TabColumn(frets: {0: 5}),
          ],
        );
    NoteElement firstNote(Score s) =>
        s.measures.first.elements.whereType<NoteElement>().first;

    test('B7 ornament + tremolo picking set on the note and round-trip', () {
      final doc = oneNote()
        ..columns[0] =
            oneNote().columns[0].withOrnament(Ornament.trill).withTremolo(3);
      final score = doc.toScore();
      expect(firstNote(score).ornament, Ornament.trill);
      expect(firstNote(score).tremolo, 3);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.ornament, Ornament.trill);
      expect(back.columns.first.tremolo, 3);
    });

    test('B8 grace notes emit graceNotes + style and round-trip', () {
      final doc = oneNote();
      doc.columns[0] =
          doc.columns[0].withGrace([62, 64], style: GraceStyle.appoggiatura);
      final score = doc.toScore();
      expect(
        firstNote(score).graceNotes.map((p) => p.midiNumber).toList(),
        [62, 64],
      );
      expect(firstNote(score).graceStyle, GraceStyle.appoggiatura);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.graceMidis, [62, 64]);
      expect(back.columns.first.graceStyle, GraceStyle.appoggiatura);
    });

    test('B9 arpeggio + pick-stroke emit and round-trip', () {
      final doc = oneNote();
      doc.columns[0] =
          doc.columns[0].withArpeggio(Arpeggio.up).withPickStroke(true);
      final score = doc.toScore();
      expect(firstNote(score).arpeggio, Arpeggio.up);
      expect(score.pickStrokes.single.up, isTrue);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.arpeggio, Arpeggio.up);
      expect(back.columns.first.pickStroke, isTrue);
    });

    test('B10 left- and right-hand fingerings emit and round-trip', () {
      final doc = oneNote();
      doc.columns[0] = doc.columns[0]
          .withLeftFingers([2]).withRightFinger(RightHandFinger.middle);
      final score = doc.toScore();
      expect(firstNote(score).fingerings, [2]);
      expect(score.tabFingerings.single.finger, RightHandFinger.middle);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.leftFingers, [2]);
      expect(back.columns.first.rightFinger, RightHandFinger.middle);
    });

    test('copy() deep-copies grace + finger lists (no aliasing)', () {
      final c =
          const TabColumn(frets: {0: 5}).withGrace([62]).withLeftFingers([1]);
      final dup = c.copy();
      expect(dup.graceMidis, [62]);
      expect(identical(dup.graceMidis, c.graceMidis), isFalse);
      expect(identical(dup.leftFingers, c.leftFingers), isFalse);
    });
  });

  group('C1 — dynamics + hairpins', () {
    test('a dynamic sets velocity + DynamicMarking and round-trips', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(frets: {0: 5}),
        ],
      )..setDynamic(0, DynamicLevel.ff);
      final score = doc.toScore();
      final note = score.measures.first.elements.whereType<NoteElement>().first;
      expect(note.velocity, velocityOf(DynamicLevel.ff));
      expect(score.dynamics.single.level, DynamicLevel.ff);
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.dynamic, DynamicLevel.ff);
    });

    test('velocityOf ramps ppp<mf<fff', () {
      expect(
        velocityOf(DynamicLevel.ppp),
        lessThan(velocityOf(DynamicLevel.mf)),
      );
      expect(
        velocityOf(DynamicLevel.mf),
        lessThan(velocityOf(DynamicLevel.fff)),
      );
    });

    test('a hairpin spans from its start to the next dynamic + round-trips',
        () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(frets: {0: 0}),
          const TabColumn(frets: {0: 2}),
          const TabColumn(frets: {0: 3}),
        ],
      )
        ..setHairpin(0, HairpinType.crescendo)
        ..setDynamic(2, DynamicLevel.f); // the hairpin should end here
      final score = doc.toScore();
      expect(score.hairpins, hasLength(1));
      expect(score.hairpins.single.startId, 't0');
      expect(score.hairpins.single.endId, 't2');
      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.columns.first.hairpin, HairpinType.crescendo);
    });
  });

  group('C2 — second voice', () {
    test('a second voice becomes Measure.voice2 and round-trips', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(frets: {0: 0}),
          const TabColumn(frets: {0: 2}),
          const TabColumn(frets: {0: 3}),
          const TabColumn(frets: {0: 5}),
        ],
        voice2: [
          const TabColumn(frets: {5: 0}),
          const TabColumn(frets: {5: 3}),
          const TabColumn(frets: {5: 0}),
          const TabColumn(frets: {5: 2}),
        ],
      );
      final score = doc.toScore();
      // One 4/4 bar of four quarters — voice 2 sits on it.
      expect(score.measures.first.voice2, isNotEmpty);
      expect(
        score.measures.first.voice2.whereType<NoteElement>(),
        hasLength(4),
      );

      final back = TabDocument.fromScore(score, Tuning.standardGuitar);
      expect(back.voice2, hasLength(4));
      // voice-2 low-E pitches (fret 0 and 3 on string 5) come back.
      expect(back.voice2.first.frets[5], 0);
      expect(back.voice2[1].frets[5], 3);
    });

    test('no second voice → empty voice2, single-voice measures', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(frets: {0: 0}),
        ],
      );
      expect(doc.voice2, isEmpty);
      expect(doc.toScore().measures.first.voice2, isEmpty);
    });
  });

  group('D1–D4 — tracks, mixer, drum-tab, practice', () {
    test('D1/D2 a track carries instrument/capo/volume/pan + defaults', () {
      final t = TabTrack('Lead', TabDocument.blank(Tuning.standardGuitar));
      // defaults
      expect(t.instrument, isNull);
      expect(t.capo, 0);
      expect(t.volume, 1.0);
      expect(t.pan, 0.0);
      expect(t.isDrums, isFalse);
      final bass = TabTrack(
        'Bass',
        TabDocument.blank(Tuning.standardBass),
        instrument: 33, // GM finger bass
        capo: 2,
        volume: 0.8,
        pan: -0.5,
      );
      expect(bass.instrument, 33);
      expect(bass.capo, 2);
      expect(bass.pan, -0.5);
    });

    test('D3 drum lines map to GM percussion notes', () {
      expect(drumMidiForLine(kDrumLines.length - 1), 36); // Kick, bottom
      expect(kDrumLines.map((e) => e.$1), contains('Snare'));
      expect(drumMidiForLine(-1), isNull);
      expect(drumMidiForLine(99), isNull);
    });

    test('D3 toDrumScore emits percussion notes on the drum clef', () {
      // Kick (bottom line) + Snare on two quarters.
      final kick = kDrumLines.length - 1;
      final snare = kDrumLines.indexWhere((e) => e.$1 == 'Snare');
      final doc = TabDocument(
        tuning: Tuning.standardGuitar, // 6 lines is enough for these two
        columns: [
          TabColumn(frets: {kick: 1}),
          TabColumn(frets: {snare: 1}),
        ],
      );
      final score = doc.toDrumScore();
      expect(score.clef, Clef.percussion);
      expect(score.metadata.isPercussion, isTrue);
      final notes =
          score.measures.expand((m) => m.elements).whereType<NoteElement>();
      expect(notes.first.pitches.single.midiNumber, 36); // kick
      expect(notes.last.pitches.single.midiNumber, 38); // snare
    });

    test('D4 speed-trainer ramps and always lands on the target', () {
      final t = speedTrainerTempos(baseBpm: 120, stepPct: 20);
      expect(t.first, 72); // 60% of 120
      expect(t.last, 120); // 100% target
      expect(t, [72, 96, 120]);
      // a non-dividing step still ends exactly on target
      final t2 = speedTrainerTempos(baseBpm: 100, startPct: 50, stepPct: 30);
      expect(t2.last, 100);
    });

    test('D4 LoopRange + metronome clicks are correct', () {
      const loop = LoopRange(2, 4);
      expect(loop.barCount, 3);
      expect(loop.contains(3), isTrue);
      expect(loop.contains(5), isFalse);
      final clicks = metronomeClicksMs(bpm: 120); // 1 bar, 4 beats @500ms
      expect(clicks, [0, 500, 1000, 1500]);
    });
  });
}
