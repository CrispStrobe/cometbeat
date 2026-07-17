// lib/features/games/note_reading/satb_voicing.dart
//
// Shared voicing + rendering for the SATB reading games (Read the Voice, Which
// Voice?, and the ear variant). A random diatonic triad (C major, or several
// major keys when `wide`) is voiced into 2 (Soprano + Alto) or 4 (SATB) parts
// and laid out on a one- or two-staff system, using crisp_notation's `Measure.voice2`
// (two voices per staff, stems up/down) — no voice crossing, Soprano/Alto on
// treble, Tenor/Bass on bass.

import 'dart:math';

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';

const _whole = NoteDuration(DurationBase.whole);

enum SatbVoice { soprano, alto, tenor, bass }

extension SatbVoiceX on SatbVoice {
  /// Element id used for highlighting.
  String get id => switch (this) {
        SatbVoice.soprano => 's',
        SatbVoice.alto => 'a',
        SatbVoice.tenor => 't',
        SatbVoice.bass => 'b',
      };

  /// Staff the voice is drawn on (S/A treble, T/B bass).
  Clef get clef => this == SatbVoice.tenor || this == SatbVoice.bass
      ? Clef.bass
      : Clef.treble;

  /// Localized display name (the enum's own `.name` stays 'soprano' etc. for ids).
  String label(AppLocalizations l) => switch (this) {
        SatbVoice.soprano => l.voiceSoprano,
        SatbVoice.alto => l.voiceAlto,
        SatbVoice.tenor => l.voiceTenor,
        SatbVoice.bass => l.voiceBass,
      };
}

/// One voice of the current chord: its role and the pitch it sings.
class SatbPart {
  final SatbVoice voice;
  final Pitch pitch;
  const SatbPart(this.voice, this.pitch);
  String get id => voice.id;
}

// Major-key diatonic triads by degree: (interval above the tonic, quality).
// null interval = the tonic itself. The first three are the primary triads
// (I / IV / V), used at the 2-voice level.
const _degreeSpec = <(Interval?, ChordQuality)>[
  (null, ChordQuality.major), // I
  (Interval.perfectFourth, ChordQuality.major), // IV
  (Interval.perfectFifth, ChordQuality.major), // V
  (Interval.majorSecond, ChordQuality.minor), // ii
  (Interval.majorThird, ChordQuality.minor), // iii
  (Interval.majorSixth, ChordQuality.minor), // vi
  (Interval.majorSeventh, ChordQuality.diminished), // vii°
];

/// Major keys used at the widened level (C plus a few near ones on the circle
/// of fifths). Triads are spelled correctly per key via the [Triad] pitches.
const _easyKeys = [Pitch(Step.c)];
const _wideKeys = [
  Pitch(Step.c),
  Pitch(Step.g),
  Pitch(Step.f),
  Pitch(Step.d),
  Pitch(Step.b, alter: -1), // B♭
];

int _nextTone(int floor, Set<int> pcs) {
  var m = floor;
  while (!pcs.contains(m % 12)) {
    m++;
  }
  return m;
}

/// Voice a random diatonic triad into 2 (Soprano + Alto) or, when [satb], 4
/// parts. [wide] draws from several major keys instead of just C. Bass sits in
/// octave 3 and each upper voice is the next chord tone above, with Alto pushed
/// to middle C so S/A land on the treble staff and T/B on the bass — no voice
/// crossing. Accidentals (in non-C keys) are spelled correctly and drawn inline.
List<SatbPart> voiceRandomChord(
  Random random, {
  required bool satb,
  bool wide = false,
}) {
  final keys = wide ? _wideKeys : _easyKeys;
  final tonic = keys[random.nextInt(keys.length)];
  final (interval, quality) = _degreeSpec[random.nextInt(satb ? 7 : 3)];
  final root = interval == null ? tonic : tonic.transposeBy(interval);

  // pitch class → correctly-spelled chord tone (from the triad).
  final spelled = {
    for (final p in Triad(root, quality).pitches) p.midiNumber % 12: p,
  };
  Pitch at(int midi) {
    final p = spelled[midi % 12]!;
    return Pitch(p.step, alter: p.alter, octave: midi ~/ 12 - 1);
  }

  final pcs = spelled.keys.toSet();
  final bass = 48 + root.midiNumber % 12;
  final tenor = _nextTone(bass + 3, pcs);
  final alto = _nextTone(max(60, tenor + 1), pcs);
  final soprano = _nextTone(alto + 3, pcs);
  return [
    SatbPart(SatbVoice.soprano, at(soprano)),
    SatbPart(SatbVoice.alto, at(alto)),
    if (satb) SatbPart(SatbVoice.tenor, at(tenor)),
    if (satb) SatbPart(SatbVoice.bass, at(bass)),
  ];
}

Score _staff(Clef clef, SatbPart upper, SatbPart? lower) => Score(
      clef: clef,
      measures: [
        Measure(
          [NoteElement.note(upper.pitch, _whole, id: upper.id)],
          voice2: lower == null
              ? const []
              : [NoteElement.note(lower.pitch, _whole, id: lower.id)],
        ),
      ],
    );

/// The one- (2-voice) or two-staff (SATB) system for [parts].
StaffSystem satbSystem(List<SatbPart> parts) {
  SatbPart of(SatbVoice v) => parts.firstWhere((p) => p.voice == v);
  SatbPart? maybe(SatbVoice v) {
    for (final p in parts) {
      if (p.voice == v) return p;
    }
    return null;
  }

  final hasLower = maybe(SatbVoice.tenor) != null;
  return StaffSystem([
    _staff(Clef.treble, of(SatbVoice.soprano), maybe(SatbVoice.alto)),
    if (hasLower) _staff(Clef.bass, of(SatbVoice.tenor), maybe(SatbVoice.bass)),
  ]);
}
