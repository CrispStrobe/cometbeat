# Scoping — External score/tab/module libraries + a Guitar-Tab Workshop mode

Worktree `../mus-libraries`, branch `feature/score-libraries-and-tab`.
Status: **SCOPING (design only — no product code yet).** Two independent
features; either can ship first. Not legal advice — the licensing findings below
are researched-and-cited but a real legal check is warranted before automated
import goes live (see §1.7).

Two research sweeps back this doc: an infra map of what the app + `crisp_notation`
already read/write, and a cited licensing/access survey of the candidate sources.
The headline for each feature:

- **Libraries:** we already have readers for every format the safe sources emit
  (MusicXML/MXL, MIDI, ABC, MEI, kern, MuseScore, `.mod/.xm/.s3m/.it`, GP). The
  net-new work is a **network fetch layer + a license/provenance gate + a browse
  UI**, funnelling into the existing Song Book. The "ask for a coffee" hook is a
  design constraint, not a feature: **never couple content to payment**, so a
  config-gated donation link can be switched on later with zero code change.
- **Tab editor:** `crisp_notation` already ships the *entire* tablature + Guitar
  Pro stack (render, layout, tunings, per-note string pinning, GP read+write,
  ASCII-tab read). None of it is wired into the app. The tab "editor" is mostly
  **wiring + an input surface** over the same `MultiPartDocument` the Workshop
  already edits — not a from-scratch build.

---

## 1. Feature A — Connections to free score / tab / module libraries

### 1.1 The governing rule

> "Free to download" ≠ "openly licensed." A public-domain *composition* can still
> carry a copyrighted *arrangement / engraving / MIDI sequence* layer.

So we do **not** connect to "sites with free music." We connect to **specific
sources whose licensing is verifiable per item**, hard-filter to a permissive
allowlist, and record provenance on every import. Everything downstream (the
donation link, the app-store posture) stays clean *because* the content does.

### 1.2 Source verdicts (researched + cited — full report in the PR description)

Full cited licensing report is recorded below and in this branch's commit history.

**Connect first (SAFE — permissive, open bulk access):**

| Source | Content | License | Access | Formats |
|---|---|---|---|---|
| **OpenScore** (Lieder, String Quartets) | ~1,300 art songs + quartets | **CC0** (confirmed) | GitHub / Zenodo bulk (bypasses musescore.com entirely) | MusicXML, MIDI, `.mscx` |
| **Mutopia Project** | ~2,100 classical/trad | per-piece PD / CC-BY / CC-BY-SA (all commercial-OK) | GitHub bulk | LilyPond, MIDI, PDF |
| **Wikimedia Commons** | per-file free/PD scores | per-file CC0/BY/BY-SA/PD | real MediaWiki API | mixed (PDF, MusicXML, MIDI) |

**Connect with a per-item license filter (CONDITIONAL — good value, needs gating):**

| Source | Why conditional | Guardrail |
|---|---|---|
| **thesession.org** (Irish trad, ABC) | custom license (share/adapt commercially) **+ a no-LLM clause**; DB is ODbL; modern settings may still be under composer copyright | live API / on-demand single-tune import only (no bundled derivative DB); show ODbL attribution; **never route this data through any LLM/TTS feature**; favour clearly-traditional tunes |
| **The Mod Archive** (`.mod/.xm/.s3m/.it`) | per-module copyright; the redistribution grant **does not cover bundling into an app** | official XML API key (disclose the app) + **hard-filter to PD/CC0/CC-BY/CC-BY-SA**; or use the pre-filtered "Big Mod Music Pack" (~700 modules) |
| **CPDL / ChoralWiki** | mixed per-edition; editor's engraving can be copyrighted even when the work is PD; US-PD only | import only PD + CPDL-license + CC-BY/BY-SA; MediaWiki API |
| **IMSLP / Petrucci** | PD vetted **US/CA/EU only** (a work PD in Canada can be under copyright in Germany); wait-timer monetization; per-file PR/NC restrictions | metadata API for browse is fine; **file download filtered to CC0/CC-BY/BY-SA + clearly-PD**, gated by user country |

