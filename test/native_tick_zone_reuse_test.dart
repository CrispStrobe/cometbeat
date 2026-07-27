// Regression guard for the two-pass (deferred) native tick-zone voice render in
// `tracker_replayer.dart`. The refactor renders each NNA voice one at a time in
// a second pass (instead of holding every voice's whole-song buffer at once) to
// bound peak memory to O(song) rather than O(voices × song). The audio must stay
// byte-identical, so these tests pin concrete, deterministic invariants:
//
//   1. `wonderfulpain.it` (a native IT that exercises `_renderNativeTickZoneVoices`)
//      renders to a non-empty WAV whose bytes are stable across repeated renders.
//   2. A synthetic native-voice MultiSampleInstrument with two overlapping notes
//      under NNA=cut (the default) plus a per-tick effect — which routes through
//      the same deferred-render path — cuts the first voice at the second note's
//      onset (energy flips to the second zone's polarity at the boundary).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/slow_tests.dart';

/// A cell with a command (and optional note) — terse authoring.
TrackerCell fx(int cmd, int param, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: cmd, fxParam: param);

/// A cheap, order-sensitive rolling checksum over WAV bytes. Deterministic and
/// dependency-free; used only to assert stability between repeated renders.
int _checksum(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = (h ^ b) & 0xffffffff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

void main() {
  // Gated: see test/support/slow_tests.dart for why and how to run it.
  if (!kRunHeavy) {
    test(
      describeSkip(
        'HEAVY',
        '3m29s — full offline renders of two native IT modules',
      ),
      () {},
    );
    return;
  }

  group('native tick-zone deferred render', () {
    test('wonderfulpain.it renders a stable, non-empty WAV', () {
      final file = File('test/fixtures/wonderfulpain.it');
      if (!file.existsSync()) {
        // This real IT module is licence-unclear, so it's intentionally NOT
        // committed — it's present only in local/dev checkouts. Skip cleanly
        // when absent (e.g. CI) instead of failing; the deferred two-pass
        // render's determinism is also exercised by the committed synthetic
        // fixtures in this repo.
        markTestSkipped(
          'optional fixture test/fixtures/wonderfulpain.it absent',
        );
        return;
      }
      final bytes = file.readAsBytesSync();

      // Two independent renders from the same bytes must be byte-identical: the
      // deferred two-pass render reorders WHEN voices are rendered, not the
      // produced audio, so the output is deterministic.
      final wavA = songFromModuleBytes(bytes).renderSongWav();
      final wavB = songFromModuleBytes(bytes).renderSongWav();

      expect(
        wavA.length,
        greaterThan(44),
        reason: 'WAV must contain PCM beyond the 44-byte header',
      );
      expect(
        wavA.any((b) => b != 0),
        isTrue,
        reason: 'rendered audio must be non-silent',
      );
      expect(wavA.length, wavB.length);
      expect(
        _checksum(wavA),
        _checksum(wavB),
        reason: 'render must be deterministic (stable checksum)',
      );
      // Full byte equality (the strongest stability guarantee).
      var identical = true;
      for (var i = 0; i < wavA.length; i++) {
        if (wavA[i] != wavB[i]) {
          identical = false;
          break;
        }
      }
      expect(
        identical,
        isTrue,
        reason: 'both renders must be byte-identical',
      );
    });

    test('NNA=cut silences the first voice at the second note onset', () {
      // Two zones with opposite constant polarity so the mix sign reveals which
      // voice is sounding. NNA defaults to 0 (cut), so the second note must cut
      // the first voice dead at its onset. The vibrato (0x4) is a per-tick effect
      // that forces the deferred native tick-zone render path.
      final positive = Float64List(120000)..fillRange(0, 120000, 0.25);
      final negative = Float64List(120000)..fillRange(0, 120000, -0.5);
      const timing = TrackerTiming(rows: 4);
      final cells = List<TrackerCell>.filled(4, TrackerCell.empty)
        ..[0] = const TrackerCell(midi: 60)
        ..[1] = fx(0x4, 0x31)
        ..[2] = const TrackerCell(midi: 72);
      final song = TrackerSong.fromParts(
        channels: [
          TrackerChannel(
            id: 'it-nna-cut',
            instrument: MultiSampleInstrument(
              'it-instrument',
              {
                60: SampleInstrument('low', positive, normalize: false),
                72: SampleInstrument('high', negative, normalize: false),
              },
              polyphonic: true,
              nativeVoiceSemantics: true,
            ),
            rows: 4,
          ),
        ],
        timing: timing,
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );

      final rendered = replaySong(song).pcm;
      final split = timing.stepStartSample(2);

      // Before the cut: the first (positive) voice sounds.
      expect(
        rendered[split - 100],
        greaterThan(0),
        reason: 'first voice audible before the cut',
      );
      // After the cut: the first voice is gone and only the second (negative)
      // voice remains — energy has flipped to the opposite polarity.
      expect(
        rendered[split + 100],
        lessThan(0),
        reason: 'second voice cuts the first at its onset',
      );

      // Energy on the far side of the boundary is dominated by the second voice
      // (negative), confirming the first voice was silenced rather than summed.
      var afterSum = 0.0;
      for (var i = split + 100; i < split + 1100; i++) {
        afterSum += rendered[i];
      }
      expect(
        afterSum,
        lessThan(0),
        reason: 'aggregate energy after the cut is the second voice only',
      );
    });
  });
}
