// PDF export — the Workshop's print-ready output (WORKSHOP_PARITY.md bucket G).
//
// crisp_notation has no PDF writer; we compose one from pieces it already has:
// `layoutPages` line-breaks + paginates, each `PositionedSystem.system.layout`
// is a `ScoreLayout` that `renderLayoutToPng` can rasterize, and the `pdf`
// package places those images on real A4 page boxes.
//
// These run under `tester.runAsync` because `renderLayoutToPng` goes through
// `dart:ui`'s real (non-faked) async rasterizer.

import 'package:comet_beat/features/workshop/export/score_pdf.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

const _quarter = NoteDuration(DurationBase.quarter);

/// A [bars]-bar 4/4 score of quarter notes.
Score _score(int bars) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        for (var b = 0; b < bars; b++)
          Measure([
            for (var i = 0; i < 4; i++)
              NoteElement.note(
                const Pitch(Step.c),
                _quarter,
                id: 'b${b}n$i',
              ),
          ]),
      ],
    );

void main() {
  testWidgets('exports a valid PDF', (tester) async {
    await tester.runAsync(() async {
      final bytes = await exportScoreToPdf(_score(4));
      expect(bytes, isNotEmpty);
      expect(
        String.fromCharCodes(bytes.take(4)),
        '%PDF',
        reason: 'a real PDF header',
      );
      expect(bytes.length, greaterThan(1000));
    });
  });

  testWidgets('a long score paginates onto several pages', (tester) async {
    await tester.runAsync(() async {
      // The same page box the exporter uses, so this pins *our* pagination
      // choice (spatium + margins), not just crisp_notation's packer.
      final metadata =
          MusicFonts.metadataOrNull(CrispNotationTheme.standard.musicFont) ??
              await MusicFonts.load(CrispNotationTheme.standard.musicFont);
      final settings = LayoutSettings(metadata: metadata);
      const spatium = 6.0;
      const metrics = PageMetrics(
        width: 595.28 / spatium, // A4 portrait, points → staff spaces
        height: 841.89 / spatium,
      );

      expect(
        layoutPages(_score(2), settings, metrics: metrics).pages,
        hasLength(1),
        reason: 'a short score is one page',
      );
      expect(
        layoutPages(_score(80), settings, metrics: metrics).pages.length,
        greaterThan(1),
        reason: 'a long score breaks onto more pages',
      );
    });
  });

  testWidgets('a longer score yields a bigger PDF', (tester) async {
    await tester.runAsync(() async {
      final short = await exportScoreToPdf(_score(2));
      final long = await exportScoreToPdf(_score(40));
      expect(long.length, greaterThan(short.length));
    });
  });
}
