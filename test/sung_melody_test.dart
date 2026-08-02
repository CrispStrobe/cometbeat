// Live pitch → melodic query, the whole mode-2 chain minus the microphone.
//
// The app's audio work is validated by synthesising the input and asserting the
// detector reads it back (the pattern CLAUDE.md records as "the acceptance
// pattern that works"). Same idea here: build the pitch frames a singer would
// produce — with the artefacts a real voice produces — and check the tune comes
// out the other end.

import 'dart:math';

import 'package:comet_beat/core/music/melodic_search.dart';
import 'package:comet_beat/core/music/sung_melody.dart';
import 'package:flutter_test/flutter_test.dart';

/// The analysis hop the mic path runs at — ~11 ms/frame is typical for a
/// 512-sample hop at 44.1 kHz.
const _hopMs = 11.0;

double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

/// Frames for [midi] held for [ms], with optional vibrato and a clarity floor.
///
/// Vibrato is not decoration: a sung note wobbles, and a segmenter that cannot
/// absorb it fragments one note into several — which would insert spurious
/// intervals and change the shape.
List<({int midi, double ms, bool silent})> _phrase(
  List<int> midis, {
  double noteMs = 400,
  double gapMs = 80,
}) =>
    [
      for (final m in midis) ...[
        (midi: m, ms: noteMs, silent: false),
        (midi: m, ms: gapMs, silent: true),
      ],
    ];

SungMelodyCollector _sing(
  List<({int midi, double ms, bool silent})> phrase, {
  double vibratoCents = 20,
  double clarity = 0.95,
}) {
  final c = SungMelodyCollector();
  var t = 0.0;
  var i = 0;
  for (final seg in phrase) {
    final frames = (seg.ms / _hopMs).round();
    for (var f = 0; f < frames; f++, i++) {
      if (seg.silent) {
        c.add(frequency: 0, clarity: 0, timeMs: t);
      } else {
        // ±vibratoCents at ~5.5 Hz, the rate a human voice actually wobbles at.
        final cents = vibratoCents * sin(2 * pi * 5.5 * (t / 1000));
        c.add(
          frequency: _hz(seg.midi) * pow(2, cents / 1200),
          clarity: clarity,
          timeMs: t,
        );
      }
      t += _hopMs;
    }
  }
  return c;
}

void main() {
  group('collecting', () {
    test('too little singing yields no query at all', () {
      // A handful of frames decodes to noise, and ranking the catalog against
      // noise gives confident-looking nonsense instead of an obvious failure.
      final c = SungMelodyCollector();
      for (var i = 0; i < 5; i++) {
        c.add(frequency: 440, clarity: 0.9, timeMs: i * _hopMs);
      }
      expect(c.hasEnough, isFalse);
      expect(c.toQuery(), isEmpty);
    });

    test('silence is KEPT as frames, not discarded', () {
      // Silence is what separates one note from the next. Dropping it fuses a
      // repeated note into one long one — a different shape.
      final c = SungMelodyCollector()
        ..add(frequency: 440, clarity: 0.9, timeMs: 0)
        ..add(frequency: 0, clarity: 0, timeMs: 11)
        ..add(frequency: 440, clarity: 0.9, timeMs: 22);
      expect(c.frameCount, 3);
      expect(c.track[1].voicedProb, 0.0);
    });

    test('clear resets it', () {
      final c = _sing(_phrase(const [60, 62, 64]));
      expect(c.hasEnough, isTrue);
      c.clear();
      expect(c.frameCount, 0);
      expect(c.toQuery(), isEmpty);
    });
  });

  group('transcribing a sung phrase', () {
    test('a plain rising phrase comes back as the notes sung', () {
      final q = _sing(_phrase(const [60, 62, 64, 65])).toQuery();
      expect(q, [60, 62, 64, 65]);
    });

    test('vibrato does not fragment a note', () {
      // 50 cents of wobble is a wide but real vocal vibrato. If the segmenter
      // broke on it, this would come back with extra notes.
      final q = _sing(_phrase(const [60, 64, 67]), vibratoCents: 50).toQuery();
      expect(q, [60, 64, 67]);
    });

    test('a REPEATED note survives as two notes', () {
      // The property the whole search rests on: "C C G" is [0,+7] and "C G" is
      // [+7]. If the gap between two equal pitches were swallowed, every tune
      // that opens by repeating a note would be unfindable.
      final q = _sing(_phrase(const [60, 60, 67])).toQuery();
      expect(q, [60, 60, 67]);
    });
  });

  group('end to end — sing it, find it', () {
    test('a sung Ode to Joy finds Ode to Joy, in a key nobody wrote it in', () {
      const ode = [64, 64, 65, 67, 67, 65, 64, 62];
      final pool = [
        const MelodicCandidate('ode', ode),
        const MelodicCandidate('scale', [60, 62, 64, 65, 67, 69, 71, 72]),
        const MelodicCandidate('flat', [60, 60, 60, 60, 60, 60, 60, 60]),
      ];
      // Sung a minor third up, with vibrato.
      final sungMidis = [for (final m in ode) m + 3];
      final q = _sing(_phrase(sungMidis), vibratoCents: 30).toQuery();

      expect(q, sungMidis, reason: 'the phrase transcribed cleanly');
      final hits = searchMelodies(q, pool);
      expect(hits.first.id, 'ode');
      expect(hits.first.score, 1.0);
    });

    test('a wrong note degrades the match without destroying it', () {
      // A hum is not exact. One wrong note must cost rank, not the result.
      const ode = [64, 64, 65, 67, 67, 65, 64, 62];
      final pool = [
        const MelodicCandidate('ode', ode),
        const MelodicCandidate('scale', [60, 62, 64, 65, 67, 69, 71, 72]),
      ];
      final wobbly = [...ode]..[5] = 66; // F -> F#
      final q = _sing(_phrase(wobbly)).toQuery();
      final hits = searchMelodies(q, pool);
      expect(hits.first.id, 'ode');
      expect(hits.first.score, lessThan(1.0));
      expect(hits.first.score, greaterThan(0.7));
    });
  });
}
