// Pins the BOUNDED-MEMORY row-chunk streaming of PROCEDURAL voices
// ([FmInstrument], [SubtractiveInstrument], [KarplusInstrument] and the OPL2
// [OplInstrument]). A flow (Bxx walk) OR variable-timing (mid-song speed change)
// song whose channel carries one of these now routes through the row-chunk
// streamer ([streamFlowVariableMonoPcm] / [streamFlowVariableStereoPcm]) instead
// of the whole-song render — each note run is synthesized into a bounded
// run-length buffer, peak-normalised by the whole-channel `gain / peak`, and read
// as chunks advance. This test pins that the streamed WAV is BYTE-IDENTICAL to
// the whole-song [TrackerSong.renderSongWav] across MANY chunks (notes ring over
// >=65536-frame boundaries), for mono and stereo, flow and variable timing — and
// that the stream is deterministic (two runs are byte-equal).
//
// sfxr is intentionally NOT streamed (its ms-derived note length can exceed the
// run span and its sequential PRNG couples runs), so it is not covered here.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/crisp_dsp/subtractive.dart';
import 'package:comet_beat/core/audio/mod/opl_voice.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal, non-blank OPL2 patch (carrier-only, both operators sustaining), so
/// a held note rings for its whole run.
List<int> _oplPatch() {
  final d = List<int>.filled(12, 0);
  d[0] = (1 & 0x0F) | 0x20;
  d[1] = (1 & 0x0F) | 0x20;
  d[2] = 63;
  d[3] = 0;
  d[4] = (15 << 4) | 15;
  d[5] = (15 << 4) | 15;
  d[6] = (0 << 4) | 15;
  d[7] = (0 << 4) | 15;
  return d;
}

/// Builds a single-channel song around [inst] with MANY bounded note runs (a new
/// note every 16 rows, each ringing ~0.85 s — long enough to straddle a
/// 65536-frame chunk boundary), the order repeated so total length spans many
/// chunks. A [flow] Bxx jump makes it a walk-render song; a [variable] speed
/// change makes it a variable-timing song — both routing through the row-chunk
/// streamer.
TrackerSong _procSong(
  TrackerInstrument inst, {
  bool stereo = false,
  bool variable = false,
  bool flow = false,
}) {
  const rows = 64;
  const notes = [45, 48, 52, 57]; // a new run every 16 rows

  TrackerPattern pat(String name, {int speed = 0, int? jumpTo}) {
    final p = TrackerPattern.empty(name: name, channels: 1, rows: rows);
    for (var r = 0; r < rows; r += 16) {
      final midi = notes[(r ~/ 16) % notes.length];
      if (variable && r == 0 && speed > 0) {
        p.cells[0][r] =
            TrackerCell(midi: midi, fxCmd: kFxSetSpeed, fxParam: speed);
      } else {
        p.cells[0][r] = TrackerCell(midi: midi);
      }
      // Release the note a few rows before the next trigger (an explicit run end).
      p.cells[0][r + 14] = TrackerCell.noteCut;
    }
    if (jumpTo != null) {
      p.cells[0][rows - 2] =
          TrackerCell(fxCmd: kFxPositionJump, fxParam: jumpTo);
    }
    return p;
  }

  final List<TrackerPattern> patterns;
  final List<int> order;
  if (variable) {
    patterns = [pat('00', speed: 4), pat('01', speed: 8)];
    order = [0, 1, 0, 1, 0, 1];
  } else if (flow) {
    // Bxx on pattern 00 jumps to order entry 2, unrolling a long non-looping walk.
    patterns = [pat('00', jumpTo: 2), pat('01'), pat('02'), pat('03')];
    order = [0, 1, 2, 3];
  } else {
    patterns = [pat('00')];
    order = [0, 0, 0, 0];
  }

  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'proc',
        instrument: inst,
        rows: rows,
        pan: stereo ? -0.4 : 0.0,
      ),
    ],
    timing: const TrackerTiming(rows: rows),
    patterns: patterns,
    order: order,
    instruments: defaultInstrumentPool(),
    initialSpeed: variable ? 4 : 6,
    stereoOutput: stereo,
  );
}

Future<Uint8List> _streamedBytes(TrackerSong song) async {
  final dir = Directory.systemTemp.createTempSync('stream_proc_bounded');
  final path = '${dir.path}/out.wav';
  try {
    await song.writeSongWavStreaming(path);
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  final voices = <String, TrackerInstrument Function()>{
    'FM': () => FmInstrument.preset('ep', kFmPresets['ePiano']!),
    'Subtractive': () =>
        SubtractiveInstrument.preset('pad', kSubPresets['pad']!),
    'Karplus': () => const KarplusInstrument('pluck'),
    'OPL2': () => OplInstrument('opl', _oplPatch()),
  };
  final shapes = <String, ({bool flow, bool variable})>{
    'flow (Bxx walk)': (flow: true, variable: false),
    'variable timing': (flow: false, variable: true),
  };

  group('procedural streaming is bounded AND byte-identical to renderSongWav',
      () {
    voices.forEach((vName, build) {
      shapes.forEach((sName, shape) {
        for (final stereo in [false, true]) {
          final label = '$vName · $sName · ${stereo ? 'stereo' : 'mono'}';
          test(label, () async {
            final song = _procSong(
              build(),
              stereo: stereo,
              flow: shape.flow,
              variable: shape.variable,
            );

            // It routes through the flow / variable streamer (not the offline
            // mixer): the procedural channel is now chunk-safe.
            expect(
              songNeedsWalkRender(song) || songUsesVariableTiming(song),
              isTrue,
              reason: 'must use the flow/variable render path',
            );
            expect(
              songCanStreamFlowVariable(song, stereo: stereo),
              isTrue,
              reason: 'procedural voices now row-chunk stream',
            );

            final whole = song.renderSongWav();
            final frames = (whole.length - 44) ~/ (stereo ? 4 : 2);
            expect(
              frames,
              greaterThan(kStreamChunkFrames),
              reason: 'must span multiple 65536-frame chunks',
            );
            expect(
              whole.any((b) => b != 0),
              isTrue,
              reason: 'song must produce real audio',
            );

            // Byte-for-byte identical to the whole-song render.
            final streamed = await _streamedBytes(song);
            expect(streamed.length, whole.length);
            expect(streamed, orderedEquals(whole));

            // Deterministic: a second stream is byte-equal to the first.
            final streamed2 = await _streamedBytes(song);
            expect(streamed2, orderedEquals(streamed));
          });
        }
      });
    });
  });
}
