# Freely-licensed music corpora — sourcing & licence findings

Working notes for sourcing bundle-able ("Tier A") song/score/tab data for
CometBeat, a **COMMERCIAL** children's music app shipping in **Germany**.
**NOT legal advice.** Anything commercial-critical wants a Fachanwalt für
Urheberrecht sign-off (§3/§4 UrhG exposure + the axis-2 questions below).

Last updated 2026-07-21. Some leads remain unverified — the research sweep hit
the weekly API limit (resets 07-25) and the VPS holding the downloaded corpus +
`LICENSES.md` was unreachable. Verified vs. pending is marked throughout.

## The test every candidate must pass — TWO axes

A dataset qualifies for **shipping** only if BOTH are clean:

- **Axis 1 — the encoding/transcription licence.** CC0 / CC BY / MIT / ISC = ok;
  CC BY-NC / research-only / unstated = not. (CC BY-SA and the CPDL License are
  ok **but copyleft** — a bundle inherits share-alike.)
- **Axis 2 — the underlying work.** EU term is **life+70**, and for co-written
  works it runs from the **last surviving** author (Term Directive art. 1(6)).
  We ship in Germany, so **US public domain ("published before 1929") is NOT
  sufficient** — many US-PD sources are still protected in the EU.

A CC0 transcription of an in-copyright song is **axis-1 clean, axis-2 fail** —
that split is the trap that sinks most candidates. The two clean shapes are:
(a) a permissive transcription of a **long-PD** work, or (b) audio/notation
**created for the dataset itself** (no third-party work underneath).

## Our import reach — format is rarely the blocker; LICENCE is

App import filters (verified in code, `import_screen.dart` /
`composition_workshop_screen.dart` / `tab_workshop_screen.dart`):

| Format | ext | into |
|---|---|---|
| MusicXML (+zip) | musicxml / xml / mxl | full Score |
| MIDI | mid / midi | full Score |
| ABC | abc | full Score |
| MEI | mei | full Score |
| **Humdrum kern** | krn | full Score (rare in consumer apps — our edge) |
| MuseScore | mscx / mscz | full Score |
| Guitar Pro (GPIF) | gp / gpx | full Score + **tab** |
| ChordPro | cho / pro | chord sheet |
| JAMS | jams | chords + melody |
| ASCII tab | (text) | tab Score |

In-library but **not UI-wired**: `scoreFromSemantic`, `scoreFromLilyNotes` — the
cheapest possible "new filters" (parser exists, only wiring missing). But note
their poster-child corpus (PrIMuS) is licence-blocked, so wire them only when a
cleanly-licensed source in those encodings turns up.

## Two strategic findings

**TABS: don't source them — generate them.** Every large Guitar-Pro corpus is a
scrape of in-copyright songs (DadaGP, ~26k, research-access-only, from Ultimate
Guitar — both axes dirty). BUT we own `arrangeTab` + `gpFretPlanFor` +
`scoreToGpif` + the `tabconv` CLI: we **manufacture playable tab from any
score**. So the tab corpus == the clean score corpus run through our arranger.
Zero third-party tab licensing needed.

**The academic classical corpora are a NonCommercial trap.** The "obvious"
symbolic-classical route (kern/ABC editions of Bach, Mozart, Beethoven) is
almost uniformly CC BY-NC-SA — axis-2 clean, axis-1 fail. Verified across 8
repos below. Reachable, but dev/test only.

---

## VERIFIED — shippable (Tier A)

All licences below read verbatim from the source's own LICENSE file / legal page
(or, for PDMX, its metadata), this effort.

### Already downloaded, on the VPS (`/mnt/volume1/jams-corpus/tierA`)

