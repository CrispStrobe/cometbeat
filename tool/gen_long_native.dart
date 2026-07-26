// CLI memory gate: build a synthetic LONG (>15 min) MONO FLOW native
// multi-sample (NNA-zone) song — the shape whose whole-song NNA voice render
// ([_renderNativeTickZoneVoices]) would allocate multiple whole-song Float64
// buffers — and render it through the bounded streaming CLI path
// (writeSongWavStreaming → streamFlowVariableMonoPcm → _zoneRunRenderChunkMono).
// Peak RSS must stay < 500 MB at any length. Measure with:
//
//   /usr/bin/time -l dart run tool/gen_long_native.dart /tmp/long.wav
//
// (grep "maximum resident set size").
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart' show kFxVibrato;
import 'package:comet_beat/core/audio/tracker_song.dart';

SampleInstrument _sineZone(String id, int baseMidi, int len, double freq) {
  final s = Float64List(len);
  for (var i = 0; i < len; i++) {
    s[i] = 0.6 * sin(2 * pi * freq * i / kSampleRate);
  }
  return SampleInstrument(id, s, baseMidi: baseMidi, normalize: false);
}

MultiSampleInstrument _native() => MultiSampleInstrument(
      'native',
      {
        48: _sineZone('z48', 48, 22000, 220),
        60: _sineZone('z60', 60, 20000, 440),
        72: _sineZone('z72', 72, 18000, 880),
      },
      polyphonic: true,
      nativeVoiceSemantics: true,
    );

TrackerPattern _pattern(String name, int rows, int notesEvery) {
  final zoneKeys = [48, 60, 72];
  final col = List<TrackerCell>.filled(rows, TrackerCell.empty);
  for (var r = 0; r < rows; r++) {
    col[r] = r % notesEvery == 0
        ? TrackerCell(midi: zoneKeys[(r ~/ notesEvery) % zoneKeys.length])
        : const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x38);
  }
  return TrackerPattern(name: name, cells: [col]);
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final out = positional.isNotEmpty ? positional[0] : '/tmp/long_native.wav';
  final cyclesArg = args.firstWhere(
    (a) => a.startsWith('--cycles='),
    orElse: () => '',
  );
  final cycles = cyclesArg.isEmpty ? 80 : int.parse(cyclesArg.split('=')[1]);
  // Two differing pattern lengths ⇒ FLOW (walk) render, NON-variable timing.
  // Default 80 × [64,48] rows = 8960 rows @ 120 ms/row ≈ 17.9 min.
  final song = TrackerSong.fromParts(
    channels: [
      TrackerChannel(id: 'native', instrument: _native(), rows: 64),
    ],
    timing: const TrackerTiming(tempoBpm: 125, rows: 64),
    patterns: [_pattern('a', 64, 6), _pattern('b', 48, 6)],
    order: [
      for (var i = 0; i < cycles; i++) ...[0, 1],
    ],
  );

  final sw = Stopwatch()..start();
  if (args.contains('--whole')) {
    // OLD path: the whole-song NNA voice render (renderSongWav) — retains a
    // whole-song Float64 mix plus per-voice whole-song buffers. Measured only to
    // document the before/after; unbounded, so it blows the ceiling on long
    // songs.
    final wav = song.renderSongWav();
    File(out).writeAsBytesSync(wav);
  } else {
    await song.writeSongWavStreaming(out);
  }
  sw.stop();

  final bytes = File(out).lengthSync();
  final frames = (bytes - 44) ~/ 2;
  final seconds = frames / kSampleRate;
  stdout.writeln(
    'wrote $out: mono · $frames frames · '
    '${(seconds / 60).toStringAsFixed(1)} min · '
    'streamed in ${sw.elapsedMilliseconds} ms',
  );
}
