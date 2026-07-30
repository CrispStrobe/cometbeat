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

### Local tracker audit corpus (2026-07-25)

The downloaded MOD/XM/IT files currently in `test/fixtures/` are **not cleared
for redistribution**. Their source URLs, checksums, and licences were not
recorded when they were downloaded, so they remain developer-local and must not
be committed or shipped. `golden.mod.wav` is generated reference audio and is
also local-only. See `test/fixtures/README.md` for the exact inventory and the
promotion requirements. This is separate from the explicitly licensed playback
assets listed in the catalog sections below.

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
  Workshop), export/save/share must affirm SA on the output. (thesession.org is
  ODbL **+ a no-LLM clause + composer-copyright risk** → excluded entirely;
  hosting it on HF can't honour "no LLM use".)
  - 🔶 **The RULE is now built (2026-07-26): `lib/core/licensing/license_obligations.dart`**
    (+ 23 tests). `obligationsFor(works)` returns what an export owes:
    `requiresAttribution`, `requiresShareAlike`, the licence the **output** must
    carry, the works to credit, and a `noticeText()`. It encodes the three things
    that make SA different from attribution: SA is **infectious** (one SA
    contributor governs the whole output); mixed CC BY-SA versions resolve to the
    **newest** (BY-SA permits relicensing an adaptation upward, so 3.0+4.0 ships
    as 4.0 — claiming 3.0 would under-license the 4.0 part); and **incompatible
    copyleft is a conflict, not a choice** (ODbL with CC BY-SA is reported so a
    caller refuses, because picking one would be inventing permission).
    It classifies via `LicensePolicy.classify` rather than matching strings
    itself — that is already the compliance spine, and a second opinion about
    what a licence means is the bug to avoid.
  - ✅ **WIRED in the Audio Editor (2026-07-26).** `Clip.provenance`
    (`LicensedWork?`) travels with the clip — `copyWith` keeps it, so an edit
    can't launder the licence away — and it is **saved in `.cbdaw`**, because an
    obligation that disappears on reload looks discharged. A stored provenance
    without a licence is dropped rather than resurrected as licence-free.
    `DawService.licenseObligations()` reports what the arrangement owes right
    now (delete the SA clip and the obligation goes with it); the export dialog
    shows the notice **before** the format chooser and **disables export**
    outright when `hasProblem` — incompatible copyleft, or NC/unstated material
    in the mix. Clips the user recorded or generated carry no provenance and owe
    nothing. +8 wiring tests on top of the 21 rule tests.
  - ✅ **Import paths POPULATE it (2026-07-26).** Every route into the Audio
    Editor funnels through `addSampleClip`, so the licence attaches in one
    place: a `SampleClip`'s `license`/`source`/`sourceUrl` become the clip's
    `LicensedWork`. A clip with no declared licence carries nothing, which is
    right — a recording or a file off the user's own disk owes nothing.
    End-to-end tests cover the real path: importing a CC-BY-SA sample makes the
    export dialog say the whole mix is CC BY-SA 4.0, and importing a CC-BY-NC
    sample **disables the export button** (asserted on `onPressed == null`, not
    just on the warning text — a gate that only warns isn't a gate).
    **⇒ For the Audio Editor, the SA-propagation requirement is met.**
  - ✅ **All three editors gated (2026-07-26)** through one shared mechanism,
    `lib/shared/music_io/license_gate.dart` → `confirmLicenseObligations()`, so
    they can't drift into three different answers about the same licence. It
    returns false when the export must not happen; nothing owed → no dialog at
    all, because the common case must not grow a click.
    - **Audio Editor** — full: `Clip.provenance` survives edits + `.cbdaw`
      save/load, populated at the `addSampleClip` funnel, export refuses on
      `hasProblem`.
    - **Tracker** — full for instruments: provenance recorded at the
      `_addSavedInstrument` funnel and read from the CURRENT pool (remove the
      instrument, remove the obligation); **all five export paths gated** (audio,
      MIDI, MusicXML, ABC, module).
    - **Workshop** — full: gate on `_export`, populated via `noteProvenance()`
      from the picker.
    - **The shared picker now carries the licence.** `showMusicPickerWithLicense`
      returns `({score, provenance})`; the catalog path builds a `LicensedWork`
      from the item's `declaredLicense` + `composer` + `sourceUrl`, while
      built-ins and files the user opened themselves return null (they owe
      nothing). `showMusicPicker` stays as a thin unwrapping wrapper so callers
      that don't export are unaffected. **All three editors record it**: the
      Workshop via `noteProvenance`, the DAW onto the created clip, the Tracker
      into its score-provenance list — so library music is covered as well as
      library samples/instruments.
  - 📎 Also unified on the way: `SavedInstrument.needsAttribution` was a third
    hand-rolled copy of the rule (`license.contains('by')`), which also fired on
    CC BY-**NC** — material that must be BLOCKED, not merely credited. It now
    delegates to the shared classifier.
  - 📝 Worth knowing: `Gemeinfrei` alone classifies as **unknown**, not free —
    matching §"gemeinfrei / GEMA-frei ≠ free to bundle" below. A test pins that,
    because assuming otherwise is the obvious mistake.

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

> **▶ Live DB snapshot (2026-07-30): `db.json` = 46,339 rows** — 45,940 scores +
> 399 playback assets (232 instruments · 166 modules · 1 soundfont). The app-facing
> **HF catalog ships 38,900 items** (score 38,431 · instrument 232 · module 139 ·
> sample 97 · soundfont 1) — verified live and unauthenticated. Scores by source:
> GregoBase 18,684 · **PDMX 10,799** (74 is_original + 3,352 classical MXL
> shippable; see below) · NIFC Polish 8,181 · **CPDL 2,546** · OpenScore Lieder
> 1,350 · **Wikimedia Commons (Gerloff) 1,088** (1,073 CC0/A + 15 CC-BY/B) ·
> Tanzsammlung Dahlhoff 672 · NIFC Chopin 512 · Mutopia 510 · DCML Bach Chorales
> 361 · Ebersberger 235 · Dreysser 1720 168 · **Wikimedia Commons (MIDI) 160** ·
> Kinder wollen singen 154 · **Wikipedia (de) `<score>` 125 (Tier C, not shipped)**
> · OpenScore SQ 122 · OpenEWLD 103 · Arendsee 68 · Musikpiraten Season Songs 51 ·
> Internet Jukebox 31 · Pete Mac 15 · EGSet12 12. Assets: VCSL 183 · ModArchive 166
> · FreePats 39 · Shortcircuit XT 9 · Salamander Grand Piano V3 1 · FluidR3 1.
> The gap between 45,960 score rows and 38,448 shipped is the deliberate hold: SA
> engravings, unverified PDMX axis 2, and the probation ledgers.

> **🇩🇪 Wikimedia Commons — Peter Gerloff CC0 MIDI settings (German folk + hymns),
> ingested 2026-07-23.** The **Rabanus Flavus** uploads of Peter Gerloff's MIDI
> settings (`Category:MIDI files of melody settings by Peter Gerloff (secular|sacred)`)
> — a real German-folk/hymn source, per-file licence verified via the Commons API.
> **Exact tiers of the 1,136 files: A (CC0/PD) 1,083 · B (CC-BY) 16 · C (CC-BY-SA) 37.**
> Ship gate = Tier A ∩ axis-2-PD (the melody source is traditional/origin, Gerloff's
> own CC0-original, or a named composer the shared `wikidata_deaths` verdict confirms
> died ≤1955) → **1,088 ingested** (1,073 Tier A + 15 Tier B) — MIDI-only (Commons hosts these as `.mid`; Gerloff
> is a priest/composer who makes a "Satz und Tondatei" for German Wikipedia articles
> and publishes **no notation source** — for richer formats use the kinder-wollen-singen
> `.mscz`/`.musicxml` or self-engraving). Tooling: `bin/commons_gerloff_{ingest,reverify,
> reconcile,demote}.py`.
> **⚠ FIVE VERIFICATION PASSES (2026-07-23) — each caught what the prior missed:**
> (1) ingest 846; (2) a spot-check of 10 found the parser only matched German `Melodie:`,
> missing English `Melody:/Music:/Kanon:` → ~401 rows had defaulted to "traditional"
> **unverified** ("Woodlands tune" is Walter Greatorex d.1949) → re-verify to 836 by
> death-checking every named composer; (3) reconcile recovered +240 genuinely-PD held
> rows via a broad multilingual descriptor set; (4) **but descriptor-matching bypassed
> the death-check** — a safety scan caught **Sibelius "Finlandia" (d.1957) and Vaughan
> Williams ×2 (d.1958)** hiding behind descriptor labels (genuinely copyrighted in the
> EU); (5) a thorough pass death-checked **every** 1-3-word name in **every** kept row's
> source → **−14, fail-closed** (Sibelius/VW + namesake false-flags like "Curtis"→De
> Curtis, "Francisco"→*Pope Francis*). (6) **Manual promote:** re-fetched the 14
> demoted files' REAL source and promoted the **11 namesake false-flags** whose actual
> composer is verified PD (De Curtis d.1937, M. Greiter d.1550, Nicholson d.1947, F. de
> Lacerda d.1934, S. Cohen d.1940, medieval/trad); only **3 genuinely-recent stay held**
> (Sibelius d.1957, Vaughan Williams ×2 d.1958). **Final: 1,073 soundly Tier A** — traditional/origin · named-PD-verified · Gerloff-CC0-original;
> **0 recent composers, 0 embedded recent years survive**. The copyrighted Sibelius MIDI
> was in the first upload → **deleted from HF HEAD** (`delete_file`; a purged file is
> 404 at `main`. ⚠ old commit SHAs may still serve it — a full history purge was NOT
> done for one file; flagged for the maintainer).
> **TIER B (CC-BY) done:** of the 16, **15 shipped with attribution** (`bin/commons_gerloff_tierb.py`; `attribution="Peter Gerloff (Rabanus Flavus), CC BY 4.0[; melody: Crüger/Mason]"` → the app's already-built "Sources & credits" surfaces it; the catalog-tiers work already ships A+B). ⚠ axis-2 still applies to the MELODY, not just the CC-BY setting — **1 held: "Sankt Josef" = Erhard Quack d.1983** (copyrighted melody under a CC-BY setting). Remaining **HELD**: 37 Tier-C (SA-propagation), the axis-2-not-provably-PD, and the 3 axis-2-recent (Sibelius/VW).
> **Lessons:** (a) never default to "traditional" — read the melody source in every
> language; (b) **a descriptor keyword must not short-circuit the composer death-check**
> — a "traditional English hymn tune by X" can still hide a d.1958 composer. **Lesson:**
> a self-attested "traditional"
> default is unsafe — read the actual melody-source field and death-check named
> composers; the parser must cover every language the source uses. ⚠ Wikimedia
> rate-limits bots (HTTP 429) — the downloader paces 1.2 s/file + 60 s backoff.

> **🌐 Wikimedia Commons — general MIDI sweep, tiered from STRUCTURED DATA
> (2026-07-30). +160 rows.** The Gerloff pass above read one contributor's
> uploads; this one sweeps `filemime:audio/midi` across Commons. The change that
> makes it defensible is *where the tier comes from*: not
> `extmetadata.LicenseShortName`, which is a rendered STRING produced by whichever
> template the uploader happened to pick, but **Structured Data on Commons** —
> `P6216` copyright status and `P275` licence as machine-readable Q ids. That is a
> claim to point at rather than prose to pattern-match. A share-alike or GFDL
> statement disqualifies even when the file *also* claims public domain: the most
> restrictive statement governs what we may redistribute. `Q99263261` ("no known
> copyright restrictions") is deliberately not treated as PD — it records an
> absence of knowledge, not a grant. ⚠ Every Q id in the table was looked up; a
> first pass *guessed* `Q71979350` meant "PD, author life+70" when it is a person's
> name. Do not extend that table from memory.
> **Axis 2 is decided separately** (`tool/music_db_commons_axis2.py`) and it is
> where the interesting shape is. 357 files cleared axis 1; **247 cleared axis 2,
> 110 held**, by four rules: **T** 123 — a generated theory example (scale,
> hexachord, equal-temperament step, chord inversion) has no separate composer at
> all, the uploader is the author and dedicated it PD, and a C-major scale is not a
> copyrightable composition; **P1g** 75 — the credit splits as
> `Melodie: <origin>; Satz und Tondatei: <arranger>`, so axis 2 turns on the
> MELODY, not on the living arranger in the same line (this is what separates a
> 1529 Wittenberg chorale from the person who typeset it); **P3** 36 — every named
> person verified dead ≤1955 via Wikidata; **P2/P1c** 13 — an explicit lifespan or
> century in the credit. Of the 247, **87 were already in the corpus** from the
> Gerloff pass and were skipped — a general sweep re-finds a single-contributor
> harvest, and two rows for one work is worse than a miss because nothing
> downstream can tell them apart. **160 ingested, all Tier A (PD), 160/160 parse,
> 25,842 notes.** The 110 held are parked in `commons-midi-held.json`.
> **The trap worth recording:** the harvested `artist` field is the UPLOADER, not
> the composer, and one editor accounts for a third of the set. Feeding it to a
> resolver as a composer name is how a username coincidentally clears; the pass
> therefore never takes names from the *title* (a work title is not a credit —
> "Da Jesus an dem Kreuze stund" yields the name-shaped "Da Jesus") and never
> resolves a **mononym**, since a one-word label is exactly what an
> all-candidates-PD rule can clear by accident.

> **🇩🇪 de.wikipedia `<score>` melodies — 127 rows, Tier C, LOCAL ONLY (2026-07-30).**
> German song articles embed their melody as a LilyPond `<score>` block. The wiki
> text is CC BY-SA, so the *engraving* is share-alike; whether a faithful
> transcription of a public-domain melody carries any new authorship at all is a
> maintainer call that has not been made, so share-alike governs and these are
> **Tier C — in `db.json`, never in the shipped catalog** (`_tier()` sends any
> `-sa` licence to C; `ships()` is A|B). Axis 2 is recorded as **UNASSESSED**
> rather than guessed: writing a confident "traditional, PD" on a row nobody
> checked is the exact failure the Ebersberger pass exists to prevent, and it
> would become load-bearing the day someone promotes these. **Assess axis 2 before
> any promotion.**
> Two bugs surfaced here, both of which had been *silently* costing music:
> (a) an earlier version of the harvester stripped `\addlyrics`/`\lyricmode` to
> avoid copying text, which left dangling `verse = ` assignments that swallowed the
> following `\score` block — 23 of 127 melodies read as empty for that reason
> alone. The source is now kept whole (a song corpus needs its words, and a
> protected text is a matter for the axis-2 gate, not for silent discard);
> (b) `\transpose f g \relative c'' { … }` — the ordinary unbraced spelling — left
> its body a *sibling* of the command, so a variable assignment bound the name to a
> transpose with no music. Single-staff sources hid it; two-staff scores read as
> silence. Fixed in crisp_notation `abb4b9e`. **All 127 now parse, 0 empty.**
> **2 held on CONTENT, not rights** (`commons-wp-ly-held.json`, out of `db.json`
> → **125 rows**): *Erika* and *Westerwaldlied*, both Herms Niel (d.1954). Axis 2
> clears them — that is exactly the point. The licence tiers encode who owns a
> work, not whether a NS-era Wehrmacht marching song belongs in a children's
> music-education corpus, so nothing in the rights pipeline would ever have
> stopped them. Restoring is a maintainer call.

> **📊 Coverage measured against `de.wikipedia Kategorie:Volkslied` (2026-07-30).**
> A category listing is a decent external yardstick for German folk-song coverage,
> so: **428 articles · 241 we have · 187 we lack.** The 241 counts the 127 Tier C
> rows above — every one of the 28 gap titles that embeds a `<score>` was already
> in that batch, so *there is nothing left to harvest this way*. The remaining
> **187 have no notation on their Wikipedia page at all**: filling them means
> sourcing or writing the melody, not scraping. A sizeable share are non-German
> folk songs catalogued in the German category (Arirang, Cielito lindo, Baïlèro,
> Chad gadja) and a few are modern enough to be axis-2 blocked regardless
> (Banana Boat Song, 1956). Tooling: `tool/music_db_wp_category_gap.py` (normalises
> titles — disambiguators, umlaut transliteration, leading articles — because a raw
> string compare reports nearly everything as missing and buries the real gaps) and
> `tool/music_db_wp_score_check.py` (splits a gap list into harvestable-today vs
> genuine content gap; without that split a gap list is only a wish list).

> **📦 SHIPPED-CATALOG SIZE — measured and cut 18x (2026-07-30).** The score shard
> was **36.5 MB of raw JSON, re-downloaded on every cold start**: the app's cache
> was in-process only, and the source file's own header wrongly claimed *"HF's CDN
> serves each file gzipped on the wire"* — it does not, verified by requesting the
> shard with and without `Accept-Encoding` and getting the identical byte count.
> Where the bytes went (38,431 items): `music` 10.81 MB · `sha256` 2.92 · `path`
> 2.41 · `sourceUrl` 2.14 · `attribution` 1.25 · `license` 1.23 · `bytes` 0.50.
> Three of those the client never reads — `LibraryItem` is built from
> id/name/kind/format/license/attribution/sourceUrl/path/music, and
> `incipitIntervals` (2.72 MB) is simply the first differences of `incipit`.
> **Dropped all three (−9.8 MB) and emitted a `.json.gz` twin advertised as
> `urlGz`: 36.5 MB → 26.7 MB raw → 2.00 MB gzipped.** Removing the incompressible
> sha256 hex also lifted the gz ratio from 8.0x to 13.3x, and not hashing ~2.5 GB
> cut `emit_catalog.py` from **2m11s to 19s**. App side prefers `urlGz`, sniffs
> the gzip magic rather than trusting the URL, and **persists shard bytes keyed on
> the catalog `version`** (reusing the existing files-on-native /
> IndexedDB-on-web byte store), so a cold start costs one ~1 KB index fetch.
> Cache faults degrade to the network — a browse that cannot persist is still a
> browse. 5 regression tests cover prefer-gz, cross-launch reuse, version
> eviction, a throwing cache, and an un-gzipped shard.
> **⚠️ Lesson from a self-inflicted bug in this very change:** the first patch's
> anchor (`"bytes": …` + `"sha256": …`) appears TWICE in `emit_catalog.py`, and it
> asserted only that the anchor was PRESENT before replacing with `count=1` — so
> it stripped sha256 from 97 percussion samples and left it on all 38,431 scores,
> i.e. exactly the 2.9 MB it was meant to remove. **Assert anchor UNIQUENESS, not
> presence.**
> **Not done (deliberate):** SQLite. It would not fix this — a `.db` is the same
> order of size and FTS5 adds 30–50%, while `sqflite` has no web support at all
> (you ship `sqlite3.wasm` + OPFS/IndexedDB). At 38k rows query speed is a
> non-issue. Revisit for FTS5-quality search, or when the index stops fitting; the
> end state if the corpus outgrows a shippable index is SQLite over HTTP Range
> (**HF does honour Range — verified 206**), which needs a custom Dart VFS.

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

- **Internet Jukebox (Internet Archive / Public Resource) — 31 rows INGESTED
  from 24 cleared items, 180 held (2026-07-28).** `collection:PublicJukebox`:
  period sheet-music prints
  (Sousa marches, silent-film pit-orchestra pieces, vintage popular song, folk
  songbooks) run through OMR by Public Resource, who publish **`.musicxml` +
  `.mid` beside the audio** — so the symbolic-only content rule is satisfied by
  taking the first two and ignoring the rest. Of 204 items carrying a symbolic
  derivation, 193 have MusicXML (238 files — five are multi-piece books whose
  pieces are transcribed separately) and 211 have MIDI.
  - **Axis 1 — mostly settled: 181 of 204 items carry CC Public Domain Mark 1.0**
    and Public Resource dedicate the derivation itself (their metadata credits
    the OMR + their own post-processing). A faithful transcription of a PD print
    carries no new authorship anyway. ⚠️ **23 items (the silent-film `ORCH-*`
    block) carry NO licence statement at all** — those are held, because we do
    not infer a dedication from a neighbour's tag.
  - **Axis 2 — the real gate, and it does NOT come with the tag.** The Internet
    Archive determines public domain on the **US pre-1930 publication rule**;
    our ship gate is **EU life+70**. Those disagree loudly here: the collection
    contains Irving Berlin (*Always* 1925, *All Alone* 1924 — US-PD, EU-protected
    until **2059**), Vaughan Williams (d. 1958), and editors/arrangers who lived
    well past 1955. So every item is **held by default** and promoted only on
    100% ground, exactly as for the other per-item-cleared sources.
  - ⚠️ **THE PARENT-BOOK TRAP — the finding that dominates this source.** Public
    Resource split multi-song books into **one IA item per song**, and the child
    item credits only *that song's* arranger. Whoever compiled and edited the
    VOLUME appears only on the parent item. **133 of the 204 items come from a
    single book** — *140 Folk-Songs For Grades I, II, And III* (E. C. Schirmer,
    1922), compiled and edited by **Archibald T. Davison (d. 1961**, Wikidata
    Q633492) and Thomas Whitney Surette (d. 1941). **Any per-item ingest from an
    archive that explodes books into items MUST resolve the parent** — not
    because the compiler's own term necessarily binds (see the resolution below:
    it does not), but because **the parent is the only place the volume is
    identifiable at all**, and identifying it is what exposed the real blockers.
    Cleared count before the parent check: 76. After: 24.
  - **Result: 24 cleared items → 31 db rows (Tier A, no attribution owed) · 180
    held.** All 24 cleared via Wikidata-confirmed life+70 (the traditional/
    anonymous rule no longer fires anywhere, because the parent book's compilers
    are named on every song that would otherwise have qualified). Held: 133 from
    the songbook (embedded English translations + newly-composed accompaniments,
    see below), 23 with no licence statement, the rest on authors who died after
    1955 or names that do not resolve. Held items live
    only in `jukebox-probation.json`, never in `db.json`, so a later pass can
    widen the set without a rebuild.
  - ✅ **RESOLVED by reading the book itself (2026-07-28) — the hold stands, but
    the mechanism is NOT Davison.** The IA scan's own front matter says
    "**Compiled and Edited** for use in school and home by Dr. Archibald T.
    Davison & Thomas Whitney Surette", and every song carries its own separate
    credit. So Davison/Surette are §4 UrhG *Sammelwerk* compilers — their right
    covers the selection and ordering OF THE COLLECTION, and **lifting a single
    song does not touch it.** Judging these songs on Davison's death year was
    directionally right (hold) but mechanically wrong.
    The songs are blocked for two better-evidenced reasons, both per-song:
    1. **The named people are TRANSLATORS, not arrangers.** The book credits
       "English words by Homer H. Harbour", "English version by William B. Snow"
       — the IA metadata's "(Arranger)" label is simply wrong. Their English
       translations are protected in their own right (life+70), and **all 133
       MusicXML files embed those lyrics** (88 syllables in the sample).
    2. **The piano accompaniments are newly composed.** The preface states the
       folk-songs "were doubtless originally sung without accompaniments", so the
       accompaniment is 1920s work, not folk material — and **all 133 files carry
       it as a second part**. Four files even retain a `<rights>1921 E. C.
       Schirmer Music Co.</rights>` line inside the XML.
  - 🛑 **DECIDED — the 133 STAY ON HOLD (maintainer, 2026-07-28). Do not
    re-open this without the maintainer.** A melody-only extraction was
    identified as the one technical route that could clear them: 130 of the 133
    are traditional folk-songs/carols, so dropping part 2 (accompaniment) and
    every `<lyric>` element would leave only the PD tune — which is exactly what
    the publisher's own companion volume was ("Book No. 3 in the Concord Series,
    containing the melodies of the songs without accompaniments"). It was **not
    taken**, because it would mean publishing a modified derivation and
    asserting our own PD determination on the melody line rather than resting on
    a rights statement. The files stay on the VPS and in
    `jukebox-probation.json`, out of `db.json`, so the option remains open at
    zero cost if that judgement ever changes.
  - **The residue is 27 names, not a wall of them** — and one name,
    **Homer H. Harbour**, gated 43 items on its own. A human-supplied alias
    ledger (`jukebox-aliases.json`) fixed source typos and abbreviations
    (*Constatin* von Sternberg, John Howard *Paine*→Payne, "Joseph" Concone =
    Giuseppe, bare "Young & Herbert" = Rida Johnson Young + Victor Herbert) and
    verified 7 of 11 against Wikidata — **the ledger supplies only the
    identification; the death year still comes from the source**, so nothing is
    promoted on recall. It also turned one vague UNKNOWN into a documented
    BLOCKED (Jos. E. Howard, d. 1961).
  - **Arrangers and editors gate a row as hard as composers.** An arrangement is
    separately protected for the arranger's life+70, which is why a traditional
    folk tune arranged in 1922 by a named arranger is not automatically clear.
  - **All 238 MusicXML files parse through `crisp_notation`** (`scoreFromMusicXml`):
    238/238, zero failures, zero note-less files.
- **Internet Jukebox OMR eval pairs — 194 (page scan → MusicXML) pairs.** The
  same items pair the original page image with the symbolic transcription of that
  page under CC PDM 1.0 — a licence-clean image→symbolic corpus, unlike the
  unnamed robustness controls. ⚠️ **SILVER, not gold:** it is OMR output with
  human post-processing of unknown depth, so it is valid for regression tracking
  and relative comparison and **not** for publishing an absolute accuracy figure
  — least of all for the engine that produced it, which would measure
  self-consistency rather than accuracy. Registry: `jukebox-omr-eval.json`.

- **CPDL / ChoralWiki — 2,265 scores INGESTED, 1,502 held (2026-07-29).** The
  largest single addition since PDMX, and now our second-largest MusicXML source.
  Choral repertoire: early-American singing-school (William Billings 212, Oliver
  Holden 194, Daniel Read 132, Samuel Holyoke 120) plus Renaissance polyphony
  (Marenzio 79). 218 distinct composers, 1,608 rows carrying a lyricist.
  - ⚠️ **LICENCE IS PER EDITION, NOT PER PAGE — this is the whole game.** A CPDL
    page hosts one edition per contributor, each with its own `{{Copy|…}}`.
    *10 catches (Henry Purcell)* carries a **Public Domain** edition
    (`Purcell_10Catches.mxl`) AND a **CPDL-licensed** one (`Purc-sweet.mxl`).
    A per-page filter would either ship the CPDL file or drop the PD one; ours
    binds each `{{CPDLno|…}}` block's licence to the `[[Media:…]]` links inside
    that block. Verified after ingest: the PD file is in `db.json`, the
    CPDL-licensed sibling is not.
  - **Licence distribution over 54,372 editions:** CPDL(GPL-derived) 31,521 ·
    Personal 11,050 · **Public Domain 5,662** · CC BY-NC 2,168 · CC BY-NC-ND 784
    · CC BY-SA 527 · Religious 430 · GnuGPL 163 · CC BY-ND 154 · Free Art 107 ·
    **CC BY 102** · CC0. Shippable = 5,769 → 3,791 after dropping PDF-only
    editions and 91 files absent from the dump.
  - ⚠️ **CC BY-ND is excluded specifically because WE CONVERT FORMATS.** ND
    forbids derivatives and a format conversion is one. Easy to wave through as
    "attribution-only"; it is not.
  - **Axis 2 gates on composer, arranger, lyricist AND translator.** CPDL records
    all four and **2,887 of the 3,791** name a lyricist — this is choral music,
    nearly every page has a text. Gating on composer alone would repeat the
    Internet Jukebox songbook mistake at ten times the scale. Result: 2,289
    cleared (2,279 via Wikidata life+70, 10 anonymous pre-1900), 1,502 held
    (1,333 unresolvable names, 148 died after 1955, 21 anonymous without a
    pre-1900 date).
  - **Parse-validated before ingest: 3,762/3,791 (99.2%)** through
    `crisp_notation`; the manifest additionally drops the 24 that fail or read
    empty, so every shipped row is known-readable. The sweep found **five real
    reader bugs and fixed them** (crisp_notation `362a2b4` + `68b8e6c`):
    `<senza-misura/>` unmetered scores — the standard encoding for barline-free
    Renaissance polyphony, which had been rejecting Byrd/Gibbons/Palestrina
    wholesale; plain MusicXML shipped under a `.mxl` extension; and three
    LilyPond bugs (`\<` lexing as a chord-opener that swallowed the rest of the
    part, plus `\new Staff = "name" << … >>` and `\context Voice = "x" { … }`
    dropping their music). Together: +49 files, and LilyPond went 42/59 → 57/59.
    ⚠️ The `\<` bug **silently truncated** — 23 files that "parsed fine" gained
    **+4,917 notes**, one going 111 → 584. Any pre-fix `.ly` note count is
    suspect. `.mxl`/`.mscz` are unwrapped
    with the pure-Dart zip readers — no MuseScore or LilyPond binary anywhere.
  - **Tiering is mixed, unlike previous sources:** 2,248 Tier A (Public Domain /
    CC0, no attribution owed) + 16 Tier B (CC BY, attribution = the *editor*,
    who made the engraving the licence covers — not the long-dead composer). All
    16 carry attribution, so none are silently dropped by the ship gate.
  - The other **31,521 editions under the CPDL licence** (GPL-derived copyleft)
    are Tier C → local-only under the current `emit_catalog` gate, which ships
    A|B. A large reserve if Tier C is ever revisited.
  - Held editions live only in `cpdl-probation.json`, never in `db.json`, so a
    later pass can widen the set without a rebuild.

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
| **TradArchiv — 3 manuscripts** ✅ **INGESTED — 908 rows** | ABC | **No copyright asserted** by the transcribers; **attribution to the source required** → Tier B | **Tanzsammlung Dahlhoff** 672 rows (Staatsbibliothek zu Berlin, Mus. ms. 40182, before 1767; 129,336 notes) · **Dreysser 1720** 168 rows (Bayerische Staatsbibliothek, Mus. ms. 1578; 11,335 notes) · **Arendsee** 68 rows (Mecklenburg, tunes est. 1760–1820; 5,021 notes). **All three 100% parse.** Axis 2 spotless: anonymous dance tunes, and the few named composers are Telemann d.1767, Hasse d.1783, Jommelli d.1774, Campra d.1744 — per-file `C:Urheber:` makes the death-check mechanical. Attribution surfaced in `attribution_screen.dart`. ⚠ The archive's ~17 *dance-category* pages are index listings with **no files**, and they credit living composers — they are not a fourth collection. |
| **Project Gutenberg Sheet Music** ✅ **INGESTED — 11 rows** | MusicXML / LilyPond / MIDI | **US public domain**, "no warnings or restrictions of any kind" → Tier A | 7 Beethoven string quartets (Opp. 18/3–6, 74, 127, 132) + a Handel overture; 170,393 notes, 100% parse. ⚠ The often-repeated "30+ scores in MusicXML" is **wrong** — it is 8 works; the other 25 items are Finale `.MUS` only, which stays opaque. |

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
| German folk-song sites (4) | — | **volksliederarchiv.de — re-verified 2026-07-30, rejected on five independent grounds** (was already rejected on two): (1) explicit NC in the Impressum — *"Downloads und Kopien dieser Seite sind nur für den privaten, nicht kommerziellen Gebrauch gestattet"*; (2) *"Die Vervielfältigung, Bearbeitung, Verbreitung und jede Art der Verwertung außerhalb der Grenzen des Urheberrechtes bedürfen der schriftlichen Zustimmung"*; (3) operated by a commercial publisher asserting site-wide copyright; (4) **`robots.txt` `Disallow: /notenpdfs` for `User-agent: *`** — the notation directory specifically, and it additionally blocks several automated user-agents from the whole site; (5) **not symbolic anyway** — the "Noten" are JPG/PDF page images, so it would be OMR input at best, and we already hold licence-clean OMR eval pairs. Scale is real (861 Kinderlieder; 11,000 texts / 5,750 melodies) but the repertoire is one we already cover from cleared sources. **Do not crawl, not even as a held control** — unlike other controls, this site's robots.txt forbids the very directory the material sits in. ⚠ lieder-archiv.de (copyright on its Notensätze; commercial/DB/republish forbidden — but offers a PAID licence); liederlexikon.de (all-rights-reserved, NOT CC, named living engraver + in-copyright 20th-c. works); ZPKM Freiburg (catalogues only). |
| **Essen Folksong Collection** (ccarh/essen-folksong-collection) | krn ✅ | **CCARH MuseData licence** (license.txt, verbatim): *"this license does not authorize the use of the enclosed MuseData files in the production of derivative editions intended for commercial distribution, nor for public performance (including broadcast), nor for sound recording."* NC + no-recording → dev/test only. ~20k folk melodies, German-relevant, but blocked. |
| **Battle of the Bits** (battleofthebits.com) | .xm/.it/.mod + rendered | **CC BY-NC-SA** to third parties (BotB CC License, verified) — NC. Original chiptune/tracker compo entries (axis-2 clean), but the NC axis-1 blocks it. Control/eval only. *Corrects an earlier "BotB is clean" note.* |
| **SymbTr** (Turkish makam, MTG/UPF) | MusicXML/MIDI/mu2 | **CC BY-NC-SA 4.0** — NC. 2,200 pieces; repertoire we have nothing comparable to, which makes the NC especially costly. |
| **ASAP** (Aligned Scores and Performances) | MusicXML/MIDI | **CC BY-NC-SA 4.0** — NC. 222 scores / 1,068 performances. |
| **SEILS** (Il Lauro Secco, 16th-c. madrigals) | .ly/.xml/kern/MEI/mens | **CC BY-NC-SA 4.0** (LICENSE.txt) — NC. Would otherwise be excellent mensural-notation material. |
| **DCMLab/schema_annotation_data** (18 Mozart sonatas) | MusicXML/mscz | **No LICENSE file** → no grant, fails closed. Consistent with the DCML house licence (BY-NC-SA) noted above. |
| **Werner Icking Music Archive** | PDF (+ some source) | **NC**, and it is a trap worth naming: PD composers throughout, but the archive imposes its own restriction on the engravings — *"free for non-commercial usage… you may not sell the files or printed copies."* |
| **Hymnary.org** | MusicXML/MIDI/PDF | No bulk grant; per-item — *"Some texts, tunes, images… are in the public domain and some are copyrighted with rights reserved."* Axis-2 compounds it: the tune is usually PD but the **hymnal harmonization inside the file** is the protected layer. |
| **Musopen** | PDF (mostly), some MIDI/LilyPond | Uploaders merely *"represent and warrant that content uploaded to the site is in the public domain"* — the uploader-asserted provenance model that already failed us elsewhere. 100k+ items are PDF; the symbolic slice largely mirrors Mutopia, which we hold directly. |
| **NWC Scriptorium** | .nwc | **Private-use / non-commercial**, verbatim: *"These pieces are for private use only… You may not market them for monetary gain."* Files are PD *or used with the copyright holders' permission* — permission granted to them, not transferable. No per-file licence field, so no filterable clean subset. 14,173 files. Format was never the blocker (open `.nwc` converters exist); the licence is. |
| **UCLA Contemporary Music Score Collection** | PDF | **CC BY-NC-ND**. NC blocks us and **ND blocks us independently — we transform formats, and a conversion is a derivative.** Living composers. |
| **NMA Online / Digital Mozart Edition** | images (+ MEI) | *"Wholesale downloading or reuse of the contents of this website is prohibited under all circumstances, whether commercial or otherwise."* Personal study only. |
| **CCARH scores / MuseData** | MuseData/kern | Editions are **under copyright** with named editors, access requires registration; Creative Commons' own directory records the licence as "copyright" and open/free as "no". Same licence family as the Essen entry above. |
| **Gallica (BnF)** | images | *"La réutilisation commerciale de ces contenus est payante et fait l'objet d'une licence."* Effectively NC for us — PD works, but the BnF asserts a paid licence over its own scans. |
| **traditionalmusic.co.uk** | ABC/MIDI/tab | *"Entire site (C) Traditional Music Library. All rights reserved."* Acknowledges the underlying content is "mainly public domain category" but grants nothing, and exposes no per-file licence field to filter on. |
| **JC's ABC music archive** (a large personal ABC collection on a university staff page) | ABC | **No licence.** Its entire copyright policy is notice-and-takedown — *"If a tune here is copyrighted and the owner objects to it being here, I will of course remove it"* — which is an explicit admission that the archive holds copyrighted tunes with no clearance done. ⚠ A `GPL.txt` sits in the collection directory, filed alphabetically among the country folders; it is the plain GNU GPL v2 text and nothing applies it to the tunes. Do not read it as a grant. Parts of the repertoire (an 1903 Irish collection, historical book transcriptions) are axis-2 clean by age, but axis 1 still fails and the archive is admittedly mixed. |

---

## Aggregator guides — swept 2026-07-29, don't re-survey

Eight "free/public-domain sheet music" link lists were worked end-to-end
(a conservatory library guide, two university library guides, a MusicXML
vendor's own list, a public-domain reference site, and four German
children's-song lists). Combined they name ~130 resources. **Net new material:
two sources, both now in hand.** Recording the sweep so the next pass starts
from the residue, not from zero.

Two gates account for essentially every rejection:

1. **It is page images, not symbolic data.** The library guides are ~85%
   digitized facsimiles. Our DB is symbolic-only, so a scan collection is not
   corpus material at all — it is input to a transcription pipeline, which is a
   different decision with a different cost. This is why a librarian's
   discovery guide has near-zero yield for us: it is optimised for *reading*
   scores, not for *reusing* them.
2. **The digitization layer carries its own restriction**, even when the
   underlying work is spotless PD. See Gallica and WIMA in the rejected table.

⚠️ **Correction to a natural assumption: US institutions do NOT uniformly
release PD scans freely.** Measured per collection — **Duke HASM** ("personal,
research, or educational use only"), **Indiana University** ("noncommercial,
personal, or research use only"), **NYPL** (commercial use "strictly
prohibited", usage fee), and **U. Chicago Chopin Early Editions** (commercial
reproduction requires permission and a fee) all impose restrictions.
**Levy/JHU** ("There are no restrictions on the public domain works") and
**UCLA APAM** ("You may use the public domain sheet music as you like") do not.
So the terms must be read per collection; do not generalise from one.

**If transcription ever becomes the strategy**, the best-licensed inputs found
were: Levy/JHU, UCLA APAM, Library of Congress *Music for the Nation*, and the
**HathiTrust Women Composers Collection** (~3,000 works by 700+ women
composers, which would fill a genuine repertoire gap). HathiTrust restricts
bulk download, so that one needs its own approach.

**Already-held sources these guides re-list** (no action, but they keep
resurfacing): IMSLP, CPDL, Mutopia, OpenScore, MuseScore.com/PDMX.
**OpenScore's CC0 grant was re-confirmed this pass** — *"These scores are
released under Creative Commons Zero (CC0)"* — and the Lieder corpus has grown
past 1,200 songs, so our snapshot is worth refreshing.

**Unresolved, worth one retry** (infrastructure failures, not rejections):
**NEUMA** (`neuma.huma-num.fr`, HTTP 502 — a Huma-Num research library of
French 17th–19th-c. corpora, plausibly open) and **Folkoteca Galega** (TLS
certificate failure on both domains — collaborative traditional Galician music
in MusicXML). **Free Music Editions** (Christoph Dalitz, three-part choir) is
CC BY *or* CC BY-SA per edition — Tier B/C, small, format not yet confirmed.

### German children's-song lists — four swept, **zero new sources**

A useful negative result: the German kids'/folk-song discovery channels all
circle back to material we already hold. Every one of the four lists is a blog
post, forum thread or link page — none is itself a corpus, and **none of them
surfaces a single MusicXML/LilyPond/MuseScore file.**

- Two of the four point straight at **corpora already in `db.json`** —
  *Kinder wollen singen* (155 rows) and the Musikpiraten Christmas songbook
  (52 rows). That is the strongest available evidence that our German
  children's-song coverage has reached the practical ceiling for this channel.
- The rest were already assessed here: Mutopia, CPDL, IMSLP (held);
  free-scores.com, volksliederarchiv.de (rejected above).
- **Das Liederprojekt** (SWR + Carus-Verlag, 600+ folk/children's/lullaby
  songs) is the only substantial new name, and it is **rejected**: no licence
  or terms-of-use statement anywhere, so default all-rights-reserved by a
  commercial publisher. An OER project that catalogued it reached the same
  conclusion independently — "not OER-compliant, requires explicit permission."
- Smaller names, all out on the symbolic-only rule or on licence:
  **kitalieder.de** (MP3 only), **BabyDuda** (PDF + MP3, no licence stated),
  **labbe.de/liederbaum** (commercial publisher).

⚠️ "GEMA-frei" is **not** a licence and does not mean reusable. It only says no
performing-rights society collects on it. A GEMA-free song can still be fully
in copyright, and the *engraving* is a separate layer again. Several of these
pages use the phrase as if it settled the question; it settles nothing for us.

**One informal grant, pending confirmation:** a classical-guitar arranger
publishing his own arrangements of PD Renaissance/Baroque works states
*"Make use of anything you find here, but please mention this site if you
do."* That is the author's own dedication on his own site — the same standard
that cleared individual contributors elsewhere in this doc — but it is not an
SPDX licence and is silent on commercial use. One email would settle it into a
grant row; until then it stays out of `db.json`.

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

**⚠️ CONTENT POLICY — the THIRD axis: appropriateness (maintainer, 2026-07-30).**
Every other gate in this document answers *who owns it*. None answers *should a
child see it*, and the two come apart in both directions. **Herms Niel died in
1954, so a Wehrmacht marching song clears axis 2 cleanly. A minstrel song from
1867 is spotless public domain and has a slur in its title** — *"Run, Nigger,
Run (1867)"* was live in the shipped catalog, having passed every rights gate we
have. So: **Wehrmacht/NS repertoire and material carrying racial slurs are held,
regardless of licence.** Tooling: `tool/music_db_content_screen.py` →
`tool/music_db_apply_content_hold.py`.

- **It reads the FILE, not the row.** A clean title routinely hides a slur in
  verse 3. Text formats directly, `.mxl`/`.mscz` unzipped in memory, MIDI decoded
  latin-1 so lyric and track meta events are searched too. 45,958 score rows.
- **Two tiers, and the split is the whole design.** `hold` = terms that are slurs
  in any context, applied automatically. `review` = context-dependent terms,
  **listed only, never auto-applied**. That is not caution for its own sake:
  **every single `Mohr` hit was Joseph Mohr, the lyricist of *Stille Nacht***.
  Auto-holding the review tier would have deleted *Silent Night* from four
  sources on a surname.
- **A term shorter than ~5 characters is not safe against this corpus.**
  `\bwog\b` and `\bcoons?\b` produced 7 hits and all 7 were false, for three
  independent reasons worth remembering: **lyrics are syllabified** (a vocal
  score stores `wog-nia` as its own syllable, so a word-boundary anchor matches a
  fragment that is not a word); German has the ordinary word *wog* (it caught
  Schumann's *Mondnacht*); and latin-1-decoded MIDI bytes can spell any short
  sequence (a 1915 Sousa march matched `WOG`). Both patterns were removed.
- **⚠️ THE BIG ONE — syllabification also causes false NEGATIVES, and those are
  invisible.** A vocal score does not store `darkey`; it stores
  `<text>dark</text>` in one `<lyric>` element and `<text>ey's</text>` in the
  NEXT one, ~200 characters of XML apart. No `\b`-anchored pattern and no amount
  of whitespace-collapsing can join them. A full-corpus scan therefore passed
  *"Carry Me Back to Old Virginny"* as clean while it carried *"this old **dark
  ey**'s heart"* and *"for old **Mas sa**"* — and vocal music is most of this
  corpus, so the same hole applied to every pattern, in every language. Found by
  sweeping **composers** rather than words, which is the only reason it surfaced
  at all. Fixed by reconstructing words from the lyric stream: MusicXML and
  MuseScore state continuation exactly via `<syllabic>` (begin/middle continue,
  end/single close), LilyPond/ABC/kern mark it inline (`dark -- ey`, `w:dark-ey`,
  `dark-`). ⚠️ Verses are **interleaved** in the file, so reconstruction must
  group by verse number or it welds stanzas together (`BeauSounds tiof ful`) and
  can invent a word nobody sang.
- **A third, crude net exists and must never auto-apply.** Whitespace-collapsed
  substring matching catches what the other two miss but over-matches across
  word boundaries: *"Pois **ambos** nós"* reads as `sambo`, *"hath done **gre**at
  things"* (Billings) as `negre`, *"**Dark Ey**es"* as `darkey`. 3 of its 4 hits
  were false, so it feeds the review tier only.
- **A keyword screen cannot see what a work IS**, and that gap is larger than it
  looks. *My Old Kentucky Home* was caught only because `darky` survived into one
  particular printing; *Massa's in the Cold Ground* only via a review-tier term.
  Five siblings from the same repertoire stayed shipped — Foster and Emmett wrote
  the dialect into words no slur list contains (*Gwine*, *De*, *ribber*) — and a
  second edition of the Kentucky song, under its full original title, slipped
  through even after that. Closed by naming the **works** in
  `content-hold-manual.json`; the work names are now also in the review tier so
  a future ingest surfaces them.
- **Exemptions are part of the policy, not an escape hatch.** "Contains a slur"
  and "inappropriate to ship" are different questions. **8 canonical art
  song/opera rows were restored** (`content-hold-exempt.json`): Wolf's
  *Die Zigeunerin*, Kinkel's *Die Zigeuner*, Paderewski's *Manru* ×3, Dvořák's
  op.55, Verdi's *Coro di Zingari*, and an untexted *Gypsy Dance*. The exonym is
  a slur in present-day German usage — the keyword fired correctly — but these
  are repertoire, not songs a child is invited to sing, and removing Verdi's
  Anvil Chorus protects nobody. The held set is the folk/minstrel material a
  child *would* be asked to sing.
- **Read the text before judging by the title — twice this reversed the call.**
  *"They Made It Twice as Nice as Paradise and They Called It Dixieland"* (1916)
  and the vocal *"Swanee"* (Gershwin/Caesar 1919) both look like mild Tin Pan
  Alley pop; both invoke the **Mammy** stereotype and cite works already held
  (*Old Black Joe*, *Old Folks at Home*), so both are held. The **untexted**
  piano-solo arrangement of *Swanee* and an untexted *Dixie Tune* are **kept** —
  the tune is not the problem, the words are, which is the same reasoning that
  kept the untexted *Gypsy Dance*.
- **Net: 18 rows held** (15 mine + 3 antisemitic 18th-century dance titles a
  parallel agent had already pulled from the TradArchiv manuscripts), **8
  exempt**, live catalog **38,431 score items**.
- **Holds are reversible and the files stay.** Each row keeps its complete
  manifest entry in `content-held.json` and its file on disk — precisely so the
  corpus remembers what not to publish again.
- **A catalog re-emit is not enough.** The catalog stops advertising a held row,
  but the payload keeps serving at its old path, so `tool/music_db_hf_purge_paths.py`
  deletes it from the dataset. ⚠️ That removes it from `main` only — HF keeps
  detached commits reachable by SHA. A full purge is delete_repo + re-upload
  (`../hf_ops.md` §7); proportionate for a licence violation, ask before spending
  it on a content hold.
- **Durable guard in `emit_catalog.py`:** every ingest APPENDS from a manifest,
  so re-running one would put a held row straight back and republish it. The
  emitter now drops any id present in `content-held.json` before anything else —
  **verified by injecting a held row into `db.json` and confirming the catalog
  count did not move.**

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

### Using a rejected site as a *bibliography* — where that stops working

A tempting move when a song site is licence-blocked: ignore its content and
mine its **source apparatus** (which songbook a tune came from, what year, who
wrote the text), then fetch the actual music from a clean archive. The facts
themselves are not protected — the same principle that lets us re-express
curriculum scope in our own words.

Two things bound it, and both bit on the one worked example (2026-07-30):

1. **§87a-e UrhG, the sui-generis database right, applies to the INDEX even
   when the facts are free.** A curated bibliographic apparatus representing a
   substantial investment is protected against extraction of a *substantial
   part*, independently of any copyright in the songs. Reading a handful of
   entries to chase a lead is fine; systematically harvesting a five-figure
   entry set is a database-right problem in its own right, and one that no
   amount of "but facts aren't copyrightable" answers.
2. **The upstream sources are almost always scans.** Historical songbooks
   (18th–20th c.) are digitized as page images by MDZ / archive.org / DDB, so
   even from a spotless archive they are OMR or transcription input, not
   symbolic corpus material — the same gate that rejects the library guides.
   Dating also still has to be checked per book: a 1920s–40s songbook can carry
   a living arranger's or editor's layer over a PD tune.

**Worked example, and why it yielded nothing:** the bibliography for one
canonical children's song named eight collections (1776 through 1945). All are
scans; the song itself was already in `db.json` **four times over** from
independent cleared sources. Spot-checks of five canonical German children's
songs found every one already held, typically 3–5×. Our German folk and
children's repertoire is at practical saturation, so the bibliography route has
little left to find — check `db.json` for the title *before* chasing a source.

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
