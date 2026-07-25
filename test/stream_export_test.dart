// Bounded-memory streaming / range WAV export for TrackerSong.
//
// The default renderSongWav allocates the whole song's PCM at once; the
// streaming/range API renders the order list in contiguous chunks and emits
// each chunk in turn, so peak memory is bounded to ~one chunk. For a UNIFORM /
// non-command song the whole-song render is already a byte-for-byte
// concatenation of independent per-order renders, so chunked/streamed output is
// byte-identical to renderSongWav — that invariant is what these tests pin down
// (multi-chunk == whole, chunk-all == default, range == concatenation of orders,
// and a valid streamed WAV header). Pure Dart, no device audio.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// PCM payload of a WAV (everything after the fixed 44-byte header).
Uint8List _pcm(Uint8List wav) => Uint8List.sublistView(wav, 44);

/// A UNIFORM song: multiple patterns/orders, note-only cells (no effect
/// commands, no per-cell instruments, no envelopes, no pan, no flow), so it
/// renders through the offline mixer path where the whole-song WAV is exactly
/// the concatenation of per-order renders.
TrackerSong _uniformSong({List<int>? order}) {
  const rows = 8;
  const timing = TrackerTiming(rows: rows);
  TrackerChannel ch(String id, Instrument ins) => TrackerChannel(
        id: id,
        instrument: AdditiveInstrument(id, ins),
        rows: rows,
      );
  TrackerPattern pat(String name, List<List<int?>> notes) => TrackerPattern(
        name: name,
        cells: [
          for (final col in notes)
            [
              for (final m in col)
                m == null ? TrackerCell.empty : TrackerCell(midi: m),
            ],
        ],
      );
  final p0 = pat('00', [
    [60, null, 64, null, 67, null, 72, null],
    [48, null, null, null, 55, null, null, null],
  ]);
  final p1 = pat('01', [
    [62, null, 65, null, 69, null, 74, null],
    [50, null, null, null, 57, null, null, null],
  ]);
  return TrackerSong.fromParts(
    channels: [ch('a', Instrument.piano), ch('b', Instrument.flute)],
    timing: timing,
    patterns: [p0, p1],
    order: order ?? [0, 1, 0, 1, 1, 0],
  );
}

int _u32(Uint8List b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);
int _u16(Uint8List b, int off) => b[off] | (b[off + 1] << 8);
String _tag(Uint8List b, int off) =>
    String.fromCharCodes(b.sublist(off, off + 4));

void main() {
  test('uniform song is on the offline path (byte-identical guarantee holds)',
      () {
    final s = _uniformSong();
    expect(s.usesCommands, isFalse);
    expect(s.usesInstruments, isFalse);
    expect(s.usesEnvelopes, isFalse);
    expect(s.usesPan, isFalse);
    expect(s.stereoOutput, isFalse);
  });

  test('(a) streamed chunk-1 PCM == whole-song PCM, byte for byte', () {
    final s = _uniformSong();
    final whole = _pcm(s.renderSongWav());
    final streamed = <int>[];
    for (final chunk in s.renderOrderChunksPcm()) {
      // default chunkOrders = 1: one order entry per chunk
      streamed.addAll(chunk);
    }
    expect(streamed.length, whole.length);
    expect(Uint8List.fromList(streamed), whole);
  });

  test('(b) --chunk-orders = all reproduces the default render exactly', () {
    final s = _uniformSong();
    final whole = s.renderSongWav();
    final ranged = s.renderOrderRangeWav(
      0,
      s.order.length,
      chunkOrders: s.order.length,
    );
    expect(ranged, whole); // full WAV incl. header, byte-identical
  });

  test('(c) range [from,to) == concatenation of exactly those orders', () {
    final s = _uniformSong();
    // Expected: render each single order [i,i+1) and concatenate its PCM.
    final expected = <int>[];
    for (var i = 1; i < 4; i++) {
      expected.addAll(_pcm(s.renderOrderRangeWav(i, i + 1)));
    }
    final range = _pcm(s.renderOrderRangeWav(1, 4));
    expect(range, Uint8List.fromList(expected));

    // And it equals the matching slice of the whole-song PCM (uniform patterns
    // → equal per-order lengths).
    final whole = _pcm(s.renderSongWav());
    final seg = whole.length ~/ s.order.length;
    expect(range, Uint8List.sublistView(whole, 1 * seg, 4 * seg));
  });

  test('(d) streamed multi-chunk WAV has a valid header and correct PCM',
      () async {
    final s = _uniformSong();
    final dir = await Directory.systemTemp.createTemp('stream_export_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/out.wav';

    // default chunkOrders = 1 → many chunks for a multi-order song
    final dataBytes = await s.streamSongWavToFile(path);
    final wav = File(path).readAsBytesSync();

    // Header integrity.
    expect(_tag(wav, 0), 'RIFF');
    expect(_u32(wav, 4), wav.length - 8); // RIFF size = file - 8
    expect(_tag(wav, 8), 'WAVE');
    expect(_tag(wav, 12), 'fmt ');
    expect(_u32(wav, 16), 16); // fmt chunk size
    expect(_u16(wav, 20), 1); // PCM
    expect(_u16(wav, 22), 1); // mono (uniform song is not panned)
    expect(_u32(wav, 24), 44100); // sample rate
    expect(_u32(wav, 28), 44100 * 2); // byte rate = sr * ch * 2
    expect(_u16(wav, 32), 2); // block align = ch * 2
    expect(_u16(wav, 34), 16); // bits per sample
    expect(_tag(wav, 36), 'data');
    expect(_u32(wav, 40), wav.length - 44); // data size = file - header
    expect(dataBytes, wav.length - 44);

    // Multiple chunks actually occurred (order length > 1).
    expect(s.order.length, greaterThan(1));
    // And the streamed PCM equals the whole-song PCM.
    expect(_pcm(wav), _pcm(s.renderSongWav()));
  });

  test(
    'CLI --stream is byte-identical to the default render for a module',
    () async {
      // Drive the real CLI on golden.mod (single order → one chunk, but exercises
      // the streaming file writer end to end).
      final dir = await Directory.systemTemp.createTemp('stream_cli_test');
      addTearDown(() => dir.delete(recursive: true));
      final def = '${dir.path}/def.wav';
      final str = '${dir.path}/str.wav';

      Future<void> render(List<String> extra, String out) async {
        final r = await Process.run(
          'dart',
          [
            'run',
            'bin/render_module.dart',
            'test/fixtures/golden.mod',
            out,
            ...extra,
          ],
        );
        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      }

      await render(const [], def);
      await render(const ['--stream', '--chunk-orders', '8'], str);
      expect(
        File(str).readAsBytesSync(),
        File(def).readAsBytesSync(),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
