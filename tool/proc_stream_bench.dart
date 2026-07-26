// Builds a synthetic LONG (>15 min) procedural-voice song with MANY bounded note
// runs and an order repeated to length, then renders it either through the
// bounded row-chunk streamer (`writeSongWavStreaming`, mode `stream`) or the
// whole-song render (`renderSongWav`, mode `whole`). Used with
// `/usr/bin/time -l` to measure peak RSS — the streamer must stay < 500 MB for
// any length; the whole-song render allocates a whole-song Float64 mix + stem
// and blows past it.
//
//   dart run tool/proc_stream_bench.dart stream [minutes] [voice] [out.wav]
//   dart run tool/proc_stream_bench.dart whole  [minutes] [voice]
//     voice: fm | sub   (default fm)
//
// The song uses a mid-song speed change (variable timing) so it routes through
// the flow/variable streamer, with a fresh note every 16 rows (each ringing
// ~0.85 s) so the run buffers stay bounded.

import 'dart:io';

import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/crisp_dsp/subtractive.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart' show kFxSetSpeed;
import 'package:comet_beat/core/audio/tracker_song.dart';

const _rows = 64;
const _notes = [45, 48, 52, 55, 57, 60, 52, 48];

TrackerPattern _pat(String name, {required int speed}) {
  final p = TrackerPattern.empty(name: name, channels: 1, rows: _rows);
  for (var r = 0; r < _rows; r += 16) {
    final midi = _notes[(r ~/ 16) % _notes.length];
    p.cells[0][r] = r == 0
        ? TrackerCell(midi: midi, fxCmd: kFxSetSpeed, fxParam: speed)
        : TrackerCell(midi: midi);
    p.cells[0][r + 14] = TrackerCell.noteCut; // explicit run end
  }
  return p;
}

Future<void> main(List<String> args) async {
  final mode = args.isNotEmpty ? args[0] : 'stream';
  final minutes = args.length > 1 ? double.parse(args[1]) : 16.0;
  final voice = args.length > 2 ? args[2] : 'fm';
  final outPath = args.length > 3 ? args[3] : null;

  final inst = voice == 'sub'
      ? SubtractiveInstrument.preset('pad', kSubPresets['pad']!)
      : FmInstrument.preset('ep', kFmPresets['ePiano']!);

  // At 120 BPM / stepsPerBeat 4 a row is 125 ms; two patterns alternate speeds
  // (4 vs 8 ticks) → variable timing. Repeat the order to reach `minutes`.
  const rowMs = 125.0;
  final targetRows = (minutes * 60 * 1000 / rowMs).ceil();
  final orderLen = (targetRows / _rows).ceil();
  final order = [for (var i = 0; i < orderLen; i++) i % 2];

  final song = TrackerSong.fromParts(
    channels: [TrackerChannel(id: 'proc', instrument: inst, rows: _rows)],
    timing: const TrackerTiming(rows: _rows),
    patterns: [_pat('00', speed: 4), _pat('01', speed: 8)],
    order: order,
    instruments: defaultInstrumentPool(),
    initialSpeed: 4,
  );

  final sw = Stopwatch()..start();
  if (mode == 'whole') {
    final wav = song.renderSongWav();
    final frames = (wav.length - 44) ~/ 2;
    stderr.writeln(
      'whole-song render: ${(frames / 44100 / 60).toStringAsFixed(1)} min, '
      '${wav.length} bytes, ${sw.elapsedMilliseconds} ms',
    );
    if (outPath != null) File(outPath).writeAsBytesSync(wav);
  } else {
    final path =
        outPath ?? '${Directory.systemTemp.path}/proc_stream_bench.wav';
    await song.writeSongWavStreaming(path);
    final len = File(path).lengthSync();
    final frames = (len - 44) ~/ 2;
    stderr.writeln(
      'streamed render: ${(frames / 44100 / 60).toStringAsFixed(1)} min, '
      '$len bytes, ${sw.elapsedMilliseconds} ms',
    );
    if (outPath == null) File(path).deleteSync();
  }
}
