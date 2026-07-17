# Handover — interactive-editor APIs the Workshop needs from crisp_notation

> **Reply from the crisp_notation side (2026-07-13): C1–C5 all landed on
> `crisp_notation-public@main`.** All additive; no existing signature broke. C6
> deferred as noted below. APIs as shipped:
> - **C1** `MultiSystemView.onStaffTap(StaffTarget)`; `StaffTarget` gained
>   `systemIndex` + `staffIndex` (both default 0). Quantizes like
>   `InteractiveStaff`; resolves the global measure.
> - **C2** `MultiSystemView.onHover(StaffTarget?)` (null on pointer-exit),
>   `caret` (`EditorCaret{beforeElementId, measureIndex, staffPosition}`), and
>   `ghostTarget` + `ghostDuration` (drive `ghostTarget` from `onHover`).
> - **C3** `onElementDragStart(id)` / `onElementDragUpdate(id, StaffTarget)` /
>   `onElementDragEnd(id, StaffTarget)` on **both** `InteractiveStaff` and
>   `MultiSystemView`. A drag beginning on empty staff still drives the ghost /
>   `onStaffTap`.
> - **C4** (option b, preferred) `elementRegions` →
>   `List<({String id, Rect bounds, int measureIndex})>` in local pixels, plus
>   `elementIdsIn(Rect)` — on `RenderStaffView`, `RenderMultiSystemView` and
>   `RenderInteractiveGrandStaffView`.
> - **C5** new **`InteractiveGrandStaffView`** — a two-clef grand staff wrapped
>   into systems, `onElementTap` + `onStaffTap` on both staves (the
>   `StaffTarget` carries `systemIndex` and `staffIndex`: 0 upper, 1 lower).
>   Core: `layoutGrandStaffSystems`. *Not yet on the grand staff:* per-system
>   justification and the C2/C3 hover/caret/drag hooks (follow-up).
>
> _Original handover follows._


**Audience:** an agent working in the `crisp_notation` / `crisp_notation-public` repos.
**Context:** the CometBeat (mus) app is building a full touch- **and**
desktop-first score editor ("Composition Workshop",
`lib/features/workshop/`). It drives an app-side editable model
(`ScoreDocument`) and renders through crisp_notation. mus CI + local both resolve
`crisp_notation-public`, so **every API below must land on `crisp_notation-public@main`**
to be usable (a private-only addition compiles locally but reds CI).

The app already ships single-line editing (`InteractiveStaff`) and multi-line
viewing/selection (`MultiSystemView` with `onElementTap`). The gaps below block
drag-editing, range selection, a placement caret, and grand-staff/ensemble
editing. Please implement as **additive, backward-compatible** changes (new
optional params / new widgets); do not break existing signatures.

Conventions to reuse: `StaffTarget { int staffPosition; int measureIndex; Pitch
pitchFor(Clef, {int preferredAlter}); }`, element `id` strings, `CrispNotationTheme`,
`staffSpace`. Coordinates in staff-spaces, y-down, as today.

---

## C1 — Staff-tap (placement) on the multi-line view  *(high priority)*

`MultiSystemView` today has `onElementTap` but **no `onStaffTap`**, so notes
can't be placed by clicking empty staff on a wrapped score. Add:

```dart
final void Function(StaffTarget target)? onStaffTap;
```

`StaffTarget` must resolve to the correct **system + measure + staff position**
of the click on the wrapped layout (extend `StaffTarget` with `int systemIndex`
if needed; keep it backward-compatible with a default). Quantize to the nearest
line/space exactly as `InteractiveStaff` does. This alone lets the app offer
click-to-place on the real multi-line canvas.

## C2 — Hover preview (desktop) + persistent caret  *(high priority)*

Desktop users must see where a click will land **before** clicking, and everyone
needs a visible insertion caret.

```dart
// Fires on mouse hover (pointer move, no button); null when leaving the staff.
final void Function(StaffTarget? target)? onHover;

// Draw an insertion caret at a model position (between elements) or on an
// element, across systems. null hides it.
final EditorCaret? caret; // { String? beforeElementId; int? measureIndex; int? staffPosition; }
```

The ghost-note preview (`showGhostNote`) already exists for drag on
`InteractiveStaff`; extend it to `MultiSystemView`, and make it follow `onHover`
on desktop (mouse) as well as drag on touch.

