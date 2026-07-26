// renderTabBandThroughTracker (tab_fx.dart) — the Tab preview path that routes
// each track through the tracker REPLAYER so a column's playing techniques are
// actually heard, instead of the dry Score voice that silently drops them.
//
// The headline claim: with a SAMPLE-backed voice, a note with vibrato / bend /
// slide renders DIFFERENTLY from the same note without it — i.e. the technique's
// effect-column command (vibrato → 4xy, bend → 1xx, slide → 3xx) reaches the
// replayer's per-tick pitch engine and changes the audio.
//
// A documented limitation is also pinned: a PROCEDURAL voice (the tab's default
// plucked string) is rendered at a fixed pitch, so for it the pitch techniques
// are inaudible — the render still plays, just without them (never worse than
// the dry path).

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show KarplusInstrument, SampleInstrument, TrackerInstrument;
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_fx.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-second two-harmonic tone as a sampler source, rooted at A3 (MIDI 57) so
/// pitch shifts up/down are clearly audible.
TrackerInstrument _sampleVoice() {
  final pcm = Float64List(44100);
  for (var i = 0; i < pcm.length; i++) {
    final t = i / 44100;
    pcm[i] = sin(2 * pi * 220 * t) + 0.5 * sin(2 * pi * 440 * t);
  }
  return SampleInstrument('tone', pcm, baseMidi: 57);
}

/// One half-note on the low-E string (string index 5), carrying [techniques].
TabDocument _note(Set<TabTechnique> techniques) => TabDocument(
      tuning: Tuning.standardGuitar,
      columns: [
        TabColumn(
          frets: const {5: 5},
          duration: NoteDuration.half,
          techniques: techniques,
        ),
      ],
    );

List<TabTrack> _band(TabDocument doc, {List<FxSpec>? fx}) =>
    [TabTrack('g', doc, fxChain: fx)];

double _maxDiff(Float64List a, Float64List b) {
  final n = min(a.length, b.length);
  var d = 0.0;
  for (var i = 0; i < n; i++) {
    d = max(d, (a[i] - b[i]).abs());
  }
  return d;
}

void main() {
  final voice = _sampleVoice();

  test('vibrato, bend and slide each change a sample-voiced note', () {
    final dry = renderTabBandThroughTracker(_band(_note(const {})), voice);
    expect(dry, isNotEmpty);
    for (final tech in [
      TabTechnique.vibrato,
      TabTechnique.bend,
      TabTechnique.slide,
    ]) {
      final wet = renderTabBandThroughTracker(_band(_note({tech})), voice);
      expect(wet.length, dry.length);
      expect(
        _maxDiff(dry, wet),
        greaterThan(0.02),
        reason: '$tech must reach the replayer and alter the note',
      );
    }
  });

  test('a procedural (plucked-string) voice plays but drops pitch techniques',
      () {
    const pluck = KarplusInstrument('tabString');
    final dry = renderTabBandThroughTracker(_band(_note(const {})), pluck);
    final vib = renderTabBandThroughTracker(
      _band(_note(const {TabTechnique.vibrato})),
      pluck,
    );
    expect(dry, isNotEmpty, reason: 'the note still plays');
    // Documented limitation: identical, because per-tick pitch is not applied
    // to a procedural voice. This test pins that so a future fix flips it.
    expect(_maxDiff(dry, vib), 0.0);
  });

  test('output is finite and bounded', () {
    final pcm = renderTabBandThroughTracker(
      _band(_note(const {TabTechnique.vibrato})),
      voice,
    );
    for (final s in pcm) {
      expect(s.isFinite, isTrue);
      expect(s.abs(), lessThanOrEqualTo(4.0));
    }
  });

  test('an empty / all-muted band renders nothing', () {
    expect(renderTabBandThroughTracker(const [], voice), isEmpty);
    final muted = [TabTrack('g', _note(const {}), muted: true)];
    expect(renderTabBandThroughTracker(muted, voice), isEmpty);
  });

  test('a per-track FX chain still applies to the tracker-rendered stem', () {
    final dry = renderTabBandThroughTracker(_band(_note(const {})), voice);
    final crunched = renderTabBandThroughTracker(
      _band(_note(const {}), fx: [defaultFx(FxType.distortion)]),
      voice,
    );
    expect(_maxDiff(dry, crunched), greaterThan(0.01));
  });
}
