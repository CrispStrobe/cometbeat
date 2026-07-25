// test/tab_tracker_interop_test.dart
//
// C1 — Tab <-> Tracker.
//
// The claim being tested is specific: going through the Tracker must not cost
// you your fingering. The old route (Tab -> Score -> Tracker) carries pitches
// only, so the string/fret choice is re-derived on the way home; the direct
// route maps one channel per string, so it survives natively.
//
// The headline test is ROUND-TRIP IDENTITY with the side-car — frets,
// techniques, durations, tuning, capo, repeats and sections all come back. The
// second group covers the no-side-car case, which must still produce a usable
// tab and say honestly what it approximated.

// The fixture spells out every column's duration, including the ones that
// happen to match the default — the whole point of these tests is which note
// value each column carries, so leaving some implicit would hide the fixture.
// ignore_for_file: avoid_redundant_argument_values

import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kFxTonePorta, kFxVibrato;
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/core/interop/tab_tracker.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

TabDocument _riff() => TabDocument(
      tuning: Tuning.standardGuitar,
      columns: const [
        // A plain quarter on the low E string.
        TabColumn(frets: {5: 3}, duration: NoteDuration.quarter),
        // An eighth with a slide.
        TabColumn(
          frets: {4: 5},
          duration: NoteDuration.eighth,
          techniques: {TabTechnique.slide},
        ),
        // A two-string chord with vibrato, and a section label.
        TabColumn(
          frets: {0: 12, 1: 12},
          duration: NoteDuration.eighth,
          techniques: {TabTechnique.vibrato},
          section: 'Chorus',
        ),
        // A half note with a hammer-on (no tracker command for it).
        TabColumn(
          frets: {3: 7},
          duration: NoteDuration.half,
          techniques: {TabTechnique.hammer},
        ),
        // A rest column — no frets at all.
        TabColumn(duration: NoteDuration.quarter),
      ],
    );

