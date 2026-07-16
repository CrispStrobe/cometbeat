# Workshop → editor parity — conceptual directions

Companion to [WORKSHOP_PLAN.md](WORKSHOP_PLAN.md) (the phase log, G1–G7). That
file records *what we built*. This one asks *why the remaining gaps exist* and
argues an order of attack. Ideas and directions — not a task list yet.

Convention (unchanged): we do **not** name or allude to other products anywhere
in code or docs, and we never frame the design as matching anyone. Interchange
**formats** are named only by their standard name / file extension. Below,
"the desktop reference class" means full-featured notation programs generically.

---

## The finding: 28 missing features, but far fewer real causes

A full inventory of the editor (2026-07-16) listed ~28 things the desktop
reference class has that we lack. Read as a list, that's a multi-year backlog.
Read causally, it collapses. **Four root causes explain almost all of it**, and
three of them are ours, not the renderer's.

The most important context for everything below:

> **`crisp_notation` already models nearly everything we're "missing".**
> `TupletSpan`, `Measure.voice2`, `keyChange`/`timeChange`/`clefChange`/
> `tempoChange` per measure, `startRepeat`/`endRepeat`/`volta`/navigation marks,
> grace notes, ornaments, notehead shapes, arpeggio, tremolo, ottavas, pedals,
> chord symbols, figured bass, annotations — all public, all engraved, all
> round-tripping through MusicXML.

We are not blocked on the library. We are blocked on **our own document model**,
which cannot *express* what the renderer can already *draw*. That reframes the
work from "build a notation program" to "stop throwing away what we already
have."

### Cause 1 — measures are derived, not real *(the load-bearing one)*

`ScoreDocument` is a **flat `List<EditorElement>` per part**; bars only come into
existence in `_packMeasures`, which greedily fills them at build time
(`score_document.dart:874`). A bar has no identity — it's a transient artifact of
packing. Everything that needs to *point at a bar* is therefore impossible:

| Missing feature | Why it's actually blocked |
|---|---|
| Mid-score key / time / clef / tempo changes | Nowhere stable to anchor a change; bar indices shift when you edit note 1 |
| Repeats, voltas, D.C./D.S./coda, barline styles | Same — they're bar-anchored properties |
| Insert / append / delete bar | Bars aren't objects, so they can't be operated on |
| Notes splitting + tying across barlines | The packer short-fills instead (`:811`) — a known silent wrong |
| Tuplets | A rhythmic container the flat packer can't express |
| Voices 2–4 | The packer assumes exactly one stream |
| Time sig limited to 2/4, 3/4, 4/4; key to ±4 fifths | Document-level singletons, so the pickers stay tiny |

That's **7 of the 28**, one cause. It also drives a second cluster: because
position is a *list index*, selection is an index range — which is why selection
can't be discontiguous and can't cross parts, and why the clipboard is per-part.

**Direction.** Promote the bar to a first-class object and make position a
**musical address `(bar, voice, tick)`** instead of a list index. Concretely:
a measure spine of `Bar` objects, each holding per-voice element lists, each with
a stable id. Selection becomes a **set of element ids**; the caret becomes an
address, not "after element *i*". This is the single highest-leverage change in
the whole document — it doesn't add features so much as *stop preventing* them,
and it maps 1:1 onto the `Measure` the renderer already wants.

It should come **before** the feature work it unblocks, not after, or we pay for
each feature twice.

#### The plan for Cause 1 (designed 2026-07-16; corrects three guesses above)

A design pass against the real code overturned three things this doc originally
assumed. All three are verified, not argued:

1. **The screen is already id-based** — so "a 2400-line consumer must be
   rewritten" is false. `selectIndex`, `measureIndexOf` and `moveByIdToMeasure`
   have **zero callers in `lib/`** (test-only); the *only* index-typed call site
   in the app is `moveByIdToIndex` (`composition_workshop_screen.dart:894`), and
   `computeDropSlot` **already returns `beforeId`** beside `index` (`:346`). The
   screen touches `.elements` exactly twice (`:489`, `:1038`), both pure
   in-order iteration with no index arithmetic. Selection needs no renderer work
   either: `highlightedIds` is already a `Set<String>`.
