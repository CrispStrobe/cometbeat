import 'package:comet_beat/core/harmony/bass_generator.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bass line.
///
/// The card's acceptance is precise and this asserts exactly it: over a 12-bar
/// blues and a 32-bar AABA, **every bar-final note is a semitone, a whole tone
/// or a fifth from the next bar's root**, no note leaves the instrument's
/// range, and the same seed reproduces the same line.
ChordSpec c(String s) => parseChordSpec(s)!;

/// Walks a whole progression the way the renderer will, threading register.
List<List<BassNote>> runLine(
  List<String> symbols, {
  BassMode mode = BassMode.walking,
  double beats = 4,
  int seed = 7,
  BassRange range = const BassRange(),
}) {
  final chords = symbols.map(c).toList();
  final out = <List<BassNote>>[];
  int? previous;
  for (var i = 0; i < chords.length; i++) {
    final bar = generateBassBar(
      chord: chords[i],
      next: i + 1 < chords.length ? chords[i + 1] : null,
      beats: beats,
      mode: mode,
      range: range,
      previousMidi: previous,
      seed: seed,
      barIndex: i,
    );
    out.add(bar);
    if (bar.isNotEmpty) previous = bar.last.midi;
  }
  return out;
}

const _blues = [
  'C7', 'F7', 'C7', 'C7', //
  'F7', 'F7', 'C7', 'C7', //
  'G7', 'F7', 'C7', 'G7',
];

const _aaba = [
  'Cmaj7', 'A7', 'Dm7', 'G7', 'Cmaj7', 'A7', 'Dm7', 'G7', //
  'Cmaj7', 'A7', 'Dm7', 'G7', 'Cmaj7', 'C7', 'Fmaj7', 'Fm7', //
  'Em7', 'A7', 'Dm7', 'G7', 'Cmaj7', 'A7', 'Dm7', 'G7', //
  'Cmaj7', 'A7', 'Dm7', 'G7', 'Em7', 'A7', 'Dm7', 'G7',
];

int pc(int midi) => ((midi % 12) + 12) % 12;

/// Semitones between two pitch classes, the short way round.
int interval(int a, int b) {
  final d = (pc(a) - pc(b)).abs();
  return d > 6 ? 12 - d : d;
}

