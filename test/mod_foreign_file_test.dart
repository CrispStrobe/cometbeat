// A module our writer did NOT produce.
//
// PLAN.md §6, fixture independence — the half that was parked as "needs an
// external authoring tool". It does not: a MOD is a documented byte layout, so
// the file can be assembled BY HAND from the spec, right here, and the reader
// checked against the FORMAT rather than against its own writer.
//
// Why that matters. Every file under `test/fixtures/` is our writer's output,
// so the reader is only ever asked to agree with something it agrees with by
// construction. That is the exact shape of the five both-directions bugs this
// audit found — reader and writer sharing a misunderstanding, round trip
// perfect, file wrong. A hand-built module has no shared misunderstanding to
// share: every byte below is placed because the format says so, and if our
// reader disagrees, the reader is wrong.
//
// The layout, from the ProTracker spec:
//
//     offset  size  meaning
//     0       20    song title, NUL-padded
//     20      31 x 30  sample headers:
//                     22  name
//                      2  length in WORDS (big-endian) — i.e. bytes / 2
//                      1  finetune, low nibble, signed −8..+7
//                      1  volume 0..64
//                      2  repeat point in WORDS
//                      2  repeat length in WORDS
//     950     1     song length in positions (1..128)
//     951     1     restart position (ProTracker writes 127)
//     952     128   order table: position → pattern number
//     1080    4     signature, "M.K." for 4 channels / 64 rows
//     1084    ...   patterns, 64 rows x channels x 4 bytes
//     ...           sample data, unsigned... no: SIGNED 8-bit PCM
//
// And one cell, the part that actually encodes the music:
//
//     byte 0   sample bits 7-4  |  period bits 11-8
//     byte 1   period bits 7-0
//     byte 2   sample bits 3-0  |  effect
//     byte 3   effect parameter
//
// ⚠️ The sample number is SPLIT across bytes 0 and 2, four bits in each. That
// split is the single most error-prone thing in the format and the reason this
// test asserts sample numbers above 15 as well as below.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

/// One pattern cell, packed the way the FORMAT says — not the way we write it.
List<int> _cell({
  int sample = 0,
  int period = 0,
  int effect = 0,
  int param = 0,
}) {
  return [
    (sample & 0xF0) | ((period >> 8) & 0x0F),
    period & 0xFF,
    ((sample & 0x0F) << 4) | (effect & 0x0F),
    param & 0xFF,
  ];
}

/// A 30-byte sample header.
List<int> _sampleHeader({
  String name = '',
  int lengthBytes = 0,
  int finetune = 0,
  int volume = 64,
  int repeatPointBytes = 0,
  int repeatLengthBytes = 2,
}) {
  final out = <int>[];
  final n = name.codeUnits.take(22).toList();
  out.addAll([...n, ...List<int>.filled(22 - n.length, 0)]);
  void word(int bytes) {
    final w = bytes ~/ 2;
    out
      ..add((w >> 8) & 0xFF)
      ..add(w & 0xFF);
  }

  word(lengthBytes);
  out.add(finetune & 0x0F);
  out.add(volume.clamp(0, 64));
  word(repeatPointBytes);
  word(repeatLengthBytes);
  return out;
}

/// The module: two samples, one pattern, four channels — built byte by byte.
///
/// Row 0 sounds sample 1 at C-2 (period 428). Row 1 sounds **sample 17** at
/// A-2 (period 254) with `C20` set-volume, because a sample number above 15
/// exercises the split-nibble encoding that a naive writer gets wrong. Row 2 is
/// an arpeggio `047` on the ringing note, and row 3 a pattern break `D00`.
Uint8List _handBuiltMod() {
  final bytes = <int>[];

  // 0: title, 20 bytes NUL-padded.
  const title = 'handbuilt';
  bytes.addAll(title.codeUnits);
  bytes.addAll(List<int>.filled(20 - title.length, 0));

  // 20: 31 sample headers. Samples 1 and 17 carry PCM; the rest are empty.
  const pcmBytes = 64;
  for (var i = 1; i <= 31; i++) {
    if (i == 1) {
      bytes.addAll(
        _sampleHeader(
          name: 'saw',
          lengthBytes: pcmBytes,
          repeatLengthBytes: pcmBytes,
        ),
      );
    } else if (i == 17) {
      bytes.addAll(
        _sampleHeader(
          name: 'square',
          lengthBytes: pcmBytes,
          finetune: 1,
          volume: 32,
          repeatLengthBytes: pcmBytes,
        ),
      );
    } else {
      bytes.addAll(_sampleHeader());
    }
  }

  // 950: song length, 951: restart, 952: order table.
  bytes.add(1); // one position
  bytes.add(127); // ProTracker's restart value
  bytes.addAll([0, ...List<int>.filled(127, 0)]);

  // 1080: signature.
  bytes.addAll('M.K.'.codeUnits);

  // 1084: one pattern, 64 rows x 4 channels x 4 bytes.
  for (var row = 0; row < 64; row++) {
    for (var ch = 0; ch < 4; ch++) {
      if (ch != 0) {
        bytes.addAll(_cell());
        continue;
      }
      bytes.addAll(
        switch (row) {
          0 => _cell(sample: 1, period: 428), // C-2
          1 => _cell(sample: 17, period: 254, effect: 0xC, param: 0x20),
          // Arpeggio is effect ZERO with a non-zero parameter — the one command
          // whose presence is carried entirely by its argument.
          2 => _cell(param: 0x47),
          3 => _cell(effect: 0xD), // pattern break, D00
          _ => _cell(),
        },
      );
    }
  }

  // Sample data: signed 8-bit. A ramp, so a byte-order slip is visible.
  for (final _ in [1, 17]) {
    for (var i = 0; i < pcmBytes; i++) {
      bytes.add((-128 + (i * 256 ~/ pcmBytes)) & 0xFF);
    }
  }

  return Uint8List.fromList(bytes);
}

