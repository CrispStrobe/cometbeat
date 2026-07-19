// midi_import.dart — the SMF parser. import_test covers the happy path + a junk
// rejection; this pins the error and transform branches it doesn't: SMPTE
// rejection, the "no notes" throw, monophonic overlap-dropping, running-status
// decoding, format-1 first-track-with-notes selection, and rest-gap insertion.

import 'dart:typed_data';

import 'package:comet_beat/core/notation/multi_part_export.dart';
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

  group('scoreFromMidi is robust to malformed input (no Error, no crash)', () {
    // A track with one complete note (note-on, delta, note-off) + end.
    const noteTrack = [0x00, 0x90, 60, 0x40, 0x40, 0x80, 60, 0x00, ..._eot];

    test('a chunk length exceeding the buffer throws cleanly, not a RangeError',
        () {
      // MThd (division 96) then an MTrk claiming a 0x7FFFFFFF body, file ends.
      final lying = Uint8List.fromList([
        ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 0, 96, //
        ...'MTrk'.codeUnits, 0x7F, 0xFF, 0xFF, 0xFF, 0x90, 60, 64,
      ]);
      // Clamped to the buffer: the (incomplete) note yields no output -> a clean
      // FormatException, never an out-of-bounds RangeError.
      expect(() => scoreFromMidi(lying), throwsFormatException);
    });

    test('a zero time division is rejected (no divide-by-zero)', () {
      // division 0 would make the 1/16 grid divide by zero (Infinity.round()).
      expect(
        () => scoreFromMidi(_smf([noteTrack], division: 0)),
        throwsFormatException,
      );
    });

    test('fuzz: no malformed input throws a non-Exception Error', () {
      for (var seed = 0; seed < 120; seed++) {
        final len = 1 + (seed * 131) % 6000;
        final b = Uint8List(len);
        var x = seed * 2654435761 + 1;
        for (var i = 0; i < len; i++) {
          x = (x * 1103515245 + 12345) & 0x7fffffff;
          b[i] = x & 0xff;
        }
        if (seed.isEven && len > 14) b.setRange(0, 4, 'MThd'.codeUnits);
        try {
          scoreFromMidi(b);
        } on Exception {
          // clean — acceptable
        } catch (e) {
          fail('seed $seed threw a non-Exception: ${e.runtimeType}: $e');
        }
      }
    });
  });

  group('multi-track SMF parsing rejects malformed input cleanly', () {
    // splitMultiTrackMidi / multiTrackMidiToMultiPart parse an untrusted MIDI
    // file. A truncated header or a chunk declaring more bytes than exist must
    // not leak a RangeError — reject with FormatException or parse leniently.
    // (Found by fuzzing: 76k RangeErrors over 100k mutations before the guards.)
    final validSmf = Uint8List.fromList([
      0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0, // MThd fmt0 1trk
      0x4D, 0x54, 0x72, 0x6B, 0, 0, 0, 4, 0x00, 0xFF, 0x2F, 0x00, // MTrk end
    ]);

    test('a sub-header SMF throws FormatException, not RangeError', () {
      for (final n in [0, 4, 12, 13]) {
        final short = Uint8List.sublistView(validSmf, 0, n);
        expect(
          () => splitMultiTrackMidi(short),
          throwsFormatException,
          reason: '$n-byte SMF',
        );
        expect(
          () => splitMultiTrackMidi(short),
          throwsA(isNot(isA<RangeError>())),
        );
      }
    });

    test('a chunk length exceeding the buffer does not over-read', () {
      // MTrk header claims a 0xFFFFFFFF-byte body but the file ends right after.
      final lying = Uint8List.fromList([
        ...validSmf.sublist(0, 14),
        0x4D, 0x54, 0x72, 0x6B, 0xFF, 0xFF, 0xFF, 0xFF, // MTrk, huge length
      ]);
      // Clamped to the buffer: no over-read, no throw — one (short) track.
      expect(() => splitMultiTrackMidi(lying), returnsNormally);
      expect(splitMultiTrackMidi(lying), hasLength(1));
    });

    test('a valid SMF still splits into one track', () {
      final tracks = splitMultiTrackMidi(validSmf);
      expect(tracks, hasLength(1));
    });
  });
}
