// SoundFont 2 reading: sample extraction + the GM preset→zone graph. Builds
// minimal valid RIFF/sfbk buffers in-test (no external asset) and checks that
// (1) samples extract with rate/root/loop, (2) a preset resolves into key-split
// zones, and (3) an Sf2Instrument plays the RIGHT sample per key.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// ── SF2 byte assembly helpers ────────────────────────────────────────────────
Uint8List _tag(String s) => Uint8List.fromList(s.codeUnits);
Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Uint8List _chunk(String id, Uint8List body) {
  final b = BytesBuilder()
    ..add(_tag(id))
    ..add(_u32(body.length))
    ..add(body);
  if (body.length.isOdd) b.addByte(0); // word alignment
  return b.toBytes();
}

Uint8List _concat(List<Uint8List> parts) {
  final b = BytesBuilder();
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

Uint8List _named(String name, int len, void Function(ByteData d) fill) {
  final r = Uint8List(len);
  final nm = name.codeUnits;
  for (var i = 0; i < nm.length && i < 20; i++) {
    r[i] = nm[i];
  }
  fill(ByteData.sublistView(r));
  return r;
}

Uint8List _shdr(
  String name,
  int start,
  int end,
  int ls,
  int le,
  int sr,
  int pitch,
) =>
    _named(name, 46, (d) {
      d.setUint32(20, start, Endian.little);
      d.setUint32(24, end, Endian.little);
      d.setUint32(28, ls, Endian.little);
      d.setUint32(32, le, Endian.little);
      d.setUint32(36, sr, Endian.little);
      d.setUint8(40, pitch);
    });

/// Wrap [samples] as an `sdta`/`smpl` LIST chunk.
Uint8List _sdta(List<Int16List> samples) => _chunk(
      'LIST',
      _concat([_tag('sdta'), _chunk('smpl', _smplBytes(samples))]),
    );

/// Wrap the given pdta sub-chunks as a `pdta` LIST chunk.
Uint8List _pdta(List<Uint8List> subChunks) =>
    _chunk('LIST', _concat([_tag('pdta'), ...subChunks]));

Uint8List _rec4(int a, int b) {
  final r = Uint8List(4);
  final d = ByteData.sublistView(r);
  d.setUint16(0, a, Endian.little);
  d.setUint16(2, b, Endian.little);
  return r;
}

Uint8List _smplBytes(List<Int16List> samples) {
  var total = 0;
  for (final s in samples) {
    total += s.length;
  }
  final out = Uint8List(total * 2);
  final d = ByteData.sublistView(out);
  var o = 0;
  for (final s in samples) {
    for (final v in s) {
      d.setInt16(o, v, Endian.little);
      o += 2;
    }
  }
  return out;
}

Int16List _sine(int n, double periods) {
  final s = Int16List(n);
  for (var i = 0; i < n; i++) {
    s[i] = (12000 * sin(2 * pi * periods * i / n)).round();
  }
  return s;
}

Uint8List _phdr(String name, int program, int bank) => _concat([
      _named(name, 38, (d) {
        d.setUint16(20, program, Endian.little);
        d.setUint16(22, bank, Endian.little);
        d.setUint16(24, 0, Endian.little); // presetBagNdx
      }),
      _named('EOP', 38, (d) => d.setUint16(24, 1, Endian.little)),
    ]);

Uint8List _inst(String name, int lastBagNdx) => _concat([
      _named(name, 22, (d) => d.setUint16(20, 0, Endian.little)),
      _named('EOI', 22, (d) => d.setUint16(20, lastBagNdx, Endian.little)),
    ]);

/// A one-sample, one-preset, single-zone (full-range) SF2.
Uint8List _oneSampleSf2({
  required Int16List pcm,
  required int sampleRate,
  required int rootKey,
  required int loopStart,
  required int loopEnd,
}) {
  final pdta = _pdta([
    _chunk('phdr', _phdr('GMTest', 0, 0)),
    _chunk('pbag', _concat([_rec4(0, 0), _rec4(1, 0)])),
    _chunk('pgen', _rec4(41, 0)), // instrument → inst 0
    _chunk('inst', _inst('GMInst', 1)),
    _chunk('ibag', _concat([_rec4(0, 0), _rec4(2, 0)])),
    _chunk('igen', _concat([_rec4(43, 0 | (127 << 8)), _rec4(53, 0)])),
    _chunk(
      'shdr',
      _concat([
        _shdr('Tone', 0, pcm.length, loopStart, loopEnd, sampleRate, rootKey),
        _shdr('EOS', 0, 0, 0, 0, 0, 0),
      ]),
    ),
  ]);
  return _chunk(
    'RIFF',
    _concat([
      _tag('sfbk'),
      _sdta([pcm]),
      pdta,
    ]),
  );
}

/// A two-sample, one-preset, TWO-zone SF2 (key split at 60): sample A (low) for
/// keys 0..59, sample B (high) for keys 60..127.
Uint8List _twoZoneSf2(Int16List a, Int16List b) {
  final pdta = _pdta([
    _chunk('phdr', _phdr('Split', 0, 0)),
    _chunk('pbag', _concat([_rec4(0, 0), _rec4(1, 0)])),
    _chunk('pgen', _rec4(41, 0)),
    _chunk('inst', _inst('SplitInst', 2)),
    // Two instrument zones → ibag [0,2), [2,4) into igen.
    _chunk('ibag', _concat([_rec4(0, 0), _rec4(2, 0), _rec4(4, 0)])),
    _chunk(
      'igen',
      _concat([
        _rec4(43, 0 | (59 << 8)), // zone A: keys 0..59
        _rec4(53, 0), // sample A
        _rec4(43, 60 | (127 << 8)), // zone B: keys 60..127
        _rec4(53, 1), // sample B
      ]),
    ),
    _chunk(
      'shdr',
      _concat([
        _shdr('Low', 0, a.length, 0, 0, 44100, 48),
        _shdr('High', a.length, a.length + b.length, 0, 0, 44100, 72),
        _shdr('EOS', 0, 0, 0, 0, 0, 0),
      ]),
    ),
  ]);
  return _chunk(
    'RIFF',
    _concat([
      _tag('sfbk'),
      _sdta([a, b]),
      pdta,
    ]),
  );
}

void main() {
  group('SF2 sample extraction', () {
    test('parses one sample with its rate, root key and loop', () {
      final pcm = _sine(880, 20);
      final sf = Sf2SoundFont.parse(
        _oneSampleSf2(
          pcm: pcm,
          sampleRate: 22050,
          rootKey: 60,
          loopStart: 44,
          loopEnd: 836,
        ),
      );
      expect(sf.samples.length, 1);
      final s = sf.samples.single;
      expect(s.name, 'Tone');
      expect(s.sampleRate, 22050);
      expect(s.originalPitch, 60);
      expect(s.pcm.length, 880);
      expect(s.loops, isTrue);
    });

    test('builds a looping, pitched SampleInstrument', () {
      final pcm = _sine(880, 20);
      final s = Sf2SoundFont.parse(
        _oneSampleSf2(
          pcm: pcm,
          sampleRate: 22050,
          rootKey: 60,
          loopStart: 44,
          loopEnd: 836,
        ),
      ).samples.single;
      final inst = sampleInstrumentFromSf2(s, id: 'sf2tone');
      expect(inst.baseMidi, 60);
      expect(inst.loops, isTrue);
      expect(soundCategoryOf(inst), SoundCategory.recorded);

      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
      ];
      final buf = inst.renderChannel(cells, timing);
      final probe = inst.sample.length + 20000;
      expect(
        buf.sublist(probe, probe + 500).any((v) => v.abs() > 1e-3),
        isTrue,
      );
    });

    test('rejects a non-SoundFont buffer', () {
      expect(
        () => Sf2SoundFont.parse(Uint8List.fromList('not an sf2!!'.codeUnits)),
        throwsFormatException,
      );
    });
  });

  group('SF2 GM preset → zone mapping', () {
    test('resolves a preset with its bank/program + a full-range zone', () {
      final sf = Sf2SoundFont.parse(
        _oneSampleSf2(
          pcm: _sine(880, 20),
          sampleRate: 44100,
          rootKey: 60,
          loopStart: 0,
          loopEnd: 0,
        ),
      );
      expect(sf.presets.length, 1);
      final p = sf.presets.single;
      expect(p.name, 'GMTest');
      expect(p.bank, 0);
      expect(p.program, 0);
      expect(p.zones.length, 1);
      expect(p.zones.single.keyLo, 0);
      expect(p.zones.single.keyHi, 127);
      expect(p.zones.single.sampleIndex, 0);
    });

    test('a key-split preset picks the RIGHT sample per note', () {
      // Sample A = low buzz (few periods), B = high buzz (many periods): a
      // note in each range should read a clearly different pitch.
      final a = _sine(2000, 8); // ~8 cycles over 2000 → low
      final b = _sine(2000, 64); // ~64 cycles over 2000 → high
      final sf = Sf2SoundFont.parse(_twoZoneSf2(a, b));
      expect(sf.presets.single.zones.length, 2);

      final inst = sf2InstrumentFromPreset(sf, sf.presets.single, id: 'split');
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      List<TrackerCell> one(int midi) => [
            TrackerCell(midi: midi),
            ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
          ];

      // Zone A plays at its root (48); zone B at its root (72). Count zero
      // crossings over the note's start — the high sample crosses far more.
      int crossings(Float64List buf) {
        var c = 0;
        for (var i = 1; i < 3000; i++) {
          if ((buf[i - 1] < 0) != (buf[i] < 0)) c++;
        }
        return c;
      }

      final low = inst.renderChannel(one(48), timing); // → zone A (root 48)
      final high = inst.renderChannel(one(72), timing); // → zone B (root 72)
      expect(low.any((v) => v != 0), isTrue);
      expect(high.any((v) => v != 0), isTrue);
      // Different zones → clearly different pitch content.
      expect(crossings(high), greaterThan(crossings(low) * 2));
    });

    test('an Sf2Instrument is a renderable tracker instrument', () {
      final sf =
          Sf2SoundFont.parse(_twoZoneSf2(_sine(1000, 8), _sine(1000, 32)));
      final inst = sf2InstrumentFromPreset(sf, sf.presets.single, id: 'x');
      expect(inst, isA<TrackerInstrument>());
      expect(inst.id, 'x');
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 55),
        ...List<TrackerCell>.filled(3, TrackerCell.empty),
      ];
      expect(inst.renderChannel(cells, timing).any((v) => v != 0), isTrue);
    });
  });
}
