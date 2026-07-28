// Everything about a groove survives a save.
//
// `GrooveSpec` is the app's single answer to three questions at once — the save
// slot, the `KU1.` share token and the render-cache key — so anything it does
// not carry is silently lost when a player saves, and silently shared as
// something else when they send a token to a friend.
//
// Three things were missing, and none of them announced itself: per-track
// LENGTH (polymeter), per-track SWING, and AUTOMATION LANES. The last is the
// one worth naming, because it was not an oversight of scope: A1 specified a
// `GrooveSpec` field, wrote the codec, and tested the codec — and then nothing
// ever called it, so a player could draw a fade across sixteen steps, save, and
// get back a groove with no fade and no error.
//
// This file is the round-trip for the WHOLE object rather than a test per
// field, because the failure mode is "a field nobody wired up", and a per-field
// test only exists for fields somebody thought about.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_track_length.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass']);
  return e;
}

/// The engine a token restores to.
LoopEngine _roundTrip(LoopEngine e) => LoopEngine(tempoBpm: 120)
  ..applySpec(decodeGrooveToken(encodeGrooveToken(e.spec))!);

/// A groove using every per-track feature at once.
LoopEngine _fullyDressed() {
  final e = _engine();
  final added = e.addRoleTrack('bass')!;
  final empty = e.addEmptyTrack();
  e
    ..levels['bass'] = 0.4
    ..setPan('bass', -0.7)
    ..setTrackFilter('bass', -0.6)
    ..setTrackSteps('drums', 3)
    ..setTrackSwing('drums', 0.4)
    ..setTrackName(empty, 'Ukulele')
    ..setTrackName(added, 'Sub')
    ..setAutomation(
      'bass',
      AutomationParam.level,
      AutomationLane(const [1, 0.66, 0.33, 0, 0.33, 0.66, 1, 1]),
    )
    ..setAutomation(
      'drums',
      AutomationParam.pan,
      AutomationLane(const [0, 1]),
    )
    ..setAutomation(
      added,
      AutomationParam.filter,
      AutomationLane(const [0.5, 0.25, 0, 0.25]),
    );
  return e;
}