2. **~~Its own worktree~~ → land it on `main` in slices.** This doc's original
   advice was the risky part. Against **353 commits in 7 days** (12 workshop
   commits in 48h), a long-lived branch rewriting the hottest file accumulates
   exactly the conflicts nobody can mechanically resolve. What makes small
   merges possible: **spine + reflow reproduces `_packMeasures`' output
   byte-for-byte**, so the representation change is externally invisible and
   each slice merges same-day.
3. **~~Snapshot → command model~~ → don't.** A command/inverse model buys memory
   efficiency (irrelevant at the 256-note cap), coalescing, and collaborative
   editing (not a goal). It costs a correct inverse for *every* mutation, and
   undo bugs are **silent data loss**. It's the highest-risk, lowest-reward item
   here and the classic place this refactor dies. The actual user-facing bug —
   deleting an instrument is unrecoverable — is fixed by **lifting the snapshot
   stack from `ScoreDocument` up to `MultiPartDocument`** (snapshot all parts +
   names + transpositions + brackets), bounding it (~100; unbounded today), and
   restoring **in place** so the identity-derived caches stay sound. Add a
   `_transact(() {…})` helper so a compound edit is one undo step — ~10 lines,
   and the one genuine win the command model offered. Screen migration: two
   lines (`_doc.canUndo`/`undo` → `_mpd.*`).

