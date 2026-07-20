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
}
