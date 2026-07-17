// midi_import.dart — the SMF parser. import_test covers the happy path + a junk
// rejection; this pins the error and transform branches it doesn't: SMPTE
// rejection, the "no notes" throw, monophonic overlap-dropping, running-status
// decoding, format-1 first-track-with-notes selection, and rest-gap insertion.

import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/import/midi_import.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show Measure, NoteElement, RestElement;
import 'package:flutter_test/flutter_test.dart';

/// Variable-length quantity encoding of a delta time.
List<int> _vlq(int value) {
  final out = <int>[value & 0x7f];
  value >>= 7;
  while (value > 0) {
    out.insert(0, (value & 0x7f) | 0x80);
    value >>= 7;
  }
  return out;
}

const _eot = [0x00, 0xff, 0x2f, 0x00]; // end-of-track meta

/// Assemble an SMF from raw track byte-lists.
Uint8List _smf(List<List<int>> tracks, {int format = 0, int division = 480}) {
  final out = <int>[
    ...'MThd'.codeUnits, 0, 0, 0, 6, //
    0, format,
    (tracks.length >> 8) & 0xff, tracks.length & 0xff,
    (division >> 8) & 0xff, division & 0xff,
  ];
  for (final t in tracks) {
    out.addAll('MTrk'.codeUnits);
    out.addAll([
      (t.length >> 24) & 0xff,
      (t.length >> 16) & 0xff,
      (t.length >> 8) & 0xff,
      t.length & 0xff,
    ]);
    out.addAll(t);
  }
  return Uint8List.fromList(out);
}

List<NoteElement> _notesOf(List<Measure> measures) => [
      for (final m in measures)
        for (final e in m.elements)
          if (e is NoteElement) e,
    ];

void main() {
  test('rejects SMPTE time division', () {
    // Division with the high bit set is SMPTE frames, not ticks-per-quarter.
    final bytes = Uint8List.fromList([
      ...'MThd'.codeUnits, 0, 0, 0, 6, //
      0, 0, 0, 1,
      0x80, 0x00, // SMPTE flag set
      ...'MTrk'.codeUnits, 0, 0, 0, _eot.length, ..._eot,
    ]);
    expect(() => scoreFromMidi(bytes), throwsFormatException);
  });

  test('rejects a file with no notes in any track', () {
    expect(() => scoreFromMidi(_smf([_eot])), throwsFormatException);
  });

  test('drops overlapping notes (keeps the monophonic line)', () {
    // C4 sounds 0..480; E4 starts mid-way (240) and must be dropped; G4 at 480.
    final track = <int>[
      0x00, 0x90, 60, 100, // C4 on @0
      ..._vlq(240), 0x90, 64, 100, // E4 on @240 (overlaps C4)
      ..._vlq(240), 0x80, 64, 0, // E4 off @480
      0x00, 0x80, 60, 0, // C4 off @480
      0x00, 0x90, 67, 100, // G4 on @480
      ..._vlq(480), 0x80, 67, 0, // G4 off @960
      ..._eot,
    ];
    final notes = _notesOf(scoreFromMidi(_smf([track])).measures);
    expect(notes.map((n) => n.pitches.first.midiNumber), [60, 67]);
  });

  test('decodes running status (omitted repeat status bytes)', () {
    // Only the first event carries the 0x90 status; the rest reuse it.
    final track = <int>[
      0x00, 0x90, 60, 100, // C4 on @0 (status 0x90)
      ..._vlq(480), 60, 0, // running status: C4 note-on vel 0 = off @480
      0x00, 62, 100, // running status: D4 on @480
      ..._vlq(480), 62, 0, // running status: D4 off @960
      ..._eot,
    ];
    final notes = _notesOf(scoreFromMidi(_smf([track])).measures);
    expect(notes.map((n) => n.pitches.first.midiNumber), [60, 62]);
  });

  test('format 1: takes the first track that actually has notes', () {
    final empty = <int>[..._eot]; // track 0 — meta only
    final withNotes = <int>[
      0x00, 0x90, 65, 100, // F4 on @0
      ..._vlq(480), 0x80, 65, 0, // off @480
      ..._eot,
    ];
    final notes = _notesOf(
      scoreFromMidi(_smf([empty, withNotes], format: 1)).measures,
    );
    expect(notes, hasLength(1));
    expect(notes.first.pitches.first.midiNumber, 65);
  });

  test('inserts a rest for the gap between notes', () {
    // C4 quarter @0..480, then G4 @960 — a quarter rest fills 480..960.
    final track = <int>[
      0x00, 0x90, 60, 100, // C4 on @0
      ..._vlq(480), 0x80, 60, 0, // C4 off @480
      ..._vlq(480), 0x90, 67, 100, // G4 on @960
      ..._vlq(480), 0x80, 67, 0, // G4 off @1440
      ..._eot,
    ];
    final elements = [
      for (final m in scoreFromMidi(_smf([track])).measures) ...m.elements,
    ];
    final rests = elements.whereType<RestElement>().toList();
    expect(rests, isNotEmpty, reason: 'the 480-tick gap must become a rest');
    expect(rests.first.duration.fraction, (1, 4));
  });
}
