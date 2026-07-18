// Shared SF2 test fixtures — assemble minimal valid RIFF/sfbk buffers (samples +
// the phdr/pbag/pgen/inst/ibag/igen/shdr graph) so the parser + downloader tests
// can synthesize a soundfont without any external asset.

import 'dart:math';
import 'dart:typed_data';

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
  int pitch, {
  int correction = 0,
}) =>
    _named(name, 46, (d) {
      d.setUint32(20, start, Endian.little);
      d.setUint32(24, end, Endian.little);
      d.setUint32(28, ls, Endian.little);
      d.setUint32(32, le, Endian.little);
      d.setUint32(36, sr, Endian.little);
      d.setUint8(40, pitch);
      d.setInt8(41, correction); // chPitchCorrection (signed cents)
    });

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

Uint8List _sdta(List<Int16List> samples) => _chunk(
      'LIST',
      _concat([_tag('sdta'), _chunk('smpl', _smplBytes(samples))]),
    );

Uint8List _pdta(List<Uint8List> subChunks) =>
    _chunk('LIST', _concat([_tag('pdta'), ...subChunks]));

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

/// A rising sine of [n] samples over [periods] cycles, as signed 16-bit PCM.
Int16List sineI16(int n, double periods) {
  final s = Int16List(n);
  for (var i = 0; i < n; i++) {
    s[i] = (12000 * sin(2 * pi * periods * i / n)).round();
  }
  return s;
}

/// A one-sample, one-preset, single-zone (full-range) SF2.
Uint8List oneSampleSf2({
  required Int16List pcm,
  required int sampleRate,
  required int rootKey,
  required int loopStart,
  required int loopEnd,
  int pitchCorrection = 0,
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
        _shdr(
          'Tone',
          0,
          pcm.length,
          loopStart,
          loopEnd,
          sampleRate,
          rootKey,
          correction: pitchCorrection,
        ),
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
Uint8List twoZoneSf2(Int16List a, Int16List b) {
  final pdta = _pdta([
    _chunk('phdr', _phdr('Split', 0, 0)),
    _chunk('pbag', _concat([_rec4(0, 0), _rec4(1, 0)])),
    _chunk('pgen', _rec4(41, 0)),
    _chunk('inst', _inst('SplitInst', 2)),
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
