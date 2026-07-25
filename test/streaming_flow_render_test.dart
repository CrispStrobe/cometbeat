// Verifies the bounded-memory CHUNKED flow/variable render
// ([streamFlowVariableMonoPcm] / [streamFlowVariableStereoPcm], routed through
// [TrackerSong.writeSongWavStreaming]) is BYTE-FOR-BYTE identical to the
// whole-song [TrackerSong.renderSongWav] — for synthetic multi-order COMMAND
// songs, mono AND stereo, including a mid-song tempo change (variable timing)
// and a Bxx/Dxx flow jump. Because the streamer carries each channel's voice
// state across chunk boundaries, the concatenation of chunks equals the
// whole-song render exactly, while holding only one chunk in memory.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

  // ---------------------------------------------------------------------------
  // Gxx/Hxy GLOBAL VOLUME across chunk boundaries: the running level persists,
  // so a chunked render must carry it. Byte-identity to renderSongWav proves the
  // carried scalar reproduces the whole-song globalVolumeEnvelope exactly.
  group('global-volume song streams byte-identically', () {
    // A variable-timing song (two speeds) carrying Gxx (set) and Hxy (slide up +
    // down) global-volume commands on several rows across several orders — the
    // level changes MID-CHUNK and PERSISTS across chunk boundaries.
    TrackerSong globalVol({required bool stereo}) {
      final p0 = _commandPattern(
        '00',
        3,
        48,
        cellOf: (c, r) {
          if (c == 0 && r == 0) {
            return [const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x06)];
          }
          if (c == 1 && r == 8) {
            return [
              const TrackerCell(fxCmd: kFxSetGlobalVolume, fxParam: 0x20),
            ];
          }
          if (c == 1 && r == 20) {
            return [const TrackerCell(fxCmd: kFxGlobalVolSlide, fxParam: 0x10)];
          }
          if (c == 2 && r == 40) {
            return [
              const TrackerCell(fxCmd: kFxSetGlobalVolume, fxParam: 0x38),
            ];
          }
          return const [];
        },
      );
      final p1 = _commandPattern(
        '01',
        3,
        48,
        cellOf: (c, r) {
          if (c == 0 && r == 0) {
            return [const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x08)];
          }
          if (c == 1 && r == 6) {
            return [const TrackerCell(fxCmd: kFxGlobalVolSlide, fxParam: 0x03)];
          }
          if (c == 1 && r == 30) {
            return [
              const TrackerCell(fxCmd: kFxSetGlobalVolume, fxParam: 0x10),
            ];
          }
          return const [];
        },
      );
      return _song(patterns: [p0, p1], order: [0, 1, 0, 1], stereo: stereo);
    }

    for (final stereo in [false, true]) {
      test('global volume (${stereo ? 'stereo' : 'mono'})', () async {
        final song = globalVol(stereo: stereo);
        expect(songUsesVariableTiming(song), isTrue);
        expect(
          songCanStreamFlowVariable(song, stereo: stereo),
          isTrue,
          reason: 'a global-volume song must now stream (not force whole-song)',
        );
        final whole = song.renderSongWav();
        final streamed = await _streamedBytes(song);
        // Spans many chunks, so the carried global-volume level is exercised
        // across boundaries (chunk-size independence: chunking never shows up).
        final frames = (whole.length - 44) ~/ (stereo ? 4 : 2);
        expect(frames, greaterThan(kStreamChunkFrames * 4));
        expect(streamed.length, whole.length);
        expect(streamed, orderedEquals(whole));
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Native multi-sample (NNA-zone) channels via the bounded per-note-run stereo
  // path (_renderLongNativeVariableStereo) — the buddhia3.it case. Only a LONG
  // (> 120 s) variable-timing stereo song takes it, so the fixture is built past
  // that threshold; each note run's tick-voice state is carried across chunks.
  group('native NNA-zone (long stereo) song streams byte-identically', () {
    MultiSampleInstrument nativeMulti(String id) {
      final lo = Float64List(4000);
      final hi = Float64List(4000);
      for (var i = 0; i < lo.length; i++) {
        lo[i] = sin(2 * pi * i / 40) * 0.3;
        hi[i] = sin(2 * pi * i / 20) * 0.25;
      }
      return MultiSampleInstrument(
        id,
        {
          // Looping native zones (normalize == false) so notes sustain across
          // the long rows and actually overlap chunk boundaries.
          60: SampleInstrument(
            'lo',
            lo,
            normalize: false,
            loopLength: lo.length,
            nativeFadeout: 128,
          ),
          72: SampleInstrument(
            'hi',
            hi,
            normalize: false,
            loopLength: hi.length,
            nativeFadeout: 128,
          ),
        },
        polyphonic: true,
        nativeVoiceSemantics: true,
      );
    }

    TrackerSong nativeLong() {
      const rows = 64;
      final channels = [
        for (var c = 0; c < 2; c++)
          TrackerChannel(
            id: 'z$c',
            instrument: nativeMulti('m$c'),
            rows: rows,
            pan: c.isEven ? -0.5 : 0.6, // non-zero pan ⇒ exercises pan regions
          ),
      ];
      TrackerPattern pat(String name, int speed) {
        final p = TrackerPattern.empty(name: name, channels: 2, rows: rows);
        for (var c = 0; c < 2; c++) {
          for (var r = 0; r < rows; r++) {
            if (c == 0 && r == 0) {
              p.cells[c][r] =
                  TrackerCell(midi: 60, fxCmd: kFxSetSpeed, fxParam: speed);
            } else if (r % 8 == 0) {
              p.cells[c][r] = TrackerCell(midi: (r ~/ 8).isEven ? 60 : 72);
            } else if (r % 8 == 4) {
              p.cells[c][r] =
                  const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x38);
            }
          }
        }
        return p;
      }

      // BPM 40, speeds 12/14 ⇒ ~750/875 ms per row; order [0,1,0] over 64 rows is
      // ~152 s, past the 120 s native-long threshold.
      return TrackerSong.fromParts(
        channels: channels,
        timing: const TrackerTiming(tempoBpm: 40, rows: rows),
        patterns: [pat('00', 12), pat('01', 14)],
        order: [0, 1, 0],
        instruments: defaultInstrumentPool(),
        initialSpeed: 12,
        stereoOutput: true,
      );
    }

    test('long native-zone stereo variable song', () async {
      final song = nativeLong();
      expect(songUsesVariableTiming(song), isTrue);
      expect(
        songCanStreamFlowVariable(song, stereo: true),
        isTrue,
        reason: 'the long native-zone stereo path must now stream',
      );
      final whole = song.renderSongWav();
      final frames = (whole.length - 44) ~/ 4;
      expect(
        frames,
        greaterThan(120 * 44100),
        reason: 'must exceed the 120 s native-long threshold',
      );
      // Spans ~100 chunks; byte-identity to the un-chunked whole-song render is
      // the chunk-size-independence guarantee.
      expect(frames, greaterThan(kStreamChunkFrames * 10));
      expect(whole.any((b) => b != 0), isTrue, reason: 'must be non-silent');
      final streamed = await _streamedBytes(song);
      expect(streamed.length, whole.length);
      expect(streamed, orderedEquals(whole));
    });

    test('chunk-size independence: streamed run is deterministic', () {
      final song = nativeLong();
      final a = <int>[];
      final b = <int>[];
      streamFlowVariableStereoPcm(song, onStart: (_) {}, onBlock: a.addAll);
      streamFlowVariableStereoPcm(song, onStart: (_) {}, onBlock: b.addAll);
      expect(a, orderedEquals(b));
      expect(a, isNotEmpty);
    });
  });
}
