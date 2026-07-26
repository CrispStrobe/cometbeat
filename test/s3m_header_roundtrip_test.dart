// test/s3m_header_roundtrip_test.dart
//
// S3M header metadata must survive a same-format round-trip through the EDITABLE
// TrackerSong (the Advanced Tracker import/export path), not just the direct
// ModuleDoc path. Before this, songFromModuleBytes → moduleDocFromSong →
// docToS3m dropped master/mixing volume, ultra-click, flags, created-with
// version, sample format, and the raw per-channel channelSettings bytes, because
// TrackerSong carried none of them. Each is asserted preserved below, plus a
// synthetic (no S3M source) song asserting sane defaults + no crash.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/s3m_header_roundtrip_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart' show docToS3m;
import 'package:comet_beat/core/audio/mod/module_doc.dart' show ModuleFormat;
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart' show parseS3m;
import 'package:comet_beat/core/audio/mod/s3m_writer.dart' show writeS3m;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signed 8-bit samples as normalized float (÷128) — the S3mSample.pcm model.
Float64List _i8(List<int> v) =>
    Float64List.fromList([for (final b in v) b / 128]);

void main() {
  // Four enabled channels with DISTINCTIVE L/R panning classes, then the
  // conventional 255 (disabled) padding to 32 bytes.
  final channelSettings = <int>[0, 8, 1, 9, ...List<int>.filled(28, 255)];

  // An S3M whose every header field is deliberately non-default.
  S3mModule buildDistinctiveS3m() {
    final rows = <List<S3mCell>>[
      [
        const S3mCell(note: 0x50, instrument: 1), // C-5 on channel 0
        S3mCell.empty,
        S3mCell.empty,
        S3mCell.empty,
      ],
      for (var r = 1; r < 64; r++) List<S3mCell>.filled(4, S3mCell.empty),
    ];
    return S3mModule(
      title: 'HDR',
      channelCount: 4,
      globalVolume: 40,
      masterVolume: 90, // 0x5A — not the 48 default
      ultraClick: 12, // not the 0 default
      flags: 0x0030, // not the 0 default
      createdWith: 0x1350, // Cwt-v — not the 0x1320 default
      sampleFormat: 2, // UNSIGNED PCM — not the 1 (signed) default
      channelSettings: channelSettings,
      order: const [0],
      samples: [
        S3mSample(
          name: 'buzz',
          pcm: _i8(const [0, 40, 80, 40, 0, -40, -80, -40]),
        ),
      ],
      patterns: [S3mPattern(rows)],
    );
  }

  test('S3M header survives songFromModuleBytes → moduleDocFromSong → docToS3m',
      () {
    final original = buildDistinctiveS3m();
    final bytes = writeS3m(original);

    // Import into the editable Advanced Tracker song, then export back.
    final song = songFromModuleBytes(bytes);
    expect(
      song.s3mHeader,
      isNotNull,
      reason: 'an S3M import must retain its native header',
    );

    final doc = moduleDocFromSong(song, targetFormat: ModuleFormat.s3m);
    final out = parseS3m(writeS3m(docToS3m(doc)));

    // Each field was LOST before this change; assert it is now preserved.
    expect(out.masterVolume, original.masterVolume, reason: 'master volume');
    expect(out.ultraClick, original.ultraClick, reason: 'ultra-click');
    expect(out.flags, original.flags, reason: 'flags');
    expect(out.createdWith, original.createdWith, reason: 'created-with (Cwt)');
    expect(out.sampleFormat, original.sampleFormat, reason: 'sample format');
    expect(
      out.channelSettings,
      channelSettings,
      reason: 'raw per-channel L/R/mute class bytes',
    );
    // The previously-fixed fields must still hold through the same path.
    expect(out.globalVolume, original.globalVolume, reason: 'global volume');
    expect(out.initialSpeed, original.initialSpeed, reason: 'initial speed');
  });

  test('synthetic song (no S3M source) exports sane header defaults + no crash',
      () {
    // A plain authored song with a real sample so the S3M export has content.
    final pcm = Float64List.fromList([
      for (var i = 0; i < 64; i++) (i % 16 < 8) ? 0.5 : -0.5,
    ]);
    final channel = TrackerChannel(
      id: 's',
      instrument: SampleInstrument('rec', pcm),
      rows: 8,
    );
    final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
    cells[0] = const TrackerCell(midi: 60);
    final song = TrackerSong.fromParts(
      channels: [channel],
      timing: const TrackerTiming(rows: 8),
      patterns: [
        TrackerPattern(name: '00', cells: [cells]),
      ],
      order: const [0],
    );

    // No S3M was ever imported, so there is no native header to carry.
    expect(song.s3mHeader, isNull);

    final doc = moduleDocFromSong(song, targetFormat: ModuleFormat.s3m);
    final out = parseS3m(writeS3m(docToS3m(doc)));

    // Defaults, and — the point of the test — no exception building the module.
    expect(out.masterVolume, 48);
    expect(out.ultraClick, 0);
    expect(out.flags, 0);
    expect(out.createdWith, 0x1320);
    expect(out.sampleFormat, 1);
    expect(out.channelCount, 1);
  });
}