void main() {
  test('our reader reads a module it did not write', () {
    final mod = parseMod(_handBuiltMod());

    expect(mod.title, 'handbuilt');
    expect(mod.channelCount, 4, reason: '"M.K." means four channels');
    expect(mod.signature, 'M.K.');
    expect(mod.samples, hasLength(31), reason: 'a MOD always has 31 slots');
    expect(mod.order.first, 0);
    expect(mod.patterns, hasLength(1));
  });

  test('the split-nibble sample number survives — including above 15', () {
    // The sample number is four bits in byte 0 and four in byte 2. A reader
    // that takes only the low nibble reports 1 for sample 17, and every module
    // using more than fifteen samples plays the wrong instrument from row one.
    final rows = parseMod(_handBuiltMod()).patterns.first.rows;
    expect(rows[0].first.sample, 1);
    expect(
      rows[1].first.sample,
      17,
      reason: 'sample 17 needs the HIGH nibble from byte 0; reading only the '
          'low nibble gives 1 and sounds the wrong instrument',
    );
  });

  test('periods and effects are read as the format encodes them', () {
    final rows = parseMod(_handBuiltMod()).patterns.first.rows;
    expect(rows[0].first.period, 428, reason: 'C-2');
    expect(rows[1].first.period, 254, reason: 'A-2');
    expect(rows[1].first.effect, 0xC);
    expect(rows[1].first.effectParam, 0x20);
    expect(rows[2].first.effect, 0x0);
    expect(
      rows[2].first.effectParam,
      0x47,
      reason: 'arpeggio is effect 0 with a parameter; a reader that treats '
          'effect 0 as "nothing" drops it entirely',
    );
    expect(rows[3].first.effect, 0xD);
  });

  test('sample headers are read in WORDS, not bytes', () {
    // Length, repeat point and repeat length are all stored halved. A reader
    // that forgets doubles every sample and loops past the end — the same shape
    // as XM's 16-bit loop-unit bug this audit already found in our own writer.
    final s1 = parseMod(_handBuiltMod()).samples[0];
    expect(s1.name, 'saw');
    expect(s1.volume, 64);
    expect(s1.pcm, hasLength(64), reason: '32 words = 64 bytes');
    expect(s1.repeatLength, 64);

    final s17 = parseMod(_handBuiltMod()).samples[16];
    expect(s17.name, 'square');
    expect(s17.volume, 32);
    expect(s17.finetune, 1);
  });

  test('sample PCM is SIGNED 8-bit', () {
    // Read as unsigned, a ramp from −128 becomes a ramp from 0 and the whole
    // sample is offset by a DC step — audible as a click and invisible to any
    // structural check.
    final pcm = parseMod(_handBuiltMod()).samples[0].pcm;
    expect(pcm.first, lessThan(0), reason: 'the ramp starts at −128');
    expect(pcm.last, greaterThan(0), reason: 'and ends positive');
  });

  test('it survives the whole import path, not just the parser', () {
    // The parser is one layer; the neutral model is what the app plays. A note
    // read correctly and then mapped wrongly is still a wrong note.
    final doc = docFromMod(parseMod(_handBuiltMod()));
    final row0 = doc.patterns.first.rows[0].first;
    final row1 = doc.patterns.first.rows[1].first;
    expect(row0.note, 60, reason: 'period 428 is our MIDI 60');
    expect(row0.instrument, 1);
    expect(
      row1.instrument,
      17,
      reason: 'the split-nibble sample number has to survive into the model, '
          'not only into the parsed cell',
    );
  });
}
