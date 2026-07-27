// D1 — adding a track, by ROLE or empty.
//
// Duplicating shipped first because it needed no instrument tree: a copy is
// made from something already on screen. It also has a ceiling — you can only
// have more of what the band already is. The maintainer's call (option C) opens
// both ends at once: the five authored roles, so the first tap always lands on
// something that plays, AND an empty track, so the ceiling is gone.
//
// The two paths are deliberately different, and the tests below are mostly
// about keeping them different:
//
//   duplicate  = this track, again, with everything it has
//   add role   = this ROLE, fresh, at authored settings
//   add empty  = nothing, waiting for the tune grid
//
// The property that used to be missing entirely: an added track has to SURVIVE
// a save. Everything else about a track is keyed by id, and `applySpec` drops
// ids it does not know, so before the roster travelled in the spec a saved
// groove came back with the copies gone and their settings silently discarded.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass']);
  return e;
}

/// The peak sample of a rendered loop — enough to tell silence from sound.
int _peak(LoopEngine e) {
  final wav = e.renderLoop();
  var peak = 0;
  for (var i = 44; i + 1 < wav.length; i += 2) {
    var v = wav[i] | (wav[i + 1] << 8);
    if (v > 32767) v -= 65536;
    if (v.abs() > peak) peak = v.abs();
  }
  return peak;
}

