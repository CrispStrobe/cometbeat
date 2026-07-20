// JAMS chord importer — pure converter (no Flutter). Verifies the Harte→name
// mapping and the JAMS→ChordPro conversion (both data shapes, title, rests,
// error cases), and that the output round-trips through the real ChordPro
// parser + chord→MIDI mapper.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show NoteElement, scoreFromMidi;
import 'package:flutter_test/flutter_test.dart';

/// The MIDI note numbers of every note in [midi], in order.
List<int> _midiPitches(Uint8List midi) => scoreFromMidi(midi)
    .measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .map((p) => p.midiNumber)
    .toList();

String _jams(List<Map<String, Object?>> chordData, {String? title}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {'namespace': 'chord', 'data': chordData},
      ],
    });

void main() {
  group('harteToChordName', () {
    test('major qualities → plain root triad', () {
      expect(harteToChordName('C:maj'), 'C');
      expect(harteToChordName('C'), 'C'); // bare root = major
      expect(harteToChordName('G:7'), 'G'); // dominant reduces to major triad
      expect(harteToChordName('F#:maj7'), 'F#');
      expect(harteToChordName('Bb:sus4'), 'Bb');
      expect(harteToChordName('D:9'), 'D');
    });

    test('minor / diminished qualities → minor triad', () {
      expect(harteToChordName('A:min'), 'Am');
      expect(harteToChordName('A:min7'), 'Am');
      expect(harteToChordName('E:minmaj7'), 'Em');
      expect(harteToChordName('B:dim'), 'Bm');
      expect(harteToChordName('C#:hdim7'), 'C#m');
    });

    test('slash bass and inversions are dropped', () {
      expect(harteToChordName('C:maj/3'), 'C');
      expect(harteToChordName('A:min7/b7'), 'Am');
      expect(harteToChordName('G:7/5'), 'G');
    });

    test('no-chord and unparseable labels → null', () {
      expect(harteToChordName('N'), isNull);
      expect(harteToChordName('X'), isNull);
      expect(harteToChordName(''), isNull);
      expect(harteToChordName('  '), isNull);
      expect(harteToChordName('foo'), isNull);
    });
  });

  group('jamsToChordPro', () {
    test('converts a chord annotation, keeps title, collapses repeats', () {
      final json = _jams(
        title: 'My Song',
        [
          {'time': 0.0, 'duration': 2.0, 'value': 'C:maj'},
          {'time': 2.0, 'duration': 2.0, 'value': 'C:maj'}, // repeat, collapsed
          {'time': 4.0, 'duration': 2.0, 'value': 'A:min'},
          {'time': 6.0, 'duration': 2.0, 'value': 'F:maj'},
          {'time': 8.0, 'duration': 2.0, 'value': 'G:7'},
        ],
      );
      final cp = jamsToChordPro(json);
      expect(cp, contains('{title: My Song}'));

      final sheet = parseChordPro(cp);
      expect(sheet.title, 'My Song');
      // C (collapsed), Am, F, G — four distinct chords, in order.
      expect(sheet.chords, ['C', 'Am', 'F', 'G']);
      // Every emitted chord is playable (maps to a triad).
      for (final c in sheet.chords) {
        expect(chordMidis(c), isNotNull, reason: c);
      }
    });

    test('a run of N (no chord) breaks the collapse but adds no chip', () {
      final json = _jams([
        {'time': 0.0, 'value': 'C:maj'},
        {'time': 1.0, 'value': 'N'},
        {'time': 2.0, 'value': 'C:maj'}, // same as before, but N broke the run
      ]);
      final cp = jamsToChordPro(json);
      // Two C chips emitted (N broke the collapse); no chip for the N itself.
      expect('[C]'.allMatches(cp).length, 2);
      // The distinct-chord list (a Set) still reports just C.
      expect(parseChordPro(cp).chords, ['C']);
    });

    test('supports the legacy dict-of-arrays data shape', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'chord',
            'data': {
              'time': [0.0, 2.0],
              'value': ['D:maj', 'B:min'],
            },
          },
        ],
      });
      expect(parseChordPro(jamsToChordPro(json)).chords, ['D', 'Bm']);
    });

    test('picks the chord annotation among several namespaces', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'beat',
            'data': [
              {'time': 0.0, 'value': 1},
            ],
          },
          {
            'namespace': 'chord',
            'data': [
              {'time': 0.0, 'value': 'E:maj'},
            ],
          },
        ],
      });
      expect(parseChordPro(jamsToChordPro(json)).chords, ['E']);
    });

    test('throws on non-JSON, non-JAMS, and chord-less inputs', () {
      expect(() => jamsToChordPro('not json'), throwsFormatException);
      expect(() => jamsToChordPro('[1,2,3]'), throwsFormatException);
      expect(
        () => jamsToChordPro(jsonEncode({'annotations': []})),
        throwsFormatException,
      );
      // A chord annotation of only no-chords is still "no usable chords".
      final onlyN = _jams([
        {'time': 0.0, 'value': 'N'},
      ]);
      expect(() => jamsToChordPro(onlyN), throwsFormatException);
    });
  });

  group('melody (note_midi)', () {
    String melodyJson(List<Map<String, Object?>> notes, {double? tempo}) =>
        jsonEncode({
          'annotations': [
            {'namespace': 'note_midi', 'data': notes},
            if (tempo != null)
              {
                'namespace': 'tempo',
                'data': [
                  {'time': 0.0, 'duration': 0.0, 'value': tempo},
                ],
              },
          ],
        });

    test('parses, sorts, rounds fractional pitch, skips bad notes', () {
      final json = melodyJson([
        {'time': 1.0, 'duration': 0.5, 'value': 62},
        {'time': 0.0, 'duration': 0.5, 'value': 60.4}, // rounds to 60
        {'time': 2.0, 'duration': 0.0, 'value': 64}, // zero-dur, skipped
        {'time': 3.0, 'duration': 0.5, 'value': 200}, // out of range, skipped
      ]);
      final notes = jamsMelodyNotes(json);
      expect(notes.map((n) => n.midi), [60, 62]); // sorted by time
      expect(notes.first.time, 0.0);
    });

    test('legacy dict-of-arrays note shape', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'note_midi',
            'data': {
              'time': [0.0, 0.5],
              'duration': [0.5, 0.5],
              'value': [60, 67],
            },
          },
        ],
      });
      expect(jamsMelodyNotes(json).map((n) => n.midi), [60, 67]);
    });

    test('jamsToMidi round-trips the pitches through the MIDI reader', () {
      // A C-major scale, one quarter each at 120 BPM (0.5 s/note).
      const scale = [60, 62, 64, 65, 67, 69, 71, 72];
      final json = melodyJson(
        tempo: 120,
        [
          for (var i = 0; i < scale.length; i++)
            {'time': i * 0.5, 'duration': 0.5, 'value': scale[i]},
        ],
      );
      expect(_midiPitches(jamsToMidi(json)), scale);
    });

    test('no note_midi annotation → throws', () {
      expect(() => jamsToMidi('{"annotations":[]}'), throwsFormatException);
    });
  });

  group('tempo / beat / key annotations', () {
    test('jamsTempo reads the BPM', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'tempo',
            'data': [
              {'time': 0.0, 'duration': 0.0, 'value': 96.0},
            ],
          },
        ],
      });
      expect(jamsTempo(json), 96.0);
      expect(jamsTempo('{"annotations":[]}'), isNull);
    });

    test('jamsBeatsPerBar infers the meter from beat positions', () {
      String beats(List<int> positions) => jsonEncode({
            'annotations': [
              {
                'namespace': 'beat',
                'data': [
                  for (var i = 0; i < positions.length; i++)
                    {'time': i * 0.5, 'duration': 0.0, 'value': positions[i]},
                ],
              },
            ],
          });
      expect(jamsBeatsPerBar(beats([1, 2, 3, 1, 2, 3])), 3); // 3/4
      expect(jamsBeatsPerBar(beats([1, 2, 3, 4, 1, 2, 3, 4])), 4); // 4/4
      expect(jamsBeatsPerBar('{"annotations":[]}'), isNull);
    });

    test('jamsKey reads TONIC:MODE (and TONIC MODE, and N)', () {
      String key(String v) => jsonEncode({
            'annotations': [
              {
                'namespace': 'key_mode',
                'data': [
                  {'time': 0.0, 'duration': 0.0, 'value': v},
                ],
              },
            ],
          });
      expect(jamsKey(key('A:minor')), 'A minor');
      expect(jamsKey(key('Eb major')), 'Eb major');
      expect(jamsKey(key('C')), 'C major'); // mode defaults to major
      expect(jamsKey(key('N')), isNull);
    });
  });

  group('JAMS writers (ground-truth generation)', () {
    test('chordsToJams → jamsToChordPro round-trips the chords', () {
      final json = chordsToJams(['C', 'Am', 'F', 'G'], title: 'RT');
      expect(jamsTitle(json), 'RT');
      expect(parseChordPro(jamsToChordPro(json)).chords, ['C', 'Am', 'F', 'G']);
    });

    test('notesToJams → jamsMelodyNotes round-trips the notes + tempo', () {
      final notes = <JamsNote>[
        (time: 0.0, duration: 0.5, midi: 60),
        (time: 0.5, duration: 0.5, midi: 64),
        (time: 1.0, duration: 1.0, midi: 67),
      ];
      final json = notesToJams(notes, title: 'Arp', tempo: 100);
      expect(jamsTitle(json), 'Arp');
      expect(jamsTempo(json), 100.0);
      expect(jamsMelodyNotes(json), notes);
    });
  });
}
