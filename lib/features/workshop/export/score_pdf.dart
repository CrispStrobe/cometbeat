// lib/features/workshop/export/score_pdf.dart
//
// Score → print-ready PDF (WORKSHOP_PARITY.md bucket G).
//
// crisp_notation writes vector PDF itself: `layoutPages` / `layoutMultiPartPages`
// line-break and paginate, `pagedLayoutToPdf` / `multiPartPagesToPdf` draw the
// pages — staff lines, stems, beams and slurs as paths, every music glyph from
// the embedded engraving font, the title block and copyright as text. So the
// print is sharp at any zoom and a fraction of the size of the old per-system
// PNGs. All this file adds is the app's page box, the font bytes from the
// asset bundle, and the title fields merged into the score's own metadata.

import 'dart:typed_data';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A4 portrait, in points.
const _a4Width = 595.28;
const _a4Height = 841.89;

/// Points per staff space. 6pt ≈ 2.1mm — a normal engraving size, and it puts
/// ~99 staff spaces across an A4 width.
const _defaultSpatium = 6.0;

/// The engraving font's `.otf` bytes, which the PDF embeds. A theme font that
/// is not bundled as a loadable asset prints in Bravura.
Future<List<int>> _fontBytes(MusicFont font) async {
  final asset = font.fontAsset ?? MusicFont.bravura.fontAsset!;
  final data = await rootBundle.load(asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// [metadata] with the export dialog's fields laid over it (a blank field
/// keeps the score's own value).
ScoreMetadata _withHeading(
  ScoreMetadata metadata, {
  String? title,
  String? subtitle,
  String? composer,
  String? lyricist,
}) {
  String? pick(String? given, String? own) =>
      (given?.trim().isNotEmpty ?? false) ? given!.trim() : own;
  return ScoreMetadata(
    title: pick(title, metadata.title),
    subtitle: pick(subtitle, metadata.subtitle),
    composer: pick(composer, metadata.composer),
    lyricist: pick(lyricist, metadata.lyricist),
    arranger: metadata.arranger,
    copyright: metadata.copyright,
  );
}

PageMetrics _metrics(
  double pageWidth,
  double pageHeight,
  double spatium,
  double margin, {
  double marginLeft = 0,
}) =>
    PageMetrics(
      width: pageWidth / spatium,
      height: pageHeight / spatium,
      marginTop: margin,
      marginBottom: margin,
      marginLeft: margin + marginLeft,
      marginRight: margin,
    );

/// Renders [score] to a paginated, print-ready vector PDF.
///
/// Systems are line-broken to the page's content width and packed into pages
/// by crisp_notation's [layoutPages], the first page keeping room for the
/// title block. [spatium] (points per staff space) sets the engraving size:
/// larger = fewer bars per line. The page is A4 unless [pageWidth] /
/// [pageHeight] (points) say otherwise; [margin] is in staff spaces.
///
/// [extraFingerings] engraves fingering marks the score does not itself carry,
/// keyed by note-element id — what a printed part needs when the fingering was
/// computed (by the bowed arranger, say) rather than authored into the score.
///
/// Needs the asset bundle (the app always has it; a widget test does).
Future<Uint8List> exportScoreToPdf(
  Score score, {
  String? title,
  String? subtitle,
  String? composer,
  String? lyricist,
  CrispNotationTheme theme = CrispNotationTheme.standard,
  double pageWidth = _a4Width,
  double pageHeight = _a4Height,
  double spatium = _defaultSpatium,
  double margin = 8,
  Map<String, List<int>> extraFingerings = const {},
}) async {
  final metadata = MusicFonts.metadataOrNull(theme.musicFont) ??
      await MusicFonts.load(theme.musicFont);
  // The PDF prints its text in Times: lyrics are spaced for that face.
  final settings = LayoutSettings(
    metadata: metadata,
    textWidth: timesTextWidth,
  );
  final heading = _withHeading(
    score.metadata,
    title: title,
    subtitle: subtitle,
    composer: composer,
    lyricist: lyricist,
  );
  final paged = layoutPages(
    score,
    settings,
    metrics: _metrics(pageWidth, pageHeight, spatium, margin),
    extraFingerings: extraFingerings,
    firstPageTop: titleBlockHeight(heading),
  );
  return pagedLayoutToPdf(
    paged,
    musicFont: await _fontBytes(theme.musicFont),
    pointsPerSpace: spatium,
    metadata: heading,
  );
}

/// A multi-part score → a print-ready vector PDF that engraves EVERY part (one
/// system per line holds all staves, joined by systemic barlines, with their
/// brackets and braces and the instrument names before the first system), so
/// a full or orchestral score prints every instrument. A single part takes
/// [exportScoreToPdf].
Future<Uint8List> exportMultiPartToPdf(
  MultiPartScore multiPart, {
  String? title,
  String? subtitle,
  String? composer,
  String? lyricist,
  CrispNotationTheme theme = CrispNotationTheme.standard,
  double pageWidth = _a4Width,
  double pageHeight = _a4Height,
  double spatium = _defaultSpatium,
  double margin = 8,
}) async {
  if (multiPart.parts.length <= 1) {
    return exportScoreToPdf(
      multiPart.parts.isEmpty
          ? const Score(clef: Clef.treble, measures: [])
          : multiPart.parts.first,
      theme: theme,
      title: title,
      subtitle: subtitle,
      composer: composer,
      lyricist: lyricist,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      spatium: spatium,
      margin: margin,
    );
  }

  final metadata = MusicFonts.metadataOrNull(theme.musicFont) ??
      await MusicFonts.load(theme.musicFont);
  // The PDF prints its text in Times: lyrics are spaced for that face.
  final settings = LayoutSettings(
    metadata: metadata,
    textWidth: timesTextWidth,
  );
  final heading = _withHeading(
    multiPart.parts.first.metadata,
    title: title,
    subtitle: subtitle,
    composer: composer,
    lyricist: lyricist,
  );
  // Room left of the staves for the instrument names and the brackets.
  var names = 0.0;
  for (final part in multiPart.parts) {
    final name = part.metadata.instrument?.trim() ?? '';
    if (name.isEmpty) continue;
    final width = 2 * estimateTextHalfWidth(name, 1.1) + 1.0;
    if (width > names) names = width;
  }
  final brackets = multiPart.brackets.isEmpty ? 0.0 : 1.8;
  final paged = layoutMultiPartPages(
    multiPart,
    settings,
    metrics: _metrics(
      pageWidth,
      pageHeight,
      spatium,
      margin,
      marginLeft: names + brackets,
    ),
    firstPageTop: titleBlockHeight(heading),
  );
  return multiPartPagesToPdf(
    paged,
    musicFont: await _fontBytes(theme.musicFont),
    pointsPerSpace: spatium,
    metadata: heading,
  );
}