| Dataset | Files | Axis 1 | Axis 2 |
|---|---|---|---|
| GuitarSet | 360 jams | CC BY 4.0 (Zenodo API) | recorded FOR the dataset — nothing underneath ✅ |
| Harmonix | 912 jams | MIT | beat/segment timestamps only ✅ |
| jams-pkg | 7 jams | ISC | synthetic ✅ |
| OpenEWLD-eu-pd | 87 works / 103 mxl | MIT | author-death filtered to EU-PD ✅ (defensible, not "cleared") |

### New, verified-clean, format-reachable (no new code needed)

| Source | →reach | Axis 1 | Notes / axis-2 |
|---|---|---|---|
| **OpenScore Lieder** | MusicXML | **CC0** (LICENSE.txt) | 1,200+ 19th-c. art songs, multi-part + lyrics. **Top pick.** Needs composer+poet death-filter (below). |
| **OpenScore String Quartets** | MusicXML | **CC0** (LICENSE.txt) | Chamber, PD composers. Smaller, same clean profile. |
| **PDMX** (is_original slice) | MusicXML | **CC0**, 7,549 (metadata, offline) | Original amateur compositions. Self-attested → wants a dup pass. |
| **Mutopia** | .ly / MIDI | **CC BY-SA / CC BY / PD — all commercial-OK** (legal.html) | Per-piece licence + editor-rights filter; BY-SA copyleft on a bundle. |
| **CPDL / ChoralWiki** | MusicXML/MXL where offered | **CPDL License = commercial + share-alike** (copyleft); editions also CC / PD | Choral/vocal — strong for a SINGING app. Per-edition filter; §3 engraving + US-PD cautions. |
| **GregoBase** | GABC (needs converter) or its MusicXML export | **CC0** | Gregorian chant; axis-2 trivially clear. Niche for kids. |

**Detail worth keeping:**

- **PDMX** — 254,077 MuseScore scores. The headline "public domain" is mostly the
  **PD Mark** (210,364) — a *claim*, not a grant. Only 43,713 are real **CC0**;
  33,142 of those carry no `license_conflict`. But CC0 covers the ENGRAVING only:
  the clean-CC0 set still contains "Seven Nation Army", "Light of the Seven",
  "Crimson Peak – Edith's Theme" (in-copyright songs, axis-2 fail). The
  `is_original` flag is the axis-2 filter → **CC0 ∧ no-conflict ∧ is_original =
  7,549** clean on both axes. Self-attested, so "defensible", not "cleared".
- **Mutopia** — all three licences permit commercial use. Native guitar `.ly`
  files are mixed: e.g. Aguado Op. 11 No. 6 (`Mutopia-2016/01/15-2097`, CC BY-SA
  4.0, plate-backed to S. Richault 6713.R.) carries sparse editor cues (one
  explicit LilyPond string event `\2`, some left-hand fingerings) and its
  `TabStaff` is commented out ("tabs are not completely developed"). Treat as
  clean score material + sparse string cues, not full tab gold. For our tab
  labeler, LilyPond string-number events (`\1`..`\6`) are the useful labels:
  fret is derivable from note pitch + string. Left-hand finger numbers are only
  auxiliary context.
  Automated scan: `tool/mutopia_guitar_scan.py` against local
  `/Users/christianstrobele/code/mutopia-guitar/manifest.json` downloaded 361
  primary `.ly` sources from 388 guitar entries; 27 derived source URLs were 404.
  Classification: 6 `dense_string_labels`, 20 `weak_string_labels`, 21
  `sparse_string_labels`, 36 `fingering_only`, 84 `tabstaff_score_only`, 194
  `score_only`, 27 `unscanned`. Strongest direct
  string-label candidates are `capricho-arabe` (229 string events),
  `moonlight-guitar-duo` (90), `sym5-1-guitar-duo` (79),
  `wtk1-prelude1-guitar-duo` (73), `claro-de-luna` (69), and
  `sorf_op35_no22` (65). Reports:
  `/Users/christianstrobele/code/mutopia-guitar/reports/mutopia_guitar_ly_scan.{json,csv}`.
  Conclusion: useful, but not GuitarSet-scale gold. Use dense files as direct
  string/fret supervision, weak/sparse string files as lower-weight supervision,
  and score-only pieces for arranger-generated pseudo-label pretraining before
  GuitarSet fine-tuning.

