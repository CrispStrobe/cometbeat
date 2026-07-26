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

  group('multi-part PDF engraves every part', () {
    Score bass(int bars) => Score(
          clef: Clef.bass,
          timeSignature: TimeSignature.fourFour,
          measures: [
            for (var b = 0; b < bars; b++)
              Measure([
                for (var i = 0; i < 4; i++)
                  NoteElement.note(
                    const Pitch(Step.c, octave: 3),
                    _quarter,
                    id: 'lb${b}n$i',
                  ),
              ]),
          ],
        );

    testWidgets('a 3-part score exports a valid, bigger PDF than 1 part',
        (tester) async {
      await tester.runAsync(() async {
        MusicFonts.metadataOrNull(CrispNotationTheme.standard.musicFont) ??
            await MusicFonts.load(CrispNotationTheme.standard.musicFont);
        final trio = MultiPartScore([_score(2), bass(2), _score(2)]);
        final bytes = await exportMultiPartToPdf(trio);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        // Three staves per system → more ink than a single part.
        final onePart = await exportMultiPartToPdf(MultiPartScore([_score(2)]));
        expect(
          bytes.length,
          greaterThan(onePart.length),
          reason: 'the extra parts add ink',
        );
      });
    });

    testWidgets('a single-part MultiPartScore matches the single path',
        (tester) async {
      await tester.runAsync(() async {
        final mp = await exportMultiPartToPdf(MultiPartScore([_score(4)]));
        final single = await exportScoreToPdf(_score(4));
        expect(
          mp.length,
          single.length,
          reason: 'one part routes through exportScoreToPdf',
        );
      });
    });
  });

  group('title block (metadata header)', () {
    testWidgets('composer/lyricist add ink and stay a valid PDF',
        (tester) async {
      await tester.runAsync(() async {
        final plain = await exportScoreToPdf(_score(4), title: 'Song');
        final full = await exportScoreToPdf(
          _score(4),
          title: 'Song',
          subtitle: 'A little study',
          composer: 'J. S. Bach',
          lyricist: 'Anonymous',
        );
        expect(String.fromCharCodes(full.take(4)), '%PDF');
        expect(full.length, greaterThan(1000));
        expect(
          full,
          isNot(equals(plain)),
          reason: 'the extra title-block lines change the bytes',
        );
      });
    });

    testWidgets('multi-part export accepts and renders metadata',
        (tester) async {
      await tester.runAsync(() async {
        final mp = await exportMultiPartToPdf(
          MultiPartScore([_score(4), _score(4)]),
          title: 'Duet',
          composer: 'Anonymous',
          lyricist: 'Traditional',
        );
        expect(String.fromCharCodes(mp.take(4)), '%PDF');
        expect(mp.length, greaterThan(1000));
      });
    });
  });

  testWidgets('a fingered part prints its fingerings', (tester) async {
    await tester.runAsync(() async {
      final score = _score(4);
      final ids = <String>[
        for (final measure in score.measures)
          for (final element in measure.elements)
            if (element is NoteElement && element.id != null) element.id!,
      ];
      final bare = await exportScoreToPdf(score);
      final fingered = await exportScoreToPdf(
        score,
        extraFingerings: {
          for (final id in ids) id: const [3],
        },
      );
      // The pages are rasterised, so "did the marks print" is a question about
      // ink: a dropped mark anywhere in layoutPages → layoutSystems →
      // engine.layout would produce a byte-identical PDF and an unfingered part.
      expect(fingered, isNot(bare));
      expect(fingered.length, greaterThan(bare.length));
    });
  });

  testWidgets('a mark for a note that is not there prints nothing extra',
      (tester) async {
    await tester.runAsync(() async {
      final score = _score(2);
      final a = await exportScoreToPdf(score);
      final b = await exportScoreToPdf(
        score,
        extraFingerings: const {
          'no-such-note': [1],
        },
      );
      expect(b.length, a.length);
    });
  });
}
