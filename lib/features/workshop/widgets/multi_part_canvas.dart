// lib/features/workshop/widgets/multi_part_canvas.dart
//
// The full-score canvas for the multi-instrument Workshop (G6): renders a
// [MultiPartDocument] as a paginating [MultiPartView] and reports taps as global
// element ids (`p2:w7`) so the screen can select across parts. This is the
// "full-score layout + selection surface" half of the two-view design — rich
// note entry stays on the single-part interactive pipeline for the active part.
//
// [MultiPartView] paints exactly one page, so this sizes the page tall enough to
// hold the whole score by probing the layout first (via [layoutMultiPartPages]),
// then renders it as a single, vertically-scrollable page. The engraving width
// is bound to the viewport so systems break on-screen.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide PageMetrics;
import 'package:klang_universum/features/workshop/model/multi_part_document.dart';
import 'package:klang_universum/shared/score_theme.dart';

class MultiPartCanvas extends StatelessWidget {
  const MultiPartCanvas({
    super.key,
    required this.document,
    this.onElementTap,
    this.onStaffTap,
    this.onHover,
    this.ghostPart,
    this.ghostTarget,
    this.ghostDuration = const NoteDuration(DurationBase.quarter),
    this.highlightedIds = const {},
    this.suppressElementIds = const {},
    this.onElementDragStart,
    this.onElementDragUpdate,
    this.onElementDragEnd,
    this.controller,
    this.caret,
    this.showMeasureNumbers = false,
    this.showNoteNames = false,
    this.noteNameStyle = NoteNameStyle.letter,
    this.staffSpace = 11,
  });

  /// The multi-instrument document to lay out and render.
  final MultiPartDocument document;

  /// Called with the tapped element's **global** id (`p<part>:<rawId>`); feed it
  /// to [MultiPartDocument.selectByGlobalId].
  final void Function(String globalId)? onElementTap;

  /// Called when the user taps empty staff — with the part hit and a quantized
  /// [StaffTarget] (crisp_notation C12). Drive note placement into that part.
  final void Function(int partIndex, StaffTarget target)? onStaffTap;

  /// Called as the pointer hovers the staff (partIndex `-1`/null off-staff);
  /// drive the placement ghost.
  final void Function(int partIndex, StaffTarget? target)? onHover;

  /// The placement ghost: part, target, and notehead duration.
  final int? ghostPart;
  final StaffTarget? ghostTarget;
  final NoteDuration ghostDuration;

  /// Global ids to paint in the highlight colour (the active part's selection).
  final Set<String> highlightedIds;

  /// Global ids hidden from the layout — a clean drag-source hide so the app can
  /// show the ghost following the pointer instead (live drag preview).
  final Set<String> suppressElementIds;

  /// Drag-to-move an element: start (by global id), then update/end report the
  /// drop `(partIndex, StaffTarget)`.
  final void Function(String globalId)? onElementDragStart;
  final void Function(String globalId, int partIndex, StaffTarget target)?
      onElementDragUpdate;
  final void Function(String globalId, int partIndex, StaffTarget target)?
      onElementDragEnd;

  /// Binds this page's element hit-regions for marquee / cross-part selection.
  final ElementRegionController? controller;

  /// An insertion caret drawn before its (global) `beforeElementId`.
  final EditorCaret? caret;

  /// Whether to label each wrapped system's first bar with its measure number.
  final bool showMeasureNumbers;

  /// Whether to draw each note's name below its staff, in [noteNameStyle].
  final bool showNoteNames;
  final NoteNameStyle noteNameStyle;

  /// Pixels per staff space (zoom).
  final double staffSpace;

  // Small margins — this is an editor canvas, not a print page.
  static const double _margin = 2;

  // Distance between adjacent parts / systems, in staff spaces — kept in step
  // with [MultiPartView]'s defaults so the height probe matches the render.
  static const double _staffGap = 4;
  static const double _systemGap = 10;

  @override
  Widget build(BuildContext context) {
    final theme = kidsScoreTheme;
    // [MultiPartView] loads the SMuFL metadata itself and re-lays-out; this
    // FutureBuilder just rebuilds once it lands so the page height can switch
    // from an estimate to the exact probed value. The view widget is always
    // present (never gated on the font) so it renders as soon as fonts load.
    return FutureBuilder<void>(
      future: MusicFonts.load(theme.musicFont),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 1000.0;
            final widthSpaces =
                (maxWidth / staffSpace).clamp(40.0, 400.0).toDouble();
            final doc = document.buildMultiPart();
            final metadata = MusicFonts.metadataOrNull(theme.musicFont);
            final heightSpaces = metadata != null
                ? _pageHeightSpaces(doc, metadata, widthSpaces)
                : _estimateHeightSpaces(doc);
            final metrics = PageMetrics(
              width: widthSpaces,
              height: heightSpaces,
              marginLeft: _margin,
              marginRight: _margin,
              marginTop: _margin,
              marginBottom: _margin,
            );
            return SingleChildScrollView(
              child: SizedBox(
                width: widthSpaces * staffSpace,
                height: heightSpaces * staffSpace,
                child: InteractiveMultiPartView(
                  document: doc,
                  metrics: metrics,
                  theme: theme,
                  staffSpace: staffSpace,
                  // staffGap (4) / systemGap (10) match the view's own defaults;
                  // the probe below mirrors them so heights agree.
                  highlightedIds: highlightedIds,
                  suppressElementIds: suppressElementIds,
                  ghostPart: ghostPart,
                  ghostTarget: ghostTarget,
                  ghostDuration: ghostDuration,
                  onElementTap: onElementTap,
                  onStaffTap: onStaffTap,
                  onHover: onHover,
                  onElementDragStart: onElementDragStart,
                  onElementDragUpdate: onElementDragUpdate,
                  onElementDragEnd: onElementDragEnd,
                  controller: controller,
                  caret: caret,
                  showMeasureNumbers: showMeasureNumbers,
                  showNoteNames: showNoteNames,
                  noteNameStyle: noteNameStyle,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// A generous height estimate used only in the brief window before the SMuFL
  /// metadata loads (over-estimates so nothing clips; the exact probe replaces
  /// it on the next frame). One 5-space staff per part plus gaps, per bar.
  double _estimateHeightSpaces(MultiPartScore doc) {
    final perSystem = doc.parts.length * (5 + _staffGap) + _systemGap;
    return 2 * _margin + doc.measureCount * perSystem;
  }

  /// Probe the layout at [widthSpaces] to find the height (in staff spaces) that
  /// fits the whole score on one page, so nothing is clipped or paginated away.
  double _pageHeightSpaces(
    MultiPartScore doc,
    SmuflMetadata metadata,
    double widthSpaces,
  ) {
    final probe = PageMetrics(
      width: widthSpaces,
      // Tall enough that the probe never itself paginates.
      height: 100000,
      marginLeft: _margin,
      marginRight: _margin,
      marginTop: _margin,
      marginBottom: _margin,
    );
    final paged = layoutMultiPartPages(
      doc,
      LayoutSettings(metadata: metadata),
      metrics: probe,
      // systemGap defaults to 8 here but MultiPartView paints at 10 — match it.
      systemGap: _systemGap,
      justifyVertically: false,
    );
    var content = 0.0;
    if (paged.pages.isNotEmpty) {
      for (final placed in paged.pages.first.systems) {
        final bottom = placed.top + placed.system.layout.height;
        if (bottom > content) content = bottom;
      }
    }
    // Add both margins; guard a minimum so an empty score still shows a staff.
    return (content + 2 * _margin).clamp(12.0, 100000.0).toDouble();
  }
}