Tabs for **every** row above come free via our own `arrangeTab` — see the tab
finding. So the shippable *tab* corpus is exactly this shippable *score* corpus.

---

## VERIFIED — rejected

| Source | →reach | Why rejected |
|---|---|---|
| craigsapp kern (Bach 370 chorales, Mozart sonatas, Joplin) | krn | **CC BY-NC-SA** (LICENSE.txt, verbatim) — NC |
| DCML (ABC, Mozart, Beethoven sonatas) | ABC/mscx | **CC BY-NC-SA** (LICENSE, verbatim) — NC |
| **JRP (Josquin Research Project)** | krn | **CONFLICTED** — LICENSE.txt header says "CC-BY-SA 4.0" but the URL beneath is `by-nc`. Unsafe → treat as NC. |
| **PrIMuS / Camera-PrIMuS** | MEI (already!) / semantic | **UNSTATED = all rights reserved**. RISM-derived, 87,678 incipits. (Ships MEI, so never a filter problem — a licence problem.) |
| **GOAT** (Guitar On Audio and Tablatures) | tab/MIDI/audio | **CC BY-NC 4.0**, restricted files, Zenodo 10.5281/zenodo.15690894; description says research-only, not for commercial products. Tempting (paired string+fret supervision) but NC. |
| DadaGP + all GP tab archives | gp | research-access-only, UG scrape of in-copyright songs |
| **thesession.org** (+ folk-rnn, folk-rnn-webapp, themachinefolksession) | ABC | dump is **ODbL + anti-LLM clause** (2025-10, tightened 2026-06). folk-rnn's MIT is code-only; it scraped thesession ~2015 when the dump had **no licence at all**. ODbL on a bundle → share-alike (§4.4) + source-offer (§4.6) + attribution (§4.3); §2.4 disclaims rights in the transcriptions, which vest in each **transcriber**. |
| German folk-song sites (4) | — | volksliederarchiv.de (private/non-commercial, notation walled off in robots.txt); lieder-archiv.de (copyright on its Notensätze; commercial/DB/republish forbidden — but offers a PAID licence); liederlexikon.de (all-rights-reserved, NOT CC, named living engraver + in-copyright 20th-c. works); ZPKM Freiburg (catalogues only). |
| **Essen Folksong Collection** (ccarh/essen-folksong-collection) | krn ✅ | **CCARH MuseData licence** (license.txt, verbatim): *"this license does not authorize the use of the enclosed MuseData files in the production of derivative editions intended for commercial distribution, nor for public performance (including broadcast), nor for sound recording."* NC + no-recording → dev/test only. ~20k folk melodies, German-relevant, but blocked. |

---

## Tab pipeline — datasets to IMPROVE it (symbolic→tab, audio→tab)

Different goal from bundling: training/eval data to make the tab pipeline
better, not content to ship. Licence logic shifts slightly — for a model shipped
in a commercial app, **CC BY / CC0 = trainable; CC BY-NC = eval/dev only; ND =
can't even derive.** Axis 2 is usually clean here because the audio is recorded
**for** the dataset (no third-party song underneath) — GAPS is the exception
(YouTube-linked real performances).

**The highest-value "improve" move needs no new data — it re-uses GuitarSet as a
BENCHMARK for our arranger.** Every note in GuitarSet's JAMS carries the
string+fret a real guitarist chose. Extract (pitch-sequence → human string/fret),
run our own `arrangeTab` on the same pitches, and measure agreement + playability.
That turns GuitarSet (CC BY 4.0, already on the VPS) from "content" into a
quantified quality metric + regression benchmark for symbolic→tab — the "improve,
not just use" the arranger currently lacks (it has a cost model, no ground truth).

### Datasets (verified via Zenodo API this session)