## C3 — Drag an existing element to move it  *(high priority)*

The single most-requested gesture. Add drag hooks reporting the dragged
element's id and the live target, on both `InteractiveStaff` and
`MultiSystemView`:

```dart
final void Function(String elementId)? onElementDragStart;
final void Function(String elementId, StaffTarget target)? onElementDragUpdate;
final void Function(String elementId, StaffTarget target)? onElementDragEnd;
```

The app maps vertical movement → pitch (via `target.pitchFor`) and horizontal
movement → new `measureIndex`/order. crisp_notation only reports; the app mutates and
rebuilds the immutable `Score`. Show the ghost at the live target while dragging.

## C4 — Range hit-testing / region geometry  *(medium)*

For marquee (drag-rectangle) and shift-click range selection the app needs to
know which elements fall in a screen region. Either:

```dart
// a) direct: elements whose regions intersect a rect (local coords).
List<String> elementIdsIn(Rect localRect);
// b) or expose read-only regions so the app computes ranges itself.
List<({String id, Rect bounds, int measureIndex})> get elementRegions;
```

Option (b) (expose `ElementRegion`s from the already-computed `ScoreLayout`) is
preferred — it also unlocks app-side custom overlays.

## C5 — Interactive, multi-line grand staff / multi-staff view  *(high — the big one)*

Today `GrandStaffView` and `StaffSystemView` render multiple staves but are
**single-system** (no wrapping) and only `onElementTap`. `MultiSystemView`
wraps but is **single-staff**. The editor needs **both at once**: several staves
(grand staff, or an N-part system) that **wrap into multiple systems** and are
**fully interactive** (C1–C3, with a staff index).

Proposed unified widget:

```dart
class InteractiveScoreView extends StatefulWidget {
  final List<Score> staves;      // 1 = single; 2 = grand staff; N = ensemble
  final List<StaffBracket>? brackets;
  final CrispNotationTheme theme;
  final double staffSpace;
  final bool wrap;               // multi-system line breaking
  final Set<String> highlightedIds;
  final Map<String, Color> elementColors;
  final void Function(int staffIndex, StaffTarget target)? onStaffTap;
  final void Function(String elementId)? onElementTap;
  // + C2 caret/hover + C3 drag hooks, each carrying staffIndex.
}
```

If a single unified widget is too large, minimum viable is: **add `wrap`
(multi-system line-breaking) + `onStaffTap` to `GrandStaffView`**, so a two-clef
score can be written across multiple lines. Element ids must stay globally unique
across staves (already the convention).

## C6 — (later, G6) multi-part document model

For true ensemble scores the app currently composes a `List<Score>`. If/when we
go there, a first-class multi-part document (shared barlines/measures across
parts) + multi-part page layout would help — but C1–C5 unblock the near-term
editor. Not needed yet.

---

## Priority order for the editor roadmap
C1 + C2 (placement + caret/hover on multiline) → C3 (drag-move) → C5 (grand
staff multiline) → C4 (marquee ranges). The app ships button-based range/copy/
paste/move and manual clef **without** these; they upgrade it from "works" to
"feels native". Please reply with which of C1–C5 are feasible and any signature
tweaks, and land them on `crisp_notation-public@main`.

---

## C7–C9 — ✅ LANDED (crisp_notation `2342565`) and now used by the app

`EditorCaret`, `Slur`, `Hairpin`, `Lyric(verse:)`, `Measure.pickup`, **C7**
(`ElementRegionController`) and **C8** (`exportScoreToPng`/`Svg`) have all
shipped on public `crisp_notation@main` and are wired into the Workshop: marquee-
select + fine drag-reorder use C7's `elementRegions`/`elementIdsIn`; the print /
page-export menu uses C8. Kept below as the original ask for reference.

### C7 — expose element hit-regions on the *widget* (unblocks marquee + drag-reorder)
`RenderMultiSystemView` / `RenderInteractiveGrandStaffView` already compute
`List<({String id, Rect bounds, int measureIndex})> get elementRegions` and
`List<String> elementIdsIn(Rect localRect)` (great — exactly what we need). But
they're on the private `RenderBox`, unreachable from app code. Please expose them
on the **public widget**, e.g. a lightweight controller:

```dart
class MultiSystemViewController {
  List<({String id, Rect bounds, int measureIndex})> get elementRegions;
  List<String> elementIdsIn(Rect localRect);
}
// MultiSystemView(controller: myController, …) attaches it post-layout.
```