void main() {
  group('per-track LENGTH survives', () {
    test('a shortened track comes back shortened', () {
      final e = _engine()..setTrackSteps('drums', 3);
      expect(_roundTrip(e).trackSteps('drums'), 3);
    });

    test('every allowed length round-trips', () {
      for (final len in kLoopTrackLengths) {
        final e = _engine()..setTrackSteps('bass', len);
        expect(_roundTrip(e).trackSteps('bass'), len, reason: 'length $len');
      }
    });

    test('a length the engine would refuse is DROPPED, not clamped', () {
      // A token is user-pasteable text. The allowed set is what bounds the
      // render buffer, and rounding a 5 to a 4 would be a lie about what plays.
      final e = _engine()
        ..applySpec(
          const GrooveSpec(
            enabled: {'drums'},
            trackSteps: {'drums': 5},
          ),
        );
      expect(e.trackSteps('drums'), kPatternSteps);
      expect(
        GrooveSpec.fromJson({
          'e': ['drums'],
          'ts': {'drums': 5},
        }).trackSteps,
        isEmpty,
      );
    });

    test('loading a groove without it un-shortens the track', () {
      // Merging instead of replacing would leave a 3-step hat behind from
      // whatever was on screen before.
      final e = _engine()..setTrackSteps('drums', 3);
      e.applySpec(const GrooveSpec(enabled: {'drums'}));
      expect(e.trackSteps('drums'), kPatternSteps);
    });
  });

  group('per-track SWING survives', () {
    test('a track with its own swing keeps it', () {
      final e = _engine()..setTrackSwing('drums', 0.4);
      final back = _roundTrip(e);
      expect(back.hasOwnSwing('drums'), isTrue);
      expect(back.trackSwing('drums'), closeTo(0.4, 0.01));
    });

    test('"its own, and equal to the global" is NOT "following"', () {
      // The distinction the engine draws deliberately: a track set to the swing
      // it would have followed anyway must not start following when the
      // groove's swing later changes.
      final e = _engine()
        ..swing = 0.2
        ..setTrackSwing('drums', 0.2);
      final back = _roundTrip(e)..swing = 0.6;
      expect(back.hasOwnSwing('drums'), isTrue);
      expect(back.trackSwing('drums'), closeTo(0.2, 0.01));
    });

    test('a track that follows the groove keeps following', () {
      final e = _engine()..swing = 0.3;
      final back = _roundTrip(e);
      expect(back.hasOwnSwing('drums'), isFalse);
      expect(back.trackSwing('drums'), closeTo(0.3, 0.01));
    });
  });

  group('AUTOMATION LANES survive — they never did before', () {
    test('a level lane comes back, value for value', () {
      final lane = AutomationLane(const [1, 0.66, 0.33, 0, 0.33, 0.66, 1, 1]);
      final e = _engine()..setAutomation('bass', AutomationParam.level, lane);
      expect(_roundTrip(e).automationFor('bass', AutomationParam.level), lane);
    });

    test('every parameter travels, on its own track', () {
      final e = _fullyDressed();
      final back = _roundTrip(e);
      for (final t in e.tracks) {
        for (final p in AutomationParam.values) {
          expect(
            back.automationFor(t.id, p),
            e.automationFor(t.id, p),
            reason: '${t.id} / ${p.name}',
          );
        }
      }
    });

    test('a lane on an added track travels with the track', () {
      // The two features have to work TOGETHER: the roster is rebuilt before
      // `known` is taken, so a lane keyed to an added track is not dropped as
      // an unknown id.
      final e = _engine();
      final added = e.addRoleTrack('bass')!;
      e.setAutomation(
        added,
        AutomationParam.filter,
        AutomationLane(const [0.5, 0]),
      );
      final back = _roundTrip(e);
      expect(back.tracks.map((t) => t.id), contains(added));
      expect(
        back.automationFor(added, AutomationParam.filter),
        AutomationLane(const [0.5, 0]),
      );
    });

    test('a restored lane RENDERS the same audio', () {
      // The round trip is only worth anything if the groove sounds the same;
      // comparing the spec to itself would pass on a lane the mixer ignores.
      final e = _fullyDressed();
      expect(_roundTrip(e).renderLoop(), orderedEquals(e.renderLoop()));
    });

    test('loading a groove without lanes clears the ones on screen', () {
      final e = _engine()
        ..setAutomation(
          'bass',
          AutomationParam.level,
          AutomationLane(const [1, 0]),
        );
      e.applySpec(const GrooveSpec(enabled: {'bass'}));
      expect(e.automationFor('bass', AutomationParam.level), isNull);
      expect(e.hasAutomation, isFalse);
    });

    test('a lane on a track the groove does not have is dropped', () {
      final e = _engine()
        ..applySpec(
          GrooveSpec(
            enabled: const {'drums'},
            automation: {
              'tuba': {
                AutomationParam.level: AutomationLane(const [0]),
              },
            },
          ),
        );
      expect(e.automationFor('tuba', AutomationParam.level), isNull);
      expect(e.hasAutomation, isFalse);
    });

    test('a malformed lane loses that lane, not the groove', () {
      final spec = GrooveSpec.fromJson({
        'e': ['bass'],
        'au': {
          'bass': {
            'level': [0.5, 'nonsense'],
            'pan': [0.25, 0.75],
          },
        },
      });
      expect(spec.enabled, contains('bass'));
      expect(spec.automation['bass']?[AutomationParam.level], isNull);
      expect(
        spec.automation['bass']?[AutomationParam.pan],
        AutomationLane(const [0.25, 0.75]),
      );
    });
  });

  group('the whole groove, end to end', () {
    test('a fully-dressed groove restores identically and sounds the same', () {
      final e = _fullyDressed();
      final back = _roundTrip(e);
      expect(back.spec.cacheKey, e.spec.cacheKey);
      expect(back.renderLoop(), orderedEquals(e.renderLoop()));
    });

    test('a groove using none of it tokenises exactly as before', () {
      // The rule every field added to this object has had to obey: absent at
      // its default, so an old token and a new one for the same groove are the
      // same bytes.
      final plain = encodeGrooveToken(_engine().spec);
      expect(plain, isNot(contains('ts')));
      expect(plain, isNot(contains('tw')));
      expect(plain, isNot(contains('au')));

      final e = _engine()
        ..setTrackSteps('drums', 3)
        ..setTrackSwing('bass', 0.4)
        ..setAutomation(
          'bass',
          AutomationParam.level,
          AutomationLane(const [1, 0]),
        );
      expect(encodeGrooveToken(e.spec), isNot(plain));

      e
        ..setTrackSteps('drums', kPatternSteps)
        ..setTrackSwing('bass', null)
        ..setAutomation('bass', AutomationParam.level, null);
      expect(
        encodeGrooveToken(e.spec),
        plain,
        reason: 'undoing all three must leave no trace in the token',
      );
    });

    test('a snapshot does not change under the engine that made it', () {
      // The lanes map is nested, and the inner map is mutable and lives on in
      // the engine — a snapshot sharing it would rewrite itself.
      final e = _engine()
        ..setAutomation(
          'bass',
          AutomationParam.level,
          AutomationLane(const [1, 0]),
        );
      final snapshot = e.spec;
      final key = snapshot.cacheKey;
      e.setAutomation(
        'bass',
        AutomationParam.pan,
        AutomationLane(const [0, 1]),
      );
      expect(snapshot.cacheKey, key);
    });

    test('a foreign token cannot make the engine unplayable', () {
      // Every field is untrusted text. Absurd values must be refused or
      // clamped, and the groove must still render.
      final e = _engine();
      e.applySpec(
        GrooveSpec.fromJson({
          'e': ['drums', 'bass'],
          'ts': {'drums': 99, 'bass': -4},
          'tw': {'drums': 900.0, 'bass': -5.0},
          'au': {
            'drums': {'level': <double>[]},
            'bass': {'filter': 'not a lane'},
          },
        }),
      );
      expect(e.trackSteps('drums'), kPatternSteps);
      expect(e.trackSwing('drums'), inInclusiveRange(0.0, 0.6));
      expect(e.trackSwing('bass'), inInclusiveRange(0.0, 0.6));
      expect(e.hasAutomation, isFalse);
      expect(e.renderLoop().length, greaterThan(44));
    });
  });
}
