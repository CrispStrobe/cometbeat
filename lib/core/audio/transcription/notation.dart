// lib/core/audio/transcription/notation.dart
//
// W-NOTATION (slice 1) — key estimation + enharmonic spelling. A raw transcriber
// emits MIDI numbers, and the engraver spells every black key as a sharp, so a
// piece in F major shows B-flat as A-sharp — wrong, and hard to read. This
// estimates the key from the notes and re-spells each pitch the way that key
// wants it (B-flat, not A-sharp), and sets the key signature. Pure Dart,
// rule-based, no model — and it improves BOTH the monophonic and neural engines'
// output because it post-processes the finished Score.
//
// Key finding: the Krumhansl-Schmuckler algorithm (a duration-weighted
// pitch-class histogram correlated with the 24 major/minor key profiles).
// Spelling: the "line of fifths" — every note name+accidental has a position on
// the chain of fifths (…F C G D A E B F# C#…); a pitch class is spelled by the
// position nearest the key's centre, which gives the key-correct accidental.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// The estimated key: [fifths] (the key-signature accidental count, −7…+7),
/// [tonic] pitch class (0=C), and whether it is [minor].
typedef KeyEstimate = ({int fifths, int tonic, bool minor});

// Krumhansl-Kessler key profiles (major / minor), indexed by scale degree.
const List<double> _major = [
  6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88, //
];
const List<double> _minor = [
  6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17, //
];

const List<Step> _fifthLetters = [
  Step.f,
  Step.c,
  Step.g,
  Step.d,
  Step.a,
  Step.e,
  Step.b,
];
const Map<Step, int> _stepSemitones = {
  Step.c: 0,
  Step.d: 2,
  Step.e: 4,
  Step.f: 5,
  Step.g: 7,
  Step.a: 9,
  Step.b: 11,
};

int _pc(int midi) => ((midi % 12) + 12) % 12;

/// Pick the clef that keeps the music on the staff: bass for a line centred below
/// middle C (a cello/bass part), treble otherwise. Splitting at middle C
/// (MIDI 60) is the textbook grand-staff boundary and minimises ledger lines for
/// a single-line transcription. Empty → treble.
Clef chooseClef(List<NoteEvent> notes) {
  if (notes.isEmpty) return Clef.treble;
  final midis = [for (final n in notes) n.midi]..sort();
  final median = midis[midis.length ~/ 2];
  return median < 60 ? Clef.bass : Clef.treble;
}

/// Estimate the key of [notes] by correlating their duration-weighted
/// pitch-class profile against the 24 Krumhansl key profiles. Empty → C major.
KeyEstimate estimateKey(List<NoteEvent> notes) {
  final pcp = List<double>.filled(12, 0);
  for (final n in notes) {
    final dur = n.offMs - n.onMs;
    pcp[_pc(n.midi)] += dur > 0 ? dur : 1;
  }
  if (pcp.every((v) => v == 0)) return (fifths: 0, tonic: 0, minor: false);

  var bestCorr = -2.0;
  var bestTonic = 0;
  var bestMinor = false;
  for (var tonic = 0; tonic < 12; tonic++) {
    for (final minor in const [false, true]) {
      final profile = minor ? _minor : _major;
      final rotated = [
        for (var pc = 0; pc < 12; pc++) profile[(pc - tonic + 120) % 12],
      ];
      final corr = _pearson(pcp, rotated);
      if (corr > bestCorr) {
        bestCorr = corr;
        bestTonic = tonic;
        bestMinor = minor;
      }
    }
  }
  // Key signature: a minor key shares its relative major's signature.
  final majorTonic = bestMinor ? (bestTonic + 3) % 12 : bestTonic;
  var fifths = (majorTonic * 7) % 12;
  if (fifths > 6) fifths -= 12; // fold to −5…+6 (e.g. F = −1, not 11)
  return (fifths: fifths, tonic: bestTonic, minor: bestMinor);
}

/// Spell [midi] the way a key with signature [fifths] wants it — B-flat in a
/// flat key, A-sharp in a sharp key — via the line of fifths.
Pitch spellMidi(int midi, {int fifths = 0}) {
  final pc = _pc(midi);
  // The line-of-fifths positions with this pitch class repeat every 12; pick the
  // one nearest the key centre so the accidental matches the key.
  final base = (7 * pc) % 12; // a position in 0…11 with this pitch class
  var best = base;
  var bestDist = (base - fifths).abs();
  for (final cand in [base - 12, base + 12]) {
    final d = (cand - fifths).abs();
    if (d < bestDist) {
      bestDist = d;
      best = cand;
    }
  }
  final letter = _fifthLetters[(best + 1) % 7];
  final alter = ((best + 1) / 7).floor();
  // Octave that makes step+alter sound at exactly `midi` (handles B#, Cb).
  final octave = ((midi - _stepSemitones[letter]! - alter) ~/ 12) - 1;
  return Pitch(letter, alter: alter, octave: octave);
}

/// Re-spell every note of [score] for the key (given as [fifths], else estimated
/// from the score's own notes) and stamp the key signature. Targets a
/// transcription Score (single voice, notes + rests); preserves durations, ids,
/// ties and clef/time/tempo.
Score respell(Score score, {int? fifths}) {
  final f = fifths ?? estimateKey(_scoreNotes(score)).fifths;
  List<MusicElement> voice(List<MusicElement> els) => [
        for (final e in els) _respellElement(e, f),
      ];
  final measures = [
    for (final m in score.measures)
      Measure(
        voice(m.elements),
        voice2: voice(m.voice2),
        voice3: voice(m.voice3),
        voice4: voice(m.voice4),
        clefChange: m.clefChange,
        keyChange: m.keyChange,
        timeChange: m.timeChange,
        tempoChange: m.tempoChange,
      ),
  ];
  return Score(
    clef: score.clef,
    keySignature: KeySignature(f),
    timeSignature: score.timeSignature,
    tempo: score.tempo,
    metadata: score.metadata,
    measures: measures,
  );
}

MusicElement _respellElement(MusicElement e, int fifths) {
  if (e is NoteElement) {
    return NoteElement(
      pitches: [
        for (final p in e.pitches) spellMidi(p.midiNumber, fifths: fifths),
      ],
      duration: e.duration,
      id: e.id,
      tieToNext: e.tieToNext,
      articulations: e.articulations,
    );
  }
  return e; // rests and anything else pass through unchanged
}

List<NoteEvent> _scoreNotes(Score score) => [
      for (final m in score.measures)
        for (final e in [...m.elements, ...m.voice2, ...m.voice3, ...m.voice4])
          if (e is NoteElement)
            for (final p in e.pitches)
              (midi: p.midiNumber, onMs: 0, offMs: 1, confidence: 1),
    ];

double _pearson(List<double> a, List<double> b) {
  final n = a.length;
  var sa = 0.0, sb = 0.0;
  for (var i = 0; i < n; i++) {
    sa += a[i];
    sb += b[i];
  }
  final ma = sa / n, mb = sb / n;
  var num = 0.0, da = 0.0, db = 0.0;
  for (var i = 0; i < n; i++) {
    final xa = a[i] - ma, xb = b[i] - mb;
    num += xa * xb;
    da += xa * xa;
    db += xb * xb;
  }
  final den = da * db;
  return den <= 0 ? 0 : num / math.sqrt(den);
}
