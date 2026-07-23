# Freely-licensed music corpora — sourcing & licence findings

Working notes for sourcing bundle-able ("Tier A") song/score/tab data — and,
from 2026-07-22, playback **assets** (SoundFonts, sampled instruments, one-shots,
tracker modules) — for CometBeat, a **COMMERCIAL** children's music app shipping
in **Germany**. The `music-db` is being generalised from a score/tab corpus into
the app's single **licensed asset registry** (see the *Playback assets* section).
**NOT legal advice.** Anything commercial-critical wants a Fachanwalt für
Urheberrecht sign-off (§3/§4 UrhG exposure + the axis-2 questions below).

Last updated 2026-07-22. Verified vs. pending is marked throughout. A **coverage
snapshot** — what is in hand vs what is still safely reachable — leads the doc;
source-by-source detail follows. (This is a *licensing/coverage* doc: it records
what each source **is** and whether it clears the two axes, not how any of it is
obtained.)

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

### Official Licensing Tiers (Enforced for all assets & scores)
We classify all content strictly according to these definitions:
- **Tier A** = CC0 / Public Domain (PD) / MIT / etc. (No attribution, totally unrestricted).
- **Tier B** = CC BY 4.0 and other licenses that **require attribution**.
- **Tier C** = Share-Alike (e.g., CC BY-SA, ODbL). 
- **Tier D** = NC (Non-Commercial). We cannot ship these.
- **Rest** = Defer totally (Unstated, All Rights Reserved, etc.).

**Ship status (2026-07-23):** the HF catalog (`cstr/cometbeat-assets`) publishes
**Tier A + Tier B**. Tier C/D/Rest stay LOCAL only (in `db.json`, never emitted).
- `bin/emit_catalog.py` `_tier()` classifies **licence-text-first** — a
  restrictive licence string (CC-BY / -SA / -NC) overrides an over-optimistic
  `rights_status`. This caught **8,790 rows tagged `rights_status:CC0` whose
  `licence` was actually `Creative Commons Attribution 4.0`** (NIFC/PDMX) — they
  are Tier B and MUST be attributed, not shipped as free. Every catalog item now
  carries a `tier` field. Current split: **A ≈ 28.9k · B 8,903** (NIFC Polish
  8,181 + Chopin first eds 512 + Mutopia-BY 98 + EGSet12 12 + CC-BY modules).
- **Tier B is shipped only because all four conditions hold** (verified): (1) B
  is pure CC-BY, no SA/NC leaked; (2) the HF dataset has a **card/README** stating
  tiers + licences + attribution; (3) attribution is **displayed** in-app
  ("Sources & credits", reachable from Settings *and* the library browser, listing
  imported songs + samples); (4) every B row has a non-empty attribution.
