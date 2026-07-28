// A derived channel inherits its source's replay rules — structurally.
//
// PLAN.md §6. The render paths synthesize channels in nine places (`zoneChannel`,
// `baked`) to isolate one zone or one baked instrument. When `ReplayProfile` was
// added as a field, none of them carried it, so zone-based renders silently fell
// back to `native` rules: a MOD bending pitch linearly and panning constant-power
// inside an otherwise correct song. Nothing failed — `native` is a valid profile,
// just the wrong one — which is what makes this class of bug worth a test rather
// than a convention.
//
// `..profile = source.profile` at nine call sites works until the tenth is
// written. `TrackerChannel.derivedFrom` copies everything by default and takes
// overrides only for what differs, so a field added to the class later is
// carried without anyone remembering.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_profile.dart';
import 'package:flutter_test/flutter_test.dart';

SampleInstrument _inst(String id) =>
    SampleInstrument(id, Float64List.fromList([0.5, -0.5, 0.5, -0.5]));

TrackerChannel _source() => TrackerChannel(
      id: 'src',
      instrument: _inst('a'),
      rows: 4,
      gain: 0.42,
      pan: -0.7,
    )..profile = ReplayProfile.screamTracker;

void main() {
  test('a derived channel carries the profile without being told', () {
    final d = TrackerChannel.derivedFrom(
      _source(),
      id: 'src:zone',
      instrument: _inst('b'),
      rows: 4,
    );
    expect(identical(d.profile, ReplayProfile.screamTracker), isTrue);
    // …and therefore the rules that hang off it, which is what actually
    // reached the render and was wrong.
    expect(d.profile.pitch, PitchDomain.amigaPeriod);
    expect(d.profile.panLaw, PanLaw.linear);
    expect(d.profile.volumeSlideOnTick0, isTrue);
  });

  test('everything else is inherited too, and overrides win', () {
    final src = _source();
    final plain = TrackerChannel.derivedFrom(src, rows: 4);
    expect(plain.gain, 0.42);
    expect(plain.pan, -0.7);
    expect(plain.instrument.id, 'a');

    final over = TrackerChannel.derivedFrom(
      src,
      id: 'other',
      instrument: _inst('b'),
      rows: 4,
      gain: 1.0,
    );
    expect(over.id, 'other');
    expect(over.instrument.id, 'b');
    expect(over.gain, 1.0);
    expect(over.pan, -0.7, reason: 'unmentioned fields still come from source');
  });

  test('the plain constructor still defaults to native', () {
    // The default has to stay `native`: a channel nobody told otherwise is one
    // of OUR songs, not a tracker import. That is what makes forgetting to
    // inherit silent rather than loud, and why derivedFrom exists.
    final fresh = TrackerChannel(id: 'x', instrument: _inst('a'), rows: 4);
    expect(identical(fresh.profile, ReplayProfile.native), isTrue);
  });

  test('no render path synthesizes a channel without derivedFrom', () {
    // Source-driven, like the command-collision guard: a hand-maintained list
    // would go stale exactly when it matters. Any `..profile =` in the replayer
    // means someone built a channel the manual way again.
    final src = File('lib/core/audio/tracker_replayer.dart').readAsStringSync();
    expect(
      src.contains('..profile = '),
      isFalse,
      reason: 'use TrackerChannel.derivedFrom instead of assigning .profile — '
          'it carries fields added later, a manual assignment does not',
    );
  });
}
