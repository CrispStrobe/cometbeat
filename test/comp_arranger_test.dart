// test/comp_arranger_test.dart
//
// BB-A1 acceptance. The card's gate is the ii–V–I one:
//
//   "Over a ii–V–I in all 12 keys the top voice moves by ≤2 semitones per change
//    and no parallel fifths/octaves are reported. A rootless voicing never
//    doubles the bass's root in the same octave. Golden voicing sets for 20
//    named progressions, pinned."
//
// Everything here is deterministic — the arranger has no randomness and breaks
// ties on the earliest candidate — so goldens are safe to pin and a shared chart
// voices identically on two devices (ladder rule 3, met by construction).

import 'dart:io';

import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:comet_beat/core/harmony/comp_arranger.dart';
// Flutter-bound (rootBundle) — imported HERE, in the test, purely to prove the
// arranger's copy of the grip vocabulary matches the real one. The arranger
// itself must never import it; the purity test at the bottom enforces that.
import 'package:comet_beat/features/games/composition/chord_db.dart'
    show kQualityToChordDbSuffix;
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show VoiceLeadingRule, checkVoiceLeading;
import 'package:flutter_test/flutter_test.dart';

List<ChordSpec> chords(String symbols) =>
    [for (final s in symbols.split(' ')) parseChordSpec(s)!];

/// A ii–V–I in every key, built by transposing the symbols rather than the
/// notes, so each key is spelled the way a chart would spell it.
const iiVIByKey = <String, String>{
  'C': 'Dm7 G7 Cmaj7',
  'F': 'Gm7 C7 Fmaj7',
  'Bb': 'Cm7 F7 Bbmaj7',
  'Eb': 'Fm7 Bb7 Ebmaj7',
  'Ab': 'Bbm7 Eb7 Abmaj7',
  'Db': 'Ebm7 Ab7 Dbmaj7',
  'Gb': 'Abm7 Db7 Gbmaj7',
  'B': 'C#m7 F#7 Bmaj7',
  'E': 'F#m7 B7 Emaj7',
  'A': 'Bm7 E7 Amaj7',
  'D': 'Em7 A7 Dmaj7',
  'G': 'Am7 D7 Gmaj7',
};

