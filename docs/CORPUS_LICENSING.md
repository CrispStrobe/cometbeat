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
  clean score material + sparse fingering cues, not full tab gold.

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

---

## Still unverified (web budget exhausted this session)

- **Essen Folksong / EsAC** — Schaffrath research data; historically "free for
  research" (NOT a clean commercial grant). ~20k melodies, German-relevant.
  Would want an EsAC→kern/model converter. Verify licence first.
- **RISM open data** — the layer *under* PrIMuS. If RISM incipits carry a clean
  CC licence, a re-export could be an MEI unlock. Verify.
- **Meertens Tune Collections (MTC)** — Dutch folk. Licence unknown.

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
4. Verify the three pending leads (Essen, RISM, Meertens).
5. rsync the corpus off `/mnt/volume1` (VPS-local, not backed up) to
   `/mnt/storage`.
