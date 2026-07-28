// WS-W5b — the project mix, made audible.
//
// WS-W5 shipped a mixer no render path honoured. These tests are about the
// thing that was missing: level, pan, mute and solo actually CHANGING THE
// SAMPLES. Assertions are on measured energy rather than on plumbing, because
// "the function was called" would have passed before this existed too.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_render.dart';
import 'package:flutter_test/flutter_test.dart';

/// A groove that actually makes noise, so the assertions measure sound rather
/// than the absence of a bug.
GrooveSpec _groove() => const GrooveSpec(enabled: {'drums'});

double _rms(Float64List x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

Project _projectWith(List<ProjectTrack> tracks) =>
    Project(name: 'Mix', tracks: tracks);

ProjectTrack _loopTrack(
  String id, {
  ProjectTrackMix mix = const ProjectTrackMix(),
}) =>
    ProjectTrack(
      id: id,
      kind: AppMode.loop,
      name: id,
      document: _groove(),
      mix: mix,
    );

void main() {
  test('a groove track renders to actual audio', () {
    // Guard for every test below: if this is silent the rest prove nothing.
    final mix = renderProject(_projectWith([_loopTrack('a')]));
    expect(mix.isSilent, isFalse);
    expect(_rms(mix.left), greaterThan(0));
    expect(mix.left.length, mix.right.length);
    expect(mix.skipped, isEmpty);
  });

  test('an empty project is silent, not an error', () {
    final mix = renderProject(_projectWith([]));
    expect(mix.isSilent, isTrue);
    expect(mix.durationMs, 0);
  });

  group('the mixer values reach the samples', () {
    test('level scales the output', () {
      final full = renderProject(_projectWith([_loopTrack('a')]));
      final half = renderProject(
        _projectWith([
          _loopTrack('a', mix: const ProjectTrackMix(level: 0.5)),
        ]),
      );
      expect(_rms(half.left), closeTo(_rms(full.left) * 0.5, 1e-9));
    });

    test('mute silences that track', () {
      final mix = renderProject(
        _projectWith([
          _loopTrack('a', mix: const ProjectTrackMix(muted: true)),
        ]),
      );
      expect(mix.isSilent, isTrue);
    });

    test('a zero fader is silent without being called muted', () {
      final mix = renderProject(
        _projectWith([_loopTrack('a', mix: const ProjectTrackMix(level: 0))]),
      );
      expect(mix.isSilent, isTrue);
    });

    test('pan moves energy between the channels, constant-power at centre', () {
      final centred = renderProject(_projectWith([_loopTrack('a')]));
      expect(
        _rms(centred.left),
        closeTo(_rms(centred.right), 1e-9),
        reason: 'centre is equal in both channels',
      );

      final hardLeft = renderProject(
        _projectWith([_loopTrack('a', mix: const ProjectTrackMix(pan: -1))]),
      );
      expect(_rms(hardLeft.right), lessThan(1e-9));
      expect(_rms(hardLeft.left), greaterThan(_rms(centred.left)));

      // Constant power: hard-panned into one channel is √2 louder than the
      // centre's per-channel level, which is what keeps loudness even as a
      // track moves off-centre.
      expect(
        _rms(hardLeft.left),
        closeTo(_rms(centred.left) * math.sqrt2, 1e-6),
      );
    });
  });

  group('solo', () {
    test('any solo silences the un-soloed', () {
      final mix = renderProject(
        _projectWith([
          _loopTrack('a', mix: const ProjectTrackMix(soloed: true)),
          _loopTrack('b'),
        ]),
      );
      final soloAlone = renderProject(_projectWith([_loopTrack('a')]));
      expect(_rms(mix.left), closeTo(_rms(soloAlone.left), 1e-9));
    });

    test('several tracks can be soloed together', () {
      // The mixer deliberately allows it, so the renderer has to honour it.
      final two = renderProject(
        _projectWith([
          _loopTrack('a', mix: const ProjectTrackMix(soloed: true)),
          _loopTrack('b', mix: const ProjectTrackMix(soloed: true)),
        ]),
      );
      final one = renderProject(_projectWith([_loopTrack('a')]));
      expect(_rms(two.left), greaterThan(_rms(one.left)));
    });

    test('a soloed AND muted track stays silent', () {
      // Muting something you soloed is a deliberate act, not a contradiction
      // to resolve in the user's favour.
      final mix = renderProject(
        _projectWith([
          _loopTrack(
            'a',
            mix: const ProjectTrackMix(soloed: true, muted: true),
          ),
        ]),
      );
      expect(mix.isSilent, isTrue);
    });
  });

  group('honesty about what it cannot render', () {
    test('a tab track is REPORTED, not silently dropped', () {
      final mix = renderProject(
        _projectWith([
          _loopTrack('a'),
          ProjectTrack(id: 'gtr', kind: AppMode.tab, document: 'a tab'),
        ]),
      );
      expect(mix.isSilent, isFalse, reason: 'the loop still sounds');
      expect(mix.skipped.map((s) => s.trackId), ['gtr']);
      expect(mix.skipped.single.reason, contains('instrument'));
    });

    test('a track with no document is reported', () {
      final mix = renderProject(
        _projectWith([ProjectTrack(id: 'x', kind: AppMode.loop)]),
      );
      expect(mix.skipped.single.reason, contains('no document'));
    });

    test('a track carried from a newer build is reported, never rendered', () {
      final mix = renderProject(
        _projectWith([
          ProjectTrack(
            id: 'future',
            kind: AppMode.loop,
            unknownKind: 'hologram',
            unreadable: const {'raw': 1},
          ),
        ]),
      );
      expect(mix.skipped.single.reason, contains('newer version'));
    });

    test('a MUTED unrenderable track is not reported', () {
      // Nothing was lost, so warning about it would be noise.
      final mix = renderProject(
        _projectWith([
          ProjectTrack(
            id: 'gtr',
            kind: AppMode.tab,
            document: 'a tab',
            mix: const ProjectTrackMix(muted: true),
          ),
        ]),
      );
      expect(mix.skipped, isEmpty);
    });
  });

  test('two tracks sum, and the longer one sets the length', () {
    final one = renderProject(_projectWith([_loopTrack('a')]));
    final two = renderProject(_projectWith([_loopTrack('a'), _loopTrack('b')]));
    expect(two.lengthInSamples, one.lengthInSamples);
    expect(
      _rms(two.left),
      greaterThan(_rms(one.left)),
      reason: 'summing two identical grooves is louder than one',
    );
  });

  test('no normalisation — the fader is not a lie', () {
    // A mixdown that quietly renormalised would make every level setting
    // meaningless while still passing a "does it make sound" test.
    final quiet = renderProject(
      _projectWith([_loopTrack('a', mix: const ProjectTrackMix(level: 0.1))]),
    );
    final loud = renderProject(_projectWith([_loopTrack('a')]));
    expect(_rms(quiet.left), lessThan(_rms(loud.left) * 0.2));
  });
}
