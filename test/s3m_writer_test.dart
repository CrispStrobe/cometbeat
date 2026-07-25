// test/s3m_writer_test.dart
//
// Scream Tracker 3 `.s3m` writer: writeS3m must be the inverse of parseS3m.
// Verified by round-trips (write → re-read preserves the module).
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/s3m_writer_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signed 8-bit samples as normalized float (÷128) — the S3mSample.pcm model.
/// ×128 on write inverts this, so the bytes round-trip exactly.
Float64List _i8(List<int> v) =>
    Float64List.fromList([for (final b in v) b / 128]);

void main() {
  test('output has the "SCRM" signature at 0x2C', () {
    final m0 = parseS3m(File('test/fixtures/golden.s3m').readAsBytesSync());
    final bytes = writeS3m(m0);
    expect(String.fromCharCodes(bytes.sublist(0x2C, 0x30)), 'SCRM');
  });

  group('golden.s3m survives parse → write → parse', () {
    late S3mModule m0, m1;
    setUpAll(() {
      m0 = parseS3m(File('test/fixtures/golden.s3m').readAsBytesSync());
      m1 = parseS3m(writeS3m(m0));
    });

    test('header + structure', () {
      expect(m1.title, m0.title);
      expect(m1.channelCount, m0.channelCount);
      expect(m1.globalVolume, m0.globalVolume);
      expect(m1.initialSpeed, m0.initialSpeed);
      expect(m1.initialTempo, m0.initialTempo);
      expect(m1.order, m0.order);
      expect(m1.samples.length, m0.samples.length);
      expect(m1.patterns.length, m0.patterns.length);
    });

    test('sample metadata + PCM', () {
      final s0 = m0.samples.first, s1 = m1.samples.first;
      expect(s1.name, s0.name);
      expect(s1.volume, s0.volume);
      expect(s1.c2spd, s0.c2spd);
      expect(s1.pcm, s0.pcm); // signed round-trip is exact
    });

    test('pattern cells', () {
      final p0 = m0.patterns.first, p1 = m1.patterns.first;
      expect(p1.rows[0][0].note, p0.rows[0][0].note); // 0x50 (C-5)
      expect(p1.rows[0][0].instrument, p0.rows[0][0].instrument); // 1
      expect(p1.rows[1][0].isEmpty, isTrue);
    });
  });

  group('hand-built module round-trips (multi-channel, loop, vol+command)', () {
    late S3mModule m1;
    setUpAll(() {
      final rows = <List<S3mCell>>[
        [
          const S3mCell(note: 0x50, instrument: 1, volume: 60), // ch0
          const S3mCell(note: 0x60, instrument: 2), // ch1
        ],
        [
          S3mCell.empty, // ch0
          // ch1
          const S3mCell(note: 0x64, instrument: 2, command: 1, info: 0x10),
        ],
        [S3mCell.empty, S3mCell.empty],
      ];
      final src = S3mModule(
        title: 'HANDS3M',
        channelCount: 2,
        globalVolume: 48,
        initialTempo: 130,
        order: const [0],
        samples: [
          S3mSample(
            name: 'lead',
            volume: 60,
            pcm: _i8([0, 40, -40, 80]),
          ),
          S3mSample(
            name: 'bass',
            volume: 50,
            c2spd: 4000,
            loop: true,
            loopEnd: 4,
            pcm: _i8([10, 20, 30, -10, -20]),
          ),
        ],
        patterns: [S3mPattern(rows)],
      );
      m1 = parseS3m(writeS3m(src));
    });

    test('header + channels', () {
      expect(m1.title, 'HANDS3M');
      expect(m1.channelCount, 2);
      expect(m1.initialTempo, 130);
      expect(m1.samples.length, 2);
    });

    test('pattern padded to 64 rows; cells preserved', () {
      final rows = m1.patterns.first.rows;
      expect(rows.length, 64);
      expect(rows[0][0].note, 0x50);
      expect(rows[0][0].instrument, 1);
      expect(rows[0][0].volume, 60);
      expect(rows[0][1].note, 0x60);
      expect(rows[0][1].instrument, 2);
      expect(rows[1][1].note, 0x64);
      expect(rows[1][1].command, 1);
      expect(rows[1][1].info, 0x10);
      expect(rows[1][0].isEmpty, isTrue);
      expect(rows[2][0].isEmpty, isTrue);
    });

    test('samples: metadata, loop, PCM', () {
      final lead = m1.samples[0], bass = m1.samples[1];
      expect(lead.name, 'lead');
      expect(lead.volume, 60);
      expect(lead.pcm, _i8([0, 40, -40, 80]));
      expect(bass.name, 'bass');
      expect(bass.c2spd, 4000);
      expect(bass.loop, isTrue);
      expect(bass.loopEnd, 4);
      expect(bass.pcm, _i8([10, 20, 30, -10, -20]));
    });
  });

  test('sparse physical channel settings preserve later pattern tracks', () {
    final rows = <List<S3mCell>>[
      [
        const S3mCell(note: 0x50, instrument: 1),
        const S3mCell(note: 0x60, instrument: 2),
      ],
    ];
    final source = S3mModule(
      title: 'SPARSE',
      channelCount: 2,
      channelSettings: const [0, 255, 2],
      order: const [0],
      samples: [
        S3mSample(pcm: _i8([20, -20])),
        S3mSample(pcm: _i8([40, -40])),
      ],
      patterns: [S3mPattern(rows)],
    );

    final parsed = parseS3m(writeS3m(source));
    expect(parsed.channelCount, 2);
    expect(parsed.patterns.first.rows.first[0].note, 0x50);
    expect(parsed.patterns.first.rows.first[1].note, 0x60);
  });

  test('preserves zero-length native patterns without shifting later patterns',
      () {
    final src = S3mModule(
      title: 'EMPTY-PATTERN',
      channelCount: 1,
      rawOrder: const [0, 1],
      order: const [0, 1],
      samples: const [],
      patterns: [
        S3mPattern(_emptyRows(1), rawData: Uint8List(0)),
        S3mPattern(_emptyRows(1), rawData: Uint8List.fromList([2, 0])),
      ],
    );

    final roundTrip = parseS3m(writeS3m(src));
    expect(roundTrip.patterns[0].rawData, isEmpty);
    expect(
      roundTrip.patterns[0].rows.expand((r) => r).every((c) => c.isEmpty),
      isTrue,
    );
    expect(roundTrip.patterns[1].rawData, [2, 0]);
  });
}

List<List<S3mCell>> _emptyRows(int channels) => List.generate(
      64,
      (_) => List<S3mCell>.filled(channels, S3mCell.empty),
      growable: false,
    );
