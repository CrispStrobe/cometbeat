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

/// An `sdta`/`smpl` chunk holding RAW bytes (for a `.sf3` fixture where `smpl`
/// is concatenated OGG-Vorbis streams, not PCM).
Uint8List _sdtaRaw(Uint8List smpl) => _chunk(
      'LIST',
      _concat([_tag('sdta'), _chunk('smpl', smpl)]),
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
  int attenuationCb = 0,
  int coarseTune = 0,
  int fineTune = 0,
  int sampleModes = 0,
}) {
  // Instrument-zone generators: keyRange, optional atten/tune/loop-mode, then
  // sampleID (terminal). Signed tune values are two's-complement bits.
  final gens = <Uint8List>[_rec4(43, 0 | (127 << 8))];
  if (attenuationCb != 0) gens.add(_rec4(48, attenuationCb));
  if (coarseTune != 0) gens.add(_rec4(51, coarseTune & 0xFFFF));
  if (fineTune != 0) gens.add(_rec4(52, fineTune & 0xFFFF));
  if (sampleModes != 0) gens.add(_rec4(54, sampleModes)); // gen 54: loop mode
  gens.add(_rec4(53, 0)); // sampleID 0
  final pdta = _pdta([
    _chunk('phdr', _phdr('GMTest', 0, 0)),
    _chunk('pbag', _concat([_rec4(0, 0), _rec4(1, 0)])),
    _chunk('pgen', _rec4(41, 0)), // instrument → inst 0
    _chunk('inst', _inst('GMInst', 1)),
    _chunk('ibag', _concat([_rec4(0, 0), _rec4(gens.length, 0)])),
    _chunk('igen', _concat(gens)),
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

/// A compressed `.sf3`-style fixture: one preset, one sample whose `smpl` data
/// is the raw [oggStream] bytes (must start with `OggS`). shdr start/end are the
/// BYTE range `[0, oggStream.length)`; loop points are DECODED-frame positions.
Uint8List compressedSf3({
  required Uint8List oggStream,
  int rootKey = 60,
  int loopStart = 0,
  int loopEnd = 0,
}) {
  final pdta = _pdta([
    _chunk('phdr', _phdr('SF3Test', 0, 0)),
    _chunk('pbag', _concat([_rec4(0, 0), _rec4(1, 0)])),
    _chunk('pgen', _rec4(41, 0)),
    _chunk('inst', _inst('SF3Inst', 1)),
    _chunk('ibag', _concat([_rec4(0, 0), _rec4(2, 0)])),
    _chunk('igen', _concat([_rec4(43, 0 | (127 << 8)), _rec4(53, 0)])),
    _chunk(
      'shdr',
      _concat([
        // start=0, end=oggStream.length (BYTE offsets into smpl).
        _shdr(
          'OggTone',
          0,
          oggStream.length,
          loopStart,
          loopEnd,
          44100,
          rootKey,
        ),
        _shdr('EOS', 0, 0, 0, 0, 0, 0),
      ]),
    ),
  ]);
  return _chunk('RIFF', _concat([_tag('sfbk'), _sdtaRaw(oggStream), pdta]));
}

/// A two-sample, one-preset SF2 split by VELOCITY (not key): both zones cover
/// the whole keyboard, but sample A ([soft]) plays for MIDI velocity 0..63 and
/// sample B ([loud]) for 64..127 — a velocity layer (SF2 gen 44).
Uint8List velSplitSf2(Int16List soft, Int16List loud) {
  final pdta = _pdta([
    _chunk('phdr', _phdr('VelSplit', 0, 0)),
    _chunk('pbag', _concat([_rec4(0, 0), _rec4(1, 0)])),
    _chunk('pgen', _rec4(41, 0)),
    _chunk('inst', _inst('VelInst', 2)),
    _chunk('ibag', _concat([_rec4(0, 0), _rec4(3, 0), _rec4(6, 0)])),
    _chunk(
      'igen',
      _concat([
        _rec4(43, 0 | (127 << 8)), // zone A: all keys
        _rec4(44, 0 | (63 << 8)), //  …velocity 0..63 (soft)
        _rec4(53, 0), // sample A
        _rec4(43, 0 | (127 << 8)), // zone B: all keys
        _rec4(44, 64 | (127 << 8)), // …velocity 64..127 (loud)
        _rec4(53, 1), // sample B
      ]),
    ),
    _chunk(
      'shdr',
      _concat([
        _shdr('Soft', 0, soft.length, 0, 0, 44100, 60),
        _shdr('Loud', soft.length, soft.length + loud.length, 0, 0, 44100, 60),
        _shdr('EOS', 0, 0, 0, 0, 0, 0),
      ]),
    ),
  ]);
  return _chunk(
    'RIFF',
    _concat([
      _tag('sfbk'),
      _sdta([soft, loud]),
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
