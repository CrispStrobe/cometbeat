// Verifies the bounded-memory MONO stream of a NATIVE multi-sample (NNA-zone)
// song — the last render path that was still on the whole-song accumulator.
//
// APPROACH B (see tracker_replayer.dart): a native multi-sample MONO channel
// streams through the bounded per-note-run path ([_zoneRunRenderChunkMono],
// mirroring the whole-song [_renderLongNativeVariable]) ONLY when the song is
// LONGER than the whole-song NNA memory budget (_nativeTickFullBufferLimit,
// 120 s). SHORT songs stay on the exact whole-song NNA voice render
// ([_renderNativeTickZoneVoices]) — byte-identical, so the corpus (all stereo,
// none reaching this MONO gate) is untouched. These tests pin:
//
//   1. A SHORT mono native song does NOT stream, and its CLI render
//      (writeSongWavStreaming) is byte-identical to renderSongWav (both take the
//      whole-song NNA path).
//   2. A LONG mono VARIABLE native song whose note runs do NOT overlap under
//      NNA=cut (so the bounded per-note-run render and the whole-song NNA render
//      compute the same audio) streams BYTE-FOR-BYTE identically to
//      renderSongWav across MANY chunks — proving the row-chunk state carry is
//      exact.
//   3. A LONG mono FLOW (non-variable) native song streams DETERMINISTICALLY
//      (two independent streams are byte-identical) in bounded RAM. The <500 MB
//      peak for a >15 min song of this shape is exercised by the CLI gate
//      (tool/gen_long_native.dart under /usr/bin/time -l).

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

/// A single-channel mono native song. A new NOTE lands every [notesEvery] rows
/// (fully TILING the row range — every row belongs to exactly one note run so
/// the runs are ADJACENT, and the last run reaches the final row); every other
/// row carries a per-tick vibrato (which forces the whole-song NNA render path).
/// No key-off is ever emitted, so every run is sustain-only (release == 0) and
/// under NNA=cut the whole-song NNA render and the bounded per-note-run render
/// compute the SAME audio. When [speedChangeRow] is set, an Fxx there makes the
/// song VARIABLE-timed (routing the whole-song render through
/// [_renderSampleChannelIntoVariable], the exact per-run kernel the stream
/// mirrors); otherwise (differing pattern lengths) it is a FLOW / walk song.
TrackerSong _nativeSong({
  required List<int> patternRows,
  required List<int> order,
  int notesEvery = 8,
  int? speedChangeRow,
}) {
  final zoneKeys = [48, 60, 72];
  final patterns = <TrackerPattern>[];
  for (var p = 0; p < patternRows.length; p++) {
    final rows = patternRows[p];
    final col = List<TrackerCell>.filled(rows, TrackerCell.empty);
    for (var r = 0; r < rows; r++) {
      if (r % notesEvery == 0) {
        col[r] =
            TrackerCell(midi: zoneKeys[(r ~/ notesEvery) % zoneKeys.length]);
      } else if (speedChangeRow != null && p == 0 && r == speedChangeRow) {
        // Fxx set-speed (< 0x20) → mid-song SPEED change ⇒ variable timing.
        col[r] = const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x04);
      } else {
        col[r] = const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x38);
      }
    }
    patterns.add(TrackerPattern(name: 'p$p', cells: [col]));
  }
  final first = patternRows.first;
  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'native',
        instrument: _nativeInstrument(),
        rows: first,
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('native_mono_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('short mono native song stays on the whole-song NNA path', () async {
    // Differing pattern lengths ⇒ FLOW (walk) render; short ⇒ below the
    // streaming budget, so it must NOT stream.
    final song = _nativeSong(patternRows: [64, 48], order: [0, 1, 0, 1]);
    expect(songUsesVariableTiming(song), isFalse);
    expect(songNeedsWalkRender(song), isTrue);
    expect(
      songCanStreamFlowVariable(song, stereo: false),
      isFalse,
      reason: 'a short native mono song must stay on the whole-song NNA render',
    );

    final out = '${tmp.path}/short.wav';
    await song.writeSongWavStreaming(out);
    final streamed = File(out).readAsBytesSync();
    final whole = song.renderSongWav();
    expect(streamed.length, whole.length);
    expect(
      _firstDiff(streamed, whole),
      -1,
      reason: 'short-song CLI render == renderSongWav (both whole-song NNA)',
    );
  });

  test('long mono VARIABLE native song streams byte-identical to renderSongWav',
      () async {
    // ~1500 rows → over the 120 s streaming budget, spanning dozens of
    // row-chunks. A mid-song Fxx makes it variable-timed so the whole-song NNA
    // voice render uses _renderSampleChannelIntoVariable — the exact per-run
    // kernel the stream mirrors. Notes tile the rows and never overlap under
    // NNA=cut, so the NNA render == the bounded per-note-run render.
    final song = _nativeSong(
      patternRows: [1500],
      order: [0],
      notesEvery: 10,
      speedChangeRow: 703,
    );
    expect(songUsesVariableTiming(song), isTrue);
    expect(
      songCanStreamFlowVariable(song, stereo: false),
      isTrue,
      reason: 'a long native mono song routes through the bounded stream',
    );

    final out = '${tmp.path}/longvar.wav';
    await song.writeSongWavStreaming(out);
    final streamed = File(out).readAsBytesSync();
    final whole = song.renderSongWav();

    final frames = (streamed.length - 44) ~/ 2;
    expect(
      frames,
      greaterThan(120 * kSampleRate),
      reason: 'song must exceed the 120 s streaming budget',
    );
    expect(
      streamed.skip(44).any((b) => b != 0),
      isTrue,
      reason: 'render must be non-silent',
    );
    expect(streamed.length, whole.length);
    expect(
      _firstDiff(streamed, whole),
      -1,
      reason: 'bounded mono stream must equal the whole-song render '
          'byte-for-byte',
    );
  });

  test('long mono FLOW native song streams deterministically', () async {
    // A long FLOW (non-variable) native song — the "no mid-song tempo change"
    // shape. Two independent streams must be byte-identical (the row-chunk state
    // carry is deterministic), in bounded RAM.
    final song = _nativeSong(
      patternRows: [64, 48],
      order: [
        for (var i = 0; i < 24; i++) ...[0, 1],
      ],
      notesEvery: 6,
    );
    expect(songUsesVariableTiming(song), isFalse);
    expect(songNeedsWalkRender(song), isTrue);
    expect(songCanStreamFlowVariable(song, stereo: false), isTrue);

    final aPath = '${tmp.path}/flowA.wav';
    final bPath = '${tmp.path}/flowB.wav';
    await song.writeSongWavStreaming(aPath);
    await song.writeSongWavStreaming(bPath);
    final a = File(aPath).readAsBytesSync();
    final b = File(bPath).readAsBytesSync();

    final frames = (a.length - 44) ~/ 2;
    expect(
      frames,
      greaterThan(120 * kSampleRate),
      reason: 'song must exceed the 120 s streaming budget',
    );
    expect(a.skip(44).any((x) => x != 0), isTrue);
    expect(a.length, b.length);
    expect(
      _firstDiff(a, b),
      -1,
      reason: 'bounded stream must be deterministic',
    );
  });
}