**Do NOT connect** (all-rights-reserved / no license grant / no sanctioned API /
active anti-scraping): **general musescore.com uploads**, **Ultimate Guitar**,
**mySongBook / GPIF tab store**, **abcnotation.com** (Uploader-Asserted/NC; composers retain rights), **Nottingham Music Database** (All Rights Reserved/NC), **Zenodo ABC Dataset 10k** (17694747; scraped without commercial rights), **IFDO kern2abc** (Densmore/Shanahan Native American; CC BY-NC-SA 4.0), 8notes, Songsterr, Delcamp, FreeMIDI, BitMidi, VGMusic,
archive.org MIDI dumps, unlicensed KernScores. **Avoid for a donation-funded app
(NonCommercial clause):** DCML corpora, MAESTRO, Kunst der Fuge.

> **Guitar tab specifically has no open source at scale.** Every tab site is
> all-rights-reserved. Open guitar *repertoire* exists only as standard notation
> (Mutopia ~395 pieces; the Boije Collection ~1,600 PD 19th-c. works). Practical
> path for tab content: **author our own from PD works and license it CC0/CC-BY.**
> This directly links Feature A → Feature B (the tab editor makes that content).

#### Tracker modules (.mod/.xm/.s3m/.it) — audited 2026, verdict: DO NOT CONNECT any archive

