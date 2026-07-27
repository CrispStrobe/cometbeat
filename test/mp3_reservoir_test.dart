// Mp3ReservoirStream — the MP3 bit-reservoir bookkeeping. Golden roundtrips
// exercise it transitively; this pins its contract directly: main_data_begin
// tracks the banked surplus and stays within resvMax, every frame's slot is
// emitted in full, and the continuous main-data stream is reconstructed
// byte-exact (a reservoir off-by-one corrupts an MP3 silently).
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_reservoir.dart';
import 'package:flutter_test/flutter_test.dart';

/// Strip the fixed [headerLen]-byte header from each [frameLen]-byte frame,
/// leaving the concatenated slot (main-data) bytes.
Uint8List _mainData(Uint8List out, int headerLen, int slotMd) {
  final frameLen = headerLen + slotMd;
  final b = BytesBuilder();
  for (var f = 0; f + frameLen <= out.length; f += frameLen) {
    b.add(out.sublist(f + headerLen, f + frameLen));
  }
  return b.toBytes();
}

void main() {
  final header = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]); // 4 bytes
  const slotMd = 100;

  Uint8List md(int n, int fill) => Uint8List.fromList(List.filled(n, fill));

  test('empty stream emits nothing and begins with a zero reservoir', () {
    final r = Mp3ReservoirStream(511);
    expect(r.mainDataBegin(), 0);
    final out = BytesBuilder();
    r.flush(out);
    expect(out.length, 0);
  });

  test('main_data_begin tracks banked surplus across easy/hard frames', () {
    final r = Mp3ReservoirStream(511);
    final out = BytesBuilder();

    // Frame A is easy (40 md bytes into a 100-byte slot) → banks 60.
    expect(r.mainDataBegin(), 0);
    r.addFrame(header, md(40, 0x11), slotMd, out);

    // Frame B is hard (160 md bytes) → draws on the 60-byte bank.
    expect(r.mainDataBegin(), 60);
    r.addFrame(header, md(160, 0x22), slotMd, out);

    // Bank spent: back to zero for frame C.
    expect(r.mainDataBegin(), 0);
    r.addFrame(header, md(100, 0x33), slotMd, out);

    r.flush(out);

    // Three frames, each header + full slot.
    final bytes = out.toBytes();
    expect(bytes.length, 3 * (header.length + slotMd));

    // Main data reconstructs byte-exact: 40×0x11, 160×0x22, 100×0x33.
    final data = _mainData(bytes, header.length, slotMd);
    expect(data.length, 300);
    expect(data.sublist(0, 40), everyElement(0x11));
    expect(data.sublist(40, 200), everyElement(0x22));
    expect(data.sublist(200, 300), everyElement(0x33));
  });

  test('reservoir is capped so main_data_begin never exceeds resvMax', () {
    const resvMax = 10;
    final r = Mp3ReservoirStream(resvMax);
    final out = BytesBuilder();

    // A slot far larger than the tiny reservoir with no main data to fill it:
    // the cap must pad rather than let the back-pointer overflow.
    r.addFrame(header, md(0, 0), slotMd, out);
    expect(r.mainDataBegin(), lessThanOrEqualTo(resvMax));

    r.addFrame(header, md(0, 0), slotMd, out);
    expect(r.mainDataBegin(), lessThanOrEqualTo(resvMax));

    r.flush(out);
    // Every slot still emitted in full despite the padding.
    expect(out.length, 2 * (header.length + slotMd));
  });

  test('total output always equals the sum of frame sizes', () {
    final r = Mp3ReservoirStream(511);
    final out = BytesBuilder();
    // A varied schedule of easy/hard/neutral granules.
    const mdLens = [10, 200, 100, 0, 150, 100, 50];
    var expected = 0;
    for (final len in mdLens) {
      expect(r.mainDataBegin(), inInclusiveRange(0, 511));
      r.addFrame(header, md(len, 0x5A), slotMd, out);
      expected += header.length + slotMd;
    }
    r.flush(out);
    expect(out.length, expected);
  });
}
