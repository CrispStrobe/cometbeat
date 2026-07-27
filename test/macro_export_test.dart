// §4 macros survive the bounded-memory EXPORT path (writeSongWavStreaming), for
// both mono and panned (stereo) songs — a macro'd song is routed off the
// per-order/per-chunk streamers (which restart voice state) onto a whole-song
// replay path that applies macros. So an exported WAV modulates like playback.

import 'dart:io';

import 'package:comet_beat/core/audio/macro_sequence.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

const _volMacro = MacroSequence(
  target: MacroTarget.volume,
  values: [64, 16, 4, 0],
  loopStart: 3,
  loopEnd: 3,
);

Future<List<int>> _export(
  List<MacroSequence> macros, {
  bool pan = false,
}) async {
  final song = TrackerSong(timing: const TrackerTiming(rows: 8));
  song.engine.setChannelInstrument(
    0,
    AdditiveInstrument('piano', Instrument.piano, macros: macros),
  );
  song.engine.setCell(0, 0, const TrackerCell(midi: 60));
  if (pan) song.engine.setChannelPan(0, 0.6); // routes to the stereo export
  final dir = await Directory.systemTemp.createTemp('macro_export');
  try {
    final path = '${dir.path}/out.wav';
    await song.writeSongWavStreaming(path);
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  test('a macro-free song is never flagged as using macros', () {
    final song = TrackerSong(timing: const TrackerTiming(rows: 8));
    song.engine.setCell(0, 0, const TrackerCell(midi: 60));
    expect(song.usesMacros, isFalse);
  });

  test('mono bounded export applies the volume macro', () async {
    final plain = await _export(const []);
    final faded = await _export(const [_volMacro]);
    expect(plain, isNotEmpty);
    expect(
      faded,
      isNot(plain),
      reason: 'the macro must reach the export render',
    );
  });

  test('panned (stereo) bounded export applies the volume macro', () async {
    final plain = await _export(const [], pan: true);
    final faded = await _export(const [_volMacro], pan: true);
    expect(plain, isNotEmpty);
    expect(faded, isNot(plain));
  });
}