| Dataset | Zenodo | Licence | Use for |
|---|---|---|---|
| **GuitarSet** | 3371780 | **CC BY 4.0** | GOLD. `.jams` w/ note+string+fret ground truth → arranger benchmark AND audio→tab train. Have it. |
| **EGSet12** | 11406378 | **CC BY 4.0** | **`.gp` + `.jams`**, 12 solo electric pieces, **original — composed by the author** (axis-2 clean). Tiny (~6 min) but BOTH-axes clean, both formats we import, real string/fret. ✅ shippable + trainable |
| **Guitar-TECHS** | 14963133 | **CC BY 4.0** (4.1 GB) | electric; techniques + excerpts + chords + scales, diverse hardware. audio→tab + technique. ✅ trainable |
| **AG-PT-set** | 10159492 | **CC BY 4.0** (6.7 GB) | acoustic; 12 playing techniques, onset-labeled (10h). technique detection. ✅ trainable |
| **EGDB (rendered)** | 12674910 | **CC BY 4.0** (1 GB) | 240 electric tracks; tone/effect robustness (FX-removal variant). ✅ trainable |
| **Five guitar dataset** | 4988354 | **CC BY 4.0** | 30 perfs, multi-setup (DI/mobile). ✅ trainable |
| **FiloBass** | 10069709 | **CC BY 4.0** | jazz bass transcriptions — only if we extend to bass. ✅ |
| **ToqueFlamenco** | 804050 | **CC BY 4.0** | flamenco falsetas + MIDI manual transcriptions. ✅ |
| **GAPS (Guitar-Aligned Performance Scores)** | 17152440 | **CC BY-NC-SA** | aligned MIDI + scores + downbeats; THE audio→score set. ❌ NC → eval/dev only, not the shipped model |
| **IDMT-SMT-Guitar** | 7544110 | **CC BY-NC-ND** | classic transcription set; NC **and** ND → ❌ dev/test only |

**For the audio→tab effort** (another agent is on a TabCNN/OMR path — see
`tabcnn_emitter.dart`, `audiveris/`): the CC-BY training expansion of the
GuitarSet-only TabCNN is **Guitar-TECHS + AG-PT-set**. **Do NOT train the
shipped model on GAPS or IDMT-SMT-Guitar** (NC) — use them only to evaluate.

**Fingering (left-hand finger 1–4), not just fret:** GuitarSet gives string+fret
(→ position), from which fingering can be *derived* but is not labelled. No clean
CC-BY explicit-fingering guitar corpus surfaced this pass — flag as a data gap if
the arranger is to output finger numbers, not just frets.

### String/fret ground-truth by FORMAT (the user's question, answered)

Where clean (both-axes) explicit string/fret supervision actually lives, per
format we import. The useful label is **string number** — given pitch + string,
fret is deterministic; left-hand fingering is only auxiliary.

- **`.jams`** — **GuitarSet** (large, CC BY, string+fret) + **EGSet12** (12,
  CC BY, string/fret via its paired `.gp`). That is essentially the entire
  clean JAMS-with-string/fret universe — JAMS guitar annotation is rare, and
  everything else that surfaced was effects/tone (GUITAR-FX, EGFxSet) with no
  fret data, or NC (IDMT).
- **`.gp` (Guitar Pro)** — `.gp` encodes string+fret inherently, but every large
  archive is a UG scrape of in-copyright songs (DadaGP, research-only). The ONLY
  both-axes-clean `.gp` found is **EGSet12** (12 original pieces). So clean `.gp`
  data = EGSet12 + whatever **we generate ourselves** via `scoreToGpif`.
- **`.ly` (LilyPond)** — **Mutopia**, scanned by `tool/mutopia_guitar_scan.py`:
  **47 files with explicit LilyPond string events (`\1`..`\6`), 1,117 events
  total** (6 dense / 20 weak / 21 sparse); densest `capricho-arabe` (229),
  `moonlight-guitar-duo` (90). The 36 `fingering_only` files are NOT string/fret
  labels. This is the main `.ly` string-label source; useful but not
  GuitarSet-scale — dense files as direct supervision, weak/sparse as
  lower-weight, score-only as arranger-pseudo-label pretraining.
