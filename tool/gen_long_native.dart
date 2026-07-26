// CLI memory gate: build a synthetic LONG (>15 min) FLOW native multi-sample
// (NNA-zone) song — the shape whose whole-song NNA voice render
// ([_renderNativeTickZoneVoices]) would allocate multiple whole-song Float64
// buffers — and render it through the bounded streaming CLI path. MONO routes
// writeSongWavStreaming → streamFlowVariableMonoPcm → _zoneRunRenderChunkMono;
// --stereo routes writeSongWavStreaming → streamFlowVariableStereoPcm →
// _zoneRunRenderChunkStereo (the last unbounded shape: stereo + long + native +
// flow/uniform non-variable timing). Peak RSS must stay < 500 MB at any length.
// Measure with:
//
//   /usr/bin/time -l dart run tool/gen_long_native.dart /tmp/long.wav
//   /usr/bin/time -l dart run tool/gen_long_native.dart --stereo /tmp/long.wav
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

// One pattern column of native NNA notes: a new note every [notesEvery] rows
// (its zone rotating through 48/60/72, offset by [phase] so parallel channels
// overlap on DIFFERENT zones), a per-tick vibrato on every other row (which forces
// the whole-song NNA render path). No key-off ⇒ overlapping NNA note runs.
List<TrackerCell> _column(int rows, int notesEvery, int phase) {
  final zoneKeys = [48, 60, 72];
  final col = List<TrackerCell>.filled(rows, TrackerCell.empty);
  for (var r = 0; r < rows; r++) {
    col[r] = r % notesEvery == 0
        ? TrackerCell(
            midi: zoneKeys[(r ~/ notesEvery + phase) % zoneKeys.length])
        : const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x38);
  }
  return col;
}

TrackerPattern _pattern(String name, int rows, int notesEvery, int channels) {
  return TrackerPattern(
    name: name,
    cells: [
      for (var c = 0; c < channels; c++) _column(rows, notesEvery, c),
    ],
  );
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final out = positional.isNotEmpty ? positional[0] : '/tmp/long_native.wav';
  final cyclesArg = args.firstWhere(
    (a) => a.startsWith('--cycles='),
    orElse: () => '',
  );
  final cycles = cyclesArg.isEmpty ? 80 : int.parse(cyclesArg.split('=')[1]);
  // --stereo → a STEREO (panned) song with two overlapping native channels; the
  // last unbounded shape (stereo + long + native + flow non-variable timing),
  // routed through streamFlowVariableStereoPcm → _zoneRunRenderChunkStereo.
  final stereo = args.contains('--stereo');
  final chanCount = stereo ? 2 : 1;
  // Two differing pattern lengths ⇒ FLOW (walk) render, NON-variable timing.
  // Default 80 × [64,48] rows = 8960 rows @ 120 ms/row ≈ 17.9 min.
  final song = TrackerSong.fromParts(
    channels: [
      for (var c = 0; c < chanCount; c++)
        TrackerChannel(
          id: 'native$c',
          instrument: _native(),
          rows: 64,
          // Hard-pan the two channels apart so `usesPan` is true (STEREO) and
          // the per-region pan gains are exercised in _zoneRunRenderChunkStereo.
          pan: stereo ? (c == 0 ? -0.6 : 0.6) : 0.0,
        ),
    ],
    timing: const TrackerTiming(tempoBpm: 125, rows: 64),
    patterns: [
      _pattern('a', 64, 6, chanCount),
      _pattern('b', 48, 6, chanCount),
    ],
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
  final bytesPerFrame = stereo ? 4 : 2;
  final frames = (bytes - 44) ~/ bytesPerFrame;
  final seconds = frames / kSampleRate;
  stdout.writeln(
    'wrote $out: ${stereo ? 'stereo' : 'mono'} · $frames frames · '
    '${(seconds / 60).toStringAsFixed(1)} min · '
    'streamed in ${sw.elapsedMilliseconds} ms',
  );
}
