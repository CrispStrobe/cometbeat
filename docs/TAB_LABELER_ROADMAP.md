# Tab-labeler roadmap — toward >85% agreement AND −5% movement

Design handover for the symbolic tab-fingering labeler (`cstr/tab-labeler-onnx`;
trainer `onnx_runtime_dart/tool/tab_labeler/{extract,train}.py`; acceptance gate
`mus/test/tab_labeler_accept_test.dart`). Licence provenance + the corpus that
feeds it: `docs/CORPUS_LICENSING.md`. NOT legal advice.

## Where we are (measured on the 60-song / 8,715-position held-out benchmark)

| Model | sha (onnx) | agreement | movement vs heuristic |
|---|---|---|---|
| heuristic (no model) | — | 56.98% | — (4095, the min-movement baseline) |
| **7859** (960K, older) | `6e51a3595072` | 78.59% | +3.4% |
| **8270** (live on HF) | `f5f8ff8a5162` | 82.70% | +6.8% |

The model is the DP's **local emission** term only; `arrangeTab`'s Viterbi
**transition** term (`|Δfret|·cost.move`, default 1.0) + hard span cap
(`kHandSpan=5`) stay the arbiter. So movement is tunable at inference:

| `cost.move` | agreement | movement vs heuristic |
|---|---|---|
| 1.0 | 82.70% | +6.8% |
| **2.0** | **80.38%** | **+1.3%** |
| 3.0 | 79.00% | −0.2% |
| 6.0 | 77.06% | −0.4% |

**8270@move-2.0 (80.4% / +1.3%) dominates 7859@move-1.0 (78.6% / +3.4%)** on both
axes → the older model is a dominated fallback, not a real contender.

## 1. Keep BOTH models in the HF repo

Do it — cheap, good provenance, and the low-movement variant is a sane fallback
if a caller ships with default `cost.move`. Suggested layout in
`cstr/tab-labeler-onnx`:
- `tab-labeler.onnx` = current **8270** (unchanged default; decoder loads this).
- `tab-labeler-v1-7859.onnx` = the older `6e51a3595072` (+ its `.best.pt`).
- Model card: a "Versions" table with the frontier above, and **fix the stale
  metric** — the card still says 78.59%/+21.6 pts, but the live weights are 8270
  (82.70%). Note the recommended `cost.move≈2.0`.
Needs the owner's HF token (`huggingface-cli upload cstr/tab-labeler-onnx …`) —
outward publish, so run it with their creds.

## 2. Why `cost.move` alone can't reach the goal — and why TRAINING must change

The move-weight sweep tops out at **82.70%** (the move=1.0 ceiling). Pushing
`cost.move` only slides DOWN that curve (less movement, less agreement). So
**>85% agreement is unreachable by inference tuning** — it needs a stronger
emission model. And **−5% movement** (below the heuristic) at high agreement
needs a model whose Pareto frontier passes through that point. Both require
shifting the frontier up-and-left, i.e. a better/differently-trained model.

**The structural gap:** `train.py`'s loss is a **per-column, per-string
cross-entropy** (`per_string_ce`). It has **no cross-column term** — so the model
is literally blind to hand movement during training, even though its input is a
9-column window. It learns local idiomaticity and nothing about smooth paths;
the DP then has to clean up movement at inference, and at move=1.0 the emission
overpowers it (+6.8%). This is exactly the "use the algorithms in training too"
opening the user identified.

### The fix, ranked by effort

1. **Movement-smoothness regularizer (cheap — do first).** Add to the loss a
   term `λ · Σ_c |Ê_c − Ê_{c-1}|`, where `Ê_c` = the expected lowest-fretted fret
   ("hand anchor") from the model's per-string fret distributions at column c
   (differentiable: softmax-weighted fret index, min over strings via a soft-min
   or the played-string expectation). Trains emissions to prefer smooth paths →
   frontier shifts up-left. Sweep λ on the acceptance harness (it already reports
   agreement AND movement — the perfect selection metric).
2. **Span / biomechanical regularizer.** Add `μ · Ê[span_c]` (expected stretch =
   highest − lowest fretted fret, from the per-column distribution). This targets
   the one thing `cost.move` can NOT fix at inference: the model **replaces** the
   local term where `cost.span` lived, so within the hard cap it picks the shape.
   Training toward narrower shapes is the only way to bias span with a model
   present (or the small `arrangeTab` change in §4).
3. **DP-in-the-loop / structured training (the principled ceiling).** Train with
   a Viterbi-decoded loss (structured hinge or a CRF over the fingering lattice)
   using the SAME transition cost as inference. The objective becomes the
   **decoded path's** quality (human agreement + movement), not per-column
   accuracy — training and inference finally consistent. This is Sayegh's
   optimum-path paradigm folded INTO training: the model is rewarded for
   emissions that yield low-cost human-like PATHS. Higher effort; strongest
   route to >85%/−5%.