A dedicated audit (cited, in the branch's commit history) reached a **structural**
conclusion: **there is no large body of tracker modules under CC0/CC-BY with
documented, key-free programmatic access.** Every archive with *volume* has *no
per-item license field*; every source with *license metadata* has *tiny volume*
or *no API*. Specifically:

- **Modland, Aminet, files.scene.org, modules.pl, OpenMPT song packs** — no
  per-file license field; access grants are "free of charge" (pre-CC custom), not
  a redistribution/derivative grant. `Aminet`'s `Distribution:` field is a
  *restriction*, not a license. **DO NOT connect.**
- **The Mod Archive** — has a license taxonomy (~950 permissive), but its own FAQ
  says the grant *"does not cover inclusion in a packed/bundled application"*, its
  "PD" tier rests on a CC instrument retired in 2010, and non-artists can upload
  the tags. **BYOK-only** (see below), never bundled.
- **"Big Mod Music Pack"** — sourced *from* The Mod Archive → inherits the same
  bundling exclusion. **DO NOT bundle.**
- **archive.org** — key-free API but `licenseurl` is uploader-asserted and <10% is
  permissive (plurality is CC BY-NC-**ND**); the named "big" collections 404.
  CONDITIONAL at best, low hundreds of items, manual review.
- **Wikimedia Commons** — **rejects tracker formats at the MediaWiki layer**
  (24-extension allowlist; modules aren't on it) — so 0 modules, *by policy*. (Its
  MIDI, already our A1b source, stays fine.)
- **United Trackers** (dead — domain now serves gambling), **keygenmusic**
  (warez provenance) — **permanent exclusion**, purge from any config.

**Conclusion honouring "totally free (CC0) only":** the only clean module paths
are (1) a **one-time manual harvest of CC0-tagged assets from OpenGameArt**
(explicit per-asset license field, no NC/ND; but zipped, no API, ~tens of
modules — vendor with a checked-in manifest, do not auto-crawl), or (2)
**author our own modules from CC0 samples** (e.g. Freesound CC0) via the Tracker
we already have — zero provenance risk, full title. A `ModArchiveSource` remains
possible **only as BYOK** (§1.2b) and only CC0-filtered, but a child won't request
a key, so it's a maintainer/power-user unlock, not a mainstream browse source.

#### §1.2b — BYOK (bring-your-own-key) sources

Some sources (The Mod Archive) issue an API key **per application** and require it
stay **confidential**. A key shipped inside a Flutter binary is trivially
extractable → embedding one **breaches the confidentiality term on day one**.
Therefore any keyed source is **BYOK**: no key ships; the source stays hidden
until the user enters a key **they requested themselves** (disclosing their use);
the `LicensePolicy` CC0/PD gate still hard-filters; imports go into the user's own
local library (we never redistribute). This keeps a keyed source legally clean but
maintainer-facing — build only if/when wanted.

### 1.3 What already exists (so we don't rebuild it)

- **Readers for every safe format** live in `crisp_notation_core`:
  `scoreFromMusicXml` / `multiPartScoreFromMusicXml`, `readMusicXmlFromMxl`,
  `scoreFromMidi`, `scoreFromAbc` / `multiPartScoreFromAbc`, `scoreFromMei`,
  `scoreFromKern`, `scoreFromMscx` / `readMscxFromMscz`, GP readers (§2), and the
  app-side module readers in `lib/core/audio/mod/` (`parseAnyModule`,
  `sniffModuleFormat`).
- **The Song Book is the sink.** `UserSongsService` (`lib/features/games/songs/
  user_songs_service.dart`) persists `ImportedSong {id, title, musicXml}` to
  SharedPreferences; `songbook_screen.dart` lists it; `import_screen.dart` already
  imports MusicXML/ABC/ChordPro/MIDI from paste/file. Modules already import into
  the Tracker (`tracker_screen.dart` → `parseAnyModule`).
- **Download precedent:** the only remote-fetch pattern today is the CrispASR /
  Kokoro model downloader (`lib/core/audio/tts/kokoro_model_store.dart`) — native
  C over FFI, **consent-gated** (nothing fetches without an explicit opt-in). We
  reuse the *consent-gated* principle, not the FFI mechanism.
- **No Dart HTTP client** (`http`/`dio` absent). `url_launcher` + `file_selector`
  are present. → We add `http` (see §1.6).

### 1.4 Proposed architecture (new, mostly pure Dart + one thin plugin dep)

```
lib/features/library/
  source_registry.dart      // pure data: the SAFE/CONDITIONAL sources above
  content_source.dart       // interface: browse(query) → List<LibraryItem>;
                            //            fetch(item)   → bytes
  sources/
    openscore_source.dart   // GitHub/Zenodo index → items (CC0)
    mutopia_source.dart     // GitHub index (PD/CC-BY/CC-BY-SA)
    commons_source.dart     // MediaWiki API
    thesession_source.dart  // REST API (?format=json) — no-LLM flag set
    modarchive_source.dart  // XML API (key) — license-filtered
  license_policy.dart       // THE GATE — see §1.5
  provenance.dart           // Provenance {sourceId, sourceUrl, title, composer,
                            //   licenseSpdx, licenseUrl, attributionText,
                            //   importedAt, modified}
  library_browser_screen.dart   // search/browse a source → preview → Import
  attribution_screen.dart       // "Sources & credits" (all imported works)
  donation.dart                 // DonationConfig — see §1.8
```

- **`LibraryItem`** = `{sourceId, title, composer, formats[], downloadUrls{},
  declaredLicense, licenseUrl, previewUrl?}`. Pure data; a source adapter's only
  job is to turn a search/index into these + fetch bytes.
- **Import pipeline** = `fetch(item)` → sniff format → existing reader → `Score` /
  `MultiPartDocument` (or module → Tracker) → **`LicensePolicy.gate(item)`** →
  store in `UserSongsService` with `Provenance`. **Reuses every existing reader
  and the Song Book unchanged** except a `provenance` field on `ImportedSong`.
- **Adding a source later = drop-in data + a ~40-line adapter.** No core change.

### 1.5 The license gate (`LicensePolicy`) — the compliance spine

A single pure function every import passes through. Behaviour:

- **DEFAULT = totally-free + permissive-software** — `PD` / `CC0` (no conditions)
  **plus `MIT` / `Apache-2.0` / `BSD`** (permissive-with-notice: use for anything,
  the only duty is preserving the license text, which the credits screen already
  does). Maintainer directive. Implemented as `LicensePolicy()` where
  `allowAttributionLicenses = false` — `LicenseKind.isUnconditional` (CC0/PD) and
  `isPermissiveNotice` (MIT/Apache/BSD) are both admitted.
- **`CC-BY` / `CC-BY-SA` are OFF by default**, opted into with
  `LicensePolicy(allowAttributionLicenses: true)` — they are permissive but carry
  obligations (credit; share-alike on *derivatives*). ⚠ Because our Tracker/Tab
  editor lets a child *edit* a work, an edited CC-BY-SA pattern is a derivative
  that must itself ship CC-BY-SA — so CC-BY-SA in an *editor* is riskier than in a
  *player*. Keep the default (CC0/PD) unless a specific source is deliberately
  opted in. **Never** admit GPL content (copyleft **and** it conflicts with
  App-Store distribution terms).
- **Hard-reject (always)**: `CC-*-NC`, `CC-*-ND`, all-rights-reserved,
  unknown/absent license → import blocked with a clear message (offer "open in
  browser" via `url_launcher` instead).
- **Country gate for PD**: default to the conservative EU rule (author d. +70y)
  for IMSLP/CPDL "public domain"; a settings toggle for the user's jurisdiction.
  Conservative default = don't auto-import a PD-in-US-only work for a DE audience.
- **ShareAlike is safe for us** (researched): bundling an *unmodified* CC-BY-SA
  file is a "collection," not an adaptation → it does **not** infect the MIT app
  code; only that file stays BY-SA. **But** if the app later *derives* a new
  arrangement/transposition from a BY-SA source, that output must itself be
  BY-SA. → `Provenance.modified` tracks this; a re-export of a modified BY-SA work
  carries the BY-SA notice. Pure format/render changes are not "adaptations."
- Emits the `Provenance` record that the attribution screen and any future
  export/share reads from.

Unit-testable in pure Dart (no network): feed declared licenses → assert
gate/allow + the exact attribution string. This is the highest-value test.

### 1.6 Networking + platform notes

- Add **`http`** (pure-Dart, works on web). Fetch is **consent-gated** — nothing
  downloads until the user taps Import; mirrors the Kokoro opt-in principle.
- Cache fetched bytes to disk (`path_provider`) keyed by source+item; re-import is
  offline.
- **Web/CORS**: GitHub raw + the MediaWiki/thesession APIs send permissive CORS;
  some sources (ModArchive, IMSLP file hosts) may not → those degrade to
  "open in browser to download, then import the file" on web. Document per source.
- Prefer **GitHub/Zenodo bulk mirrors** over hotlinking a site (OpenScore,
  Mutopia) — avoids the origin site's ToS/paywall entirely and is the sanctioned
  path.

### 1.7 Compliance checklist (ships with the feature)

1. Every imported work carries a `Provenance` record — no anonymous imports.
2. `LicensePolicy` blocks anything outside the permissive allowlist.
3. An **"Sources & credits"** screen lists every imported work's attribution
   (author, title, source link, license name+link, "modified" flag) — extends the
   existing About/`showLicensePage` + `custom_licenses_registry.dart` pattern.
4. thesession data is flagged **no-LLM** at the source adapter (never fed to the
   TTS/any generative feature).
5. ModArchive/IMSLP/CPDL imports are license-filtered before they reach the sink.
6. `docs/` records each source + its license basis + the retrieval date.
7. **A real legal review before enabling IMSLP/CPDL/ModArchive auto-import** (the
   jurisdiction PD question is the biggest real-world risk). OpenScore + Mutopia
   (CC0 / explicit permissive) are safe to enable without that gate.

### 1.8 "Ask for a coffee" — designed in so it needs no later adaptation

The maintainer wants to add a donation ("buy me a coffee") later **without
touching the app**. The way to guarantee that is a **design constraint now**:

- **Content is free and ungated, forever. The donation unlocks nothing, removes no
  ads, gates no import.** This is the single decision that keeps everything clean:
  - It sidesteps the CC-NC ambiguity (we only bundle CC0/BY/BY-SA/PD anyway, and
    the donation is never "selling" the content).
  - It fits **Apple** (US storefront now allows external links/CTAs post-*Epic*;
    a Ko-fi/PayPal link is fine) and **Google Play's peer-to-peer tip exception**
    (100% to the developer, unlocks no digital content → no Play Billing needed).
- Ship a **`DonationConfig {enabled=false, url, label}`** const from day one, read
  by a small "Support the developer" tile (external browser via `url_launcher`,
  already a dep). Flipping `enabled=true` + setting a URL is the *entire* future
  change — no feature rework, because nothing else ever depended on it.
- Frame it as "support the developer," an **external browser link**, not in-app
  billing, not an in-app fundraiser. Re-verify store policy at submission (both
  stores' rules are shifting through 2026–27).

### 1.9 Phasing (value ÷ risk)

- **A0 — Pipeline + gate + one CC0 source (OpenScore).** `SourceRegistry`,
  `ContentSource`, `LicensePolicy`, `Provenance`, browser screen, attribution
  screen, `http` dep, Song-Book `provenance` field. Zero licensing risk (CC0,
  GitHub bulk). Proves the whole path end-to-end.
- **A1 — Mutopia + Wikimedia Commons** (SAFE). Breadth of classical repertoire.
- **A2 — The Mod Archive** (license-filtered) → imports straight into the
  **Tracker** (the mod readers already exist). Natural synergy with the tracker
  work already on `main`.
- **A3 — thesession.org** (ABC folk, no-LLM flag) → Song Book; great for the
  interval-mnemonic / folk-song curriculum hooks.
- **A4 — IMSLP + CPDL** (conditional, country-gated) — only after the legal review.
- **A5 — DonationConfig tile** flipped on when the maintainer's Ko-fi/PayPal is
  ready (one const change; already wired).

---

## 2. Feature B — A guitar-tab editor as a Workshop mode

### 2.1 What already exists in `crisp_notation` (the big surprise)

The library ships the **whole tab + GPIF stack**; the app just never wired
it. Verified:

- **Rendering (Flutter):** `TabStaffView(score, tuning, {capo, showTuning,
  highlightedIds, theme})`, `FretboardView`, `NotationTabView` (synced standard +
  tab) — all barrel-exported from `crisp_notation`.
- **Layout/theory (core):** `TabLayoutEngine.layout(score, tuning, …)` (string
  lines, fret sizing, bends), `NotationTabLayout`, `tab_techniques.dart`;
  `Tuning` with presets — `standardGuitar`, `dropDGuitar`, `dadgadGuitar`,
  `openGGuitar`, 7/8-string, `standardBass`, `fiveStringBass`, `banjoOpenG`,
  `ukulele`, `mandolin` — and fret↔pitch math (`fret = pitch.midi − string.midi`).
- **Explicit string control in the model:** `TabVoicing(noteId, strings)` **pins a
  note to specific strings**, overriding the engine's default lowest-fret
  placement, and `ChordDiagram(frets, {fingers, baseFret, barreFret, name})`. So a
  faithful editor where the *user picks the string* needs **no library change**.
- **GPIF I/O (core):** read `gp5/gp4/gp3ToScore`, `scoreFromGpif`, `.gp`/
  `.gpx` containers (clean-room); **write** `scoreToGpif` + `.gp`/`.gpx`
  containers. `asciiTabToScore` reads ASCII tab.
- **App today (✅ SHIPPED):** the dedicated **Tab editor**
  (`tab_workshop_screen.dart`) renders tab (`TabStaffView`), exposes fret/string
  editing, and **exports GPIF `.gp`** (menu label "GP tab (.gp)") preserving the
  arranged string/fret choices + techniques. A headless **`bin/tabconv.dart`**
  exports `.gp` from any notation format too, and the **Composition Workshop's
  `kExportFormats`** now includes GP (fret via the cost-based arranger, one track
  per part). So GP export is wired on every surface.

**Implication:** the editor is an **input surface + wiring** job over the existing
`MultiPartDocument`, reusing `TabStaffView`/`FretboardView` for display and
`TabVoicing` for string choice. Estimated effort is a fraction of the Tracker.

### 2.2 Where it plugs in — recommend a sibling editor sharing the document

The Workshop (`lib/features/workshop/screens/composition_workshop_screen.dart`) is
a single-document score editor with shelves (`sandbox`/`studio`) and staff modes
(`treble`/`bass`/`grand`). The **Tracker** is a *separate screen* bridged via a
menu entry + an `initialScore`/`initialNames` handoff (two-way).

Two options:

- **(a) A new `_StaffMode.tab`** inside the Workshop canvas. Cheapest to reach, but
  tab needs a fundamentally different input surface (fretboard + per-string fret
  entry) that would overload the staff canvas and its gesture model.
- **(b, recommended) A dedicated Tab editor screen** that edits the **same
  `MultiPartDocument`**, reachable from the **Workshop home dropdown** (which
  already lists "Score Workshop" / "Advanced Tracker") and bridged both ways via
  the existing `initialScore` handoff. Mirrors the proven Tracker relationship:
  one shared model, three editors (staff / grid / fretboard) over it.

Recommend **(b)**: `lib/features/games/composition/tab_workshop_screen.dart`,
constructor `TabWorkshopScreen({MultiPartDocument? initialDocument})`, plus a
dropdown entry. Shared model = free round-trip Score↔Tab↔Tracker.

### 2.3 SOTA UX (GPIF / TuxGuitar / Songsterr / Soundslice / Flat), kid-first

- **Dual view:** `NotationTabView` — standard staff synced above the 6-line tab.
  Toggle to tab-only for beginners.
- **Two input paths (both, like the Tracker):**
  1. **Tab grid**: a cursor on a string line; type a fret number (0–24); arrows
     move string/beat; a **duration palette** (whole…sixteenth, dot, triplet).
  2. **On-screen fretboard** (`FretboardView`): tap a fret → places the note on
     that string at the cursor and auto-sets a `TabVoicing` (touch-first, kid
     friendly). Optional live-mic later (the pitch pipeline exists).
- **String choice is explicit** via `TabVoicing` — same pitch, different
  string/fret is a first-class edit (the thing generic score editors can't do).
- **Tunings + capo**: a tuning picker (the presets) + capo stepper
  (`TabStaffView.capo`). Persist per document.
- **Techniques** (`tab_techniques.dart`): hammer-on/pull-off, slide, bend,
  vibrato, palm-mute, harmonic, tap — a technique palette on the selected note.
- **Chord diagrams** (`ChordDiagram` + `chord_presets.dart`): insert a diagram
  above a beat; a preset picker for common shapes.
- **Playback with fret highlighting**: reuse the shipped "notes light up as they
  play" primitive — a `PlayingTabView` wrapping `TabStaffView.highlightedIds` on a
  Ticker, exactly like `PlayingStaffView` (`lib/features/games/widgets/
  playing_staff.dart`). Audio via the existing synth path.
- **Multi-track "band"**: `MultiPartDocument` is already multi-part — a track
  strip (guitar / bass / drums), each its own tuning.
- **Import/Export**: GP import already works → now it *displays* as tab; GP
  export (`scoreToGpif` → `.gp`) into `kExportFormats` (✅ **done**, arranged), plus
  the existing MusicXML/MIDI/ABC. ASCII-tab paste-in via `asciiTabToScore`.

### 2.4 License / patent / copyright guardrails

- **Tablature itself is centuries old — no patents.** Standard tab-editing
  interactions (fret entry, string lines, technique marks) are unencumbered.
- **GPIF format**: we only touch the **GPIF XML** via `crisp_notation`'s
  **clean-room** reader/writer (per its file-header docstrings). We do **not** ship
  Arobas soundbanks / RSE, or replicate GPIF's icon set / trade dress —
  build our own kid-friendly look.
- **No copyrighted tab content is bundled or fetched** — there is no open tab
  library (§1.2). Content for the editor comes from the user or from **PD works we
  transcribe ourselves** (then license CC0/CC-BY) — the Feature A ↔ B loop.
- Avoid cloning any *specific* patented player interaction (e.g. a named product's
  exact synchronized-scrub patent) — a basic editor + highlighted playback is
  standard prior art, but flag any fancy interaction for a check before building.

### 2.5 Likely-needed library touch (small, or avoidable)

The model already covers string pinning (`TabVoicing`) and chords (`ChordDiagram`).
The one thing to verify against a real GP round-trip: whether `scoreFromGpif`
**preserves** per-note string/fret into `TabVoicing` (faithful re-display of an
imported GP), or whether import lands as bare pitches (the engine re-derives
lowest-fret). If the former, GP import → tab render is faithful out of the box; if
the latter, a small reader enhancement in `crisp_notation` carries GP string data
into `TabVoicing`. **CI tracks public `crisp_notation@main`, so any library change
lands there first** — scope it as a separate crisp_notation task if needed.

### 2.6 Phasing

- **B0 — Read-only tab render in a new screen.** `TabWorkshopScreen` over a
  `MultiPartDocument`, `NotationTabView` + tuning picker + capo, dropdown entry.
  Instantly makes the *already-working* GP import visible as tab. Highest value ÷
  effort; no new model.
- **B1 — Fret/string input**: tab-grid cursor + fret entry + duration palette +
  on-screen `FretboardView`, writing notes + `TabVoicing` into the document.
- **B2 — Techniques + chord diagrams** (palettes over the selected note/beat).
- **B3 — GP export wired into `kExportFormats` (✅ done, arranged); `PlayingTabView`
  playback highlighting; tuning/capo persistence.**
- **B4 — Multi-track band view; ASCII-tab paste-in; live-mic fret capture (later).**

---

## 3. Coordination + collision notes (per docs/PLAN.md board)

- **Feature A is mostly disjoint** — new files under `lib/features/library/` + a
  `provenance` field on `ImportedSong` (`user_songs_service.dart`) + `pubspec`
  (`http`) + one dropdown/settings tile. Light touch on the hot Song-Book files;
  coordinate on the board before editing `user_songs_service.dart`/`import_screen.
  dart`. `pubspec.yaml` is hot — rebase before pushing.
- **Feature B overlaps the Workshop**: the home dropdown (`home_screen.dart`),
  `composition_workshop_screen.dart` (the `initialScore` bridge + `kExportFormats`
  GP entry), `game_registry.dart`, and the ARBs are **hot shared files** watched by
  the active `tracker-ui` / Workshop agents. **Claim on the board and rebase before
  each push.** The new screen file itself is disjoint.
- Both features need EN/DE ARB strings (`flutter gen-l10n`) and a test each.
- Pre-commit: `flutter pub get` → `dart format <files>` → `flutter analyze` (whole
  project) → tests. Never pipe test output through `tail` before a push.

## 4. Recommended first slice

**A0 (OpenScore pipeline + license gate)** and **B0 (read-only tab render)** are
the two "prove it end-to-end, near-zero risk" slices. A0 exercises the whole
fetch→gate→provenance→Song-Book path against CC0 content; B0 lights up tab display
for GP files the app *already imports*. Either is a clean, self-contained first
slice — built in small commits and merged straight to `main` (no PRs on our repos).