**Rhythm is the subtle part.** Greedy spill and stable bar identity are
different editing paradigms and we need both — you cannot simultaneously have
"this key change is anchored to bar 5" and "a note in bar 1 reflows every
barline". So make it explicit policy on the document: `RhythmPolicy.spill`
(default, Sandbox — today's greedy reflow, byte-identical output) and
`RhythmPolicy.split` (Studio — an overflowing note splits into tied notes across
the barline; bars keep identity).

Split **explicitly in the model, not at build time**: store two tied elements
rather than one logical note that `buildScore` splits into two noteheads. Build-
time splitting would force one id → two noteheads, which breaks `highlightedIds`,
hit-testing, lyric anchoring and `DynamicMarking` — all of which assume id ↔
notehead 1:1. Splitting needs `List<NoteDuration> notate(Fraction)`; **the
library has no public one** (only private single-value lookups in the readers),
and since `NoteDuration` is base + ≤2 dots, 5/8 *must* become tied half+eighth.
Write it locally, propose upstreaming later.

**Under-full bars stay legal and unpadded** — "always full, pad the remainder"
would violate the Sandbox constraint (type 3 quarters in 4/4, get an unrequested
rest). Under-full becomes an addressable intentional state; Studio can badge it.
**Over-full bars** stay tolerated in the model (import must never fail) and are
prevented at the command level.

**The slice sequence** (0–3 and 6–8 never touch the screen, so they land while
other agents edit it; keep each under ~300 lines, rebase daily):

| # | Slice | Screen? |
|---|---|---|
| 0 | **Golden characterization tests** for `buildScore()` output ✅ **DONE** | no |
| 1 | Extract `_packMeasures` into a pure `reflow()` ✅ **DONE** | no |
| 2 | ~~`Bar` + `List<Bar>` as source of truth~~ **— see the refinement below** | — |
| 3 | Id-set selection internally; `selectByIds` becomes exact | no |
| 4 | `ScoreAddress` + bar-addressing API; caret as address | 2 lines |
| 5 | Global bounded undo + `_transact` | 2 lines |
| 6 | Mid-score changes → `buildScore` mapping (clef + key + time ✅ **DONE** + UI) | no |
| 7 | `RhythmPolicy.split` + `notate(Fraction)` + tie groups (default off) | no |
| 8 | Voice 2 → `Measure.voice2` | no |

#### Refinement (2026-07-16): element-id anchors, not a bar-spine flip

Doing slice 1 exposed the real cost of slice 2 as originally drawn: **~60
index-based mutation sites across 25 methods** all treat `_elements` as a flat
mutable list (`insert`/`removeAt`/`[i]=`/`removeRange`). Flipping the source of
truth to `List<Bar>` means rewriting all of them at once — the highest-risk edit
in the codebase — and, worse, it may be the **wrong** architecture: under the
default `RhythmPolicy.spill`, bars are reflowed on every edit, so a bar has *no
stable identity to anchor to*. A "key change on bar 5" is ill-defined the moment
bar 5's contents shift.

The cheaper, correct mechanism for a spill-mode editor is to **anchor
bar-attributes to an element id** (a side-map on the existing flat document) and
let `buildScore` stamp them onto whichever bar that element reflows into. The id
moves with its note, so the attribute rides re-barring for free — exactly the
property a bar index can't give. **This needs no mutator rewrite and no
source-of-truth flip.** Slice 6 (mid-score clef, shipped) proves it: a
`Map<String,Clef> _clefChanges` + a post-reflow pass in `buildScore`, with an
empty-map fast path so every golden stays byte-identical. Key/time changes
follow the same shape (time additionally teaches `reflow` to switch capacity at
the anchor — the one extra wrinkle).

So **slice 2 is retired** in favour of this. A first-class `Bar` object only
becomes worth its cost when we build `RhythmPolicy.split` (slice 7, Studio),
where bars genuinely keep identity; until then the flat model + id-anchors
carries every Sandbox feature at a fraction of the risk.

The index API survives as a **derived facade** (`elements` = bars flattened),
which works because flat order *is* spine order concatenated. Convert
`moveByIdToIndex` to `moveBefore(id, beforeId)` using the `beforeId`
`computeDropSlot` already returns, then delete the index API once tests migrate.

**Ranked risks.** (1) *The reflow-identity claim is load-bearing, and pickup is
the trap* — `_packMeasures`' capacity depends on `isFirst`, which flips inside
`flush()`; any divergence is a subtle wrong-bar bug. Slice 0's goldens are the
whole mitigation, which is why they went first. (2) Split ↔ id identity (above).
(3) **`buildGrandStaff` is a second, independent packing path** — it must ride
the same spine or the two views silently diverge; the goldens pin it too.
(4) Churn. (5) `maxNotes = 256` is a flat-count cap that wants to become a bar
cap.

**Defer:** tuplets (→ D), **voices 3–4 entirely** (crisp_notation's engine never
engraves them — `layout_engine.dart` has zero `voice3`/`voice4` references, so
plan for 2 engraved voices), multi-rest/measure-repeat/navigation, cross-part
selection (needs `MultiPartDocument` to own selection), and the shelf itself
(slice C is shelf-agnostic — that's E).

Realistic size: slices 0–3 are the de-risking core and ~40% of the work; slice 2
is the one that can't be rushed.

### Cause 2 — the editor has no modes

There is no note-input mode. The staff is *always* live for placement, so there's
no safe pointer state for navigating or inspecting (marquee-mode is the
workaround). Worse, the value strip is **dual-purpose**: picking a duration both
arms the next note *and* retroactively rewrites the selection (`_pickValue:850`).
The reference class universally separates two states — *input* (caret advances,
typing enters notes) and *select/object* (clicking selects, palettes apply to the
selection). That separation is what makes keyboard-first entry possible at all.

**Direction.** An explicit input-mode state machine, with the caret as a musical
address (Cause 1 pays for this). Mode is always visible in the status line. This
is what turns the existing shortcut set (A–G, 1–5, R) from a convenience into an
actual entry method — you can't do fluent keyboard entry while every click is a
note placement.

### Cause 3 — depth has nowhere to live

Every property lives in one `⌃` popup that only appears for a **single**-note
selection. That's why the last 15 element types have no UI: there's no surface to
put them on, and nobody wants toolbar button #40. Note the shape of this problem
— it's not 15 features, it's one missing surface.

**Direction.** A **selection-driven inspector** (a panel/sheet reflecting whatever
is selected). It scales to arbitrary element types at ~zero marginal UI cost, and
it's the standard answer in the reference class for exactly this reason. Pair it
with categorized palettes for *insertion* (dynamics, lines, repeats, text), the
inspector for *modification*.

### Cause 4 — the canvas defeats a renderer that's already correct

The lag is **not** the engine, and (after `22f9e5f`) it is **not** single-part.
`crisp_notation` carefully routes every interactive setter — `ghostTarget`,
`caret`, `highlightedIds`, `suppressElementIds` — to `markNeedsPaint`, and
early-returns on a value-equal document. Single-part hover therefore costs **zero
layouts**, correctly. Multi-part costs **~4 full layouts per rebuild, across 2
frames**, because our canvas defeats each guard in turn:

1. **A fresh `Future` every build.** `multi_part_canvas.dart:108` passes
   `MusicFonts.load(...)` inline to `FutureBuilder`; `music_font.dart:110`
   returns `Future.value(cached)` — a **new instance** each call, never `==`. So
   `FutureBuilder` resubscribes and rebuilds a second time, on a second frame.
   The snapshot is then **ignored** (`builder: (context, _)`) — it reads
   `metadataOrNull` instead. This buys nothing and doubles everything.
2. **`PageMetrics` has no `==`.** `page_layout.dart:12` declares no
   `operator ==`, so the fresh instance at `multi_part_canvas.dart:122` fails the
   render object's identity guard → `markNeedsLayout()` on *every* build, even a
   pure hover. This also makes the deep `MultiPartScore ==` walk pure waste: it
   correctly concludes "equal, skip relayout", and then `metrics` forces the
   relayout anyway.
3. **A discarded probe layout.** `multi_part_canvas.dart:190` runs a full
   `layoutMultiPartPages` and throws away everything but one height double.
4. **`buildMultiPart()` is the one un-memoized builder** — its `ScoreDocument`
   sibling has `_scoreCache`/`_invalidate` (`score_document.dart:205`);
   `MultiPartDocument` has no equivalent, so it re-allocates every `Measure` and
   element per call (`multi_part_document.dart:173`).
5. **`_onMpDragUpdate` was missed by `22f9e5f`** (`:511`) — it `setState`s
   unconditionally, so multi-part note-drag costs ~4 full layouts *per pixel*.
   Its single-part twin `_onElementDragUpdate:802` is correctly guarded.

**Direction.** The fix is to *stop calling layout*, not to make layout faster —
1, 2, 4, 5 are each a handful of lines and together should take multi-part hover
from ~4 layouts per tick to **zero**. Then decouple the canvas from screen-level
`setState` (a `ValueNotifier` for hover/caret + a `ValueListenableBuilder` around
the canvas only) so pointer traffic can't rebuild the parts strip and input bar.

**The remaining ceiling is a genuine library ask.** `crisp_notation` has **no
incremental layout**: one keystroke in bar 400 of a 12-part score re-engraves all
parts × all measures × 2–3 passes (`multi_system.dart:99-140`, `:412`). Fixes
1–5 make our *interaction* free; they don't make a large *edit* cheap. A
dirty-measure-range API (or reusing the "natural" pass across edits) is the
scaling story for big scores — worth opening as a contract, but **only after**
1–5, because right now we'd be optimizing an engine we're calling 4× more than
we need to.

---

## The thing that isn't on the feature list: we can't round-trip our own saves

Worth separating out, because it reads as a papercut and isn't. `Save` writes
MusicXML into the Song Book (`_save:1431`), but `loadScore` is **lossy by
construction**: voice 1 only, **chord → first pitch only**, ties and
articulations dropped (`score_document.dart:747`, `:765`).

So **save → reopen silently destroys the user's work.** There is no native
document format and no lossless round-trip. Before any parity feature: a score
editor you can't reliably save and reopen isn't one, and every feature we add
above this line inherits the data loss. Cheap-ish, and it's the credibility
floor.

(Adjacent, same theme: only MusicXML/`.mxl` export all parts — every other
format silently exports the **active part only** (`_generateExport:1157`). Same
class of quiet wrong. The multi-part *readers* all exist in the library; only
MusicXML has a multi-part *writer* — so this one is partly a library ask.)

---

## The strategic tension worth naming

This is a music-education app for ages 6+. **Parity with the desktop reference
class is the wrong goal if it's read as parity of *surface*.** A kid opening the
Workshop should not meet an inspector, a mode switch, and a 40-button palette.

The goal is **capability parity with progressive disclosure** — already the
stated intent in WORKSHOP_PLAN.md ("simple by default … yet scales"), but the
architecture is what makes it honest. Two shelves on one document:

- **Sandbox** — today's surface, ~unchanged. Glyph strip + piano. No modes.
- **Studio** — inspector, input modes, palettes, page view, full meters/keys.

One document model, one renderer, two densities. This is also the *reason* Causes
1–3 are worth paying for: a first-class measure spine and an inspector are
invisible to the kid surface and load-bearing for the other one. Feature work
that can't hide itself behind a shelf toggle should be viewed with suspicion.

---

## Suggested order of attack

Ordered by *unblocking*, not by size.

- **A · Make it fast** ✅ **SHIPPED** (`1d9c804`) — Cause 4, fixes 1–5. Multi-part
  hover/drag now costs **zero layouts** (verified by counters through the real
  rebuild path). The discarded probe measured **~155–247ms per rebuild**; that
  was the lag. The engine ceiling (no incremental layout) is untouched and is
  now the *only* remaining perf story — see G.
- **B · Make it trustworthy** ✅ **SHIPPED** (`20fa35e`) — `loadScore` is now the
  exact inverse of `buildScore` for everything the element stream can hold, so
  **save → reopen is lossless** (chords, ties, articulations, dynamics and the
  pickup all used to be destroyed); and the export sheet now names what each
  format drops instead of silently writing one part of four. Voices, tuplets and
  mid-score changes are still dropped on load — those the flat model genuinely
  can't express, and they're C's job, not a bug here.
- **C · Make the document real** ◐ **planned + slice 0 landed** — Cause 1:
  measure spine, `(bar, voice, tick)` addressing, id-set selection. The unlock.
  See the plan under Cause 1: land it on `main` in 9 invisible slices (**not** a
  long-lived worktree), keep the snapshot stack (**not** a command model) but
  lift it to `MultiPartDocument` so deleting an instrument stops being
  unrecoverable, and bound it. Slices 0–3 are the de-risking core.
- **D · Cash in the unlock** — tuplets, voice 2, mid-score key/time/clef/tempo,
  repeats/voltas, measure ops, cross-bar splitting, full meters and keys. Each is
  now small, and each is mostly *wiring to a renderer that already draws it*.
- **E · Make entry professional** — Causes 2+3: input modes, keyboard-first
  entry, the inspector, palettes. Rides on C's caret.
- **F · Make it sound** — playback is currently a fixed-tempo, rest-less,
  chord-less, active-part-only beep sequence (`_play:955`), which is odd given
  the library ships `playbackTimeline` / `soundingAt` / `TempoMap` and the app
  already owns audio. Real transport + moving cursor + per-part mute is mostly
  wiring, and it's disproportionately motivating for the target user.
- **G · Scale** — the incremental-layout contract, the 256-note cap, page/print
  view, PDF. Only meaningful once A–F land.

**A and B are independent of everything and should start now. C is the fork in
the road** — every feature in D built *before* C gets built twice.

---

## Open questions for the maintainer

1. ~~**Is Studio actually wanted?**~~ **Decided 2026-07-16: yes — two shelves.**
   Sandbox (today's kid surface, ~unchanged) + Studio (full capability), on one
   document and one renderer. So C–E are green-lit, and the shelf toggle is a
   design constraint on every later feature, not an afterthought.
2. **Where does the notation depth get taught?** If Studio exists, it's a second
   product surface with its own learnability burden — does it get primers /
   tutorials like the games do?
3. **How big is a realistic score?** The incremental-layout ask (G) is only worth
   opening if people write 30+ bars × 4+ parts. If real use is 8 bars × 2 parts,
   fixes A1–A5 end the performance story permanently.
</content>