4. **Biomechanical-cost-weighted data.** Weight/oversample GuitarSet columns by
   playing-ease (Heijink & Meulenbroek 2002 biomechanical cost) so the model
   sees more of the idiomatic-and-easy region. Weak on its own; a complement.

**Honest caveat:** the GuitarSet human labels ALREADY encode the human's
movement↔comfort tradeoff. So more/better human data is the primary lever for
raw agreement; the regularizers above mainly (a) generalize to sequences/
positions the 6 players don't cover and (b) stop the model over-weighting local
idiomaticity at the expense of smoothness. Don't expect the regularizers alone
to add many agreement points — their job is to move the movement axis without
losing agreement, which is precisely the −5% goal.

### Recommended plan for the goal
(1)+(2) regularizers to shift the frontier, on the expanded data (§3 below), then
sweep `cost.move` to land the movement target; escalate to (3) structured
training if >85% doesn't fall out. Gate every candidate on the acceptance harness
(agreement AND movement), like now.

## 3. More training data — but DENSE (string,fret) is genuinely scarce

Current: **GuitarSet only** (~35k columns, 6 players; player 05 = val). The
labeler needs **dense per-note (string, fret)** ground truth. That is much rarer
than it first looks, and the sources split sharply:

**Dense, clean, directly usable (the real "more data"):**
- **EGSet12** (Zenodo 11406378, CC BY 4.0) — **verified GuitarSet-compatible**:
  its `.jams` carries **6 `note_midi` annotations (one per string)**, same shape
  `extract.py` reads (legacy dict-of-arrays — a trivial parse branch). 12 original
  pieces by a pro (axis-2 clean); ships `.gp` too (cross-check on string↔fret).
  Small — a 7th player/style, not a big volume bump, but genuinely dense + clean.
- **Guitar-TECHS** (Zenodo 14963133, CC BY 4.0) — audio-primary (hex/multitrack).
  Only dense-symbolic *if* it exposes per-string labels — CHECK before assuming;
  otherwise it belongs to the audio→tab TabCNN, not this labeler.

**⚠ NOT dense supervision — Mutopia `.ly` is sparse PARTIAL string pins.**
Correcting an earlier read: treble-clef **guitar staff notation is structurally
incapable of full (string, fret)** — a pitch sits on several fretboard positions,
so the notation underspecifies by design. The 47 `non-sa/` files with explicit
LilyPond string events (`\1`..`\6`) carry string marks on **under half their
notes even at the densest** (Sor Op.35 No.22: 65 string events / ~138 notes;
1,117 events across all 47). So Mutopia's role is **sparse string PINS**
(`Score.tabVoicings` pin the labeled notes; `arrangeTab` fills the unpinned
majority) + arranger pseudo-labels — **not** a per-note training set like
GuitarSet. Do not count it as dense labels. (And `sa/` is copyleft — CC-BY model
must use `non-sa/` only, regardless.)

**Where dense fret actually lives historically: tablature — a separate, harder
avenue.** Only *tablature* gives a fret at every note. For the guitar family that
is the EARLIER repertoire — lute, vihuela, Baroque guitar (Milán, Sanz, de Visée,
Dowland): fret-numbers-on-string-lines, centuries PD, and *easier* for vision
than staff notation (a grid of plain digits, no circle-vs-fingering ambiguity).
The catch: the modern *encodings* (ECOLM, Gerbode) are NC/unlicensed, so the
clean route is **OMR/vision on the PD original prints** — a real project, and
tuning/instrument differs from 6-string guitar. Flag as a distinct data avenue,
not a quick win.

**Vision/OMR is WEAKER for guitar strings than expected.** On image-only sources
the target is the *string number* (the circled ①–⑥), but a bare digit above a
note is ambiguous between **left-hand finger (0–4)** and **string (1–6)** — the
only disambiguator is a small circle glyph that scan noise / OCR easily loses.
So for the 47 Mutopia files vision earns nothing (labels are already in the
`\N` events); it only pays off on image-only tablature, where the grid is clean.

**Augmentation:** transposition exists (`AUG`). Add valid **string-shift**
augmentation (a shape moved to an equivalent string set where pitches allow) to
fill fretboard/inversion coverage — idiomatic transforms only.

**Bottom line on data:** dense clean symbolic fingering is basically GuitarSet +
EGSet12 (+ Guitar-TECHS, roundtrip-verified). Because the well is shallow, the
**biomechanical-aware training (§2) and augmentation matter more than usual** —
they are how you generalize from few players rather than collect more. Val is a
held-out PLAYER and the gap is generalization, not fit (train 82.6 / val 80.8),
so squeezing generalization out of limited dense data is the game.

