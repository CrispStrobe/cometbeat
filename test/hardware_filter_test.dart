// test/hardware_filter_test.dart
//
// The Amiga/GUS HARDWARE output low-pass filter, toggled by E0x (MOD/XM extended
// sub-command 0x0) and S0x (S3M/IT special sub-command 0x0). On real hardware
// this is a GLOBAL fixed ~3.3 kHz low-pass over the whole output mix, switched
// on/off and persisting until toggled: E00/S00 = OFF, E01/S01 = ON.
//
// These tests render a bright (HF-rich, 8 kHz) sample voice and assert, via a
// single-bin DFT (Goertzel), that turning the filter ON drops the HF energy,
// toggling it OFF again restores it, and that a filter-OFF (or no-E0x) render is
// byte-identical to the pre-filter engine. Cross-format S0x <-> E0x mapping and
// the export-loss report (S0 no longer "unmapped") are also pinned, plus streamed
// == whole-song for a filtered song.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/hardware_filter_test.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_export_report.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// Goertzel magnitude of [x] at [freq] (single-bin DFT).
double goertzel(List<double> x, double freq, {double sr = kSampleRate + 0.0}) {
  final w = 2 * pi * freq / sr;
  final coeff = 2 * cos(w);
  double s1 = 0, s2 = 0;
  for (final v in x) {
    final s0 = v + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final real = s1 - s2 * cos(w);
  final imag = s2 * sin(w);
  return sqrt(real * real + imag * imag);
}

const double _hf = 8000.0;

/// A native (non-normalised), fully LOOPING 1 s [freq] sine — bright HF-rich
/// source material that rings for the whole song (so a mid-song filter toggle
/// still has a tone to act on in the tail).
SampleInstrument brightSine(double freq) {
  const n = kSampleRate; // 1 s
  final s = Float64List(n);
  for (var i = 0; i < n; i++) {
    s[i] = 0.5 * sin(2 * pi * freq * i / kSampleRate);
  }
  return SampleInstrument(
    'bright',
    s,
    normalize: false,
    loopLength: n, // loopStart defaults to 0 → full-sample loop
  );
}

/// A one-channel song whose channel-0 column is [ch0] (a note + optional E0x
/// toggle), playing the bright sine. Uniform timing, [rows] rows, mono unless
/// [stereo].
TrackerSong hwSong(
  List<TrackerCell> ch0, {
  int rows = 16,
  bool stereo = false,
}) {
  final col = List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true);
  for (var i = 0; i < ch0.length && i < rows; i++) {
    col[i] = ch0[i];
  }
  final channel = TrackerChannel(
    id: 'c0',
    instrument: brightSine(_hf),
    rows: rows,
    gain: 1.0,
  );
  final pattern = TrackerPattern(name: '00', cells: [col]);
  return TrackerSong.fromParts(
    channels: [channel],
    timing: TrackerTiming(rows: rows),
    patterns: [pattern],
    order: [0],
    stereoOutput: stereo,
  );
}

/// The E0x toggle cell (E00 off / E01 on) — kFxExtended, sub-nibble 0x0.
TrackerCell e0(int value, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: kFxExtended, fxParam: value & 0xF);

List<double> mono(TrackerSong s) =>
    [for (final v in replaySong(s).pcm) v / 32768.0];

