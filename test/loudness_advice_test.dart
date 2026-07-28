// WS-A5 — what a loudness reading MEANS.
//
// The measurement itself is already pinned in loudness_test (the BS.1770
// filters, the gating, the inter-sample peak). What these tests protect is the
// half that faces a person: that the meter says the RIGHT thing about a mix,
// and in particular that it never tells someone their mix is fine when it will
// audibly break on delivery.
//
// So each test constructs a reading with one deliberate property and asserts
// the judgement, not the formatting. A meter that renders five numbers
// beautifully and reasons about them wrongly is worse than no meter, because it
// is trusted.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/loudness.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loudness_advice.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// A reading that is fine in every respect, so each test can spoil exactly one
/// thing and attribute the result to it.
LoudnessReading _clean({
  double integrated = -14,
  double shortTerm = -12,
  double momentary = -11,
  double truePeak = -2,
  double correlation = 0.4,
}) =>
    (
      integratedLufs: integrated,
      shortTermLufs: shortTerm,
      momentaryLufs: momentary,
      truePeakDb: truePeak,
      correlation: correlation,
    );

bool _hasWarning(List<LoudnessNote> notes) =>
    notes.any((n) => n.status == LoudnessStatus.warn);

LoudnessNote? _about(List<LoudnessNote> notes, String word) {
  for (final n in notes) {
    if (n.headline.toLowerCase().contains(word) ||
        n.detail.toLowerCase().contains(word)) {
      return n;
    }
  }
  return null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the things that actually break on delivery', () {
    test('a true peak over −1 dBTP is a WARNING, at any target', () {
      // The one reading here that describes damage rather than preference, so
      // it must not be silenced by choosing a different target.
      for (final target in LoudnessTarget.values) {
        final notes = loudnessAdvice(_clean(truePeak: -0.3), target: target);
        expect(_hasWarning(notes), isTrue, reason: target.name);
        expect(_about(notes, 'dbtp')?.status, LoudnessStatus.warn);
      }
    });

    test('a peak under the ceiling is not flagged', () {
      // −2 dBTP is the clean fixture's own default, i.e. a well-behaved mix.
      final notes = loudnessAdvice(_clean());
      expect(_about(notes, 'dbtp')?.status, LoudnessStatus.good);
    });

    test('negative correlation is a WARNING — the failure you cannot hear', () {
      // It sounds fine on the speakers in front of you and collapses on a
      // phone. That asymmetry is exactly why it earns a warning rather than a
      // note.
      final notes = loudnessAdvice(_clean(correlation: -0.4));
      expect(_about(notes, 'mono risk')?.status, LoudnessStatus.warn);
    });

    test('healthy stereo is not flagged', () {
      // 0.4 — the fixture default: ordinary, healthy stereo.
      final notes = loudnessAdvice(_clean());
      expect(_hasWarning(notes), isFalse);
    });

    test('near-mono is a NOTE, not a warning — nothing is wrong', () {
      // A mono-ish mix is a choice. Warning about it would train people to
      // widen material that does not need it.
      final notes = loudnessAdvice(_clean(correlation: 0.99));
      expect(_about(notes, 'near mono')?.status, LoudnessStatus.note);
      expect(_hasWarning(notes), isFalse);
    });
  });

  group('level is judged against where the mix is GOING', () {
    test('too loud says the loudness buys nothing', () {
      // The substantive point: it is not "too loud" in the abstract, it is that
      // playback normalisation will undo it and the squeezed dynamics will not
      // come back.
      final notes = loudnessAdvice(_clean(integrated: -8));
      final level = _about(notes, 'louder');
      expect(level, isNotNull);
      expect(level!.detail.toLowerCase(), contains('turned down'));
    });

    test('quieter than target is GOOD, not a fault', () {
      // The common wrong meter: flagging quiet as a problem, which is what
      // pushes people into the loudness war for no gain.
      final notes = loudnessAdvice(_clean(integrated: -20));
      final level = _about(notes, 'quieter');
      expect(level?.status, LoudnessStatus.good);
    });

    test('the same mix reads differently for broadcast than for streaming', () {
      // The whole reason the target is a parameter. −20 LUFS is quiet for
      // streaming and loud for R128.
      final reading = _clean(integrated: -20);
      expect(
        _about(loudnessAdvice(reading), 'quieter'), // streaming is the default
        isNotNull,
      );
      expect(
        _about(
          loudnessAdvice(reading, target: LoudnessTarget.broadcast),
          'louder',
        ),
        isNotNull,
      );
    });

    test('within tolerance says so instead of nagging', () {
      final notes = loudnessAdvice(_clean(integrated: -14.4));
      expect(_about(notes, 'on target')?.status, LoudnessStatus.good);
    });

    test('with NO target, level is reported and not judged', () {
      // Someone measuring a stem or a sound effect has no delivery target, and
      // inventing one would be advice about nothing.
      final notes = loudnessAdvice(
        _clean(integrated: -30),
        target: LoudnessTarget.none,
      );
      expect(_about(notes, 'quieter'), isNull);
      expect(_about(notes, 'louder'), isNull);
      expect(_about(notes, 'lufs integrated'), isNotNull);
      // …but the delivery-breaking checks still run.
      final clipping = loudnessAdvice(
        _clean(truePeak: -0.2),
        target: LoudnessTarget.none,
      );
      expect(_hasWarning(clipping), isTrue);
    });
  });

  group('silence and degenerate readings', () {
    test('silence says "silence" and stops', () {
      // Every other line would be a comment on nothing — "your silence is 14 dB
      // too quiet" is worse than useless.
      final notes = loudnessAdvice(_clean(integrated: kLoudnessSilenceLufs));
      expect(notes, hasLength(1));
      expect(notes.single.headline, 'Silence');
    });

    test('an empty measurement of real silence round-trips from the DSP', () {
      // Not a constructed fixture: measure actual digital silence and confirm
      // the advice layer recognises what the measurement layer produced. The
      // two agree on the floor, or this whole path lies about quiet material.
      final reading = measureLoudness(
        Float64List(44100),
        Float64List(44100),
        sampleRate: 44100,
      );
      expect(loudnessAdvice(reading).single.headline, 'Silence');
    });
  });

  group('the crest note', () {
    test('a squashed mix is described, not condemned', () {
      // It is a choice, so it is a note. But it is the number that explains why
      // a loud master gets tiring, which is worth saying.
      final notes = loudnessAdvice(_clean(shortTerm: -5));
      expect(_about(notes, 'dynamics are tight')?.status, LoudnessStatus.note);
    });

    test('a dynamic mix gets no crest note at all', () {
      final notes = loudnessAdvice(_clean(shortTerm: -18));
      expect(_about(notes, 'dynamics are tight'), isNull);
    });
  });

  test('every note carries a headline AND a reason', () {
    // The point of the layer. A headline with no explanation is the number
    // dump this exists to replace.
    for (final reading in [
      _clean(),
      _clean(truePeak: -0.1, correlation: -0.5, integrated: -6, shortTerm: -5),
      _clean(integrated: -30),
    ]) {
      for (final note in loudnessAdvice(reading)) {
        expect(note.headline, isNotEmpty);
        expect(note.detail.length, greaterThan(20), reason: note.headline);
      }
    }
  });

  group('the meter is actually reachable, and reports', () {
    // WS-A5 asked for the metering as a VIEW. The DSP and the CLI were already
    // done; what did not exist was any way to see it, so "the door opens and
    // shows a real reading" IS the feature being tested here.
    testWidgets('a mix opens the meter and it reads the audio', (tester) async {
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
      );
      final daw = Provider.of<DawService>(
        tester.element(find.byType(DawScreen)),
        listen: false,
      );
      // A steady tone at a known level, so the readout cannot be "Silence"
      // by accident.
      final pcm = Float64List(kDawSampleRate * 2);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = 0.25 * math.sin(2 * math.pi * 440 * i / kDawSampleRate);
      }
      daw.addClip(SampleSource(pcm));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loudness'));
      await tester.pumpAndSettle();

      expect(find.text('Loudness — mix'), findsOneWidget);
      // It reported on real audio rather than falling through to the silence
      // short-circuit.
      expect(find.text('Silence'), findsNothing);
      expect(find.textContaining('LUFS'), findsWidgets);
      // And the target is offered, because every level line depends on it.
      expect(find.text('Streaming'), findsOneWidget);
      expect(find.text('Broadcast'), findsOneWidget);
    });

    testWidgets('with no clips the door is disabled, not empty',
        (tester) async {
      // Opening onto "Silence" would be a worse answer than not offering it.
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Loudness'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}