void main() {
  group('walking into the next chord', () {
    for (final (name, progression) in [
      ('12-bar blues', _blues),
      ('AABA', _aaba),
    ]) {
      test('$name: every bar-final note approaches the next root', () {
        final line = runLine(progression);
        final chords = progression.map(c).toList();

        for (var i = 0; i < line.length - 1; i++) {
          final last = line[i].last.midi;
          final nextRoot = chords[i + 1].root.midiNumber;
          final gap = interval(last, nextRoot);
          expect(
            gap == 1 || gap == 2 || gap == 5 || gap == 0,
            isTrue,
            reason: 'bar ${i + 1} ends on ${pc(last)}, next root '
                '${pc(nextRoot)} — gap $gap is not a step, a fifth or the root',
          );
        }
      });

      test('$name: nothing leaves the instrument range', () {
        const range = BassRange();
        for (final bar in runLine(progression)) {
          for (final note in bar) {
            expect(
              range.contains(note.midi),
              isTrue,
              reason: '${note.midi} is outside ${range.low}..${range.high}',
            );
          }
        }
      });

      test('$name: the same seed reproduces the same line', () {
        expect(
          runLine(progression).expand((b) => b).map((n) => n.midi).toList(),
          runLine(progression).expand((b) => b).map((n) => n.midi).toList(),
        );
      });
    }

    test('a repeated chord does not repeat its line verbatim', () {
      // Eight bars of one chord must not be eight identical bars.
      final line = runLine(List.filled(8, 'C7'));
      final rendered = line.map((b) => b.map((n) => n.midi).join(',')).toList();
      expect(
        rendered.toSet().length,
        greaterThan(1),
        reason: 'every bar of a static chord came out identical',
      );
    });

    test('register is continuous across the barline', () {
      // A line that jumps an octave whenever the root does is not a line.
      final line = runLine(_aaba);
      for (var i = 1; i < line.length; i++) {
        final gap = (line[i].first.midi - line[i - 1].last.midi).abs();
        expect(gap, lessThanOrEqualTo(12), reason: 'octave leap at bar $i');
      }
    });
  });

  group('the modes', () {
    test('root holds one note for the bar', () {
      final bar = generateBassBar(
        chord: c('F'),
        next: c('C'),
        beats: 4,
        mode: BassMode.root,
      );
      expect(bar, hasLength(1));
      expect(bar.single.duration, 4);
      expect(pc(bar.single.midi), pc(c('F').root.midiNumber));
    });

    test('rootFive alternates root and fifth', () {
      final bar = generateBassBar(
        chord: c('C'),
        next: c('G'),
        beats: 4,
        mode: BassMode.rootFive,
      );
      expect(bar, hasLength(2));
      expect(interval(bar[0].midi, bar[1].midi), 5);
    });

    test('twoFeel puts two half notes in the bar and approaches', () {
      final bar = generateBassBar(
        chord: c('C'),
        next: c('F'),
        beats: 4,
        mode: BassMode.twoFeel,
      );
      expect(bar, hasLength(2));
      expect(bar[0].duration, 2);
      // The second note leads somewhere, rather than restating the chord.
      final gap = interval(bar[1].midi, c('F').root.midiNumber);
      expect(gap == 1 || gap == 2 || gap == 5 || gap == 0, isTrue);
    });

    test('walking fills the bar with quarter notes', () {
      final bar = generateBassBar(
        chord: c('C'),
        next: c('F'),
        beats: 4,
        mode: BassMode.walking,
      );
      expect(bar, hasLength(4));
      expect(bar.map((n) => n.beat), [0, 1, 2, 3]);
    });

    test('pedal is one note however long the bar', () {
      final bar = generateBassBar(
        chord: c('C'),
        next: c('F'),
        beats: 7,
        mode: BassMode.pedal,
      );
      expect(bar, hasLength(1));
      expect(bar.single.duration, 7);
    });

    test('tumbao is syncopated, not on every beat', () {
      final bar = generateBassBar(
        chord: c('C'),
        next: c('F'),
        beats: 4,
        mode: BassMode.tumbao,
      );
      expect(bar.map((n) => n.beat), contains(1.5));
      expect(bar.map((n) => n.beat), isNot(contains(1.0)));
    });

    test('a slash bass sounds the written bass, not the root', () {
      final bar = generateBassBar(
        chord: c('C/G'),
        next: c('F'),
        beats: 4,
        mode: BassMode.root,
      );
      expect(pc(bar.single.midi), 7);
    });

    test('every mode fills a short bar without throwing', () {
      // 2/4 and 3/4 bars reach these paths; a mode that assumed four beats
      // would produce a note past the barline.
      for (final mode in BassMode.values) {
        for (final beats in [1.0, 2.0, 3.0]) {
          final bar = generateBassBar(
            chord: c('Bb7'),
            next: c('Eb'),
            beats: beats,
            mode: mode,
          );
          expect(bar, isNotEmpty, reason: '$mode at $beats beats');
          for (final note in bar) {
            expect(
              note.beat + note.duration,
              lessThanOrEqualTo(beats + 1e-9),
              reason: '$mode overran a $beats-beat bar',
            );
          }
        }
      }
    });
  });

  group('range', () {
    test('a very low chord is lifted into range, not clamped flat', () {
      const range = BassRange(low: 40);
      final bar = generateBassBar(
        chord: c('C'),
        next: c('F'),
        beats: 4,
        mode: BassMode.walking,
        range: range,
      );
      for (final note in bar) {
        expect(range.contains(note.midi), isTrue);
      }
      // Lifting by octaves preserves the pitch class; clamping would not.
      expect(pc(bar.first.midi), pc(c('C').root.midiNumber));
    });

    test('a zero-length bar produces nothing rather than a stuck note', () {
      expect(
        generateBassBar(
          chord: c('C'),
          next: null,
          beats: 0,
          mode: BassMode.walking,
        ),
        isEmpty,
      );
    });
  });
}
