// lib/features/workshop/export/score_pdf.dart
//
// Score → print-ready PDF (WORKSHOP_PARITY.md bucket G's last open item).
//
// crisp_notation has no PDF writer, but it doesn't need one: pagination and
// rendering already exist, and they compose.
//
//   layoutPages(score, settings, metrics:)  → PagedLayout        (core)
//     .pages[i].systems[j] is a PositionedSystem                 (core)
//       .system.layout IS a ScoreLayout, .top is its y offset    (core)
//   renderLayoutToPng(ScoreLayout)          → PNG bytes          (flutter pkg)
//
// so we line-break + paginate with the engine, raster each *system* on its own,
// and place the images on real page boxes with the `pdf` package. Every
// coordinate crisp_notation hands back is in **staff spaces**; one [spatium]
// (points per staff space) converts the whole thing to PDF points.
//
// Why raster and not vector: the SVG exporter emits `<text>` against an
// `@font-face` data-URI, which the pdf package's SVG parser doesn't resolve, and
// Bravura is CFF/OTF — the pdf package's font embedder is TrueType-only. Both
// vector routes lose the glyphs, so we rasterize each system through the same
// painter the app draws with (correct glyphs, guaranteed) at [rasterScale]× for
// print resolution.

import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A4 at 72 dpi, in points — the default page box.
const _a4 = PdfPageFormat.a4;

/// Points per staff space. 6pt ≈ 2.1mm — a normal engraving size, and it puts
/// ~99 staff spaces across an A4 width.
const _defaultSpatium = 6.0;

/// Renders [score] to a paginated, print-ready PDF.
///
/// Systems are line-broken to the page's content width and packed into pages by
/// crisp_notation's [layoutPages]; each system is rasterized at [rasterScale]×
/// [spatium] (so ~216 dpi by default) and placed at its exact staff-space
/// position. [spatium] sets the engraving size: larger = fewer bars per line.
///
/// Must run inside a Flutter binding with the engraving font registered (the app
/// always is; a test needs `MusicFonts.load` first) — [renderLayoutToPng]
/// rasterizes through `dart:ui`.
Future<Uint8List> exportScoreToPdf(
  Score score, {
  String? title,
  CrispNotationTheme theme = CrispNotationTheme.standard,
  PdfPageFormat pageFormat = _a4,
  double spatium = _defaultSpatium,
  double rasterScale = 3,
  double margin = 8,
}) async {
  final metadata = MusicFonts.metadataOrNull(theme.musicFont) ??
      await MusicFonts.load(theme.musicFont);
  final settings = LayoutSettings(metadata: metadata);

  // The page box, expressed in staff spaces for the engine.
  final titleText = title?.trim() ?? '';
  final titleGap = titleText.isEmpty ? 0.0 : 18.0;
  final metrics = PageMetrics(
    width: pageFormat.width / spatium,
    height: pageFormat.height / spatium,
    marginTop: margin + titleGap,
    marginBottom: margin,
    marginLeft: margin,
    marginRight: margin,
  );
  final paged = layoutPages(score, settings, metrics: metrics);

  // Rasterize every system up front: the pdf builder callback is sync.
  final pages = <List<(PositionedSystem, Uint8List)>>[];
  for (final page in paged.pages) {
    final rendered = <(PositionedSystem, Uint8List)>[];
    for (final positioned in page.systems) {
      final png = await renderLayoutToPng(
        positioned.system.layout,
        staffSpace: spatium * rasterScale,
        theme: theme,
        // Transparent: the PDF page is already white, and an opaque box would
        // clip the neighbouring system's overhang.
        background: const Color(0x00000000),
      );
      rendered.add((positioned, png));
    }
    pages.add(rendered);
  }

  final doc = pw.Document();
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final rendered = pages[pageIndex];
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        // We position everything ourselves in page coordinates.
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            if (pageIndex == 0 && titleText.isNotEmpty)
              pw.Positioned(
                left: metrics.marginLeft * spatium,
                top: margin * spatium,
                child: pw.Text(
                  titleText,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            for (final (positioned, png) in rendered)
              pw.Positioned(
                left: metrics.marginLeft * spatium,
                top: (metrics.marginTop + positioned.top) * spatium,
                child: pw.Image(
                  pw.MemoryImage(png),
                  width: positioned.system.layout.width * spatium,
                  height: positioned.system.layout.height * spatium,
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// A multi-part score → a print-ready PDF that engraves EVERY part (one system
/// per line holds all staves, connected by systemic barlines), so a full/
/// orchestral score prints every instrument — unlike [exportScoreToPdf], which
/// renders a single staff. Mirrors it exactly, swapping the single-staff
/// pagination + rasterizer for their multi-part twins (`layoutMultiPartPages` +
/// `renderStaffSystemLayoutToPng`, both already in crisp_notation).
Future<Uint8List> exportMultiPartToPdf(
  MultiPartScore multiPart, {
  String? title,
  CrispNotationTheme theme = CrispNotationTheme.standard,
  PdfPageFormat pageFormat = _a4,
  double spatium = _defaultSpatium,
  double rasterScale = 3,
  double margin = 8,
}) async {
  if (multiPart.parts.length <= 1) {
    return exportScoreToPdf(
      multiPart.parts.isEmpty
          ? const Score(clef: Clef.treble, measures: [])
          : multiPart.parts.first,
      theme: theme,
      title: title,
      pageFormat: pageFormat,
      spatium: spatium,
      rasterScale: rasterScale,
      margin: margin,
    );
  }

  final metadata = MusicFonts.metadataOrNull(theme.musicFont) ??
      await MusicFonts.load(theme.musicFont);
  final settings = LayoutSettings(metadata: metadata);

  final titleText = title?.trim() ?? '';
  final titleGap = titleText.isEmpty ? 0.0 : 18.0;
  final metrics = PageMetrics(
    width: pageFormat.width / spatium,
    height: pageFormat.height / spatium,
    marginTop: margin + titleGap,
    marginBottom: margin,
    marginLeft: margin,
    marginRight: margin,
  );
  final paged = layoutMultiPartPages(multiPart, settings, metrics: metrics);

  final pages = <List<(PositionedMultiPartSystem, Uint8List)>>[];
  for (final page in paged.pages) {
    final rendered = <(PositionedMultiPartSystem, Uint8List)>[];
    for (final positioned in page.systems) {
      final png = await renderStaffSystemLayoutToPng(
        positioned.system.layout,
        staffSpace: spatium * rasterScale,
        theme: theme,
        background: const Color(0x00000000),
      );
      rendered.add((positioned, png));
    }
    pages.add(rendered);
  }

  final doc = pw.Document();
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final rendered = pages[pageIndex];
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            if (pageIndex == 0 && titleText.isNotEmpty)
              pw.Positioned(
                left: metrics.marginLeft * spatium,
                top: margin * spatium,
                child: pw.Text(
                  titleText,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            for (final (positioned, png) in rendered)
              pw.Positioned(
                left: metrics.marginLeft * spatium,
                top: (metrics.marginTop + positioned.top) * spatium,
                child: pw.Image(
                  pw.MemoryImage(png),
                  width: positioned.system.layout.width * spatium,
                  height: positioned.system.layout.height * spatium,
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