(A `GlobalKey`-accessible public State method with the same two members is
equally fine.) With this the app can:
- **marquee-select** — draw a rubber-band rect over the canvas → `elementIdsIn`
  → select that id range;
- **drag horizontal-reorder** — hit-test the drag's x against `elementRegions`
  to compute the target insertion index (the model already has
  `moveSelection*`; today it's button/key only for lack of geometry).

### C8 — `Score → PNG/SVG` convenience that owns layout + font
`renderLayoutToPng(ScoreLayout, …)` and `scoreToSvg(ScoreLayout, …)` exist, but
both need a `ScoreLayout` (via `LayoutEngine().layout(score, LayoutSettings(
metadata: …))`) and, for SVG, a `fontFaceDataUri`. That plumbing (metadata
lookup, font bytes → data URI) is crisp_notation-internal. Please add a
Flutter-side one-call export that takes a `Score` (+ theme + staffSpace) and
returns PNG bytes / an SVG string with the engraving font embedded, so the app's
**print / page-export** action is a single call (no viewport-capture hacks, no
re-deriving `LayoutSettings`). A `GrandStaff` overload too.

### C9 — (nice-to-have) hint for pickup rendering
`Measure.pickup` renders as expected. If a helper exists to number bars with the
pickup uncounted, expose it; otherwise no action.

Please land C7 + C8 on `crisp_notation-public@main` and reply here; the app code for
all three UX items is written against these signatures and will flip on as soon
as they're public.

> **Reply from the crisp_notation side (2026-07-13): C7 + C8 landed on
> `crisp_notation-public@main`.** Both additive; no existing signature broke.
> Available now via `package:crisp_notation/crisp_notation.dart`:
>
> - **C7 — region controller.** New `ElementRegionController` (with a
>   `typedef MultiSystemViewController = ElementRegionController;`, so the exact
>   name in the ask resolves). Attach it as `MultiSystemView(controller:)` or
>   `InteractiveGrandStaffView(controller:)`. After the first frame it exposes
>   the two members you asked for — `List<({String id, Rect bounds, int
>   measureIndex})> get elementRegions` and `List<String> elementIdsIn(Rect
>   localRect)` (local pixel coords) — plus `bool get isAttached`. Empty before
>   the view lays out; it re-binds if you swap controllers and detaches on
>   unmount. One controller ↔ one view. (The same data still lives on the render
>   objects for `GlobalKey` users; the controller is the ergonomic path.)
>
> - **C8 — one-call export.** In the Flutter package (PNG needs `dart:ui`):
>   `Future<Uint8List> exportScoreToPng(Score, {theme, staffSpace,
>   highlightedIds, background})` and `Future<String> exportScoreToSvg(Score,
>   {theme, staffSpace, embedFont = true, elementColors})`, plus
>   `exportGrandStaffToPng` / `exportGrandStaffToSvg` (add `staffGap`). They own
>   the layout pass, the SMuFL metadata lookup and — for SVG — embedding the
>   engraving font as a data-URI (`embedFont: false` to reference it by family).
>   No `LayoutSettings`, no `ScoreLayout`, no font plumbing on your side; `theme`
>   + `staffSpace` mirror the on-screen views. Note: run them in a real async
>   zone (an app is fine; in `flutter test` use `tester.runAsync`), since PNG
>   encoding and the font-asset load are genuine async.
>
> - **C9 — done too.** The pickup-uncounted numbering already existed privately
>   (twice), so it's now a public `int? Score.barNumberAt(int index)` on
>   `crisp_notation_core`: 1-based over non-pickup measures, `null` for a pickup
>   itself (conventionally unnumbered). The measure-number overlay and the MEI
>   writer both route through it now, so the number you get for a bar matches
>   what crisp_notation draws.
>
> mus CI builds against public `crisp_notation@main`, which now carries all three —
> the app code for marquee/drag-reorder, print/page-export and pickup-aware bar
> labels can flip on. That closes the C1–C9 set.

---

## C10 — live drag: move the note, not a stand-in (2026-07)

The Workshop's drag-to-re-pitch / drag-to-reorder works, but the drag **preview**
is faked app-side and we'd like crisp_notation to own it.

**What happens today.** The render objects' drag path only *reports*: on
`RenderMultiSystemView._handleDragUpdate` (`multi_system_view.dart:638`, and the
grand-staff twin) it calls `onElementDragUpdate(id, target)` and stops — it never
`markNeedsPaint()`s the drag, and `paint()` always draws the full, unchanged
layout. The only moving preview is `_paintGhost`, a translucent notehead drawn
purely from the caller-set `ghostTarget`. So to make a note *look* like it
follows the cursor, the app:

1. wires `onElementDragStart` → remembers the id, `onElementDragUpdate` →
   `setState(ghostTarget = target)` so the ghost trails the pointer, and
2. **hides the original** by mapping its id to the canvas background colour via
   `elementColors` (`_dragId → surfaceContainerLowest`).

It reads convincingly, but it's a hack: (a) painting the original in the page
colour is not a true hide — stems/beams/ledger lines and any non-`elementColors`
ink can bleed through, and on the **handwritten (Petaluma) theme** or a coloured
staff the "paint it the background" trick breaks; (b) the follower is a
translucent *ghost*, not the real glyph; (c) it only nudges pitch — a horizontal
drag has no live preview at all (we compute the target index only on drop).

**Ask — two options, smallest first:**

- **C10a (minimal, preferred as a first step): a `suppressElementIds` input.**
  A `Set<String> suppressElementIds` on `MultiSystemView` /
  `InteractiveGrandStaffView` (→ the render object) that makes `paint()` skip
  those elements entirely (notehead + stem + beams + ledger + flags). Then the
  app hides the dragged note *cleanly* (theme-independent) while its own ghost
  follows — no background-colour trickery. Tiny, additive, no gesture change.

- **C10b (full): the view renders the live drag itself.** While a drag is in
  progress, paint the dragged element translated to follow the pointer — reuse
  the existing `resolveStaffTarget` / staff mapping for the vertical (pitch)
  position and the raw `localPosition` for horizontal — and suppress the
  original. A real "the note follows your mouse", no app-side ghost at all.
  Optionally a small `dragPreviewOpacity` / style knob. If you expose the drag
  as an overlay the app can also drop its `ghostTarget` bookkeeping for moves.

Either unblocks a true live drag; **C10a alone** already removes the ugly part
(the fake hide) and lets our existing ghost stand in properly. As with C1–C9,
mus CI builds against public `crisp_notation@main`, so the app can't call the new
input until it ships there — we'll wire it the moment it lands. Thanks!

> **Landed & wired (2026-07-13): C10a on `crisp_notation-public@main`.** Additive, no
> signature broke. `MultiSystemView` and `InteractiveGrandStaffView` gained
> `suppressElementIds: Set<String>` (→ the shared `LayoutPainter.suppressIds`);
> `paint()` skips those elements' primitives entirely — notehead, stem, flag,
> beam, ledger, curve — a **clean, theme-independent hide** with no ink bleed
> (works on the Petaluma font and coloured staves). Repaint-only; ids match on
> either staff. Pixel-tested (a green-coloured note's ink drops to ~0 when
> suppressed) + CONTRACT/CHANGELOG updated. **The app now hides the dragged note
> with `suppressElementIds: {_dragId}`** and lets its duration-matched ghost
> follow the pointer — the old `elementColors`=background trick is gone. **C10b**
> (the view paints the dragged glyph itself) remains an optional later polish;
> C10a makes the ghost stand in cleanly, so it's no longer needed for a correct
> live drag.

> **C10b landed & wired too (2026-07-13): `dragPreviewOpacity` on
> `crisp_notation-public@main`.** `MultiSystemView` / `InteractiveGrandStaffView`
> gained `double? dragPreviewOpacity`; when set, the view **owns the live drag** —
> it suppresses the dragged element and re-paints the *real* glyph (notehead,
> stem, accidental, flag, ledgers) translated to follow the pointer, snapped
> vertically to the target line/space (pitch) and free horizontally, faded to
> that opacity; the render object repaints itself on each drag update. The
> painter's per-primitive switch was refactored into a shared, opacity-aware
> helper (`paintLayout` byte-identical → all 122 goldens unchanged); a gesture
> pixel test drags a coloured note up and asserts its ink moves up. **The app now
> passes `dragPreviewOpacity: 0.85` and dropped its `suppressElementIds` + ghost
> bookkeeping for moves** — the note itself follows the cursor. The full C10
> (a+b) is done; no app-side drag fake remains.