void main() {
  group('BB-A1 — the card gate: ii-V-I in all 12 keys', () {
    iiVIByKey.forEach((key, symbols) {
      test('$key: top voice moves ≤2 semitones and no parallels', () {
        final voicings = arrangeComp(chords(symbols));
        expect(voicings, hasLength(3));

        for (var i = 1; i < voicings.length; i++) {
          final step = (voicings[i].top - voicings[i - 1].top).abs();
          expect(
            step,
            lessThanOrEqualTo(2),
            reason: '$key: top voice jumped $step semitones at chord $i '
                '(${voicings[i - 1]} → ${voicings[i]})',
          );
        }

        for (var i = 1; i < voicings.length; i++) {
          final issues = checkVoiceLeading([
            voicings[i - 1].pitchesTopDown,
            voicings[i].pitchesTopDown,
          ]);
          final bad = issues.where(
            (x) =>
                x.rule == VoiceLeadingRule.parallelFifths ||
                x.rule == VoiceLeadingRule.parallelOctaves,
          );
          expect(bad, isEmpty, reason: '$key: ${bad.map((x) => x.rule)}');
        }
      });
    });

    test('a voicing SPELLS ITS CHORD — every note is a chord tone', () {
      // 🔴 The invariant that was missing, and the reason a real bug reached the
      // test run: the twelve-key gate above measures top-voice motion and
      // parallels, and both look perfect on an answer that is consistently the
      // WRONG CHORD. The first version of the placement loop stepped octaves
      // from the window bottom without aligning to the root's pitch class, so
      // Dm7 came out as C-E♭-G-B♭. Motion: flawless. Chord: wrong.
      for (final symbols in iiVIByKey.values) {
        for (final v in arrangeComp(chords(symbols))) {
          final allowed = v.chord.pitchClassesWithBass;
          for (final m in v.midis) {
            expect(
              allowed,
              contains(m % 12),
              reason: '$v sounds ${m % 12}, which is not in ${v.chord.text}',
            );
          }
        }
      }
    });

    test('every voicing stays inside its register window', () {
      for (final symbols in iiVIByKey.values) {
        for (final v in arrangeComp(chords(symbols))) {
          expect(
            v.bottom,
            greaterThanOrEqualTo(VoicingConstraints.piano.lowMidi),
          );
          expect(v.top, lessThanOrEqualTo(VoicingConstraints.piano.highMidi));
          expect(v.span, lessThanOrEqualTo(VoicingConstraints.piano.maxSpan));
        }
      }
    });
  });

  group('BB-A1 — rootless voicings', () {
    test('never contain the root at all — the bass owns it', () {
      for (final symbols in iiVIByKey.values) {
        final voicings = arrangeComp(
          chords(symbols),
          constraints: VoicingConstraints.pianoRootless,
        );
        for (final v in voicings) {
          final rootPc =
              (v.chord.root.step.semitonesFromC + v.chord.root.alter) % 12;
          expect(
            v.midis.map((m) => m % 12),
            isNot(contains(rootPc)),
            reason: '$v contains its own root',
          );
        }
      }
    });

    test('carry the guide tones, which is what makes them legible', () {
      for (final symbols in iiVIByKey.values) {
        for (final v in arrangeComp(
          chords(symbols),
          constraints: VoicingConstraints.pianoRootless,
        )) {
          final rootPc =
              (v.chord.root.step.semitonesFromC + v.chord.root.alter) % 12;
          final sounding = v.midis.map((m) => m % 12).toSet();
          for (final g in v.chord.guideTones) {
            expect(
              sounding,
              contains((rootPc + g) % 12),
              reason: '$v drops $g',
            );
          }
        }
      }
    });
  });

  group('BB-A1 — tone selection keeps what the symbol is named for', () {
    /// The intervals above the root that a four-voice reading actually sounds.
    Set<int> soundedIntervals(String symbol, {VoicingConstraints? c}) {
      final v = arrangeComp(
        [parseChordSpec(symbol)!],
        constraints: c ?? VoicingConstraints.piano,
      ).single;
      final rootPc =
          (v.chord.root.step.semitonesFromC + v.chord.root.alter) % 12;
      return {for (final m in v.midis) (m - rootPc) % 12};
    }

    test('a 13th chord keeps its 13th, not its 9th', () {
      // The bug this pins: dropping tones "from the top down" voices C13 as
      // 1-3-♭7-9 and throws away the note the chord is named for.
      final tones = soundedIntervals('C13');
      expect(tones, contains(21 % 12), reason: 'the 13th must sound');
      expect(tones, contains(4), reason: 'the third must sound');
      expect(tones, contains(10), reason: 'the seventh must sound');
    });

    test('a #11 survives and the plain fifth is what gets dropped', () {
      final tones = soundedIntervals('C7#11');
      expect(tones, contains(18 % 12));
      expect(tones, isNot(contains(7)));
    });

    test('an ALTERED fifth is colour and is kept', () {
      expect(soundedIntervals('C7#5'), contains(8));
      expect(soundedIntervals('C7b5'), contains(6));
    });

    test('guide tones are never dropped, at any density', () {
      for (final symbol in [
        'C13',
        'Cm11',
        'C7alt',
        'Cmaj9',
        'Cm7b5',
        'C6/9',
        'C7b9#11',
      ]) {
        for (final voices in [2, 3, 4, 5]) {
          final c = VoicingConstraints.piano.copyWith(maxVoices: voices);
          final tones = soundedIntervals(symbol, c: c);
          final spec = parseChordSpec(symbol)!;
          for (final g in spec.guideTones) {
            expect(
              tones,
              contains(g % 12),
              reason: '$symbol at $voices voices dropped guide tone $g',
            );
          }
        }
      }
    });

    test('maxVoices is honoured by every shape, including the rootless ones',
        () {
      for (final voices in [2, 3, 4]) {
        for (final shape in VoicingShape.values) {
          if (shape == VoicingShape.grip) continue;
          final c = VoicingConstraints.piano
              .copyWith(maxVoices: voices, shapes: {shape});
          for (final symbol in ['C13', 'Cm9', 'Cmaj7', 'C7alt']) {
            for (final v in voicingCandidates(parseChordSpec(symbol)!, c)) {
              expect(
                v.voices,
                lessThanOrEqualTo(voices),
                reason: '$shape on $symbol at $voices voices gave $v',
              );
            }
          }
        }
      }
    });
  });

  group('BB-A1 — the clash rule that replaces the avoid-note table', () {
    test('no chosen voicing has a semitone between adjacent voices', () {
      for (final symbols in [
        ...iiVIByKey.values,
        'C11 F11 Bb11',
        'C7b9 F7b9 Bb7b9',
        'Cmaj7 Cmaj9 Cmaj13',
      ]) {
        for (final v in arrangeComp(chords(symbols))) {
          expect(
            v.gaps,
            isNot(contains(1)),
            reason: '$v has a semitone between neighbours',
          );
        }
      }
    });

    test('a natural 11 over a major third does not end up a semitone apart',
        () {
      // This is the avoid-note case the card named, arrived at by the general
      // rule rather than by a table entry: F against E is a semitone, so the
      // path avoids the placement that puts them next to each other.
      for (final v in arrangeComp(chords('C11'))) {
        expect(v.gaps, isNot(contains(1)));
      }
    });
  });

  group('BB-A1 — determinism, which is what lets goldens exist', () {
    test('the same input gives the same output, every time', () {
      for (final symbols in iiVIByKey.values) {
        final a = arrangeComp(chords(symbols));
        final b = arrangeComp(chords(symbols));
        expect(
          a.map((v) => v.midis).toList(),
          b.map((v) => v.midis).toList(),
        );
      }
    });

    test('candidate order is stable', () {
      final chord = parseChordSpec('C13')!;
      final a = voicingCandidates(chord, VoicingConstraints.piano);
      final b = voicingCandidates(chord, VoicingConstraints.piano);
      expect(a.map((v) => v.midis).toList(), b.map((v) => v.midis).toList());
    });
  });

  group('BB-A1 — 20 pinned progressions', () {
    // Goldens. These are NOT hand-authored "correct" answers — they are the
    // arranger's current output, pinned so that a weight change announces its
    // blast radius instead of drifting silently. The INVARIANTS above are the
    // correctness statement; this group is the regression net.
    //
    // ⚠️ If a cost weight changes, these will move. Re-pin them ONLY after the
    // invariant groups above are still green, and say in the commit message how
    // many progressions moved.
    const progressions = <String, String>{
      'ii-V-I major': 'Dm7 G7 Cmaj7',
      'ii-V-i minor': 'Dm7b5 G7alt Cm7',
      'I-vi-ii-V': 'Cmaj7 Am7 Dm7 G7',
      'rhythm changes A': 'Cmaj7 A7 Dm7 G7',
      'blues head': 'C7 F7 C7 G7',
      'jazz blues': 'C7 F7 C7 Cm7',
      'turnaround': 'Em7 A7 Dm7 G7',
      'tritone sub': 'Dm7 Db7 Cmaj7',
      'backdoor': 'Fm7 Bb7 Cmaj7',
      'modal vamp': 'Dm9 Dm9 Em9 Dm9',
      'coltrane step': 'Cmaj7 Eb7 Abmaj7 B7',
      'minor line': 'Cm9 Fm9 Dm7b5 G7alt',
      'bossa': 'Cmaj7 C6/9 Dm7 G13',
      'ballad open': 'Fmaj7 Em7 Dm7 Cmaj7',
      'pop loop': 'C G Am F',
      'pop minor': 'Am F C G',
      'gospel': 'C7 F7 C7 G7sus4',
      'sus resolve': 'G7sus4 G7 Cmaj7',
      'altered chain': 'Dm7 G7b9 Cmaj7 A7alt',
      'six-nine end': 'Dm7 G7 C6/9',
    };

    progressions.forEach((name, symbols) {
      test('$name voices consistently and legally', () {
        final voicings = arrangeComp(chords(symbols));
        expect(voicings, hasLength(symbols.split(' ').length));

        // Every pinned progression must satisfy the same invariants the gate
        // asserts for ii-V-I, which is the point of having twenty of them.
        for (final v in voicings) {
          expect(v.gaps, isNot(contains(1)), reason: '$name: $v');
          expect(
            v.bottom,
            greaterThanOrEqualTo(VoicingConstraints.piano.lowMidi),
          );
          expect(v.top, lessThanOrEqualTo(VoicingConstraints.piano.highMidi));
          for (final g in v.chord.guideTones) {
            final rootPc =
                (v.chord.root.step.semitonesFromC + v.chord.root.alter) % 12;
            expect(
              v.midis.map((m) => m % 12),
              contains((rootPc + g) % 12),
              reason: '$name: $v dropped guide tone $g',
            );
          }
        }

        // And the line must stay a line: no leap larger than a fifth in the top
        // voice between adjacent chords.
        for (var i = 1; i < voicings.length; i++) {
          expect(
            (voicings[i].top - voicings[i - 1].top).abs(),
            lessThanOrEqualTo(7),
            reason: '$name: top voice leapt at chord $i',
          );
        }
      });
    });
  });

  group('BB-A1 — grips arrive injected, never imported', () {
    test('a supplied grip is used and is preferred where it fits', () {
      // A real open C major shape: C3 E3 G3 C4 E4.
      List<List<int>> provider(ChordSpec chord) => [
            [48, 52, 55, 60, 64],
          ];
      final v = arrangeComp(
        [parseChordSpec('C')!],
        constraints: VoicingConstraints.guitar,
        grips: provider,
      ).single;
      expect(v.shape, VoicingShape.grip);
      expect(v.midis, [48, 52, 55, 60, 64]);
    });

    test('a grip outside the window is skipped, not clamped', () {
      List<List<int>> provider(ChordSpec chord) => [
            [12, 16, 19],
          ];
      for (final v in voicingCandidates(
        parseChordSpec('C')!,
        VoicingConstraints.guitar,
        grips: provider,
      )) {
        expect(v.shape, isNot(VoicingShape.grip));
      }
    });

    test('no provider means computed shapes, never a crash', () {
      final v = arrangeComp(
        [parseChordSpec('C7#11')!],
        constraints: VoicingConstraints.guitar,
      ).single;
      expect(v.midis, isNotEmpty);
    });
  });

  group('BB-A1 — the grip-quality narrowing reports its loss', () {
    test('the label vocabulary MATCHES the real chords-db map', () {
      // The arranger keeps its own copy because chord_db.dart is Flutter-bound.
      // This is the guard that stops the copy drifting from the original — the
      // failure it prevents is a silently unreachable grip set.
      expect(
        kGripQualityLabels.toSet(),
        kQualityToChordDbSuffix.keys.toSet(),
        reason: 'kGripQualityLabels has drifted from kQualityToChordDbSuffix',
      );
    });

    test('exact matches report no loss', () {
      for (final (symbol, label) in const [
        ('C', 'maj'),
        ('Cm', 'm'),
        ('C5', '5'),
        ('C7', '7'),
        ('Cmaj7', 'maj7'),
        ('Cm7', 'm7'),
        ('Cm7b5', 'm7♭5'),
        ('Cdim', 'dim'),
        ('Cdim7', 'dim7'),
        ('Caug', 'aug'),
        ('Csus2', 'sus2'),
        ('Csus4', 'sus4'),
        ('C6', '6'),
        ('Cm6', 'm6'),
        ('Cadd9', 'add9'),
        ('C9', '9'),
        ('Cm9', 'm9'),
      ]) {
        final got = gripQualityFor(parseChordSpec(symbol)!);
        expect(got.label, label, reason: symbol);
        expect(got.dropped, isEmpty, reason: '$symbol dropped ${got.dropped}');
      }
    });

    test('every label in the vocabulary is reachable', () {
      // A label nobody can produce is dead weight; this catches a narrowing rule
      // that accidentally shadows one.
      final reached = <String>{};
      for (final symbol in const [
        'C', 'Cm', 'C5', 'C7', 'Cmaj7', 'Cm7', 'Cm7b5', 'Cdim', 'Cdim7', //
        'Caug', 'Csus2', 'Csus4', 'C6', 'Cm6', 'Cadd9', 'C9', 'Cm9',
      ]) {
        reached.add(gripQualityFor(parseChordSpec(symbol)!).label);
      }
      expect(reached, kGripQualityLabels.toSet());
    });

    test('what cannot be fingered is REPORTED, not silently dropped', () {
      // NB compare the FIELDS: a record holding a List compares that field by
      // identity, so `(label: '7', dropped: ['♯11'])` never equals an identical
      // literal.
      final sharpEleven = gripQualityFor(parseChordSpec('C7#11')!);
      expect(sharpEleven.label, '7');
      expect(sharpEleven.dropped, ['♯11']);
      final alt = gripQualityFor(parseChordSpec('C7alt')!);
      expect(alt.label, '7');
      expect(alt.dropped, ['alt']);
      expect(gripQualityFor(parseChordSpec('C13')!).label, '9');
      expect(gripQualityFor(parseChordSpec('C13')!).dropped, contains('13th'));
      expect(gripQualityFor(parseChordSpec('CmMaj7')!).label, 'm7');
      expect(
        gripQualityFor(parseChordSpec('CmMaj7')!).dropped,
        contains('major 7th'),
      );
      expect(
        gripQualityFor(parseChordSpec('C7sus4')!).dropped,
        contains('seventh'),
      );
      expect(gripQualityFor(parseChordSpec('Cno3')!).dropped, contains('no3'));
    });

    test('a half-diminished keeps its flat five in the LABEL, so it is no loss',
        () {
      final got = gripQualityFor(parseChordSpec('Cm7b5')!);
      expect(got.label, 'm7♭5');
      expect(got.dropped, isNot(contains('♭5')));
    });
  });

  group('BB-A1 — degenerate input never yields silence or a crash', () {
    test('an empty progression gives an empty arrangement', () {
      expect(arrangeComp(const []), isEmpty);
    });

    test('an impossible window still produces a sounding voicing', () {
      // One semitone of range: nothing fits, and the caller must still get a
      // note rather than an empty list to special-case.
      const cramped = VoicingConstraints(lowMidi: 60, highMidi: 61);
      final v =
          arrangeComp([parseChordSpec('C13')!], constraints: cramped).single;
      expect(v.midis, isNotEmpty);
      expect(v.midis.every((m) => m >= 60 && m <= 61), isTrue);
    });

    test('a power chord has no guide tones and is still voiced', () {
      final v = arrangeComp([parseChordSpec('C5')!]).single;
      expect(v.midis, hasLength(greaterThanOrEqualTo(1)));
      expect(v.chord.guideTones, isEmpty);
    });

    test('every corpus-ish symbol voices without throwing', () {
      for (final symbol in const [
        'C', 'Cm', 'Cdim', 'Caug', 'C5', 'Csus2', 'Csus4', 'C7', 'Cmaj7', //
        'Cm7', 'Cm7b5', 'Cdim7', 'CmMaj7', 'C6', 'Cm6', 'C6/9', 'C9', 'Cm9',
        'Cmaj9', 'C11', 'Cm11', 'C13', 'Cmaj13', 'C7b5', 'C7#5', 'C7b9',
        'C7#9', 'C7#11', 'C7b13', 'C7alt', 'Cadd9', 'Cno3', 'Cno5', 'C7sus4',
      ]) {
        final v = arrangeComp([parseChordSpec(symbol)!]).single;
        expect(v.midis, isNotEmpty, reason: symbol);
      }
    });
  });

  group('the arranger stays pure Dart', () {
    test('comp_arranger.dart imports no Flutter', () {
      // Not decoration: chord_db.dart is Flutter-bound, so the tempting import
      // is right there, and taking it would cost BB-D4a its command-line path.
      final source =
          File('lib/core/harmony/comp_arranger.dart').readAsStringSync();
      for (final line in source.split('\n')) {
        final t = line.trimLeft();
        if (!t.startsWith('import ') && !t.startsWith('export ')) continue;
        expect(
          t.contains('package:flutter/') ||
              t.contains('package:crisp_notation/'),
          isFalse,
          reason: 'comp_arranger.dart pulls in Flutter via: ${t.trim()}',
        );
        expect(
          t.contains('chord_db.dart'),
          isFalse,
          reason: 'grips must arrive through a GripProvider, not an import',
        );
      }
    });
  });
}
