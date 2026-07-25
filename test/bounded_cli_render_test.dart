// Bounded-memory streaming CLI render (TrackerSong.writeSongWavStreaming).
//
// The default `render_module <in> <out>` path streams the whole-song render to
// disk in PCM16 blocks so the int16 PCM + WAV copy are never held alongside the
// float mix accumulator (bounded peak). These tests pin the invariant that
// matters: the streamed file is BYTE-IDENTICAL to the in-memory renderSongWav()
// for a multi-order COMMAND song — on BOTH the stereo (panned) and the mono
// command paths — and that the streamed WAV header is well-formed. Pure Dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart' show kFxSetVolume;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

int _u32(Uint8List b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);
int _u16(Uint8List b, int off) => b[off] | (b[off + 1] << 8);
String _tag(Uint8List b, int off) =>
    String.fromCharCodes(b.sublist(off, off + 4));

/// A cell from a compact `midi:vol` code: `-1` → empty, a bare midi → a note,
/// and `midi | (vol << 8)` → a note carrying a Cxx set-volume command (so the
/// song routes through the tick replayer, not the offline mixer).
TrackerCell _cell(int code) {
  if (code < 0) return TrackerCell.empty;
  final midi = code & 0xFF;
  final vol = code >> 8;
  return vol == 0
      ? TrackerCell(midi: midi)
      : TrackerCell(midi: midi, fxCmd: kFxSetVolume, fxParam: vol);
}

List<TrackerCell> _col(List<int> codes) => [for (final c in codes) _cell(c)];

int _v(int midi, int vol) => midi | (vol << 8);

TrackerSong _commandSong({required bool panned}) {
  const rows = 8;
  const timing = TrackerTiming(rows: rows);
  TrackerChannel ch(String id, Instrument ins, double pan) => TrackerChannel(
        id: id,
        instrument: AdditiveInstrument(id, ins),
        rows: rows,
        pan: pan,
      );
  final p0 = TrackerPattern(
    name: '00',
    cells: [
      _col([_v(60, 48), 64, -1, 67, 72, -1, 76, -1]),
      _col([48, -1, _v(55, 32), -1, 52, -1, -1, -1]),
    ],
  );
  final p1 = TrackerPattern(
    name: '01',
    cells: [
      _col([62, _v(65, 40), -1, 69, 74, -1, 77, -1]),
      _col([_v(50, 24), -1, 57, -1, 53, -1, -1, -1]),
    ],
  );
  return TrackerSong.fromParts(
    channels: [
      ch('a', Instrument.piano, panned ? -0.6 : 0.0),
      ch('b', Instrument.flute, panned ? 0.7 : 0.0),
    ],
    timing: timing,
    patterns: [p0, p1],
    order: [0, 1, 0, 1, 1, 0],
  );
}

Future<Uint8List> _streamed(TrackerSong s, String name) async {
  final dir = await Directory.systemTemp.createTemp('bounded_cli_test');
  addTearDown(() => dir.delete(recursive: true));
  final path = '${dir.path}/$name.wav';
  await s.writeSongWavStreaming(path);
  return File(path).readAsBytesSync();
}

void main() {
  test('stereo command song: streamed CLI render == renderSongWav (bytes)',
      () async {
    final s = _commandSong(panned: true);
    expect(s.usesCommands, isTrue, reason: 'must route through the replayer');
    expect(s.usesPan, isTrue, reason: 'must take the stereo streaming path');

    final inMemory = s.renderSongWav();
    final streamed = await _streamed(s, 'stereo');

    // Byte-for-byte identical to the whole-song in-memory render (header + PCM).
    expect(streamed.length, inMemory.length);
    expect(streamed, inMemory);

    // Streamed WAV header is well-formed (stereo).
    expect(_tag(streamed, 0), 'RIFF');
    expect(_u32(streamed, 4), streamed.length - 8);
    expect(_tag(streamed, 8), 'WAVE');
    expect(_tag(streamed, 12), 'fmt ');
    expect(_u32(streamed, 16), 16);
    expect(_u16(streamed, 20), 1); // PCM
    expect(_u16(streamed, 22), 2); // stereo
    expect(_u32(streamed, 24), 44100);
    expect(_u32(streamed, 28), 44100 * 4); // byte rate = sr * ch * 2
    expect(_u16(streamed, 32), 4); // block align = ch * 2
    expect(_u16(streamed, 34), 16); // bits per sample
    expect(_tag(streamed, 36), 'data');
    expect(_u32(streamed, 40), streamed.length - 44);
  });

  test('mono command song: streamed CLI render == renderSongWav (bytes)',
      () async {
    final s = _commandSong(panned: false);
    expect(s.usesCommands, isTrue);
    expect(s.usesPan, isFalse);
    expect(s.stereoOutput, isFalse);

    final inMemory = s.renderSongWav();
    final streamed = await _streamed(s, 'mono');

    expect(streamed.length, inMemory.length);
    expect(streamed, inMemory);

    // Header well-formed (mono).
    expect(_tag(streamed, 0), 'RIFF');
    expect(_u32(streamed, 4), streamed.length - 8);
    expect(_tag(streamed, 8), 'WAVE');
    expect(_u16(streamed, 22), 1); // mono
    expect(_u32(streamed, 28), 44100 * 2); // byte rate = sr * 1 * 2
    expect(_u16(streamed, 32), 2); // block align
    expect(_tag(streamed, 36), 'data');
    expect(_u32(streamed, 40), streamed.length - 44);
  });
}
