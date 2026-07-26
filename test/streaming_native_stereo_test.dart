// Verifies the bounded-memory STEREO stream of a NATIVE multi-sample (NNA-zone)
// song — the LAST render path that was still on the whole-song accumulator (a
// stereo + long + native + flow/uniform NON-variable song used the whole-song
// _renderNativeTickZoneVoices stereo render, allocating a whole-song L/R mix plus
// per-voice buffers).
//
// APPROACH B (see tracker_replayer.dart): a native multi-sample STEREO channel
// streams through the bounded per-note-run path ([_zoneRunRenderChunkStereo],
// mirroring the whole-song [_renderLongNativeVariableStereo]) ONLY when the song
// is LONGER than the whole-song NNA memory budget (_nativeTickFullBufferLimit,
// 120 s). SHORT songs stay on the exact whole-song NNA voice render
// ([_renderNativeTickZoneVoices]) — byte-identical, so the corpus (none reaching
// this gate) is untouched. The gate ([_songUsesNativeLongStereo]) now fires for
// FLOW / uniform (non-variable) timing too, not just VARIABLE. These tests pin:
//
//   1. A SHORT stereo native song does NOT stream, and its CLI render
//      (writeSongWavStreaming) is byte-identical to renderSongWav (both take the
//      whole-song stereo NNA path).
//   2. A LONG stereo FLOW (non-variable) native song streams DETERMINISTICALLY
//      (two independent streams are byte-identical) in bounded RAM. The <500 MB
//      peak for a >15 min song of this shape is exercised by the CLI gate
//      (tool/gen_long_native.dart --stereo under /usr/bin/time -l).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A short one-shot sine, NATIVE (normalize:false) so its scale is `channel.gain`
/// (the bounded per-note-run path's precondition).
SampleInstrument _sineZone(String id, int baseMidi, int len, double freq) {
  final s = Float64List(len);
  for (var i = 0; i < len; i++) {
    s[i] = 0.6 * sin(2 * pi * freq * i / kSampleRate);
  }
  return SampleInstrument(id, s, baseMidi: baseMidi, normalize: false);
}

/// A native (IT-style NNA) multi-sample instrument over three zones.
MultiSampleInstrument _nativeInstrument() => MultiSampleInstrument(
      'native',
      {
        48: _sineZone('z48', 48, 22000, 220),
        60: _sineZone('z60', 60, 20000, 440),
        72: _sineZone('z72', 72, 18000, 880),
      },
      polyphonic: true,
      nativeVoiceSemantics: true,
    );

/// One native-note column: a new note every [notesEvery] rows (zone rotating,
/// offset by [phase] so parallel channels overlap on different zones); every other
/// row carries a per-tick vibrato (which forces the whole-song NNA render path).
/// No key-off is ever emitted, so runs are sustain-only (release == 0).
List<TrackerCell> _column(int rows, int notesEvery, int phase) {
  final zoneKeys = [48, 60, 72];
  final col = List<TrackerCell>.filled(rows, TrackerCell.empty);
  for (var r = 0; r < rows; r++) {
    col[r] = r % notesEvery == 0
        ? TrackerCell(
            midi: zoneKeys[(r ~/ notesEvery + phase) % zoneKeys.length],
          )
        : const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x38);
  }
  return col;
}

/// A two-channel STEREO native song (channels hard-panned apart ⇒ `usesPan`).
/// Differing pattern lengths ⇒ FLOW (walk) render, NON-variable timing.
TrackerSong _stereoNativeSong({
  required List<int> patternRows,
  required List<int> order,
  int notesEvery = 6,
}) {
  final patterns = <TrackerPattern>[];
  for (var p = 0; p < patternRows.length; p++) {
    final rows = patternRows[p];
    patterns.add(
      TrackerPattern(
        name: 'p$p',
        cells: [
          _column(rows, notesEvery, 0),
          _column(rows, notesEvery, 1),
        ],
      ),
    );
  }
  final first = patternRows.first;
  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'nativeL',
        instrument: _nativeInstrument(),
        rows: first,
        pan: -0.6,
      ),
      TrackerChannel(
        id: 'nativeR',
        instrument: _nativeInstrument(),
        rows: first,
        pan: 0.6,
      ),
    ],
    timing: TrackerTiming(tempoBpm: 125, rows: first),
    patterns: patterns,
    order: order,
  );
}

int _firstDiff(List<int> a, List<int> b) {
  final n = min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : n;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('native_stereo_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('short stereo native song stays byte-identical to renderSongWav',
      () async {
    // Differing pattern lengths ⇒ FLOW (walk) render; short ⇒ below the streaming
    // budget, so it must NOT stream — the whole-song stereo NNA render is kept.
    final song = _stereoNativeSong(patternRows: [64, 48], order: [0, 1, 0, 1]);
    expect(song.usesPan, isTrue, reason: 'panned channels ⇒ stereo');
    expect(songUsesVariableTiming(song), isFalse);
    expect(songNeedsWalkRender(song), isTrue);
    expect(
      songCanStreamFlowVariable(song, stereo: true),
      isFalse,
      reason:
          'a short stereo native song must stay on the whole-song NNA render',
    );

    final out = '${tmp.path}/short.wav';
    await song.writeSongWavStreaming(out);
    final streamed = File(out).readAsBytesSync();
    final whole = song.renderSongWav();
    expect(streamed.length, whole.length);
    expect(
      streamed.skip(44).any((b) => b != 0),
      isTrue,
      reason: 'render must be non-silent',
    );
    expect(
      _firstDiff(streamed, whole),
      -1,
      reason: 'short-song CLI render == renderSongWav (both whole-song NNA)',
    );
  });

  test('long stereo FLOW native song streams deterministically', () async {
    // A long FLOW (non-variable) STEREO native song — the last unbounded shape.
    // Two independent streams must be byte-identical (the row-chunk state carry is
    // deterministic), in bounded RAM. Byte-identity to the whole-song NNA render
    // is NOT claimed here: at this length that render is infeasible (it would
    // exceed the ceiling) and the bounded per-note-run render diverges from it by
    // design — the guarantee is deterministic + bounded.
    final song = _stereoNativeSong(
      patternRows: [64, 48],
      order: [
        for (var i = 0; i < 24; i++) ...[0, 1],
      ],
    );
    expect(song.usesPan, isTrue);
    expect(songUsesVariableTiming(song), isFalse);
    expect(songNeedsWalkRender(song), isTrue);
    expect(
      songCanStreamFlowVariable(song, stereo: true),
      isTrue,
      reason: 'a long stereo native song routes through the bounded stream',
    );

    final aPath = '${tmp.path}/flowA.wav';
    final bPath = '${tmp.path}/flowB.wav';
    await song.writeSongWavStreaming(aPath);
    await song.writeSongWavStreaming(bPath);
    final a = File(aPath).readAsBytesSync();
    final b = File(bPath).readAsBytesSync();

    final frames = (a.length - 44) ~/ 4; // stereo: 4 bytes/frame
    expect(
      frames,
      greaterThan(120 * kSampleRate),
      reason: 'song must exceed the 120 s streaming budget',
    );
    expect(a.skip(44).any((x) => x != 0), isTrue, reason: 'non-silent');
    expect(a.length, b.length);
    expect(
      _firstDiff(a, b),
      -1,
      reason: 'bounded stereo stream must be deterministic',
    );
  });
}
