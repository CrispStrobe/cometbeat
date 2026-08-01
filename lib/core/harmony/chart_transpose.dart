// lib/core/harmony/chart_transpose.dart
//
// BB-T4 — transposition, and the reason there are TWO of them.
//
// A horn player reads B♭ while the band plays concert pitch. Those are not the
// same operation and collapsing them into one "transpose" control is the
// classic mistake:
//
//   * SOUNDING — the tune moves to another key. The band plays it there and the
//     chart shows it there. This is "take it up a step".
//   * DISPLAY — only what is PRINTED moves. The band is unaffected. This is
//     "I read B♭" or "I have a capo on 3", and it must never change the audio.
//
// Everything here is INTERVAL-based rather than semitone-based, which is what
// makes the spelling come out right for free: `Pitch.transposeBy` already knows
// that up a major third from A♭ is C, not B♯. A semitone count cannot express
// that difference, so a semitone API would have to re-derive spelling from the
// key — badly. Semitones are accepted only at the edges (a capo is a fret
// count), and converted to the conventional interval immediately.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Interval, IntervalQuality, Pitch, Step;

/// What the player's instrument is pitched in.
///
/// The value is the interval the player READS ABOVE concert pitch: a B♭
/// trumpet sounding a concert B♭ is reading a C, a major second higher.
enum TransposingInstrument {
  /// Piano, guitar, strings, voice — reads what sounds.
  concert,

  /// B♭ trumpet, clarinet, tenor sax — reads a major second up.
  bFlat,

  /// E♭ alto/baritone sax — reads a major sixth up.
  eFlat,

  /// F horn, english horn — reads a perfect fifth up.
  f,
}

/// The interval [instrument] reads above concert, or null for concert pitch.
Interval? readingInterval(TransposingInstrument instrument) =>
    switch (instrument) {
      TransposingInstrument.concert => null,
      TransposingInstrument.bFlat => Interval.majorSecond,
      TransposingInstrument.eFlat => Interval.majorSixth,
      TransposingInstrument.f => Interval.perfectFifth,
    };

/// Both axes at once. Held by the screen; neither is stored on the chart,
/// because both are about the PLAYER rather than about the tune.
class ChartTransposition {
  const ChartTransposition({
    this.soundingSemitones = 0,
    this.instrument = TransposingInstrument.concert,
    this.capo = 0,
  });

  /// How far the tune itself moves. Affects audio AND print.
  final int soundingSemitones;

  /// What the reader's instrument is pitched in. Affects print only.
  final TransposingInstrument instrument;

  /// Guitar capo fret. Affects print only: with a capo on 3 you finger shapes
  /// three semitones BELOW what sounds.
  final int capo;

  bool get isIdentity =>
      soundingSemitones == 0 &&
      instrument == TransposingInstrument.concert &&
      capo == 0;

  /// True when only the printing changes, so the audio can be reused.
  bool get soundsUnchanged => soundingSemitones == 0;
}

/// The chart as it SOUNDS — what the band renders.
///
/// Display transpositions are deliberately absent: a capo and a B♭ horn change
/// nothing about the audio, and applying them here is the bug this whole file
/// exists to prevent.
Chart soundingChart(Chart chart, ChartTransposition t) =>
    t.soundingSemitones == 0
        ? chart
        : transposeChartBySemitones(chart, t.soundingSemitones);

/// The chart as it is PRINTED — what the grid shows.
///
/// Sounding first, then the reader's own offset on top, because a B♭ player
/// reading a tune that has been taken up a step reads both.
Chart displayChart(Chart chart, ChartTransposition t) {
  var out = soundingChart(chart, t);
  final reading = readingInterval(t.instrument);
  if (reading != null) out = transposeChart(out, reading);
  if (t.capo != 0) out = transposeChartBySemitones(out, -t.capo);
  return out;
}

