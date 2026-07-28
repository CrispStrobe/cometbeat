// XM's effect column is numbered by its own letters, and we had two of them
// swapped: tremor was written as KEY OFF and key off read back as tremor.
//
// PLAN.md §6. XM effect bytes ARE the neutral numbering from 10h up — that is
// the whole reason effects above MOD's range pass straight through:
//
//     10h G global volume · 11h H global volume slide · 19h P pan slide
//     1Bh R multi retrigger · 1Dh T tremor
//
// 14h was the single exception. libxmp states both plainly (`src/effects.h`):
//
//     #define FX_KEYOFF  0x14
//     #define FX_TREMOR  0x1d
//
// We mapped tremor↔14h in BOTH directions, so `parseXm(writeXm(x)) == x` held
// perfectly while the file said key-off to every other player. openmpt123
// rendered our tremor fixture as one unbroken tone — a key off on an instrument
// with no envelope does nothing at all — and the spectral gate read 0.844 with
// no way to say why.
//
// This is the FOURTH bug of exactly this shape in the audit (IT's hex break
// row, XM's 16-bit loop units, the fine-porta reverse map). They are invisible
// to round-trip tests by construction: a reader and writer that share a
// misunderstanding agree with each other perfectly. Every assertion below is
// therefore made at the FORMAT level — the byte on disk, which is the only
// thing a foreign player sees.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/xm_module.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kFxSetSpeedFull, kFxTremor;
import 'package:flutter_test/flutter_test.dart';

/// libxmp `src/effects.h` — XM's own numbering, which it passes through.
const int kXmKeyOff = 0x14;
const int kXmTremor = 0x1D;
const int kXmSetSpeed = 0x0F;

Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * i / n);
  }
  return out;
}

/// A one-channel doc: a note, then [effect]/[param] on row 1.
ModuleDoc _withEffect(int effect, int param) {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'xm numbering',
    channelCount: 4,
    order: const [0],
    samples: [DocSample(name: 'sine', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < 8; r++)
            [
              if (r == 0)
                const DocCell(note: 60, instrument: 1, volume: 64)
              else if (r == 1)
                DocCell(effect: effect, effectParam: param)
              else
                DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        4,
      ),
    ],
  );
}

/// The (effect, param) bytes our writer actually put on disk at row 1 — read
/// back through the FORMAT parser, before any of our own remapping runs.
({int effect, int param}) _onDisk(int effect, int param) {
  final xm = parseXm(convertToXm(_withEffect(effect, param)));
  final cell = xm.patterns.first.rows[1].first;
  return (effect: cell.effect, param: cell.effectParam);
}

void main() {
  test('tremor writes as T (1Dh), not K (14h)', () {
    final d = _onDisk(kFxTremor, 0x32);
    expect(
      d.effect,
      kXmTremor,
      reason: 'writing tremor as 14h makes the file say KEY OFF — openmpt '
          'played our tremor fixture as one unbroken tone',
    );
    expect(d.param, 0x32, reason: 'the parameter must survive untouched');
  });

  test('a K (14h) cell reads back as a key-off, not as tremor', () {
    // Built as a real XM byte stream so the reader sees 14h the way a foreign
    // file would present it, rather than through our own writer.
    final source = parseXm(convertToXm(_withEffect(kFxTremor, 0x32)));
    final row = source.patterns.first.rows[1];
    final patched = XmModule(
      name: source.name,
      trackerName: source.trackerName,
      version: source.version,
      rawHeader: source.rawHeader,
      channelCount: source.channelCount,
      defaultTempo: source.defaultTempo,
      defaultBpm: source.defaultBpm,
      linearFrequency: source.linearFrequency,
      restart: source.restart,
      order: source.order,
      instruments: source.instruments,
      patterns: [
        XmPattern(
          [
            for (var r = 0; r < source.patterns.first.rows.length; r++)
              if (r == 1)
                [
                  XmCell(
                    note: row.first.note,
                    instrument: row.first.instrument,
                    volume: row.first.volume,
                    effect: kXmKeyOff,
                  ),
                  ...row.skip(1),
                ]
              else
                source.patterns.first.rows[r],
          ],
          rawHeader: source.patterns.first.rawHeader,
        ),
      ],
    );

    final cell = docFromXm(patched).patterns.first.rows[1].first;
    expect(
      cell.noteOff,
      isTrue,
      reason: '14h is key off, and key off already has a home in the neutral '
          'model — the note column carries it as note 97',
    );
    expect(
      cell.effect,
      isNot(kFxTremor),
      reason: 'reading a key off AS tremor is the other half of the swap',
    );
  });

  test('full-range speed does not fall into the key-off slot', () {
    // kFxSetSpeedFull is 14h in OUR numbering, which is XM's key off. It cannot
    // pass through, and it has no exact XM encoding either: XM's F splits the
    // range at 20h, so an S3M/IT `Axx` above 1Fh must be clamped, the same
    // squeeze MOD's Fxx needs. Passing it through turned every imported
    // full-range speed into a key-off on export.
    final fast = _onDisk(kFxSetSpeedFull, 0x08);
    expect(fast.effect, kXmSetSpeed, reason: 'speed must write as F');
    expect(fast.param, 0x08);

    final tooFast = _onDisk(kFxSetSpeedFull, 0x99);
    expect(tooFast.effect, kXmSetSpeed);
    expect(
      tooFast.param,
      lessThan(0x20),
      reason: 'above 1Fh XM reads F as a BPM, so a speed must be clamped '
          'rather than silently becoming a tempo change',
    );
  });

  test('the round trip still recovers tremor', () {
    // The assertion that passed throughout while the file was wrong. Kept
    // because it must still hold, not because it proves anything on its own.
    final back = docFromXm(parseXm(convertToXm(_withEffect(kFxTremor, 0x32))));
    final cell = back.patterns.first.rows[1].first;
    expect(cell.effect, kFxTremor);
    expect(cell.effectParam, 0x32);
    expect(cell.noteOff, isFalse);
  });
}
