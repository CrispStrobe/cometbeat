// NoteEvent.program — the instrument carried from MT3 through to the score.
//
// Two things are worth pinning, and only one of them is the happy path:
//
//  1. **Every producer that is not MT3 reports -1, not 0.** That distinction is
//     the entire point of the sentinel: 0 is Acoustic Grand Piano, so a piano
//     transcriber emitting 0 would be asserting an instrument it never
//     computed, and nothing downstream could tell that apart from MT3 actually
//     recognising a piano. These tests run the REAL producers (pYIN's note-HMM
//     and Basic Pitch's posteriorgram decoder) rather than a stub, because a
//     stub would only pin what this file already believes.
//  2. **The program reaches the notation stage** — `transcribeToParts` splits a
//     multi-instrument take into one engraved part per instrument, names each
//     with its GM name, and stamps the `<midi-program>` that the MusicXML and
//     MIDI writers emit.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/basic_pitch.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/gm_programs.dart';
import 'package:comet_beat/core/audio/transcription/note_hmm.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 22050;

/// A 1 s sine at [hz] — enough for pYIN to find a note.
Float64List _tone(double hz, {double seconds = 1.0}) {
  final out = Float64List((seconds * _sr).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = 0.6 * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

const RhythmGrid _grid = (
  bpm: 120.0,
  beatMs: [0.0, 500.0, 1000.0, 1500.0, 2000.0, 2500.0],
  onsetMs: <double>[],
);

NoteEvent _n(int midi, double on, double off, int program) =>
    (midi: midi, onMs: on, offMs: off, confidence: 1.0, program: program);

void main() {
  group('the sentinel — a producer that identifies no instrument says so', () {
    test('the constants are -1 and 128, and 0 is a real instrument', () {
      // Pinned as literals on purpose: these values are an ABI shared with
      // crispasr's `PianoNoteWithProgram`, so renumbering them here would
      // silently disagree with the C side rather than fail to compile.
      expect(gmProgramUnknown, -1);
      expect(gmProgramPercussion, 128);
      expect(hasInstrument(gmProgramUnknown), isFalse);
      expect(hasInstrument(0), isTrue, reason: '0 is Acoustic Grand Piano');
      expect(hasInstrument(gmProgramPercussion), isTrue);
      expect(gmProgramNames, hasLength(128));
      expect(gmProgramNames[0], 'Acoustic Grand Piano');
      expect(gmProgramName(gmProgramUnknown), isNot(contains('Piano')));
    });

    test('pYIN + the note-HMM report -1 (NOT 0) for every note', () {
      final notes = segmentNotes(pyinF0(_tone(440), sampleRate: _sr));
      expect(notes, isNotEmpty, reason: 'a 1 s A4 must segment to a note');
      for (final n in notes) {
        expect(n.program, gmProgramUnknown);
        expect(n.program, isNot(0), reason: '0 would claim a grand piano');
      }
    });

    test('removeOctaveArtifacts keeps the program it was handed', () {
      // The cleanup filters notes; it must not launder their provenance.
      final kept = removeOctaveArtifacts([
        _n(60, 0, 500, 71),
        _n(48, 500, 560, 71), // a subharmonic blip — dropped
        _n(62, 560, 1000, 71),
      ]);
      expect(kept.map((n) => n.program), everyElement(71));
    });

    test('Basic Pitch reports -1 for every note it decodes', () {
      // Drive the decoder directly with a synthetic posteriorgram: one pitch
      // held long enough to survive the minimum-length gate. This is the real
      // decode path, model-free.
      const frames = 40;
      const bins = 88;
      const midiOffset = 21;
      const bin = 45;
      final frameGram = [for (var t = 0; t < frames; t++) Float64List(bins)];
      final onsetGram = [for (var t = 0; t < frames; t++) Float64List(bins)];
      for (var t = 4; t < 30; t++) {
        frameGram[t][bin] = 0.9;
      }
      onsetGram[4][bin] = 0.9;
      final notes = notesFromPosteriorgrams(frameGram, onsetGram);
      expect(notes, isNotEmpty);
      for (final n in notes) {
        expect(n.midi, bin + midiOffset);
        expect(n.program, gmProgramUnknown);
        expect(n.program, isNot(0));
      }
    });
  });

  group('transcribeToParts — the program reaches the score', () {
    test('a single-instrument take is ONE part, as before', () {
      final notes = [
        for (var i = 0; i < 4; i++)
          _n(60 + i, i * 500.0, i * 500.0 + 450, gmProgramUnknown),
      ];
      final parts = transcribeToParts(notes, _grid);
      expect(parts, hasLength(1));
      expect(parts.single.program, gmProgramUnknown);
      // Byte-for-byte the score the old single-staff entry point produces.
      final flat = transcribeToScore(notes, _grid);
      expect(parts.single.score.measures.length, flat.measures.length);
      // ...and NO instrument is claimed for it.
      expect(parts.single.score.metadata.instrument, isNull);
      expect(parts.single.score.metadata.midiProgram, isNull);
    });

    test('a wind trio becomes three named parts, high to low', () {
      // The shape of MusicNet 1819 as MT3 reports it: French Horn (60),
      // Bassoon (70), Clarinet (71).
      final notes = [
        _n(65, 0, 500, 60), // horn, middle register
        _n(67, 500, 1000, 60),
        _n(45, 0, 500, 70), // bassoon, low
        _n(47, 500, 1000, 70),
        _n(77, 0, 500, 71), // clarinet, high
        _n(79, 500, 1000, 71),
      ];
      final parts = transcribeToParts(notes, _grid);
      expect(
        parts.map((p) => p.program),
        [71, 60, 70],
        reason: 'highest median pitch first',
      );
      expect(
        parts.map((p) => p.score.metadata.instrument),
        ['Clarinet', 'French Horn', 'Bassoon'],
      );
      expect(parts.map((p) => p.score.metadata.midiProgram), [71, 60, 70]);
      // Each part holds only its own notes.
      for (final p in parts) {
        expect(p.notes.map((n) => n.program), everyElement(p.program));
      }
      // The low part picks a bass clef on its own — the reason for splitting
      // before choosing a clef rather than after.
      expect(parts.last.score.clef, Clef.bass);
      expect(parts.first.score.clef, Clef.treble);
    });

    test('percussion is flagged, and writes no <midi-program>', () {
      final parts = transcribeToParts(
        [_n(38, 0, 250, gmProgramPercussion)],
        _grid,
      );
      final meta = parts.single.score.metadata;
      expect(meta.isPercussion, isTrue);
      expect(meta.instrument, 'Percussion');
      // 128 is not a legal <midi-program>; the flag carries the meaning.
      expect(meta.midiProgram, isNull);
    });

    test('unidentified notes sort last and stay unnamed', () {
      final parts = transcribeToParts(
        [
          _n(80, 0, 500, gmProgramUnknown), // high, but nameless
          _n(50, 0, 500, 71),
        ],
        _grid,
      );
      expect(parts.map((p) => p.program), [71, gmProgramUnknown]);
      expect(parts.last.score.metadata.instrument, isNull);
    });

    test('the parts export as a multi-part MusicXML document', () {
      final parts = transcribeToParts(
        [_n(72, 0, 500, 71), _n(48, 0, 500, 70)],
        _grid,
      );
      final xml = multiPartToMusicXml(
        MultiPartScore([for (final p in parts) p.score]),
      );
      expect(xml, contains('<part-name>Clarinet</part-name>'));
      expect(xml, contains('<part-name>Bassoon</part-name>'));
      // MusicXML numbers programs from 1, so GM 71 is written as 72.
      expect(xml, contains('<midi-program>72</midi-program>'));
      expect(xml, contains('<midi-program>71</midi-program>'));
    });

    test('empty input still yields one (empty) part', () {
      final parts = transcribeToParts(const [], _grid);
      expect(parts, hasLength(1));
      expect(parts.single.notes, isEmpty);
    });
  });
}