/// [chart] moved by [interval].
///
/// Every chord, the slash bass and the key signature move together; nothing
/// else about the chart changes.
Chart transposeChart(
  Chart chart,
  Interval interval, {
  bool descending = false,
}) {
  if (interval == Interval.perfectUnison) return chart;

  final tonic = _tonicPitch(chart.keyFifths, minor: chart.minor);

  // ⚠️ The interval may have to be RESPELLED before anything moves. F♯ major up
  // a major second is G♯ major — eight sharps, a signature that does not exist.
  // The fix is not to clamp the key (that silently lands on an unrelated one),
  // it is to transpose by the ENHARMONIC interval instead: F♯ up a diminished
  // third is A♭, four flats, and every chord then spells in flats to match. Any
  // notation program does the same thing, and the card's "spelling follows the
  // target key signature" is exactly this.
  final chosen = _spellableInterval(
    interval,
    tonic,
    descending: descending,
    minor: chart.minor,
  );
  final newTonic = tonic.transposeBy(chosen, descending: descending);

  return Chart(
    title: chart.title,
    composer: chart.composer,
    keyFifths: _fifthsFor(newTonic, minor: chart.minor),
    minor: chart.minor,
    meter: chart.meter,
    tempoBpm: chart.tempoBpm,
    styleId: chart.styleId,
    pickupBeats: chart.pickupBeats,
    extra: chart.extra,
    sections: [
      for (final section in chart.sections)
        ChartSection(
          label: section.label,
          repeatCount: section.repeatCount,
          feel: section.feel,
          tempoScale: section.tempoScale,
          intensity: section.intensity,
          extra: section.extra,
          bars: [
            for (final bar in section.bars)
              ChartBar(
                meterChange: bar.meterChange,
                barline: bar.barline,
                endingNumber: bar.endingNumber,
                navigation: bar.navigation,
                extra: bar.extra,
                chords: [
                  for (final c in bar.chords)
                    ChartBeatChord(
                      chord:
                          c.chord.transposedBy(chosen, descending: descending),
                      beat: c.beat,
                      beats: c.beats,
                      extra: c.extra,
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

/// [chart] moved by [semitones], up or down, using the conventional interval.
///
/// For the cases a UI produces — a capo fret, a "+2 / −2" button — the
/// conventional spelling is what a musician expects: up two semitones is a
/// major second, not a diminished third.
Chart transposeChartBySemitones(Chart chart, int semitones) {
  final steps = ((semitones % 12) + 12) % 12;
  if (steps == 0 && semitones != 0) return chart; // whole octaves: no respell
  if (semitones == 0) return chart;
  final descending = semitones < 0;
  // A downward move of N is an upward move of N; the direction is the flag, so
  // the interval is always the positive one.
  final magnitude = descending ? (12 - steps) % 12 : steps;
  if (magnitude == 0) return chart;
  return transposeChart(
    chart,
    intervalForSemitones(magnitude),
    descending: descending,
  );
}

/// The interval a musician means by [semitones] (1..11).
///
/// Two of these are choices rather than facts: 6 could be an augmented fourth
/// or a diminished fifth, and the tritone has no conventional default — the
/// augmented fourth is taken because it spells upward moves with sharps, which
/// matches the ascending default. 3 is a minor third rather than an augmented
/// second for the same reason: it is what anyone would write.
Interval intervalForSemitones(int semitones) {
  final n = ((semitones % 12) + 12) % 12;
  return switch (n) {
    0 => Interval.perfectUnison,
    1 => Interval.minorSecond,
    2 => Interval.majorSecond,
    3 => Interval.minorThird,
    4 => Interval.majorThird,
    5 => Interval.perfectFourth,
    6 => Interval.augmentedFourth,
    7 => Interval.perfectFifth,
    8 => Interval.minorSixth,
    9 => Interval.majorSixth,
    10 => Interval.minorSeventh,
    _ => Interval.majorSeventh,
  };
}

/// The tonic of the key with [fifths] accidentals.
Pitch _tonicPitch(int fifths, {required bool minor}) {
  // The circle of fifths, major tonics from 7 flats to 7 sharps.
  const majors = <(Step, int)>[
    (Step.c, -1), (Step.g, -1), (Step.d, -1), (Step.a, -1), //
    (Step.e, -1), (Step.b, -1), (Step.f, 0), (Step.c, 0), //
    (Step.g, 0), (Step.d, 0), (Step.a, 0), (Step.e, 0), //
    (Step.b, 0), (Step.f, 1), (Step.c, 1),
  ];
  const minors = <(Step, int)>[
    (Step.a, -1), (Step.e, -1), (Step.b, -1), (Step.f, 0), //
    (Step.c, 0), (Step.g, 0), (Step.d, 0), (Step.a, 0), //
    (Step.e, 0), (Step.b, 0), (Step.f, 1), (Step.c, 1), //
    (Step.g, 1), (Step.d, 1), (Step.a, 1),
  ];
  final table = minor ? minors : majors;
  final (step, alter) = table[(fifths + 7).clamp(0, 14)];
  return Pitch(step, alter: alter);
}

/// [interval], or its enharmonic twin when [interval] would produce a key with
/// no signature.
///
/// The twin has the same semitone count and a diatonic number one away, which
/// is what "the same sound spelled differently" means: M2 ↔ dim3, m3 ↔ aug2,
/// M3 ↔ dim4, P4 ↔ aug3, P5 ↔ dim6, m6 ↔ aug5, M6 ↔ dim7, m7 ↔ aug6.
/// Only reached when the first choice runs off the circle of fifths.
Interval _spellableInterval(
  Interval interval,
  Pitch tonic, {
  required bool descending,
  required bool minor,
}) {
  bool fits(Interval i) {
    final f = _rawFifths(
      tonic.transposeBy(i, descending: descending),
      minor: minor,
    );
    return f >= -7 && f <= 7;
  }

  if (fits(interval)) return interval;
  for (final twin in _enharmonicTwins) {
    if (twin.semitones == interval.semitones &&
        twin.number != interval.number &&
        fits(twin)) {
      return twin;
    }
  }
  return interval; // nothing spellable; the caller clamps rather than throwing
}

/// The alternative spellings tried above, in the order they are preferred.
const _enharmonicTwins = <Interval>[
  Interval(IntervalQuality.diminished, 3),
  Interval(IntervalQuality.augmented, 2),
  Interval(IntervalQuality.diminished, 4),
  Interval(IntervalQuality.augmented, 3),
  Interval(IntervalQuality.diminished, 6),
  Interval(IntervalQuality.augmented, 5),
  Interval(IntervalQuality.diminished, 7),
  Interval(IntervalQuality.augmented, 6),
  Interval(IntervalQuality.diminished, 5),
];

/// The signature whose tonic is [tonic], clamped to a real one.
int _fifthsFor(Pitch tonic, {required bool minor}) =>
    _rawFifths(tonic, minor: minor).clamp(-7, 7);

/// The signature whose tonic is [tonic], NOT clamped — so the caller can tell
/// whether the key exists at all.
int _rawFifths(Pitch tonic, {required bool minor}) {
  const naturals = {
    Step.f: -1,
    Step.c: 0,
    Step.g: 1,
    Step.d: 2,
    Step.a: 3,
    Step.e: 4,
    Step.b: 5,
  };
  var fifths = (naturals[tonic.step] ?? 0) + 7 * tonic.alter;
  // A minor key's signature is its relative major's: three fifths flatter.
  if (minor) fifths -= 3;
  return fifths;
}
