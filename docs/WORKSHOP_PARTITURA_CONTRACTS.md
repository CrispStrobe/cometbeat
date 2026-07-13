# Handover — interactive-editor APIs the Workshop needs from partitura

> **Reply from the partitura side (2026-07-13): C1–C5 all landed on
> `partitura-public@main`.** All additive; no existing signature broke. C6
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


**Audience:** an agent working in the `partitura` / `partitura-public` repos.
**Context:** the KlangUniversum (mus) app is building a full touch- **and**
desktop-first score editor ("Composition Workshop",
`lib/features/workshop/`). It drives an app-side editable model
(`ScoreDocument`) and renders through partitura. mus CI + local both resolve
`partitura-public`, so **every API below must land on `partitura-public@main`**
to be usable (a private-only addition compiles locally but reds CI).

The app already ships single-line editing (`InteractiveStaff`) and multi-line
viewing/selection (`MultiSystemView` with `onElementTap`). The gaps below block
drag-editing, range selection, a placement caret, and grand-staff/ensemble
editing. Please implement as **additive, backward-compatible** changes (new
optional params / new widgets); do not break existing signatures.

Conventions to reuse: `StaffTarget { int staffPosition; int measureIndex; Pitch
pitchFor(Clef, {int preferredAlter}); }`, element `id` strings, `PartituraTheme`,
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
movement → new `measureIndex`/order. partitura only reports; the app mutates and
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
  final PartituraTheme theme;
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
tweaks, and land them on `partitura-public@main`.

---

## C7–C9 — new asks (2026-07, blocking the editor's last three UX items)

The app already uses `EditorCaret`, `Slur`, `Hairpin`, `Lyric(verse:)`,
`Measure.pickup` (all landed — thanks). These three remain blocked purely
because the enabling API lives on the **private render object**, not the public
widget, and mus CI builds against **public `partitura@main`** — so the app
cannot call it until it ships publicly.

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
lookup, font bytes → data URI) is partitura-internal. Please add a
Flutter-side one-call export that takes a `Score` (+ theme + staffSpace) and
returns PNG bytes / an SVG string with the engraving font embedded, so the app's
**print / page-export** action is a single call (no viewport-capture hacks, no
re-deriving `LayoutSettings`). A `GrandStaff` overload too.

### C9 — (nice-to-have) hint for pickup rendering
`Measure.pickup` renders as expected. If a helper exists to number bars with the
pickup uncounted, expose it; otherwise no action.

Please land C7 + C8 on `partitura-public@main` and reply here; the app code for
all three UX items is written against these signatures and will flip on as soon
as they're public.