void main() {
  group('tab -> tracker', () {
    test('one channel per string, in tab order', () {
      final result = trackerSongFromTabDocument(_riff());
      expect(result.song.channels, hasLength(6));
      expect(result.song.channels.first.id, 'string1');
      expect(result.song.channels.last.id, 'string6');
    });

    test('the fingering survives NATIVELY — channel index IS the string', () {
      final doc = _riff();
      final result = trackerSongFromTabDocument(doc);
      // Column 0: string 5 (low E, midi 40) at fret 3 -> G2, midi 43, and it
      // must be on CHANNEL 5, not wherever a re-fretting would have put it.
      final lowE = result.song.channels[5];
      expect(lowE.cells[0].midi, 43);
      // No other channel sounds on row 0.
      for (var s = 0; s < 6; s++) {
        if (s == 5) continue;
        expect(result.song.channels[s].cells[0].midi, isNull, reason: 'ch $s');
      }
    });

    test('a chord lands on its own two strings simultaneously', () {
      final result = trackerSongFromTabDocument(_riff());
      // Columns: quarter(8 steps) + eighth(4) = row 12 at stepsPerBeat 8.
      const row = 12;
      expect(result.song.channels[0].cells[row].midi, 64 + 12);
      expect(result.song.channels[1].cells[row].midi, 59 + 12);
    });

    test('capo raises the sounding pitch and is recorded for the way back', () {
      final open = trackerSongFromTabDocument(_riff());
      final capoed = trackerSongFromTabDocument(_riff(), capo: 2);
      expect(
        capoed.song.channels[5].cells[0].midi,
        open.song.channels[5].cells[0].midi! + 2,
      );
      expect(capoed.annotations.docMeta[AnnotationKeys.capo], 2);
    });

    test('techniques with a tracker equivalent become effect commands', () {
      final result = trackerSongFromTabDocument(_riff());
      // The slide is at row 8 on string 4.
      expect(result.song.channels[4].cells[8].fxCmd, kFxTonePorta);
      // The vibrato chord is at row 12.
      expect(result.song.channels[0].cells[12].fxCmd, kFxVibrato);
      // The hammer-on has no command — it lives only in the side-car.
      expect(result.song.channels[3].cells[16].fxCmd, 0);
    });

    test('the report names what the tracker could not hold', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: [
          const TabColumn(
            frets: {5: 3},
            duration: NoteDuration.quarter,
            startRepeat: true,
          ),
        ],
      );
      final result = trackerSongFromTabDocument(doc);
      expect(result.report.lossless, isFalse);
      expect(result.report.lost, contains('repeat structure and voltas'));
    });

    test('an empty document still yields a valid one-row song', () {
      final result = trackerSongFromTabDocument(
        TabDocument(tuning: Tuning.standardGuitar),
      );
      expect(result.song.channels, hasLength(6));
      expect(result.song.channels.first.cells, hasLength(1));
    });
  });

  group('round-trip identity (with the side-car)', () {
    test('frets and strings come back exactly', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;

      expect(back.columns, hasLength(doc.columns.length));
      for (var i = 0; i < doc.columns.length; i++) {
        expect(back.columns[i].frets, doc.columns[i].frets, reason: 'col $i');
      }
    });

    test('durations come back exactly', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;
      for (var i = 0; i < doc.columns.length; i++) {
        expect(
          back.columns[i].duration,
          doc.columns[i].duration,
          reason: 'col $i',
        );
      }
    });

    test(
        'techniques come back exactly — including ones the tracker cannot play',
        () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;
      expect(back.columns[1].techniques, {TabTechnique.slide});
      expect(back.columns[2].techniques, {TabTechnique.vibrato});
      // The hammer-on has NO tracker command, so only the side-car can bring
      // it home. This is the case the old Score route lost outright.
      expect(back.columns[3].techniques, {TabTechnique.hammer});
    });

    test('the rest column survives — it has no note to find it by', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;
      expect(back.columns.last.frets, isEmpty);
      expect(back.columns.last.duration, NoteDuration.quarter);
    });

    test('tuning, capo, time and key signature come back', () {
      final doc = TabDocument(
        tuning: Tuning.dropDGuitar,
        columns: const [
          TabColumn(frets: {5: 0}),
        ],
        timeSignature: const TimeSignature(3, 4),
        keySignature: const KeySignature(-3),
      );
      final out = trackerSongFromTabDocument(doc, capo: 3);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;
      expect(
        [for (final s in back.tuning.strings) s.midiNumber],
        [for (final s in doc.tuning.strings) s.midiNumber],
      );
      expect(back.timeSignature.beats, 3);
      expect(back.timeSignature.beatUnit, 4);
      expect(back.keySignature.fifths, -3);
      // The capo was baked into the pitch and must be subtracted again.
      expect(back.columns.first.frets[5], 0);
    });

    test('structure comes back — repeats, voltas, sections, ties', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(
            frets: {5: 3},
            duration: NoteDuration.quarter,
            startRepeat: true,
            volta: 1,
            section: 'Verse',
            tieToNext: true,
          ),
          TabColumn(
            frets: {5: 3},
            duration: NoteDuration.quarter,
            endRepeat: true,
          ),
        ],
      );
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;
      expect(back.columns[0].startRepeat, isTrue);
      expect(back.columns[0].volta, 1);
      expect(back.columns[0].section, 'Verse');
      expect(back.columns[0].tieToNext, isTrue);
      expect(back.columns[1].endRepeat, isTrue);
    });

    test('a tuplet ratio comes back', () {
      final doc = TabDocument(
        tuning: Tuning.standardGuitar,
        columns: const [
          TabColumn(
            frets: {0: 5},
            duration: NoteDuration.eighth,
            tuplet: (3, 2),
          ),
        ],
      );
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: out.annotations,
      ).doc;
      expect(back.columns.first.tuplet, (3, 2));
    });

    test('the side-car survives its own JSON round-trip', () {
      // It has to, or the conversion cannot be persisted or shared.
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final revived = SymbolicAnnotations.fromJson(out.annotations.toJson());
      final back = tabDocumentFromTrackerSong(
        out.song,
        annotations: revived,
      ).doc;
      for (var i = 0; i < doc.columns.length; i++) {
        expect(back.columns[i].frets, doc.columns[i].frets, reason: 'col $i');
        expect(
          back.columns[i].duration,
          doc.columns[i].duration,
          reason: 'col $i',
        );
      }
      expect(back.columns[3].techniques, {TabTechnique.hammer});
    });
  });

  group('best effort (no side-car)', () {
    test('frets still come back — they were never in the side-car', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        fallbackTuning: Tuning.standardGuitar,
      );
      // The trailing rest column has no note, so it cannot be recovered; every
      // noteful column can.
      expect(back.doc.columns.length, greaterThanOrEqualTo(4));
      expect(back.doc.columns[0].frets, {5: 3});
      expect(back.doc.columns[1].frets, {4: 5});
      expect(back.doc.columns[2].frets, {0: 12, 1: 12});
      expect(back.doc.columns[3].frets, {3: 7});
    });

    test('techniques are inferred from the effect column where possible', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        fallbackTuning: Tuning.standardGuitar,
      );
      expect(back.doc.columns[1].techniques, {TabTechnique.slide});
      expect(back.doc.columns[2].techniques, {TabTechnique.vibrato});
      // The hammer-on is genuinely gone without the side-car — that is the
      // cost the report must be honest about.
      expect(back.doc.columns[3].techniques, isEmpty);
    });

    test('durations are inferred from the row spacing', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        fallbackTuning: Tuning.standardGuitar,
      );
      expect(back.doc.columns[0].duration, NoteDuration.quarter);
      expect(back.doc.columns[1].duration, NoteDuration.eighth);
      expect(back.doc.columns[2].duration, NoteDuration.eighth);
    });

    test('the report admits the tuning was a guess', () {
      final doc = _riff();
      final out = trackerSongFromTabDocument(doc);
      final back = tabDocumentFromTrackerSong(
        out.song,
        fallbackTuning: Tuning.standardGuitar,
      );
      expect(back.report.lossless, isFalse);
      expect(
        back.report.approximated.any((s) => s.contains('tuning assumed')),
        isTrue,
      );
    });
  });
}
