// CROSS-FEATURE integration gate — run by the orchestrator ONLY after all three
// features (A mid-song timing, B per-pattern length, C stereo/pan) are merged.
// Verifies they COMPOSE. Copy into test/ at final integration; adjust to the
// merged API if an agent deviated (the per-feature acceptance tests are the
// authority for each feature's own API).

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerCell fxx(int param) => TrackerCell(fxCmd: kFxSetSpeed, fxParam: param);

void main() {
  test('A+B+C compose: variable length + mid-song tempo + panning', () {
    // Pattern 0: 8 rows, a note on ch0. Pattern 1: 16 rows, drops tempo to 60
    // (Fxx on ch1) with a note on ch0. Channel 0 is panned hard-left.
    final s = TrackerSong(
      timing: const TrackerTiming(rows: 8), // song tempo 120 (the default)
      patternCount: 2,
    );
    s.setPatternRows(1, 16); // B
    s.selectPattern(0);
    s.engine.setCell(0, 0, const TrackerCell(midi: 60));
    s.selectPattern(1);
    s.engine.setCell(1, 0, fxx(0x3C)); // A: 60 BPM in the 2nd entry
    s.engine.setCell(0, 0, const TrackerCell(midi: 62));
    s.engine.setChannelPan(0, -1.0); // C
    s.order
      ..clear()
      ..addAll([0, 1]);
    s.syncCurrent();

    // B+A: 8 rows @125ms + 16 rows @250ms = 1000 + 4000 = 5000 ms.
    expect(resolveTimingMap(s).length, 8 + 16);
    expect((s.songTotalMs - 5000).abs(), lessThan(40));

    // C: pan flips the output to stereo, panned left.
    expect(s.usesPan, isTrue);
    final wav = s.renderCurrentPatternWav();
    // (renderCurrentPatternWav renders the current pattern; the whole-song
    // stereo+timing assertions use renderSongWav below.)
    expect(wav.isNotEmpty, isTrue);

    final songWav = s.renderSongWav();
    // 2-channel header.
    expect(songWav[22] | (songWav[23] << 8), 2);
    final renderedMs =
        (songWav.length - 44) / 4 / kSampleRate * 1000; // stereo frames
    expect((renderedMs - s.songTotalMs).abs(), lessThan(60));
  });
}