- ⚠️ **Tier C (Share-Alike, incl. ODbL) is NOT shippable until the app enforces
  SA-propagation** — once SA content enters an Editor (Audio Editor / Tracker /
  Workshop), export/save/share must affirm SA on the output. Requirement noted;
  not yet built. (thesession.org is ODbL **+ a no-LLM clause + composer-copyright
  risk** → excluded entirely; hosting it on HF can't honour "no LLM use".)

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

## Coverage snapshot (2026-07-22) — what we hold vs what is still reachable

The direct answer to "what have we covered / what could we still safely add."
Every line here is a *licence/coverage* statement; detail per source follows.

> **▶ Live DB snapshot (2026-07-23): `db.json` = 42,108 rows** — 41,718 scores +
> 390 playback assets (223 instruments · 166 modules · 1 soundfont). The app-facing
> **HF catalog ships 34,804 items** (score 34,344 · instrument 223 · module 139 ·
> sample 97 · soundfont 1). Scores by source: GregoBase 18,710 · NIFC Polish 8,181 ·
> **PDMX 10,799** (74 is_original + 3,352 classical MXL shippable; see below) ·
> OpenScore Lieder 1,350 · NIFC Chopin 512 · Mutopia 510 · DCML Bach Chorales 361 ·
> OpenScore SQ 122 · OpenEWLD 103 · **Wikimedia Commons (Gerloff) 836** · Kinder
> wollen singen 155 · Musikpiraten Season Songs 52 · Pete Mac 15 · EGSet12 12.
> Assets: VCSL 183 · ModArchive 166 · FreePats 39 · Salamander Grand Piano V3 1 ·
> FluidR3 1.

> **🇩🇪 Wikimedia Commons — Peter Gerloff CC0 MIDI settings (German folk + hymns),
> ingested 2026-07-23.** The **Rabanus Flavus** uploads of Peter Gerloff's MIDI
> settings (`Category:MIDI files of melody settings by Peter Gerloff (secular|sacred)`)
> — a real German-folk/hymn source, per-file licence verified via the Commons API.
> **Exact tiers of the 1,136 files: A (CC0/PD) 1,083 · B (CC-BY) 16 · C (CC-BY-SA) 37.**
> Ship gate = Tier A ∩ axis-2-PD (the melody source is traditional/origin, Gerloff's
> own CC0-original, or a named composer the shared `wikidata_deaths` verdict confirms
> died ≤1955) → **836 ingested** (CC0, `kind:score`, MIDI; `bin/commons_gerloff_ingest.py`
> + `bin/commons_gerloff_reverify.py`; per-file axis-2 note).
> **⚠ AUDIT + RE-VERIFY (2026-07-23):** a spot-check of 10 rows found the first-pass
> melody parser only matched German `Melodie:` and missed `Melody:/Music:/Kanon:` — so
> ~401 rows had defaulted to "traditional" **unverified** (e.g. "Woodlands tune" is
> actually Walter Greatorex d.1949 — PD by luck, not by check). Fixed by re-fetching
> every file's live `Artist` field, extracting the melody source with a broad
> multilingual pattern, and **death-checking every named composer**: **836 confirmed
> soundly Tier A** (0 recent/copyrighted composers survive a final scan), **10 demoted**
> (also PD — medieval/anon/liturgical/obscure-19th-c — but held fail-closed).
> **HELD** (`commons-gerloff-held.json`): 16 Tier-B (attribution), 37 Tier-C
> (SA-propagation), ~245 axis-2-not-provably-PD (obscure composers → manual check), 3
> axis-2-recent/alive (correctly excluded). **Lesson:** a self-attested "traditional"
> default is unsafe — read the actual melody-source field and death-check named
> composers; the parser must cover every language the source uses. ⚠ Wikimedia
> rate-limits bots (HTTP 429) — the downloader paces 1.2 s/file + 60 s backoff.

> **⚠️ PDMX OVERHAUL (2026-07-23) — copyright incident + composer_name fix + classical
> recovery.** A title scan caught **25 in-copyright holiday songs** (White Christmas,
> Frosty, Feliz Navidad, Mary Did You Know…) that slipped in via PDMX's self-attested
> `is_original` slice — CC0 engravings of copyrighted songs with a blank/uploader
> composer field, invisible to the composer-name pass. **Root cause + fix:** PDMX is
> the only source whose axis-2 is self-attested; we had been resolving the uploader
> `author`, when the dataset provides a dedicated **`composer_name`** field + a
> **`license_conflict`** flag. New gate: **a PDMX row ships iff `composer_name`
> (cleaned of arranger markers) resolves via Wikidata to a musician dead ≤1955 AND
> `license_conflict==False`** (`bin/pdmx_pd_composer.py` + shared
> `bin/wikidata_deaths.py` raw-fact cache; `emit_catalog.py` gates PDMX unless
> `pdmx_clearance=="pd_composer"`). **Recovery:** our original ingest filtered to
> `is_original=True` (amateur originals — where `composer_name` is the uploader), so
> it *both* let copyrighted songs in *and* excluded the PD-classical repertoire, which
> lives in the `is_original=False` arrangement subset. Recovered **3,352 cc-zero
> PD-classical arrangements** (Bach 1,004 · Mozart 225 · Beethoven 204 · Chopin 148 ·
> Satie · Handel · Vivaldi · Tchaikovsky…), **MusicXML-primary** (the format PDMX is
> built on; `files={mxl,midi}`), curated-PD-surname-verified + derivative/namesake
> filtered. **PDMX catalog contribution: 74 → 3,426.** A local 3-format test corpus
> (`pdmx_classical_test_manifest.json`: mxl+midi+pdf per piece) feeds an
> importer/exporter/OMR round-trip harness. **HF hard-purge done + verified:** repo
> set private → `delete_repo`+`create_repo` → re-uploaded only clean dirs → public;
> a purged copyrighted MIDI is **404 at `main` AND the oldest commit SHA**.
> **Reusable lesson:** for any self-attested corpus, resolve the dataset's own
> composer field (not the uploader) and honour its internal license-conflict flag —
> the uploader's "is this original?" self-claim is unsafe in *both* directions.

> **⚠ Title-based copyright quarantine (2026-07-23): 25 in-copyright holiday songs
> removed.** A title scan (the axis-2 trap the PDMX notes warned about — works
> hiding under a blank/amateur composer field, recognisable only by TITLE) caught
> **24 PDMX** self-attested `is_original` rows that are in fact copyrighted
> Christmas/pop songs (*White Christmas*, *Frosty the Snowman*, *Little Saint Nick*,
> *Feliz Navidad*, *Mary Did You Know*, *Have Yourself a Merry Little Christmas*,
> *Let It Snow*, *The Christmas Song*, *Santa Claus Is Coming to Town*,
> *It's Beginning to Look…*, *Mele Kalikimaka*, *Grown-Up Christmas List*, *Rudolf
> the Red-Nosed Reindeer*) **+ 1 GregoBase** (*Reno erat Rudolphus* = the Latin
> Rudolph, on the still-copyright Marks 1949 melody). Removed from `db.json`,
> payloads moved to `quarantine-xmas/`, recorded in `christmas_copyright_
> quarantine.json` (`bin/quarantine_xmas.py`, idempotent/reproducible). PD namesakes
> correctly kept (*Jingle Bells* 1857; Lasso's *Rudolph di Lasso* masses).
> **⚠ HF catalog:** the 24 PDMX MIDIs were in the shipped score shard → the catalog
> agent must **re-emit + purge those payloads from `cstr/cometbeat-assets`** (row
> removal stops future emit but uploaded files persist). A broader pop/film
> title-copyright sweep of PDMX beyond the holiday category is still owed.

### Covered now — assessed, licence-cleared, in hand

- **Unified shippable score corpus — 16,800 scores, 8 sources, both axes clean**
  (`music-db/db.json`): PDMX CC0-original 7,471 · NIFC Polish (life+70-filtered)
  6,720 · OpenScore Lieder (composer+poet death-checked) 1,350 · NIFC Chopin 512 ·
  OpenScore String Quartets 122 · OpenEWLD-eu-pd 103 · Mutopia 510 · EGSet12 12.
  Licences: CC0 / CC BY / MIT / PD (per source), each filtered on axis 2. Held
  in multiple formats (midi/mxl/pdf/json/mscx/mscz/ly). *(Superseded by the live
  snapshot above; kept for the per-axis-2-filter detail.)*
- **Tabs for every one of those scores come free** via our own `arrangeTab` — the
  shippable *tab* corpus **is** this score corpus, no third-party tab licensing.
- **JAMS Tier-A** (`jams-corpus/tierA`): GuitarSet 360 (CC BY) · Harmonix 912 (MIT)
  · jams-pkg 7 (ISC) · OpenEWLD-eu-pd 103 (MIT).
- **Tab-pipeline data, assessed:** GuitarSet + EGSet12 (both-axes clean, real
  string/fret) shippable; Guitar-TECHS + AG-PT-set (CC BY) trainable for audio→tab;
  GAPS / IDMT (NC) eval-only.
- **IMSLP — "Marieh" CC0 guitar transcriptions: 235 tablature + 259 standard-notation
  PDFs.** Axis 1 = explicit **CC0** dedication by the arranger; axis 2 = PD 19th-c.
  composers (Giuliani d.1829, Viñas d.1888, Sor, …) → **both axes clean.** Dual
  value: (a) real-world PDF **OMR test input**, (b) clean guitar score/tab material.
  A per-work composer death-check stays prudent (as for any PD claim), but this is
  the cleanest guitar-tab-of-PD-works source found.

### Safely reachable next — clean, identified, not yet ingested

- **OpenScore Lieder — the rest of the CC0 set** beyond the 1,350 shipped, as the
  composer+poet death-filter clears further pairs. Highest-value clean growth.
- **NIFC Polish — the 1,860 undated-anonymous manuscripts currently HELD**, if a
  provenance/RISM date pass can establish pre-1955 publication (fail-closed today).
- **Self-engraved German Kinderlieder** from pre-1900 PD facsimiles (Erk/Böhme
  *Deutscher Liederhort*, Zuccalmaglio) — the only clean route to the German
  children's repertoire the app wants; sidesteps every third-party encoding/DB claim.
  **▶ NOW IN PROGRESS:** 55 tunes self-engraved (`german_ly` LilyPond → Score),
  shipped as **Musikpiraten Season Songs** (52, PD — `github.com/Musikpiraten/
  public-domain-season-songs`) + **Kinder wollen singen** (3, PD — verified-PD
  children's-song initiative). Keep extending from the Erk/Böhme facsimiles.
  Related German-CC0 leads to mine next: **cc0.oer-musik.de / oer-musik.de** (an OER
  portal of CC0 classical + public-domain music — 403s to a bare fetcher, needs a
  browser/manual pass) and **autenrieths.de** (free notation index).
- **CPDL / ChoralWiki** (CPDL License = commercial + share-alike, copyleft) —
  strong for a singing app; per-edition axis-2 filter. (**GregoBase** moved to
  *in hand* — 18,711 CC0 chants + a GABC reader; see the shippable table.)
- **Fingered layers:** Burgmüller Op.100 (PD, fingered) + NIFC Chopin `**fing`
  spines (CC BY, PD fingering); and **dead-editor PD scans** via a vision/OMR pass —
  recovers notes + authentic period fingerings owned outright (guitar/cello solution).
- **Broader IMSLP CC0** — other CC0-dedicating arrangers beyond "Marieh", same
  two-axis test applied per work.
- **Playback assets** — first wave INGESTED (FluidR3_GM · 39 FreePats CC0 · 183
  VCSL = 223 assets); the **97 VCSL percussion one-shots** are also surfaced as
  standalone `sample`s. **New CC0 sample/SFX ingest — VERIFIED per source
  (2026-07-23), because our prior notes were optimistic:**
  - ✅ **VSCO 2 CE** (`github.com/sgossner/VSCO-2-CE`, **CC0-1.0** confirmed via
    the repo licence, 2.3 GB open-source orchestral library) — the clean, big
    CC0 win; Versilian themselves point here. Yields instruments **and** more
    percussion one-shots (via the emit sample scan). **Ingest target.**
  - ✅ **Open Music Academy CC0 SFX** (openmusic.academy, film-sample-library-cc0,
    page states **CC0** + WAV one-shots) — the real SFX-one-shot fit. ⚠ take the
    SFX, NOT their classical *recordings* (performance copyright). Per-file check.
  - ⚠ **freesound.org CC0** — genuine one-shots but needs the API + a per-file
    CC0 filter; deferred.
  - ❌ **Versilian Miscellania I & II** — NOT CC0. The page (cert expired) calls
    the samples **"freeware … download and use at your own risk … products
    without a licence"**; the GPL/MIT on it is the site theme. Versilian's own
    advice: "Download VSCO 2 / VCSL instead." **Excluded** (corrects the earlier
    "CC0 SFX/perc" claim).
  - ❌ **Salamander Drumkit V1** — archive.org metadata = **CC BY-SA 3.0 = Tier C**
    (share-alike), NOT PD/CC0 as our note claimed → **held** (no SA until the app
    enforces SA-propagation on export). (Salamander Grand Piano V3 licence still
    to re-verify per-item; don't trust the "PD" note.)
  - Other still-to-verify (don't trust the label until checked): **University of
    Iowa MIS**, **Discord GM SFZ Bank**, **AVL Drumkits** (BY-SA=Tier C),
    **Flame Studios** (GPLv3+, output exception). Full detail in *Playback assets*.
  **Lesson (again): verify every sample source's actual licence file — "CC0
  SFX" claims keep failing (Miscellania freeware, Salamander BY-SA), same as the
  ABC (thesession ODbL) and module (ModArchive uploader-asserted) dead-ends.**

### Not reachable (settled — see the rejected tables)

Academic classical kern/ABC (craigsapp, DCML, JRP, Essen, Meertens — NC); all large
Guitar Pro archives (DadaGP / UG scrapes — research-only + in-copyright); thesession
(ODbL + anti-LLM); German folk-song sites (private/all-rights-reserved); GOAT / GAPS /
IDMT tab-training (NC/ND → eval-only). PrIMuS / RISM MEI (unstated licence).

---

## VERIFIED — shippable

All licences below read verbatim from the source's own LICENSE file / legal page
(or, for PDMX, its metadata), this effort.

### Already downloaded, on the VPS (`/mnt/volume1/jams-corpus/tierA`)

| Dataset | Files | Axis 1 | Axis 2 |
|---|---|---|---|
| GuitarSet | 360 jams | CC BY 4.0 (Zenodo API) | recorded FOR the dataset — nothing underneath ✅ |
| Harmonix | 912 jams | MIT | beat/segment timestamps only ✅ |
| jams-pkg | 7 jams | ISC | synthetic ✅ |
| OpenEWLD-eu-pd | 87 works / 103 mxl | MIT | author-death filtered to EU-PD ✅ (defensible, not "cleared") |

### music-db integration status (2026-07-22) — 16,800 entries

`/mnt/volume1/music-db/db.json` now indexes **16,800 scores** across 8 sources,
each with a multi-format `files{}` map. By source: PDMX 7,471 · **NIFC Polish
Scores 6,720** · OpenScore Lieder 1,350 · NIFC Chopin 512 · OpenScore SQ 122 ·
OpenEWLD 103 · Mutopia 510 · EGSet12 12.

- **NIFC Polish Scores** (2026-07-22): `git clone`d the 8,918-krn repo. Verified
  axis-2 from the **authoritative `!!!CDT` composer-date headers** (source metadata,
  beats Wikidata — and corrected Wikidata's namesake false-positives) AND
  parseability. Ships iff parseable AND (composer CDT latest year ≤1955, OR
  anonymous **with a pre-1955 source/publication date**). Result: **SHIPPED 6,743**
  (PD-composer 6,177 + dated-anonymous 566); **HELD 2,150** = undated-anonymous
  1,861 + undated-composer 289; **DROPPED 25** (dated >1955, e.g. S. Kazuro d.1961).
  CC BY 4.0 → attribution.
  - ⚠ **Anonymous ≠ automatically PD** (EU: anon = 70y from *publication*). So the
    **1,861 undated-anonymous manuscripts are HELD**, not shipped — historical-looking
    (NIFC archives, mostly 16th–19th c by SMS-siglum) but not *provably* pre-1955.
    A provenance/RISM date pass could clear many (`polish_held.json`).
  - Tooling: `tool/music_db_ingest_polish.py`, `music_db_polish_cdt_classify.py`,
    `music_db_krn_parse_sweep.dart`.
- **OpenScore quarantine applied**: the 2 genuine in-copyright poet cases (Erich
  Jansen d.1968, Bruce Blunt d.1957) removed via `os_exclude.json` (merge skips
  them); the other 11 flagged were Wikidata namesake false-positives, kept. Lieder
  1,352 → 1,350.
- **kern parser quality-checked at corpus scale — and it found real bugs.** Ran a
  **VPS parse-sweep** (our own reader via `/mnt/volume1/toolchain/flutter/bin/dart` +
  a `crisp_notation` clone) over **all 8,918** Polish krn + a **verovio** content
  oracle (the Humdrum-native renderer) on a 60-file Chopin/Polish sample. Fixes:
  - **breve/long/maxima** (`0`/`00`/`000`) durations crashed the reader (crisp_notation
    `d4655e7`).
  - **exotic meters** (`*M3/3`, `*M2/21`) and **null-token variants** (`..`/`./`/`.\`) +
    a lone unparseable/unmeasured token wrongly aborted the whole score (`886cc1d`) —
    now the exotic meter/token is skipped, not fatal.
  - Net: **24 failures → 0. All 8,918 parse (100%).**
  - **Oracle result vs verovio: 93.84% pitch-multiset agreement** (music21 gave only
    75.92% — it `ExpanderException`s on early-music repeats and drops notes, so it's an
    *unreliable* oracle here). The residual is **repeat-expansion** (verovio expands
    repeats, we read the notated score once → on those files our notes are a correct
    *subset* of verovio's), not a parse error.
  - Known limitation (out of scope for the DB): our **kern *writer*** is lossy for
    dense multi-voice (single spine per part). We ship original krn; the reader — what
    the app uses — is validated above.

- **Added this session:** **OpenEWLD** (103 mxl, MIT, author-death-filtered EU-PD,
  `tool/music_db_ingest_openewld.py`) · **NIFC Chopin First Editions** (512 krn, CC
  BY 4.0, Chopin d.1849 = PD + PD first-edition fingering; `music_db_ingest_nifc.py`)
  · **EGSet12** (12 `.gp`, CC BY 4.0, original by the dataset authors;
  `music_db_ingest_egset12.py`). CC BY entries carry attribution → `ATTRIBUTION.md`.
- **OpenScore axis-2 VERIFIED** (was "assumed"): a composer+**poet** life+70 Wikidata
  check (`tool/music_db_openscore_life70.py`) over 661 unique names → **1,461/1,474
  CLEAR, 13 BLOCKED** (`os_problematic.json`). Most of the 13 are Wikidata **namesake
  false-positives** (Glinka d.1857 matched a 1936-2022 person; "John Howard Payne"
  d.1852 → a 1912-1989 "John Payne"; "A. S." → novelist A.S. Byatt) — only ~2 look
  genuine, both **poets/lyricists** (Erich Jansen d.1968, Bruce Blunt d.1957). Pending
  a targeted quarantine of the genuine cases.
- **HELD (not added):** **humdrum-polish-scores** — turns out to be **8,918 krn**
  (not a small companion); CC BY on axis-1 but composers not all PD → needs the same
  life+70 pass before shipping. **CPDL** — copyleft + per-edition axis-2 filter, a
  separate project. (**GregoBase** — resolved: the CC0 SQL dump on GitHub + a
  clean-room GABC reader in crisp_notation; 18,711 chants in hand, see the table above.)

### New, verified-clean, format-reachable (no new code needed)

| Source | →reach | Axis 1 | Notes / axis-2 |
|---|---|---|---|
| **OpenScore Lieder** | MusicXML | **CC0** (LICENSE.txt) | 1,200+ 19th-c. art songs, multi-part + lyrics. **Top pick.** Needs composer+poet death-filter (below). |
| **OpenScore String Quartets** | MusicXML | **CC0** (LICENSE.txt) | Chamber, PD composers. Smaller, same clean profile. |
| **PDMX** (is_original slice) | MusicXML→**MIDI built** | **CC0**, 7,547 MIDIs ✅ | Original amateur compositions. Self-attested → wants a dup pass. MIDIs converted + roundtrip-verified (see below). |
| **Mutopia** | .ly / MIDI | **CC BY-SA / CC BY / PD — all commercial-OK** (legal.html) | Per-piece licence + editor-rights filter; BY-SA copyleft on a bundle. |
| **CPDL / ChoralWiki** | MusicXML/MXL where offered | **CPDL License = commercial + share-alike** (copyleft); editions also CC / PD | Choral/vocal — strong for a SINGING app. Per-edition filter; §3 engraving + US-PD cautions. |
| **GregoBase** ✅ **IN HAND** | GABC → Score (**reader built** — crisp_notation `scoreFromGabc`) | **CC0** (all transcriptions; 33 copyright-flagged rows excluded) | **18,711 chants downloaded** to the VPS (`gabc-corpus/gregobase`, from the CC0 SQL dump); ancient-PD melodies → both axes clean. Clean-room GABC reader (spec-derived, gabctk-oracle-validated 98.9%); **99.7% parse / 0 crash** on a 1.5k sample. |
| **Library of Plainsong** | GABC | **CC0** (site statement) | Nascent placeholder site — no accessible corpus yet; bookmark. |
| **IMSLP "Marieh" guitar transcriptions** | PDF (tab + notation) | **CC0** (arranger's explicit dedication) | 235 tablature + 259 standard-notation PDFs; underlying composers PD 19th-c. (Giuliani d.1829, Viñas d.1888, Sor…) → both axes clean. Dual use: **OMR test input** + clean guitar score/tab. Per-work composer death-check prudent. |

**Detail worth keeping:**

- **PDMX** — **254,077** MuseScore scores (the superset; `subset:all`). The headline
  "public domain" is mostly the **PD Mark** (210,364) — a *claim*, not a grant. Only
  **43,713** are real **CC0** (`cc-zero`). CC0 covers the ENGRAVING only: the
  clean-CC0 set still contains "Seven Nation Army", "Light of the Seven", "Crimson
  Peak – Edith's Theme" (in-copyright songs, axis-2 fail). The `is_original` flag is
  the axis-2 filter. Other named subsets in the current HF CSV: `subset:rated` 14,182,
  `subset:deduplicated` 102,635, `subset:rated_deduplicated` 13,187 (there is **no**
  `subset:no_license_conflict` column in this release, though the README recommends
  one). Counts verified directly from the tarball's `PDMX.csv` (2026-07-21).
  - **Our clean slice → 7,547 CC0-original MIDIs built + validated** at
    **`/mnt/volume1/pdmx-cc0-midi/mid/`** (2026-07-21). Filter = `cc-zero ∧
    is_original ∧ no license_conflict`. NB the **current** HF CSV dropped the
    `license_conflict` column, so in it `cc-zero ∧ is_original = 9,744`; our 7,547 is
    that **minus 2,197** conflict-flagged rows (7,547 + 2,197 = 9,744) — the safe,
    conservative subset. All 7,547 re-confirmed `cc-zero ∧ is_original` against the
    current CSV (0 misclassified). (Source list `pdmx_cc0_mid.txt` had 7,549 rows /
    7,548 unique basenames, one a null `NA` → 7,547 real scores; all converted, 0
    skipped, 1 out-of-range pitch clamped across 9.78M notes.)
  - **PDMX ships JSON-only** on HuggingFace: `openmusic/pdmx` is a single 1.59 GB
    `PDMX.tar.gz` = 508k `.json` (254k score `data/` + 254k `metadata/`), **0
    `.mid`/`.mxl`/`.pdf`**. This release's CSV has `path`(=json)/`metadata` columns
    and **no `mid`/`mxl` columns at all** — the phantom `mid/`/`mxl/` paths came from
    an older/Zenodo CSV. The name "Public Domain **MusicXML**" is provenance (scraped
    as MusicXML from MuseScore); the fuller **Zenodo** release (`zenodo.15571083`)
    adds "MXL, PDF, MID when available". MusicXML/MIDI are **derivable** from the JSON
    (muspy → music21) if ever wanted.
  - **Validation — is the conversion perfect? vs the authoritative ground truth
    (muspy, the lib PDMX was built with, and beneath it the source JSON note list):**
    (a) full-corpus roundtrip (our own independent MIDI parser vs source JSON):
    **7,547/7,547 perfect, 9,778,989/9,778,989 note-ons = 100.0000%**; (b) vs muspy's
    own object on samples: **pitch+onset 100.0000%**; (c) mine vs muspy's own `.mid`,
    apples-to-apples incl. duration: **99.9997%** (298/299 perfect, 300-file sample).
    The residual is **muspy dropping notes**, not us: across the sample **mine = JSON
    exactly (377,636 note-ons, Δ0)** while **muspy wrote 377,239 (Δ−397)** and crashed
    outright on 1 file (a `♭`/U+266D track name → latin-1 error). Mechanism = muspy's
    writer collapses **same-pitch temporally-overlapping notes**; our writer preserves
    every note. Caveat (MIDI format limit, not a bug): overlapping same-pitch notes
    can't have their paired durations uniquely recovered on read-back — pitch+onset is
    exact, counts are exact, only such overlaps' durations are ambiguous (true of every
    writer, muspy included). **Net: our converter is at least as faithful as muspy and
    strictly more note-preserving.**
  - Converter + validator: `tool/pdmx_json_to_midi.py` (stdlib-only,
    `extract`/`convert`/`validate`/`all`). MIDIs derived from CC0 source →
    redistributable; still self-attested on axis-2, so a dup/plagiarism pass is wise
    before shipping.
  - **In-app Dart importer** (2026-07-21): `crisp_notation_core`'s
    `musicrender_reader.dart` reads muspy/PDMX JSON into the notation model —
    `musicRenderToMidi` (note-exact JSON→SMF, the Dart twin of muspy's write_midi),
    `multiPartScoreFromMusicRender`, `scoreFromMusicRender`. Surfaced via
    `bin/musicrenderconv.dart` (CLI) and the Song Book import screen (`.json`).
    Cross-validated on the corpus: Dart `musicRenderToMidi` = the Python converter
    **100%**, = muspy **99.9997%** (residual = muspy's note-drops). This doubles as a
    pipeline oracle (muspy JSON → our importer → our MIDI/MXL vs PDMX's own MID/MXL).
  - **Integrated into the music DB** (`/mnt/volume1/music-db/`, 2026-07-21): the
    7,547 clean MIDIs are a new **`PDMX`** source in `db.json` (now 9,531 items:
    Mutopia 510 + OpenScore Lieder 1,352 + String Quartets 122 + **PDMX 7,547**),
    ingested via `tool/pdmx_ingest_music_db.py` (→ `bin/ingest_pdmx.py` on the VPS)
    and merged with `bin/merge_db.py`. Files at `music-db/pdmx/ship/midi/<hash>.mid`;
    metadata (title, uploader, GM-program-derived instruments) from `PDMX.csv`.
    Each entry is `rights_status: CC0` but `rights_method` marks it **self-attested,
    UNVERIFIED** and kept as a distinct `source` so it never mixes with the
    hand-verified core, adds **0** attribution obligations. ⚠ **Axis-2 caveat is
    real and large:** `is_original` is unreliable — **55.3% (4,174/7,547) name a
    third-party composer ≠ the uploader** (e.g. "Crimson Peak – Edith's Theme" /
    Fernando Velázquez, Bert Appermont, "Arranged by…"). That count over-estimates
    (some are same-person username mismatches or PD composers like Satie), but a
    proper dedup/originality pass is warranted before treating PDMX as clean-original.
  - **Originality pass done + quarantine applied** (2026-07-21): a Wikidata life+70
    check (reusing `bin/eu_pd_check.py`'s logic, extended to flag *living*
    composers) over the 2,245 unique third-party composer names split them: **~3,357
    demonstrably clean** (PD composer d≤1955 → CC0 engraving of a PD work; or a
    placeholder like "Composer"; or an amateur that resolves to no notable composer),
    **~741 unresolvable/odd** (low-risk), and **76 that name a real in-copyright
    composer** — the actionable residual (jazz standards: Ellington/Garner/Goodman;
    film/game/pop: Rodgers, Denver, Ed Sheeran, Einaudi, Koji Kondo, Santaolalla…;
    plus a ~29-entry "James Brown" Wikidata **namesake false-positive** — an amateur
    band arranger, though those titles are pop covers so risky anyway). All **76 were
    quarantined**: `pdmx_exclude.json` (the ingest now skips them), MIDIs moved to
    `pdmx/quarantine/midi/`, record in `pdmx_quarantine.json`. **PDMX 7,547 → 7,471**
    in `db.json` (total 9,455). Tooling: `tool/pdmx_originality_classify.py` +
    `tool/pdmx_originality_report.py`. NB this catches only *named* copyrighted
    composers; works hiding under a blank/amateur composer field (recognisable by
    TITLE — "Hallelujah", "Perfect") would need a separate title-based scan.
  - **Multi-format `files` map** (2026-07-21): every `db.json` entry carries a
    `files` object of format→relative-path, added by `bin/enrich_files.py`
    (`tool/pdmx_music_db_enrich_files.py`) as the final pipeline step after
    `merge_db.py`. PDMX carries all four (midi/mxl/json/pdf — the big json/pdf/mxl
    are relative **dir-symlinks** `pdmx/ship/{mxl,json,pdf}` → the cache, not copied).
  - **Overnight format enrichment DONE** (2026-07-22, `bin/overnight.sh`, ~18 min, 0
    failures): (1) fetched **Mutopia PDF (505) + LilyPond `.ly` (442)** from the FTP
    dirs → `mutopia/ship/<cat>/{pdf,ly}/`; (2) derived **MIDI for all 1,352 OpenScore**
    scores from their `.mxl` via a pure-stdlib MusicXML→MIDI (`tool/music_db_mxl_to_midi.py`,
    validated 40/40, note-ons 1.0007× expected). Final availability across 9,455
    entries: **midi 9,333 · mxl 8,823 · pdf 7,976 · json 7,471 · mscx 1,474 · mscz
    1,352 · ly 442**; formats-per-entry: 4→8,823, 3→440, 2→67, **1→125** (the 122
    String Quartets, mscx-only, + 3 Mutopia lacking pdf/ly).
  - **What could NOT be fetched from the web:** the **OpenScore StringQuartets repo
    ships `.mscx` only** (no mxl/mscz on GitHub — verified via the API), and
    musescore.com MIDI/PDF are Pro-gated; so the 122 SQ stay mscx-only until derived
    Dart-side (crisp_notation `scoreFromMscx`→`scoreToMidi`, off-VPS).
  - **Full Zenodo release cached** (`zenodo.15571083`, 2026-07-21) on the VPS at
    `/mnt/volume1/pdmx-cc0-midi/zenodo/`: `mid.tar.gz` (254,035 official MIDIs),
    `mxl.tar.gz` (MusicXML), `pdf.tar.gz` (9 GB sheet-music PDFs), full `PDMX.csv`
    (215 MB, with mid/mxl/pdf path columns), `subset_paths.tar.gz`. Their `.mid`/
    `.mxl`/`.pdf` use the same `Qm…`-hash basenames. The **7,547 clean subset** is
    extracted per-format under `zenodo/{mid_official,mxl,pdf}/`. NB their official
    `.mid` are muspy-written → carry the same same-pitch-overlap note-drops; our
    built MIDIs are more faithful.
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
| DCML (ABC, Mozart/Beethoven sonatas, Chopin, Schumann… — **52 score corpora**) | ABC/mscx | **CC BY-NC-SA** (`.zenodo.json`, verified across the org) — NC. **ONE exception:** `DCMLab/bach_chorales` = **CC0-1.0** (`.zenodo.json` authoritative) → both-axes clean (Bach d.1750). **Ingested: 361 chorales (mscx) + 722 CC0 note/measure TSVs** as `DCML Bach Chorales`. The DCML *corpus-initiative* moved bach_chorales to CC0; the rest stay NC. Swept all 127 DCMLab repos: only bach_chorales is clean. |
| **JRP (Josquin Research Project)** | krn | **CONFLICTED** — LICENSE.txt header says "CC-BY-SA 4.0" but the URL beneath is `by-nc`. Unsafe → treat as NC. |
| **PrIMuS / Camera-PrIMuS** | MEI (already!) / semantic | **UNSTATED = all rights reserved**. RISM-derived, 87,678 incipits. (Ships MEI, so never a filter problem — a licence problem.) |
| **GOAT** (Guitar On Audio and Tablatures) | tab/MIDI/audio | **CC BY-NC 4.0**, restricted files, Zenodo 10.5281/zenodo.15690894; description says research-only, not for commercial products. Tempting (paired string+fret supervision) but NC. |
| DadaGP + all GP tab archives | gp | research-access-only, UG scrape of in-copyright songs |
| **thesession.org** (+ folk-rnn, folk-rnn-webapp, themachinefolksession) | ABC | dump is **ODbL + anti-LLM clause** (2025-10, tightened 2026-06). folk-rnn's MIT is code-only; it scraped thesession ~2015 when the dump had **no licence at all**. ODbL on a bundle → share-alike (§4.4) + source-offer (§4.6) + attribution (§4.3); §2.4 disclaims rights in the transcriptions, which vest in each **transcriber**. |
| **abcnotation.com** | ABC | **UPLOADER-ASSERTED / NC**. Search engine aggregator. Transcriptions lack a CC0 grant. Its consent list explicitly states composers retain copyright and forbids commercial use (NC). |
| **Zenodo ABC Dataset 10k** (17694747) | ABC | **UPLOADER-ASSERTED**. Blanket "CC-BY 4.0" over massive web scrape of abcnotation, Nottingham, etc. The Zenodo author does not own the commercial rights to the underlying transcriptions. |
| **Nottingham Music Database** | ABC | **All Rights Reserved / NC**. IPR held by Mick Peat / Eric Foxley. Often used academically under fair use or explicitly CC BY-NC. |
| **IFDO kern2abc** (Densmore/Shanahan Native American) | ABC | **CC BY-NC-SA 4.0**. Converted by Seymour Shlien from `humdrum-data` modules (`craigsapp`, `shanahdt`) which explicitly use Non-Commercial licenses. |
| German folk-song sites (4) | — | volksliederarchiv.de (private/non-commercial, notation walled off in robots.txt); lieder-archiv.de (copyright on its Notensätze; commercial/DB/republish forbidden — but offers a PAID licence); liederlexikon.de (all-rights-reserved, NOT CC, named living engraver + in-copyright 20th-c. works); ZPKM Freiburg (catalogues only). |
| **Essen Folksong Collection** (ccarh/essen-folksong-collection) | krn ✅ | **CCARH MuseData licence** (license.txt, verbatim): *"this license does not authorize the use of the enclosed MuseData files in the production of derivative editions intended for commercial distribution, nor for public performance (including broadcast), nor for sound recording."* NC + no-recording → dev/test only. ~20k folk melodies, German-relevant, but blocked. |
| **Battle of the Bits** (battleofthebits.com) | .xm/.it/.mod + rendered | **CC BY-NC-SA** to third parties (BotB CC License, verified) — NC. Original chiptune/tracker compo entries (axis-2 clean), but the NC axis-1 blocks it. Control/eval only. *Corrects an earlier "BotB is clean" note.* |

---

## Playback assets — SoundFonts · instruments · samples · tracker modules (2026-07-22)

New scope: the `music-db` becomes the app's single **licensed asset registry** —
not just scores/tabs but every bundle-able *sound* asset (SoundFonts, sampled
instruments, one-shots, tracker modules), each carrying the same licence
provenance so one ship gate covers everything. Same two axes, with **axis 2
re-read for audio**:

- **Axis 1** unchanged: CC0 / CC BY / MIT / permissive = ship; CC BY-NC /
  unstated = not; CC BY-SA / GPL = ship-but-copyleft.
- **Axis 2 for a *recording*** = who/what is under the sample. A sample
  **recorded for the library** (a struck snare, a bowed note) has no third-party
  *work* underneath → trivially clean. The two traps: (a) a SoundFont
  **assembled from other soundfonts** of unknown origin (provenance inherited),
  and (b) a tracker module that **samples a copyrighted recording**.

The app is already wired for this: SF2/SFZ/MOD/multi-sample loaders
(`lib/core/audio/{sf2,mod,multi_sample_instrument.dart}`), a FreePats-aware 7z
reader (`sevenz_reader.dart`), and it already bundles **VCSL CC0** percussion
(`assets/sounds/percussion/LICENSE.txt`). Attribution flows via
`attribution_screen.dart`'s `needsAttribution` — **CC0 lists nothing; CC BY /
BY-SA carry a credit** (the "save extra" case).

### Tier A — CC0 / public-domain (bundle freely, NO attribution)

| Asset | What | Axis 1 | Axis 2 |
|---|---|---|---|
| **VCSL** (Versilian) | 4,000+ orchestral+world multisamples, SFZ+WAV | **CC0-1.0** | recorded for the library ✅ (already our percussion source) |
| **VSCO 2 Community Edition** | 3 GB chamber orchestra | **CC0** | recorded for the library ✅ |
| **VCSL Keys** | 10 keyboard instruments, 1,466 samples | **CC0** | ✅ |
| **FreePats CC0 SFZ** | timpani, tubular bells, ocarina, hang, FM piano 2, e-bass YR, world perc, old piano | **CC0-1.0** (per-repo) | recorded for the set ✅ — ⚠ *per-repo*: MuldjorKit=CC BY, Colombo=GPL → Tier B |
| **OpenGameArt — CC0 subset** | .xm/.it/.mod/.s3m + ogg game music | **CC0** | original compositions ✅ |
| **Selekt Audio — CC0/PD catalog** | 100k+ cleared one-shots/loops, per-sample cert | **CC0 + US-PD** | fingerprint-screened; PD tier = pre-1926 US recs + Library-of-Congress field recs ✅ (US-PD ≠ EU-PD — recheck axis 2 for the PD tier) |
| **freesound (CC0 filter)** | individual sounds | **CC0** (must filter) | per-sample check |
| **University of Iowa MIS** (Electronic Music Studios) ⭐**NEW** | Steinway piano + strings / winds / brass / percussion, WAV/AIFF | **PD / no-restrictions** — site (L. Fritts, since 1997): *"may be downloaded and used for any projects, without restrictions"* | recorded at the university → nothing underneath ✅. **Top Tier-A acoustic-instrument pick alongside FluidR3**; individual-note samples ideal for a multisample instrument. |
| **Versilian Miscellania I & II** ⭐**NEW** | SFX + percussion one-shots, WAV | **CC0-1.0** (Versilian) | recorded for the library ✅ (same house as our VCSL) |
| **Discord GM SFZ Bank** ⭐**NEW** | full General MIDI bank in SFZ (`sfzinstruments/Discord-SFZ-GM-Bank`) | **per-`.sfz` licence** — filter to CC0/CC-BY | assembled per-instrument; check each file. Useful GM fallback for `gm_song_render.dart`. |

### Tier B — "NA" (Needs Attribution): permissive but attribution / notice required

Non-NC, commercial-OK, but oblige a credit or a bundled licence file →
`needsAttribution` + drop a `LICENSE.txt` beside the asset (as the percussion
folder already does). Does NOT include ShareAlike/copyleft licenses.

| Asset | Axis 1 | Obligation |
|---|---|---|
| **FluidR3_GM** (Frank Wen) — full GM SoundFont | **MIT** | bundle copyright/README; no per-render credit. **Best full-GM candidate** for `gm_song_render.dart`. |
| **GeneralUser GS** — low-footprint full GM | permissive (no attribution *required*) | ⚠ author admits some legacy sample origins uncertain (project began 2000). Low practical risk, but FluidR3's clean MIT is the safer ship. |
| **OpenGameArt — CC BY / OGA-BY** | CC BY / OGA-BY | attribution. |
| **Big MOD Music Pack** (itch) | mixed CC0 / CC BY / PD | per-file — CC0 → Tier A, rest → credit. .xm, handled by the MOD loader. |
| **FreePats MuldjorKit** | CC BY 4.0 | attribution |
| **Salamander Grand Piano V3** (Alexander Holm) ✅**INGESTED** ⚠ | **CC BY 3.0** — **NOT public domain** (repo `LICENSE` = CC-BY-3.0 verbatim; a widespread misconception). | attribution. **Best free acoustic grand** (Yamaha C5, 16 vel layers, 641 FLAC + one SFZ). Now in `db.json` (`kind:instrument`, source *Salamander Grand Piano*, `bin/ingest_salamander.py`, wired into `merge_db`). ⚠ the SFZ uses ARIA/sforzando opcodes → the CC-BY FLAC set is the durable asset; in-app playback via our SFZ loader may need a simplified mapping (app-side). Do NOT ship as CC0/PD. |

### Tier C — "SA" (ShareAlike): copyleft, attribution required

Non-NC, commercial-OK, but carries a ShareAlike or GPL copyleft clause.

| Asset | Axis 1 | Obligation |
|---|---|---|
| **OpenGameArt — CC BY-SA / GPL** | CC BY-SA / GPL | attribution + SA/GPL copyleft. |
| **Big MOD Music Pack** (itch) | CC BY-SA | attribution + SA copyleft. |
| **JummBox SoundFont fork V11** (stgiga) | **CC BY-SA 4.0** | attribution **+ ShareAlike** (derivative banks stay BY-SA). Base BeepBox/JummBox engine is MIT. |
| **FreePats Colombo Drumkit** | GPL-2.0 | GPL notice (awkward to embed; fine standalone) |
| **AVL Drumkits** (Glen MacArthur) ⭐**NEW** | **CC BY-SA 3.0** **+ a music-output exception**: SA binds only if you modify the samples / repackage a sample library — **rendered music using the kit is unrestricted**. | attribution + SA on the *sample payload*; the drum sound in a rendered track is free. SFZ / SF2 / h2. Strong acoustic-drum source (Black Pearl, Red Zeppelin, Blonde Bop). |
| **Flame Studios GigaSamples** (guitars / bass / banjo) ⭐**NEW** | **GPLv3+** with an output exception (produced audio unrestricted). | GPL notice on the sample payload; output free. SF2 / SFZ. Fills the guitar/bass instrument gap. |

**OpenGameArt is the spine for tracker music.** It **structurally forbids NC** —
every OGA asset is CC0 / CC BY / CC BY-SA / GPL / OGA-BY, all commercial-OK — so
the licence gate is done for you: filter Music + license checkboxes, split
CC0 → Tier A / CC BY / OGA-BY → Tier B / CC BY-SA / GPL → Tier C. Original compositions → axis-2 clean.

### Excluded — NC or unverifiable provenance

- **Battle of the Bits — NC.** Verified the BotB CC License: every entry is
  **CC BY-NC-SA** to third parties (+ a CC BY-ND reservation for BotB itself).
  Despite "original → axis-2 clean," the NC axis-1 kills it → control/eval only,
  same tier as IDMT/GAPS. *(Corrects an earlier "BotB is clean" assumption.)*
- **Sonatina Symphonic Orchestra (SSO)** — **CC Sampling Plus 1.0** (retired,
  non-standard). It lets you *sample the sounds into your own works* commercially,
  but **restricts redistribution of the sample library itself to non-commercial +
  "no advertising."** Bundling the whole library into a commercial app is the
  *restricted* case → **defer / legal-review, NOT clean.** (VSCO 2 CE + University
  of Iowa MIS cover the same orchestral need on clean Tier-A terms.)
- **General community module archives** whose licences are **uploader-asserted
  or absent** — excluded as sources. The licence field is set by the *uploader*,
  rarely the author; the bulk is unclear/"non-licensed" and much of it samples
  copyrighted recordings (axis-2 dirty). A specific module is usable only if its
  CC0/PD grant is **author-verifiable**; otherwise robustness/eval-control at
  best (cf. the OLGA posture) — never a shippable bulk source.

### DB schema — one registry, one ship gate

Generalising `db.json` means each row answers the same axes. Extend the manifest:
`kind` (soundfont|instrument|sample|module|score|track|example), `format`
(sf2|sf3|sfz|wav|xm/it/mod/s3m|mid|musicxml|krn|json), `license` (**SPDX**),
`tier` (A | B/"NA" | C/"SA"), `attribution` (credit + URL; null for Tier A), `axis2`
(original-recording | long-PD | sampled-risk), `provenance`
(**author-asserted vs uploader-asserted** — the module-archive trap).
**Ship gate:** `tier==A ∨ ((tier==B ∨ tier==C) ∧ attribution≠null)` **∧** licence≠NC **∧**
`axis2≠sampled-risk`. Anything failing = control/eval only, exactly as the score
corpus already treats its HELD/quarantine rows.

### Status
**Asset-registry scaffolding is LIVE** in the `music-db` (2026-07-22): `db.json`
rows now carry a `kind` field (existing 16,823 → `score`), `merge_db.py` reads an
`assets-manifest.json`, and `bin/ingest_assets.py` is the data-driven ingest
(append to its `ASSETS` list). **First assets ingested: (1) **FluidR3 GM/GS**
(MIT full-GM SoundFont, 151 MB, `assets/soundfonts/`), sha256-recorded, licence
bundled — licence re-verified as genuinely MIT (Frank Wen's own COPYING + Debian
*main*; the archive.org download mirror mis-tags CC-BY-ND, ignored). (2) **39
FreePats CC0 instruments** (`assets/instruments/freepats/`, SFZ + FLAC, 1.5 GB) —
**per-instrument** rows (`kind:"instrument"`), SPDX read per-repo from the GitHub
API so only `CC0-1.0` repos are taken (muldjordkit=CC-BY, colomboADK=GPL
excluded). (3) **183 VCSL voices** (Versilian Community Sample Library, `assets/instruments/
vcsl/`, 5.8 GB) — **per-SFZ** rows (`kind:"instrument"`), CC0-1.0 (repo SPDX). Its
`sfz` branch is self-contained (SFZ + all WAVs), so one download; SFZ reference
samples relative to their own folder (verified: 22/22 resolve). Families: drums 85
/ pipe 51 / strings 23 / reed 8 / bass 7 / piano 7 / synth 2.
**Assets total: 223** (1 soundfont + 222 instruments), folded in by **append**
(`bin/append_manifest.py`), not a full rebuild, to avoid the Mutopia/Lieder
path-truncation defect; append reads the live db.json so it preserves concurrent
score additions. **db.json = 18,484, 0 dangling.** VSCO 2 CE skipped as largely
subsumed by VCSL (Versilian call it "the broader expansion to the VSCO 2 CE
sample set").

**⚠️ CONTENT POLICY — music is SYMBOLIC; audio only as sample payloads
(maintainer, 2026-07-22).** The registry admits **rendered audio (mp3/ogg/wav/
flac) ONLY as an instrument/sample payload** (SFZ samples, soundfonts). For
*music/tracks* it takes **symbolic data only** — MIDI / MusicXML / kern / ABC (the
existing 18k-score corpus IS this), plus **tracker modules** (`.xm/.it/.mod` —
symbolic pattern data + samples). An OpenGameArt CC0 harvest (`bin/oga_harvest.py`)
pulled 130 finished-audio tracks and was **reverted** under this rule; **finding:**
OGA's CC0 set is ~all finished ogg/mp3 (0 modules in the top ~170 nodes), so OGA
is **not** a symbolic-music source. Clean CC0/CC-BY tracker **modules** were
instead sourced from a per-file-licensed community module archive by its explicit
licence categories (see §Status above — 1,650 shipped). The itch "Big MOD Music
Pack" (700+ per-file PD/CC0/CC-BY/CC-BY-SA `.xm`, with a `MasterList.txt` licence
map) is a *curated subset of that same archive*, so going direct to the source's
licence categories was cleaner (no itch download gate, all tiers).

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
  mutopia_guitar_scan.py`) are **sparse PARTIAL string PINS, not dense per-note
  labels** (guitar staff notation can't carry full string/fret — string marks on
  <½ the notes even at densest). Role: `Score.tabVoicings` pins + arranger
  pseudo-labels, NOT a GuitarSet-grade training set. And the **CC BY-SA subset is
  copyleft** — only `non-sa/` (CC BY / PD) may feed a CC-BY model. See
  `docs/TAB_LABELER_ROADMAP.md` §3 for the dense-vs-sparse data picture.
- **Guitar-TECHS / AG-PT-set (CC BY)** — for the *audio*→tab TabCNN, not this
  symbolic labeler.

### Movement is a TUNABLE knob, not a model property — measured Pareto frontier

The `8270` model raised human-fingering agreement to 82.70% but at **+6.8% hand
movement** vs the heuristic (the `7859` model was +25→+21.6 pts at +3.4%). That
extra movement is NOT baked into the weights: `arrangeTab` is already a Viterbi
DP whose transition term penalises hand travel (`|Δfret|·cost.move`, default
1.0) — the model only replaces the *local* term, so its idiomatic-position
preference just outvotes `cost.move`. Raising that one weight claws movement
back, measured on the 60-song / 8,715-position benchmark (8270 model):

| `cost.move` | agreement | movement | vs heuristic mvmt |
|---|---|---|---|
| heuristic (no model) | 56.98% | 4095 | — |
| 1.0 (shipped) | **82.70%** | 4372 | +6.8% |
| 1.5 | 81.66% | 4251 | +3.8% |
| **2.0 (knee)** | **80.38%** | **4147** | **+1.3%** |
| 3.0 | 79.00% | 4086 | −0.2% |
| 6.0 | 77.06% | 4078 | −0.4% |

**`move≈2.0` keeps 80.4% agreement at near-heuristic movement**, and
**8270@move-2.0 (80.4% / +1.3%) dominates 7859@move-1.0 (78.6% / +3.4%) on both
axes** — so ship 8270 with a higher `cost.move`, archive 7859 as a dominated
fallback. This is a bog-standard result: string-instrument fingering as a
min-cost path over hand-position states is the **Sayegh (1989) "optimum path
paradigm"**, extended by Radicioni & Lombardo, Radisavljevic & Driessen (2004,
learned costs), Barbancho et al. (2012, HMM w/ fingering-difficulty transitions),
and Heijink & Meulenbroek (2002, biomechanical cost). Our emission-model + DP-
transition stack is exactly that family; the model supplies local idiomaticity,
the DP enforces low movement/span globally.

**One caveat — span vs movement differ.** Raising `cost.move` fixes *movement*
(a transition cost). It does NOT bias toward smaller *spans*, because the model
**replaces** the local term where `cost.span` lived — so within the hard span cap
(`kHandSpan=5`) the model picks the shape. To also prefer *narrower* shapes, the
one code change worth making is to keep `cost.span`/`cost.height` in the local
cost **additively** even when the model is present (`local = −modelScore·w +
_localCost(f)`), rather than replacing it. Small, in `arrangeTab`'s `local()`.

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
