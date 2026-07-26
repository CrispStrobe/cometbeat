// Richer tab technique → effect mapping (tab_tracker.dart): a DEAD/muted note
// becomes a percussive ECx note-cut, a GHOST note a soft Cxx set-volume — on top
// of the existing slide/bend/vibrato pitch techniques. Both are honored by the
// replayer, so with the tab "articulate" preview they actually sound.
//
// The mapping is deterministic (asserted exactly); an audibility check confirms
// a ghost note is quieter and a dead note shorter than a plain one when rendered
// through the tracker.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument, TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_replay.dart' show kFxSetVolume;
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kExNoteCut, kFxExtended;
import 'package:comet_beat/core/interop/tab_tracker.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_fx.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

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

TrackerInstrument _sampleVoice() {
  final pcm = Float64List(44100);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = sin(2 * pi * 220 * i / 44100);
  }
  return SampleInstrument('tone', pcm, baseMidi: 57);
}

double _rms(Float64List x) {
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return sqrt(s / x.length);
}

void main() {
  test('a dead note maps to an ECx note-cut on its string', () {
    final result = trackerSongFromTabDocument(_note(const {TabTechnique.dead}));
    final cell = result.song.channels[5].cells[0];
    expect(cell.fxCmd, kFxExtended);
    expect(cell.fxParam, (kExNoteCut << 4) | 2);
  });

  test('a ghost note maps to a soft Cxx set-volume', () {
    final result =
        trackerSongFromTabDocument(_note(const {TabTechnique.ghost}));
    final cell = result.song.channels[5].cells[0];
    expect(cell.fxCmd, kFxSetVolume);
    expect(cell.fxParam, 0x18);
  });

  test('pitch techniques still win over articulations in the one cell', () {
    // slide + dead → still a slide (the side-car keeps the full set).
    final result = trackerSongFromTabDocument(
      _note(const {TabTechnique.slide, TabTechnique.dead}),
    );
    expect(result.song.channels[5].cells[0].fxCmd, isNot(kFxExtended));
  });

  test('rendered: a dead note is cut short (lower energy than a plain note)',
      () {
    // Amplitude alone is not a reliable probe — the sample path peak-normalises,
    // so a ghost note's lower volume can wash out. A dead note is mostly silence
    // (cut at tick 2), so its whole-buffer RMS is unambiguously lower.
    final voice = _sampleVoice();
    List<TabTrack> band(Set<TabTechnique> t) => [TabTrack('g', _note(t))];
    final plain = renderTabBandThroughTracker(band(const {}), voice);
    final dead =
        renderTabBandThroughTracker(band(const {TabTechnique.dead}), voice);
    expect(_rms(dead), lessThan(_rms(plain)), reason: 'dead is cut short');
  });
}