### REDACTED's credited sources — traced (REDACTED.org/credits.htm, 2026-07-21)

Traced every music link on REDACTED's credits page to see if a clean *symbolic*
(string,fret) source hides among its provenance. **It does not** — the sources
split into three groups, none of which is dense string/fret gold:

- **Other hobbyist TAB archives** (same contested profile as REDACTED —
  amateur transcriptions of PD works, no explicit licence): REDACTED.com,
  delcamp.net, REDACTED.net (On-Line Guitar Archive), REDACTED.org, REDACTED.com,
  REDACTED.com, REDACTED.de, REDACTED.com/CGCL, REDACTED.org,
  REDACTED (archived). ASCII/tab → has (string,fret), but the same
  §3-Schöpfungshöhe / §44b-TDM question as REDACTED, and same noisy-amateur
  caveat. Not cleaner than REDACTED itself — so not a *training* source.

  **⚠ Correction + a REDACTED (eval-only) exception — REDACTED.com.**
  Earlier filed as "ASCII tab"; it actually publishes **`.gpx` (Guitar Pro)**
  next to PDF + MIDI — `REDACTED.com/gpx/<name>.gpx`, **229+ pieces** on the
  index, composers all long-PD (Sor, Bach, Tárrega, Aguado, Coste, Carcassi,
  Giuliani, Carulli). `.gpx` carries **full explicit (string, fret) per note**,
  and **we already import it** (`scoreFromGpif`), so each file → (pitch-window →
  string/fret) columns in the `acceptance.json` schema, exactly like the IDMT NC
  set. Licence: no explicit grant (about page bot-blocks; hobbyist transcriptions
  → §3/§44b contested, same as REDACTED). So **NOT for the shipped model's
  weights** — but for a **REDACTED generalization benchmark** (produces
  numbers only, never trained on, never shipped) it sits in the same eval-only
  tier as IDMT (CC BY-NC-ND). Cleaner than IDMT on axis 2 (PD classical vs
  original recordings), richer labels than ASCII. Keep the primary ship gate on
  GuitarSet player 05; use REDACTED `.gpx` + IDMT as secondary OOD checks.
- **MIDI archives** (pitch only — no string/fret; and NOT clean):
  **REDACTED.com** — 5,641 MIDIs, but *"Copyright François Faucher
  1998–2025,"* **no licence**, and includes still-in-copyright composers
  (Villa-Lobos d.1959, Piazzolla d.1992). midiworld.com, kunstderfuge.com
  (largely subscription/restricted), guitarist.com. Pitch pseudo-labels at best,
  with a sequencer copyright claim on top.
- **Institutional PD facsimile collections** (cleanest on *both* axes — genuinely
  PD works, PD scans — but **PDF images of STAFF notation**, so pitch-only after
  OMR, NO string/fret): **Ophee Collection** (Appalachian State — 500+ PD first
  editions of Sor/Giuliani/Carcassi, *"digitized files of public domain music,"*
  credit requested); **Boije** (Swedish Music & Theatre Library, ~early-19thc.
  guitar); **Rischel & Birket-Smith** (Danish Royal Library); **IMSLP**;
  **Mutopia** (already assessed — CC BY-SA/BY/PD, `.ly`). These are the clean
  route, but only via OMR → pitch → arranger pseudo-labels, never direct
  string/fret.
- (Non-sources on the page: dolmetsch / musictheory.org.uk / vt.edu = theory
  references; google-groups / reddit / facebook / vk / gametabs = forums.)

**Conclusion:** tracing REDACTED's provenance confirms §3 above — there is **no
clean dense (string,fret) symbolic source** in the classical-guitar web. The
tab archives all carry REDACTED's contested profile; the genuinely-PD material
is staff-notation facsimiles (pitch-only, OMR-gated) or copyright-claimed MIDI.
So the clean dense data really is GuitarSet + EGSet12 + Guitar-TECHS, and the
classical-guitar web is a **pseudo-label / weak-supervision** tier at best —
reinforcing the generate-and-augment strategy over sourcing.

## TL;DR
- Keep 7859 + 8270 both on HF; fix the stale card; recommend `cost.move≈2.0`.
- Inference tuning caps at 82.7% — **>85% needs a better model.**
- Add a **movement-smoothness + span regularizer** to the loss (the model is
  currently movement-blind), and/or **DP-in-the-loop structured training** — this
  is "honour the optimum-path/biomechanical optima in training," done right.
- Dense clean data is basically **GuitarSet + EGSet12** (verified compatible);
  **Mutopia is sparse PINS, not dense labels** (guitar staff notation can't carry
  full string/fret). Full historical fret data lives in **tablature** (PD lute/
  Baroque-guitar prints, via OMR — a separate harder avenue; modern encodings are
  NC). So generalization from few players (§2 regularizers + augmentation) matters
  more than chasing volume.