Future<List<int>> streamedBytes(TrackerSong song) async {
  final dir = Directory.systemTemp.createTempSync('hw_filter');
  final path = '${dir.path}/out.wav';
  try {
    await song.writeSongWavStreaming(path);
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  group('render: the hardware filter attenuates HF when ON', () {
    test('E01 (ON) drops 8 kHz energy vs E00 (OFF)', () {
      final off = mono(hwSong([e0(0x0, midi: 60)]));
      final on = mono(hwSong([e0(0x1, midi: 60)]));

      // Skip the attack + one-pole settling transient.
      const skip = 4000;
      final offMag = goertzel(off.sublist(skip), _hf);
      final onMag = goertzel(on.sublist(skip), _hf);

      expect(offMag, greaterThan(0), reason: 'OFF must carry the HF tone');
      // A one-pole LP at ~3.3 kHz on an 8 kHz tone → |H| ≈ 0.38.
      expect(
        onMag,
        lessThan(offMag * 0.6),
        reason: 'filtered HF ($onMag) must be well below open ($offMag)',
      );
    });

    test('toggling OFF mid-song restores the HF in the tail', () {
      const rows = 32;
      // E01 at row 0, E00 at row 16: the first half is filtered (dark), the
      // second half passes through (bright again).
      final cells = <TrackerCell>[e0(0x1, midi: 60)];
      for (var r = 1; r < 16; r++) {
        cells.add(TrackerCell.empty);
      }
      cells.add(e0(0x0)); // row 16: filter OFF
      final song = hwSong(cells, rows: rows);
      final out = mono(song);

      final mid = song.timing.stepStartSample(16);
      final total = song.timing.totalSamples;
      // Filtered window (well inside the ON region) vs restored window (well
      // inside the OFF region), each avoiding the toggle transient.
      final filtered = goertzel(out.sublist(4000, mid - 1000), _hf);
      final restored = goertzel(out.sublist(mid + 2000, total - 1), _hf);

      expect(filtered, greaterThan(0));
      expect(
        restored,
        greaterThan(filtered * 1.5),
        reason: 'HF must return after E00 (filtered $filtered, restored '
            '$restored)',
      );
    });
  });

  group('byte-identity: the filter is a true passthrough when OFF', () {
    // Two songs with IDENTICAL voice content (E00 and E01 are both no-ops for
    // the voice — kFxExtended sub-nibble 0x0), differing ONLY in whether the
    // filter is engaged in the FIRST half. In the second half both toggle the
    // filter OFF, so the OFF-passthrough output must be sample-for-sample equal
    // to the raw mix — proving the OFF path leaves the audio untouched.
    test(
        'the OFF (E00) tail is byte-identical between filtered/unfiltered runs',
        () {
      const rows = 32;
      List<TrackerCell> col(int firstToggle) {
        final c = <TrackerCell>[e0(firstToggle, midi: 60)];
        for (var r = 1; r < 16; r++) {
          c.add(TrackerCell.empty);
        }
        c.add(e0(0x0)); // row 16: OFF in both songs
        return c;
      }

      final toggled =
          replaySong(hwSong(col(0x1), rows: rows)).pcm; // ON then OFF
      final neverOn =
          replaySong(hwSong(col(0x0), rows: rows)).pcm; // OFF then OFF
      final mid = hwSong(col(0x0), rows: rows).timing.stepStartSample(16);

      // First half differs (one is filtered)…
      expect(
        toggled.sublist(4000, mid),
        isNot(orderedEquals(neverOn.sublist(4000, mid))),
      );
      // …the OFF tail is identical to the raw (never-filtered) mix.
      expect(
        toggled.sublist(mid + 2000),
        orderedEquals(neverOn.sublist(mid + 2000)),
      );
    });

    test('a song with no E0x builds no filter schedule', () {
      // hardwareFilterSchedule returns null (→ the render skips the filter and
      // stays byte-identical) when no E0x appears.
      final rows = [
        [const TrackerCell(midi: 60), const TrackerCell()],
        [const TrackerCell(), const TrackerCell()],
      ];
      expect(hardwareFilterSchedule(rows, const [0, 100], 200), isNull);
    });

    test('an all-OFF (E00-only) schedule marks nothing ON', () {
      final rows = [
        [e0(0x0, midi: 60)],
        [TrackerCell.empty],
      ];
      final sched = hardwareFilterSchedule(rows, const [0, 100], 200);
      expect(sched, isNotNull);
      expect(sched!.every((b) => b == 0), isTrue);
    });

    test('an E01 schedule marks the ON range', () {
      final rows = [
        [e0(0x1, midi: 60)],
        [TrackerCell.empty],
      ];
      final sched = hardwareFilterSchedule(rows, const [0, 100], 200)!;
      expect(sched.every((b) => b == 1), isTrue);
    });
  });

  group('cross-format: S0x <-> E0x is the SAME hardware filter', () {
    /// A one-channel, one-row S3M carrying a single note + effect command.
    ModuleDoc s3mDoc(int command, int info) => docFromS3m(
          S3mModule(
            channelCount: 1,
            order: const [0],
            samples: const [],
            patterns: [
              S3mPattern([
                [
                  S3mCell(
                    note: 0x30,
                    instrument: 1,
                    command: command,
                    info: info,
                  ),
                ],
              ]),
            ],
          ),
        );

    ModuleDoc itDoc(int command, int value) => docFromIt(
          ItModule(
            channelCount: 1,
            order: const [0],
            samples: const [],
            patterns: [
              ItPattern(
                [
                  [
                    ItCell(
                      note: 60,
                      instrument: 1,
                      command: command,
                      commandValue: value,
                    ),
                  ],
                ],
                1,
              ),
            ],
          ),
        );

    ModuleDoc modSourcedDoc(int effect, int effectParam) => ModuleDoc(
          sourceFormat: ModuleFormat.mod,
          channelCount: 1,
          order: const [0],
          samples: const [],
          patterns: [
            DocPattern(
              [
                [
                  DocCell(
                    note: 60,
                    instrument: 1,
                    effect: effect,
                    effectParam: effectParam,
                  ),
                ],
              ],
              1,
            ),
          ],
        );

    test('S3M S01 → neutral E01 → MOD E01', () {
      final cell = s3mDoc(19, 0x01).patterns.first.rows.first.first; // S01
      expect(cell.effect, 0xE);
      expect(cell.effectParam, 0x01); // E01
      final mc = parseMod(convertToMod(s3mDoc(19, 0x01)))
          .patterns
          .first
          .rows
          .first
          .first;
      expect(mc.effect, 0xE, reason: 'S01 → E01');
      expect(mc.effectParam, 0x01);
    });

    test('IT S01 → neutral E01 → MOD E01', () {
      final cell = itDoc(19, 0x01).patterns.first.rows.first.first;
      expect(cell.effect, 0xE);
      expect(cell.effectParam, 0x01);
    });

    test('MOD E01 → S3M S01', () {
      final s3m = parseS3m(convertToS3m(modSourcedDoc(0xE, 0x01)));
      final sc = s3m.patterns.first.rows.first.first;
      expect(sc.command, 19, reason: 'E01 → Sxy');
      expect(sc.info, 0x01); // S01
    });

    test('MOD E01 → IT S01', () {
      final it = parseIt(convertToIt(modSourcedDoc(0xE, 0x01)));
      final ic = it.patterns.first.rows.first.first;
      expect(ic.command, 19);
      expect(ic.commandValue, 0x01);
    });

    test('S0x is NO LONGER reported as an unmapped Sxy drop', () {
      final report = moduleExportLossReport(s3mDoc(19, 0x01), ModuleFormat.mod);
      expect(report, isNot(contains(ModuleExportLoss.unmappedSpecialEffects)));
    });
  });

  group('streaming: a filtered render streams == whole-song', () {
    test('mono filtered song: writeSongWavStreaming == renderSongWav',
        () async {
      final cells = <TrackerCell>[e0(0x1, midi: 60)];
      for (var r = 1; r < 8; r++) {
        cells.add(TrackerCell.empty);
      }
      cells.add(e0(0x0)); // toggle mid-song → time-varying schedule
      final song = hwSong(cells);
      expect(songUsesHardwareFilter(song), isTrue);

      final whole = song.renderSongWav();
      final streamed = await streamedBytes(song);
      expect(streamed.length, whole.length);
      expect(whole.any((b) => b != 0), isTrue, reason: 'must be non-silent');
      expect(streamed, orderedEquals(whole));
    });

    test('stereo filtered song: writeSongWavStreaming == renderSongWav',
        () async {
      final cells = <TrackerCell>[e0(0x1, midi: 60)];
      for (var r = 1; r < 8; r++) {
        cells.add(TrackerCell.empty);
      }
      cells.add(e0(0x0));
      final song = hwSong(cells, stereo: true);
      expect(songUsesHardwareFilter(song), isTrue);

      final whole = song.renderSongWav();
      final streamed = await streamedBytes(song);
      expect(streamed.length, whole.length);
      expect(streamed, orderedEquals(whole));
    });
  });
}
