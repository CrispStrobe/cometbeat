// Envelope round-trip: a DocSample's volume/pan envelope survives
// doc → convertToXm → parseAnyModule → doc. XM carries envelopes on the
// instrument; MOD/S3M have none, so the envelope drops there (documented).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertToMod, convertToXm, parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

ModuleDoc _docWith(DocEnvelope vol, DocEnvelope pan) {
  final pcm = Float64List.fromList([
    for (var i = 0; i < 64; i++) i % 8 < 4 ? 0.5 : -0.5,
  ]);
  return ModuleDoc(
    sourceFormat: ModuleFormat.xm,
    channelCount: 1,
    order: [0],
    patterns: [
      const DocPattern(
        [
          [DocCell(note: 60, instrument: 1)],
        ],
        1,
      ),
    ],
    samples: [DocSample(pcm: pcm, volumeEnvelope: vol, panEnvelope: pan)],
  );
}

DocSample _firstUsed(ModuleDoc doc) =>
    doc.samples.firstWhere((s) => !s.isEmpty);

void main() {
  test('an XM volume + pan envelope round-trips through the doc', () {
    const vol = DocEnvelope(
      points: [(0, 64), (20, 32), (50, 0)],
      sustain: 1,
      loopStart: 0,
      loopEnd: 2,
      enabled: true,
    );
    const pan = DocEnvelope(
      points: [(0, 32), (30, 48)],
      enabled: true,
    );

    final back = parseAnyModule(convertToXm(_docWith(vol, pan)));
    final s = _firstUsed(back);

    expect(s.volumeEnvelope.enabled, isTrue);
    expect(s.volumeEnvelope.points, [(0, 64), (20, 32), (50, 0)]);
    expect(s.volumeEnvelope.sustain, 1);
    expect(s.volumeEnvelope.loopStart, 0);
    expect(s.volumeEnvelope.loopEnd, 2);

    expect(s.panEnvelope.enabled, isTrue);
    expect(s.panEnvelope.points, [(0, 32), (30, 48)]);
    // No sustain/loop flagged → indices stay null.
    expect(s.panEnvelope.sustain, isNull);
    expect(s.panEnvelope.loopStart, isNull);
  });

  test('a sample with no envelope round-trips as empty (not enabled)', () {
    final back = parseAnyModule(
      convertToXm(_docWith(const DocEnvelope(), const DocEnvelope())),
    );
    final s = _firstUsed(back);
    expect(s.volumeEnvelope.enabled, isFalse);
    expect(s.volumeEnvelope.isEmpty, isTrue);
    expect(s.panEnvelope.isEmpty, isTrue);
  });

  test('an XM sample default pan round-trips through the doc', () {
    final pcm = Float64List.fromList([
      for (var i = 0; i < 64; i++) i % 8 < 4 ? 0.5 : -0.5,
    ]);
    final doc = ModuleDoc(
      sourceFormat: ModuleFormat.xm,
      channelCount: 1,
      order: [0],
      patterns: [
        const DocPattern(
          [
            [DocCell(note: 60, instrument: 1)],
          ],
          1,
        ),
      ],
      samples: [DocSample(pcm: pcm, pan: 200)], // right of centre
    );
    // Panning is a raw header byte, so it survives exactly.
    expect(_firstUsed(parseAnyModule(convertToXm(doc))).pan, 200);
  });

  test('MOD has no envelopes — the envelope drops (documented limitation)', () {
    const vol = DocEnvelope(points: [(0, 64), (40, 0)], enabled: true);
    final back = parseAnyModule(
      convertToMod(_docWith(vol, const DocEnvelope())),
    );
    // The note/sample still round-trip; the envelope simply isn't there.
    expect(_firstUsed(back).volumeEnvelope.isEmpty, isTrue);
  });
}