- **`.mei`** — **GAP.** MEI's `<tabGrp>` module encodes string+fret+finger
  natively and historical lute/guitar tab is long-PD, but **no accessible CC0/
  CC-BY MEI-tablature *data* corpus surfaced** (the TabMEI org is empty; the lute
  repos found are editors/converters, e.g. ECOLM's `ecolmeditor` (GPL code), not
  licensed encoded corpora). Historical lute tab is also 6-course, non-guitar
  tuning — marginal for a guitar app even if a corpus turned up. Treat `.mei`
  string/fret as not-currently-available rather than promising.

**Net:** the clean string/fret world is small and concentrated — GuitarSet
(`.jams`, the anchor) + EGSet12 (`.gp`+`.jams`) + Mutopia's 47 `.ly` files. This
is *exactly* why the "generate tabs from clean scores via `arrangeTab`" strategy
matters: sourced ground truth alone won't scale a fret/fingering model.

### Tab-labeler model — SHIPPED, and how this corpus work feeds it

The symbolic→tab labeler is built and published: `cstr/tab-labeler-onnx` (HF),
trainer at `onnx_runtime_dart/tool/tab_labeler/{extract,train}.py`, acceptance
gate `test/tab_labeler_accept_test.dart`. It's the "improve the arranger"
direction, done: a tiny CNN scores `(string,fret)` placements so `arrangeTab`'s
Viterbi fingers like a human. Same `[6,21]` contract as the audio→tab TabCNN, so
the shipped decoder consumes both.

