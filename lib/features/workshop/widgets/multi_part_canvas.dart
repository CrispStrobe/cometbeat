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

import 'package:comet_beat/features/workshop/model/multi_part_document.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide PageMetrics;

class MultiPartCanvas extends StatefulWidget {
  const MultiPartCanvas({
    super.key,
    required this.document,
    this.onElementTap,
    this.onStaffTap,
    this.onHover,
    this.onElementHover,
    this.ghostPart,
    this.ghostTarget,
    this.ghostDuration = const NoteDuration(DurationBase.quarter),
    this.highlightedIds = const {},
    this.suppressElementIds = const {},
    this.onElementDragStart,
    this.onElementDragUpdate,
    this.onElementDragEnd,
    this.controller,
    this.onMarquee,
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

  /// 🔍 Called with the **global** id of the note under the mouse (null off any
  /// note), for desktop hover-inspect. Resolved inside this widget's own scroll
  /// space via [controller], so it's correct while the page is scrolled.
  final void Function(String? globalId)? onElementHover;

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

  /// Reports a rubber-band rectangle in the same local coordinates as
  /// [controller]. The overlay lives inside the scrollable page so the two
  /// coordinate spaces stay aligned while the full score is scrolled.
  final void Function(Rect rect)? onMarquee;

  /// An insertion caret drawn before its (global) `beforeElementId`.
  final EditorCaret? caret;

  /// Whether to label each wrapped system's first bar with its measure number.
  final bool showMeasureNumbers;

  /// Whether to draw each note's name below its staff, in [noteNameStyle].
  final bool showNoteNames;
  final NoteNameStyle noteNameStyle;

  /// Pixels per staff space (zoom).
  final double staffSpace;

  @override
  State<MultiPartCanvas> createState() => _MultiPartCanvasState();
}

class _MultiPartCanvasState extends State<MultiPartCanvas> {
  // Small margins — this is an editor canvas, not a print page.
  static const double _margin = 2;

  // Distance between adjacent parts / systems, in staff spaces — kept in step
  // with [MultiPartView]'s defaults so the height probe matches the render.
  static const double _staffGap = 4;
  static const double _systemGap = 10;

  // The SMuFL load, held for the widget's lifetime. It MUST NOT be created in
  // build(): once loaded, MusicFonts.load returns `Future.value(cached)` — a
  // new instance every call — so an inline future made FutureBuilder
  // unsubscribe/resubscribe and rebuild a second time on every build, doubling
  // all the layout work below and adding a frame of latency per hover tick.
  late final Future<void> _fontLoad = MusicFonts.load(kidsScoreTheme.musicFont);

  // Memoized page geometry, keyed on everything it depends on. Two reasons:
  //  1. [_pageHeightSpaces] is a *full* engraving pass whose result is thrown
  //     away except for one height (measured at ~150-250ms for a 4-part score)
  //     — far too costly to redo on every build.
  //  2. [PageMetrics] declares no `operator ==`, so RenderMultiPartView's
  //     `if (value == _metrics) return;` guard is an identity check. A
  //     fresh-but-equal instance forced markNeedsLayout() on *every* build,
  //     even a pure hover where nothing moved — which also made its deep
  //     `document ==` check pure waste. Reusing the instance lets both guards
  //     fire, so hover costs zero layouts.
  MultiPartScore? _geomDoc;
  double? _geomWidthSpaces;
  SmuflMetadata? _geomMetadata;
  PageMetrics? _geomMetrics;
  double _geomHeightSpaces = 0;

  ({PageMetrics metrics, double heightSpaces}) _geometry(
    MultiPartScore doc,
    SmuflMetadata? metadata,
    double widthSpaces,
  ) {
    if (_geomMetrics != null &&
        identical(doc, _geomDoc) &&
        identical(metadata, _geomMetadata) &&
        widthSpaces == _geomWidthSpaces) {
      return (metrics: _geomMetrics!, heightSpaces: _geomHeightSpaces);
    }
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
    _geomDoc = doc;
    _geomMetadata = metadata;
    _geomWidthSpaces = widthSpaces;
    _geomHeightSpaces = heightSpaces;
    _geomMetrics = metrics;
    return (metrics: metrics, heightSpaces: heightSpaces);
  }

  @override
  Widget build(BuildContext context) {
    final theme = kidsScoreTheme;
    // [MultiPartView] loads the SMuFL metadata itself and re-lays-out; this
    // FutureBuilder just rebuilds once it lands so the page height can switch
    // from an estimate to the exact probed value. The view widget is always
    // present (never gated on the font) so it renders as soon as fonts load.
    return FutureBuilder<void>(
      future: _fontLoad,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 1000.0;
            final widthSpaces =
                (maxWidth / widget.staffSpace).clamp(40.0, 400.0).toDouble();
            // Memoized in MultiPartDocument, so an unchanged score returns an
            // identical instance — which both keys the cache below and lets the
            // render object's own `document ==` fast path early-return.
            final doc = widget.document.buildMultiPart();
            final metadata = MusicFonts.metadataOrNull(theme.musicFont);
            final geom = _geometry(doc, metadata, widthSpaces);
            final heightSpaces = geom.heightSpaces;
            return SingleChildScrollView(
              child: MouseRegion(
                onHover: widget.onElementHover == null
                    ? null
                    : (e) {
                        final ids = widget.controller?.elementIdsIn(
                              Rect.fromCenter(
                                center: e.localPosition,
                                width: 6,
                                height: 6,
                              ),
                            ) ??
                            const [];
                        widget.onElementHover!(ids.isEmpty ? null : ids.first);
                      },
                onExit: widget.onElementHover == null
                    ? null
                    : (_) => widget.onElementHover!(null),
                child: SizedBox(
                  width: widthSpaces * widget.staffSpace,
                  height: heightSpaces * widget.staffSpace,
                  child: Stack(
                    children: [
                      InteractiveMultiPartView(
                        document: doc,
                        metrics: geom.metrics,
                        theme: theme,
                        staffSpace: widget.staffSpace,
                        // staffGap (4) / systemGap (10) match the view's own defaults;
                        // the probe below mirrors them so heights agree.
                        highlightedIds: widget.highlightedIds,
                        suppressElementIds: widget.suppressElementIds,
                        ghostPart: widget.ghostPart,
                        ghostTarget: widget.ghostTarget,
                        ghostDuration: widget.ghostDuration,
                        onElementTap: widget.onElementTap,
                        onStaffTap: widget.onStaffTap,
                        onHover: widget.onHover,
                        onElementDragStart: widget.onElementDragStart,
                        onElementDragUpdate: widget.onElementDragUpdate,
                        onElementDragEnd: widget.onElementDragEnd,
                        controller: widget.controller,
                        caret: widget.caret,
                        showMeasureNumbers: widget.showMeasureNumbers,
                        showNoteNames: widget.showNoteNames,
                        noteNameStyle: widget.noteNameStyle,
                      ),
                      if (widget.onMarquee != null)
                        Positioned.fill(
                          child: _CanvasMarqueeOverlay(
                            onSelect: widget.onMarquee!,
                          ),
                        ),
                    ],
                  ),
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

class _CanvasMarqueeOverlay extends StatefulWidget {
  const _CanvasMarqueeOverlay({required this.onSelect});

  final ValueChanged<Rect> onSelect;

  @override
  State<_CanvasMarqueeOverlay> createState() => _CanvasMarqueeOverlayState();
}

class _CanvasMarqueeOverlayState extends State<_CanvasMarqueeOverlay> {
  Offset? _start;
  Offset? _current;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => setState(() {
        _start = details.localPosition;
        _current = details.localPosition;
      }),
      onPanUpdate: (details) =>
          setState(() => _current = details.localPosition),
      onPanEnd: (_) {
        final start = _start;
        final current = _current;
        if (start != null && current != null) {
          widget.onSelect(Rect.fromPoints(start, current));
        }
        setState(() {
          _start = null;
          _current = null;
        });
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _CanvasMarqueePainter(_start, _current, color),
      ),
    );
  }
}

class _CanvasMarqueePainter extends CustomPainter {
  _CanvasMarqueePainter(this.start, this.current, this.color);

  final Offset? start;
  final Offset? current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final start = this.start;
    final current = this.current;
    if (start == null || current == null) return;
    final rect = Rect.fromPoints(start, current);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CanvasMarqueePainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.current != current;
}
