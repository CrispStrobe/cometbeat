// Pins the streaming contract for PROCEDURAL voices — [FmInstrument],
// [SubtractiveInstrument], [SfxrInstrument], [KarplusInstrument] and the OPL2
// [OplInstrument]. A song whose channel carries one of these AND uses commands /
// flow / variable timing (so it routes through [TrackerSong.writeSongWavStreaming]
// and NOT the offline mixer) must produce output BYTE-IDENTICAL to the whole-song
// [TrackerSong.renderSongWav], even when a note RINGS across a >=65536-frame
// chunk boundary.
//
// WHY THIS HOLDS WITHOUT ANY CARRIED CHUNK STATE (the verification result):
// The bounded-memory row-chunk streamer ([streamFlowVariableMonoPcm] /
// [streamFlowVariableStereoPcm]) only ever handles ADDITIVE, native SAMPLE, and
// native MULTI-SAMPLE channels — the channel kinds [_channelChunkSafe] accepts.
// A procedural voice is none of those, so [songCanStreamFlowVariable] returns
// false for any song containing an active procedural channel. As a result
// [writeSongWavStreaming] NEVER row-chunks such a song; it falls back to the
// whole-song render ([replaySong] for mono, [songStereoFloat] for stereo) and
// streams that materialised result. Each procedural note is synthesized in ONE
// piece over its full run ([renderChannelPerNote] / [OplInstrument.renderChannel]
// / [_renderPerNote]) — there is no chunk boundary for it to re-attack at. So the
// streamed bytes equal the whole-song render by construction, and the tests below
// pin exactly that (byte-for-byte), asserting both the byte-identity AND the
// `songCanStreamFlowVariable == false` invariant that guarantees it.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/subtractive.dart';
import 'package:comet_beat/core/audio/mod/opl_voice.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal, non-blank OPL2 patch: carrier-only (modulator silenced), both
/// operators sustaining, so a held note rings for its whole run.
List<int> _oplPatch() {
  final d = List<int>.filled(12, 0);
  d[0] = (1 & 0x0F) | 0x20; // modulator: mult 1, sustaining
  d[1] = (1 & 0x0F) | 0x20; // carrier:   mult 1, sustaining
  d[2] = 63; // modulator total level = silence (carrier-only)
  d[3] = 0; // carrier full level
  d[4] = (15 << 4) | 15; // attack/decay
  d[5] = (15 << 4) | 15;
  d[6] = (0 << 4) | 15; // sustain/release
  d[7] = (0 << 4) | 15;
  return d;
}

/// Builds a single-channel song around [inst]. A long note is struck at row 0 and
/// held across all 64 rows (~1.2 s/row group at 125 BPM / speed 6 ⇒ ~7.7 s total),
/// so it rings across many 65536-frame chunk boundaries. The song is made a
/// command / variable / flow song (routing it through the streaming path, not the
/// offline mixer) per [variable] / [flow].
TrackerSong _procSong(
  TrackerInstrument inst, {
  bool stereo = false,
  bool variable = false,
  bool flow = false,
}) {
  const rows = 64;
  TrackerPattern pat(String name) {
    final p = TrackerPattern.empty(name: name, channels: 1, rows: rows);
    if (variable) {
      // A speed command ON the trigger row: still one long note, but two
      // distinct speeds across the order ⇒ variable timing.
      p.cells[0][0] =
          const TrackerCell(midi: 45, fxCmd: kFxSetSpeed, fxParam: 0x04);
    } else {
      p.cells[0][0] = const TrackerCell(midi: 45); // long ringing note
      // A per-tick command on a LATER, note-free row ⇒ usesCommands (routes
      // through replaySong) without retriggering the ringing note.
      p.cells[0][40] = const TrackerCell(fxCmd: kFxVibrato, fxParam: 0x38);
    }
    if (flow && name == '00') {
      // A Bxx position jump makes it a flow (walk-render) song.
      p.cells[0][60] = const TrackerCell(fxCmd: kFxPositionJump, fxParam: 2);
    }
    return p;
  }

  final patterns = variable
      ? [
          pat('00'),
          TrackerPattern.empty(name: '01', channels: 1, rows: rows)
            ..cells[0][0] =
                const TrackerCell(midi: 45, fxCmd: kFxSetSpeed, fxParam: 0x08),
        ]
      : flow
          ? [pat('00'), pat('01'), pat('02')]
          : [pat('00')];
  final order = variable
      ? [0, 1, 0, 1]
      : flow
          ? [0, 1, 2]
          : [0, 0, 0];

  return TrackerSong.fromParts(
    channels: [
      TrackerChannel(
        id: 'proc',
        instrument: inst,
        rows: rows,
        pan: stereo ? -0.4 : 0.0,
      ),
    ],
    timing: const TrackerTiming(tempoBpm: 125, rows: rows),
    patterns: patterns,
    order: order,
    instruments: defaultInstrumentPool(),
    initialSpeed: variable ? 4 : 6,
    stereoOutput: stereo,
  );
}