**Licence provenance — verified clean.** Trained **only on GuitarSet (CC BY 4.0)**
(`extract.py` reads GuitarSet JAMS; val held out on player 05). HF card is
`license: cc-by-4.0` and attributes GuitarSet verbatim (*"Trained on GuitarSet
(Xi et al., ISMIR 2018, CC BY 4.0) — derived weights redistributable with
attribution. No DadaGP / no request-gated data."*). So the shipped model is
commercial-clean **provided the app carries the GuitarSet attribution** (add it
to the About/licenses registry alongside Bravura OFL).

**Measured result (my run of the promoted `8270` model, 60 held-out songs /
8,715 positions):** human-fingering agreement **56.98% (heuristic) → 82.70%
(model), +25.71 pts**, at ~equal hand movement. The model never emits tab — it
only scores positions the arranger enumerates, so playability invariants hold.

⚠ **Stale model card:** the HF card documents **78.59% (+21.6 pts)** — an earlier
model. The promoted weights (`8270`) now measure **82.70% (+25.71 pts)**. Update
the card, and confirm which weights are actually live on HF (there's a local
`hf-upload-8270` dir).

**How the corpus findings extend it (clean training expansion):**
- **EGSet12** (CC BY 4.0, `.jams`+`.gp`, original) — new clean per-string data
  beyond GuitarSet's 6 players. Tiny, but adds a 7th player/style at zero licence
  cost. Fold into `extract.py`'s GuitarSet glob.
- **Mutopia `.ly`, `non-sa/` only** — the 47 string-labeled files (`tool/
  mutopia_guitar_scan.py`) are extra symbolic supervision, BUT the **CC BY-SA
  subset is copyleft** — training a CC-BY model on it risks forcing share-alike.
  The `sa/` vs `non-sa/` split exists for exactly this: **only `non-sa/` (CC BY /
  PD) may feed the shipped CC-BY model**; `sa/` files are eval-only unless the
  model itself goes BY-SA.
- **Guitar-TECHS / AG-PT-set (CC BY)** — for the *audio*→tab TabCNN, not this
  symbolic labeler.

## Still unverified

- **RISM open data** — the layer *under* PrIMuS; a possible MEI unlock if its
  incipits carry a clean CC licence. Could NOT verify: rism.online is a JS SPA
  that returns an empty shell to fetchers and hangs on curl; the static
  open-data pages 404. Widely *reputed* CC0, but unconfirmed — do NOT rely on
  memory. **Low priority** anyway: incipits are short fragments, less useful
  than full scores, and the PrIMuS route is licence-blocked regardless.
- (**Meertens resolved → rejected**: **CC BY-NC-SA 3.0** Unported, verbatim from
  liederenbank.nl — *"Meertens Tune Collections by Meertens Instituut is licensed
  under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported
  License."* NonCommercial. kern/MIDI/LilyPond, so reachable — but dev/test only.)

(**Essen resolved → rejected**, see table above: CCARH MuseData = NC.)

## The recurring German-law point (from multiple sources, incl. the sites themselves)

Even for a PD tune, a **modern Notensatz / arrangement carries its own fresh
copyright** (§3 UrhG), and a curated collection carries a **database right**
(§4 / §87a-e UrhG). "gemeinfrei" / "GEMA-frei" ≠ "free to bundle". **Lyrics
clear separately** from melody and often later. This is why OpenScore Lieder
needs a composer-**and**-poet death check, and why CPDL/Mutopia need a per-item
filter that also considers the modern editor.

## Recommended next actions (when limits + VPS return)

1. **OpenScore Lieder, death-date filtered** — reuse the OpenEWLD Wikidata filter
   on **both** composer and poet (a sampled 8 Lieder poets all died pre-1948:
   Campbell 1914, Coleridge 1907, Crewe-Milnes 1945, Davidson 1909, Evers 1947,
   Eschelbach 1948, Falke 1916, Fallström 1937 — encouraging, but a sample).
   Highest-value clean growth: CC0 + filterable + real repertoire with lyrics.
2. **PDMX is_original slice** — fetch the 7,549, add a dup/plagiarism pass.
3. **Self-engrave German Kinderlieder** from pre-1900 PD facsimiles (Erk/Böhme
   *Deutscher Liederhort*, Zuccalmaglio) into our own MusicXML via crisp_notation
   — sidesteps every third-party encoding/DB claim, and is the only clean route
   to the German children's-song repertoire the app actually wants.
4. Fetch the CC-BY tab-training sets (Guitar-TECHS 14963133, AG-PT-set 10159492)
   and build the GuitarSet arranger-benchmark (see tab-pipeline section).
5. rsync the corpus off `/mnt/volume1` (VPS-local, not backed up) to
   `/mnt/storage`.

## Preserving fingering/fret/bowing — the performance layer (2026-07-21)

Regenerating fingering algorithmically loses the human choice, so sources that
*retain* it are worth more. Structural finding across a five-instrument sweep:
**no openly-licensed corpus is simultaneously (a) at scale, (b) clean for a
commercial EU/German ship, and (c) carries a real string/fret/finger/bow layer.**
The layer must be **authored, or taken from a dead-editor source**, never
harvested from a modern edition.

### Sources that DO carry fingering and are shippable
- **NIFC Chopin First Editions** — `github.com/pl-wnifc/humdrum-chopin-first-editions`,
  **CC BY 4.0** (verified). 188 `.krn` files carry populated `**fing` spines
  (~65k finger tokens). Fingerings are from 1830s first editions → the fingering
  layer itself is PD; only the encoding needs CC BY attribution. Companion
  `humdrum-polish-scores`, same terms. **Best off-the-shelf fingered source found.**
- **Mutopia Burgmüller Op.100** (`ftp/BurgmullerJFF/O100/25EF-*`) — **Public
  Domain**, ~18 études with genuine LilyPond note-attached fingering (`e8-5`).
  In reach today via the LilyPond reader.
- **LilyPond PD snippets** (`fretted-strings` set) — 31 fragments, genuinely PD
  (the LilyPond README carves `snippets/` out of GFDL/GPL into public domain).
  Tab-notation teaching examples, not repertoire.
- **Cellofun.eu Bach Suites playing edition** (on IMSLP, BWV 1007/1009/1010/1012)
  — fingering + bowing, tagged "PD dedicated" but the site footer says
  "Copyright 2023". **Gated:** confirm the IMSLP uploader is the author, get
  written CC0 confirmation, and open the ZIP to check the markup is encoded (not
  baked into a PDF) before relying on it.

### Disqualified fingered sources (verified)
PIG (academic-only, walled), MAESTRO/ASAP/SMD/Batik/TRIOS (CC BY-**NC**-SA),
Gerbode lute 20k (CC BY-NC-SA), SCORE-SET (CC BY-NC-SA; arXiv metadata *wrongly*
says CC-BY), ECOLM / E-LAUTE / SyncViolinist (no data licence), URMP/Bach10 (no
licence), Suzuki (all-rights + trademark). **Corrections to earlier notes:**
GAPS has **no licence file at all** (not "CC-BY-NC-SA"); PDMX is **CC BY 4.0**,
not CC0 despite the name; MusicNet's Zenodo release is now CC BY 4.0 (pitch only).

### The dead-editor strategy (the general solution, all instruments)
A modern editor's fingering on a PD work is a fresh §2/§70 contribution — but an
editor **dead before 1955** has an EU-clear editorial layer too. So an OMR/vision
pass over a *dead-editor* PD scan yields notes AND authentic period fingerings,
owned outright. Candidates (death year → editorial layer PD): cello — Grützmacher
1903, Klengel 1933, Feuillard 1935; piano — Köhler 1886, Ruthardt 1934; guitar —
19th-c. first editions (Boije scans). Keep a per-score provenance record
(edition, first-publication year, editor death year) as the §70 audit trail —
the DB manifest schema already carries these fields.

### OMR capability audit + a vision-LLM result
- **Our OMR models do NOT emit fingering.** Verified in source: the
  `semantic` / `bekern` / `lilynotes` converters
  (`crisp_notation_cli/lib/omr.dart` + `crisp_notation_core/.../omr/`) contain no
  fingering/technical parsing. They recover pitch + rhythm only. But the target
  model **can hold it** — `NoteElement.fingerings: List<int>`
  (`core/lib/src/model/element.dart:163`) and `TabVoicing` for strings exist.
  So the pipeline can carry fingering the OMR step throws away.
- **A vision-LLM can read the fingerings the OMR model ignores — tested.**
  Rendered Burgmüller Op.100 No.1 to an image, transcribed the right-hand
  fingerings visually, and scored against the LilyPond ground truth:
  **9/9 exact** on the resolvable digits (`5,3,5,5,2,1,3,2,1`). Demo output shape
  in `scratchpad/vtest/bar1_demo.json`, mapping to `NoteElement`.
  **Honest bounds:** this was a *clean computer-engraved* score, not a historical
  lithograph — real scans are materially harder; fingering *digits* read cleanly
  but full pitch/rhythm accuracy is a separate, less-verified question; and
  per-page cost makes it a targeted tool (the repertoire pieces that matter), not
  a bulk harvester. Any output needs a validation pass (round-trips to plausible
  pitches, fingerings make hand-sense) — the same defensive posture that caught
  the year-field and cello-range bugs elsewhere in this effort.

### Bottom line
Ship NIFC (piano, fingered, CC BY) + Burgmüller (piano, fingered, PD) now. For
guitar/cello, the fingered layer must be **built**: either the arranger computes
fret (guitar, already shipping) or a **vision pass over dead-editor PD scans**
recovers real period fingerings. The §2/§3-vs-§70 status of editorial fingering
is genuinely unsettled in German law — a Fachanwalt sign-off is warranted before
a commercial ship relies on any post-1900 editorial layer.
