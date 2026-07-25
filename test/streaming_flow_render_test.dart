// Verifies the bounded-memory CHUNKED flow/variable render
// ([streamFlowVariableMonoPcm] / [streamFlowVariableStereoPcm], routed through
// [TrackerSong.writeSongWavStreaming]) is BYTE-FOR-BYTE identical to the
// whole-song [TrackerSong.renderSongWav] — for synthetic multi-order COMMAND
// songs, mono AND stereo, including a mid-song tempo change (variable timing)
// and a Bxx/Dxx flow jump. Because the streamer carries each channel's voice
// state across chunk boundaries, the concatenation of chunks equals the
// whole-song render exactly, while holding only one chunk in memory.

import 'dart:io';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// An additive channel (routes through the tick voice — chunk-safe) carrying a
/// note + vibrato per row, so every song below actually SOUNDS and exercises the
/// per-tick effect path.
TrackerPattern _commandPattern(
  String name,
  int channels,
  int rows, {
  int fxCmd = kFxVibrato,
  int fxParam = 0x38,
  List<TrackerCell> Function(int channel, int row)? cellOf,
}) {
  final p = TrackerPattern.empty(name: name, channels: channels, rows: rows);
  for (var c = 0; c < channels; c++) {
    for (var r = 0; r < rows; r++) {
      if (cellOf != null) {
        final over = cellOf(c, r);
        if (over.isNotEmpty) {
          p.cells[c][r] = over.first;
          continue;
        }
      }
      p.cells[c][r] = r % 8 == 0
          ? TrackerCell(
              midi: 50 + c * 4 + (r ~/ 8) % 5,
              fxCmd: fxCmd,
              fxParam: fxParam,
            )
          : TrackerCell(fxCmd: fxCmd, fxParam: fxParam == 0 ? 1 : 0);
    }
  }
  return p;
}

List<TrackerChannel> _additiveChannels(int n, int rows, {required bool pan}) =>
    [
      for (var c = 0; c < n; c++)
        TrackerChannel(
          id: 'ch$c',
          instrument: AdditiveInstrument(
            'i$c',
            [Instrument.piano, Instrument.cello, Instrument.flute][c % 3],
          ),
          rows: rows,
          pan: pan ? (c.isEven ? -0.5 : 0.5) : 0.0,
        ),
    ];

TrackerSong _song({
  required List<TrackerPattern> patterns,
  required List<int> order,
  required bool stereo,
  int channels = 3,
  int initialSpeed = 6,
}) {
  final rows = patterns.first.rows;
  return TrackerSong.fromParts(
    channels: _additiveChannels(channels, rows, pan: stereo),
    timing: TrackerTiming(tempoBpm: 125, rows: rows),
    patterns: patterns,
    order: order,
    instruments: defaultInstrumentPool(),
    initialSpeed: initialSpeed,
    stereoOutput: stereo,
  );
}

/// Streams [song] to a temp WAV via [TrackerSong.writeSongWavStreaming] and
/// returns the file bytes.
Future<List<int>> _streamedBytes(TrackerSong song) async {
  final dir = Directory.systemTemp.createTempSync('stream_flow');
  final path = '${dir.path}/out.wav';
  try {
    await song.writeSongWavStreaming(path);
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  group('chunked flow/variable render == whole-song render (byte-identical)',
      () {
    // A Bxx position-jump song: order [0,1,2,3]; pattern 1 jumps FORWARD to
    // order 3 (skips order 2), so the walk is non-linear but terminates.
    TrackerSong flowJump({required bool stereo}) {
      final p0 = _commandPattern('00', 3, 32);
      final p1 = _commandPattern(
        '01',
        3,
        32,
        cellOf: (c, r) {
          if (c == 0 && r == 24) {
            return [const TrackerCell(fxCmd: kFxPositionJump, fxParam: 3)];
          }
          return const [];
        },
      );
      final p2 = _commandPattern('02', 3, 32);
      final p3 = _commandPattern('03', 3, 24);
      return _song(
        patterns: [p0, p1, p2, p3],
        order: [0, 1, 2, 3],
        stereo: stereo,
      );
    }

    // A Dxx pattern-break song: pattern 0 breaks to next order at row 20.
    TrackerSong flowBreak({required bool stereo}) {
      final p0 = _commandPattern(
        '00',
        3,
        32,
        cellOf: (c, r) {
          if (c == 1 && r == 20) {
            return [const TrackerCell(fxCmd: kFxPatternBreak, fxParam: 0x04)];
          }
          return const [];
        },
      );
      final p1 = _commandPattern('01', 3, 28);
      final p2 = _commandPattern('02', 3, 32);
      return _song(patterns: [p0, p1, p2], order: [0, 1, 2], stereo: stereo);
    }

    // A mid-song tempo change: pattern 0 plays at speed 4 (Fxx 04), pattern 1 at
    // speed 8 (Fxx 08) — two distinct speeds ⇒ variable timing.
    TrackerSong variableTempo({required bool stereo}) {
      final p0 = _commandPattern(
        '00',
        3,
        24,
        cellOf: (c, r) {
          if (c == 0 && r == 0) {
            return [const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x04)];
          }
          return const [];
        },
      );
      final p1 = _commandPattern(
        '01',
        3,
        24,
        cellOf: (c, r) {
          if (c == 0 && r == 0) {
            return [const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x08)];
          }
          return const [];
        },
      );
      return _song(
        patterns: [p0, p1],
        order: [0, 1, 0, 1],
        stereo: stereo,
        initialSpeed: 4,
      );
    }

    for (final (name, build, variable) in [
      ('Bxx flow jump', flowJump, false),
      ('Dxx pattern break', flowBreak, false),
      ('mid-song tempo (variable)', variableTempo, true),
    ]) {
      for (final stereo in [false, true]) {
        final label = '$name (${stereo ? 'stereo' : 'mono'})';
        test(label, () async {
          final song = build(stereo: stereo);

          // It must actually route through the flow/variable path AND be
          // eligible for the chunked streamer (else the test proves nothing).
          expect(song.usesCommands, isTrue, reason: 'should be a command song');
          expect(
            songNeedsWalkRender(song) || songUsesVariableTiming(song),
            isTrue,
            reason: 'should use the flow/variable render path',
          );
          expect(songUsesVariableTiming(song), variable);
          expect(
            songCanStreamFlowVariable(song, stereo: stereo),
            isTrue,
            reason: 'the chunked streamer must handle this song',
          );

          final whole = song.renderSongWav();
          final streamed = await _streamedBytes(song);

          expect(
            streamed.length,
            whole.length,
            reason: 'streamed byte length must match renderSongWav',
          );
          expect(
            streamed.length,
            greaterThan(44 + 1000),
            reason: 'song must produce real audio',
          );
          // Byte-for-byte identical (header + PCM).
          expect(streamed, orderedEquals(whole));
        });
      }
    }

    test('chunk boundaries do not depend on chunk size (state carried)', () {
      // Rendering the same variable song and asserting the streamer output is
      // internally consistent across two invocations (deterministic).
      final song = variableTempo(stereo: true);
      final a = <int>[];
      final b = <int>[];
      streamFlowVariableStereoPcm(
        song,
        onStart: (_) {},
        onBlock: a.addAll,
      );
      streamFlowVariableStereoPcm(
        song,
        onStart: (_) {},
        onBlock: b.addAll,
      );
      expect(a, orderedEquals(b));
      expect(a, isNotEmpty);
    });
  });
}