/// Streams [song] to a temp WAV via [TrackerSong.writeSongWavStreaming] and
/// returns the file bytes.
Future<Uint8List> _streamedBytes(TrackerSong song) async {
  final dir = Directory.systemTemp.createTempSync('stream_proc');
  final path = '${dir.path}/out.wav';
  try {
    await song.writeSongWavStreaming(path);
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  group('procedural-voice streaming == whole-song render (byte-identical)', () {
    final cases = <String, TrackerSong Function()>{
      'FM (mono, command)': () =>
          _procSong(FmInstrument.preset('ep', kFmPresets['ePiano']!)),
      'FM (stereo, command)': () => _procSong(
            FmInstrument.preset('ep', kFmPresets['ePiano']!),
            stereo: true,
          ),
      'FM (mono, variable timing)': () => _procSong(
            FmInstrument.preset('ep', kFmPresets['ePiano']!),
            variable: true,
          ),
      'FM (mono, flow Bxx)': () => _procSong(
            FmInstrument.preset('ep', kFmPresets['ePiano']!),
            flow: true,
          ),
      'Subtractive (mono, command)': () =>
          _procSong(SubtractiveInstrument.preset('pad', kSubPresets['pad']!)),
      'Subtractive (stereo, command)': () => _procSong(
            SubtractiveInstrument.preset('pad', kSubPresets['pad']!),
            stereo: true,
          ),
      'Sfxr (mono, command)': () =>
          _procSong(SfxrInstrument.preset('zap', sfxrZap, seed: 7)),
      'Karplus (mono, command)': () =>
          _procSong(const KarplusInstrument('pluck')),
      'OPL2 (mono, command)': () =>
          _procSong(OplInstrument('opl', _oplPatch())),
      'OPL2 (stereo, command)': () =>
          _procSong(OplInstrument('opl', _oplPatch()), stereo: true),
      'OPL2 (mono, variable timing)': () =>
          _procSong(OplInstrument('opl', _oplPatch()), variable: true),
    };

    cases.forEach((label, build) {
      test(label, () async {
        final song = build();
        final stereo = song.usesPan || song.stereoOutput;

        // (1) It must route through the streaming path (command / flow /
        // variable), NOT the offline mixer — else the test proves nothing.
        expect(
          song.usesCommands ||
              songNeedsWalkRender(song) ||
              songUsesVariableTiming(song),
          isTrue,
          reason: 'must use the command/flow/variable render path',
        );

        // (2) The invariant that MAKES the stream match the whole-song render:
        // a procedural voice is not chunk-safe, so the row-chunk streamer is
        // never engaged; the whole-song render is streamed instead.
        expect(
          songCanStreamFlowVariable(song, stereo: false),
          isFalse,
          reason: 'procedural voices are not row-chunk-safe (mono)',
        );
        expect(
          songCanStreamFlowVariable(song, stereo: true),
          isFalse,
          reason: 'procedural voices are not row-chunk-safe (stereo)',
        );

        final whole = song.renderSongWav();
        final frames = (whole.length - 44) ~/ (stereo ? 4 : 2);

        // (3) The note actually rings across at least one 65536-frame chunk
        // boundary (the condition under which a re-attack bug would show).
        expect(
          frames,
          greaterThan(kStreamChunkFrames),
          reason: 'note must ring across a >=65536-frame chunk boundary',
        );
        expect(
          whole.any((b) => b != 0),
          isTrue,
          reason: 'song must produce real audio',
        );

        // (4) Byte-for-byte identical (header + PCM).
        final streamed = await _streamedBytes(song);
        expect(
          streamed.length,
          whole.length,
          reason: 'streamed byte length must match renderSongWav',
        );
        expect(streamed, orderedEquals(whole));
      });
    });
  });
}