void main() {
  group('adding a role', () {
    test('it joins the band, enabled, playing that role', () {
      final e = _engine();
      final id = e.addRoleTrack('bass');
      expect(id, isNotNull);
      expect(e.tracks.map((t) => t.id), contains(id));
      expect(e.enabled, contains(id));
      expect(e.isExtraTrack(id!), isTrue);
      expect(
        e.tracks.firstWhere((t) => t.id == id).variants,
        same(e.tracks.firstWhere((t) => t.id == 'bass').variants),
        reason: 'a role add plays that role\'s authored patterns',
      );
    });

    test('an unknown role is refused, not invented', () {
      expect(_engine().addRoleTrack('tuba'), isNull);
      expect(_engine().addRoleTrack(''), isNull);
    });

    test('it does NOT inherit the playing instance\'s settings', () {
      // The difference from duplicate, stated directly. A role add is a fresh
      // instance of the role; if it copied the mix settings it would just be a
      // second, worse duplicate.
      final e = _engine();
      e.levels['bass'] = 0.2;
      e.setPan('bass', -0.9);
      e.setTrackFilter('bass', -0.8);
      e.setTrackSteps('bass', 6);

      final id = e.addRoleTrack('bass')!;
      expect(e.levels[id], isNull);
      expect(e.panOf(id), 0.0);
      expect(e.trackFilter(id), 0.0);
      expect(e.trackSteps(id), kPatternSteps);
    });

    test('it takes a variant the role is not already playing', () {
      // Two tracks on the identical pattern are indistinguishable from one
      // louder track, so "add a bass" would read as a volume bump.
      final e = _engine();
      expect(e.variants['bass'] ?? 0, 0);
      final second = e.addRoleTrack('bass')!;
      expect(e.variants[second], isNot(0));

      final third = e.addRoleTrack('bass')!;
      expect(
        {0, e.variants[second], e.variants[third]}.length,
        3,
        reason: 'each added bass should be a different part',
      );
    });

    test('a role whose instances are DISABLED starts at A again', () {
      // "Not already playing" means playing. A muted bass is not competing
      // with the new one, so there is no reason to move off the authored A.
      final e = _engine()..enabled.remove('bass');
      expect(e.variants[e.addRoleTrack('bass')!] ?? 0, 0);
    });

    test('it runs out of variants gracefully', () {
      final e = _engine();
      final role = e.tracks.firstWhere((t) => t.id == 'bass');
      for (var i = 0; i < role.variants.length + 2; i++) {
        expect(e.addRoleTrack('bass'), isNotNull);
      }
      for (final t in e.tracks) {
        expect(
          e.variants[t.id] ?? 0,
          lessThan(role.variants.length),
          reason: 'never an out-of-range variant',
        );
      }
    });
  });

  group('adding an empty track', () {
    test('it joins enabled but SILENT', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      expect(e.enabled, contains(id));
      expect(e.isEmptyTrack(id), isTrue);

      // Enabled-but-silent is the point: the first note drawn into it is
      // audible without having to switch the track on afterwards.
      final withEmpty = _peak(e);
      e.enabled.remove(id);
      expect(withEmpty, _peak(e));
    });

    test('drawing notes into it makes it sound', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      final before = _peak(e);
      e.setTrackCells(id, const [
        PatternCell(midis: [60], steps: 8),
        PatternCell(midis: [67], steps: 8),
      ]);
      expect(_peak(e), isNot(before));
    });

    test('two empties are two tracks', () {
      final e = _engine();
      final a = e.addEmptyTrack();
      final b = e.addEmptyTrack();
      expect(a, isNot(b));
      expect(e.isEmptyTrack(a) && e.isEmptyTrack(b), isTrue);
    });

    test('a role add is not an empty track', () {
      final e = _engine();
      expect(e.isEmptyTrack(e.addRoleTrack('drums')!), isFalse);
      expect(e.isEmptyTrack('bass'), isFalse);
    });
  });

  group('naming', () {
    test('a track has no name until it is given one', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      expect(e.trackName(id), isNull);
      e.setTrackName(id, 'Ukulele');
      expect(e.trackName(id), 'Ukulele');
    });

    test('a blank name clears it rather than storing whitespace', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      e
        ..setTrackName(id, 'Ukulele')
        ..setTrackName(id, '   ');
      expect(e.trackName(id), isNull);
      e
        ..setTrackName(id, 'Ukulele')
        ..setTrackName(id, null);
      expect(e.trackName(id), isNull);
    });

    test('a name is trimmed and capped', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      e.setTrackName(id, '  Bass 2  ');
      expect(e.trackName(id), 'Bass 2');
      e.setTrackName(id, 'x' * 200);
      expect(e.trackName(id)!.length, 40);
    });

    test('removing the track takes its name with it', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      e.setTrackName(id, 'Ukulele');
      expect(e.removeExtraTrack(id), isTrue);
      expect(e.trackName(id), isNull);
    });
  });

  group('added tracks survive a save', () {
    test('a role add comes back, with its settings', () {
      final e = _engine();
      final id = e.addRoleTrack('bass')!;
      e.levels[id] = 0.3;
      e.setPan(id, 0.6);
      e.setTrackFilter(id, -0.5);
      e.setTrackName(id, 'Sub');
      final token = encodeGrooveToken(e.spec);

      final restored = LoopEngine(tempoBpm: 120)
        ..applySpec(decodeGrooveToken(token)!);
      expect(restored.tracks.map((t) => t.id), contains(id));
      expect(restored.enabled, contains(id));
      expect(restored.levels[id], closeTo(0.3, 1e-9));
      expect(restored.panOf(id), closeTo(0.6, 0.01));
      expect(restored.trackFilter(id), closeTo(-0.5, 0.01));
      expect(restored.trackName(id), 'Sub');
      expect(restored.isExtraTrack(id), isTrue);
    });

    test('an empty track comes back empty, with the notes drawn into it', () {
      final e = _engine();
      final id = e.addEmptyTrack();
      e.setTrackCells(id, const [
        PatternCell(midis: [60], steps: 16),
      ]);
      final restored = LoopEngine(tempoBpm: 120)
        ..applySpec(decodeGrooveToken(encodeGrooveToken(e.spec))!);
      expect(restored.isEmptyTrack(id), isTrue);
      expect(restored.trackCellsOverride(id)?.first.midis, [60]);
    });

    test('a COPY comes back too — the gap this closed', () {
      final e = _engine();
      e.variants['bass'] = 2;
      final copy = e.duplicateTrack('bass')!;
      final restored = LoopEngine(tempoBpm: 120)
        ..applySpec(decodeGrooveToken(encodeGrooveToken(e.spec))!);
      expect(restored.tracks.map((t) => t.id), contains(copy));
      expect(restored.variants[copy], 2);
    });

    test('loading a groove without added tracks removes the ones present', () {
      final e = _engine();
      final id = e.addRoleTrack('bass')!;
      const plain = GrooveSpec(enabled: {'drums'});
      e.applySpec(plain);
      expect(e.tracks.map((t) => t.id), isNot(contains(id)));
      expect(e.levels.containsKey(id), isFalse);
    });

    test('a stale setting cannot be inherited by a reused id', () {
      // The trap `removeExtraTrack` already avoided, now closed on the load
      // path too: `bass-2` goes away, `bass-2` comes back, and it must not
      // arrive muted at the old one's length.
      final e = _engine();
      final id = e.addRoleTrack('bass')!;
      e.setTrackSteps(id, 6);
      e.setAutomation(
        id,
        AutomationParam.level,
        AutomationLane(const [0, 0, 0, 0]),
      );
      e.applySpec(const GrooveSpec(enabled: {'drums'}));

      final again = e.addRoleTrack('bass')!;
      expect(again, id, reason: 'the id is free again, so it is reused');
      expect(e.trackSteps(again), kPatternSteps);
      expect(e.automationFor(again, AutomationParam.level), isNull);
    });

    test('a groove with no added tracks tokenises exactly as before', () {
      final e = _engine();
      final plain = encodeGrooveToken(e.spec);
      final id = e.addEmptyTrack();
      expect(encodeGrooveToken(e.spec), isNot(plain));
      e.removeExtraTrack(id);
      expect(
        encodeGrooveToken(e.spec),
        plain,
        reason: 'add-then-remove must leave no trace in the token',
      );
    });

    test('a foreign roster cannot smuggle a track in', () {
      // Token fields are user-pasteable text. An unknown role is dropped, and
      // an id colliding with the base band is refused rather than shadowing it.
      final e = _engine();
      e.applySpec(
        const GrooveSpec(
          enabled: {'drums', 'tuba-2', 'bass'},
          extraTracks: {'tuba-2': 'tuba', 'bass': 'drums'},
        ),
      );
      expect(e.tracks.map((t) => t.id), isNot(contains('tuba-2')));
      expect(
        e.tracks.where((t) => t.id == 'bass').length,
        1,
        reason: 'the base band cannot be shadowed by a roster entry',
      );
    });
  });
}
