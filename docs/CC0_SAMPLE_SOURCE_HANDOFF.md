# Handoff — CC0 audio-sample source → Tracker sample instrument

**Owner of this piece:** `opus (libraries-and-tab)` built the **source**; the
**consumer** belongs to whoever owns the Tracker's sample-instrument UI
(`@tracker-ui` / `@tracker-adv`). This spec is the clean seam between them.

## What's already built (ready to consume)

- **`CommonsSource.audio(http, {policy})`** (`lib/features/library/sources/
  commons_source.dart`) — browses **Wikimedia Commons WAV files** via the open,
  **key-free** MediaWiki API (`filemime:audio/wav` + `imageinfo|extmetadata`),
  returns `LibraryItem`s with `format: 'wav'`, per-file license, artist and a
  `downloadUrl`. It **CC0/PD-filters by default** (the maintainer directive) —
  `browse()` runs every result through `LicensePolicy`, so under the default
  policy you only ever see CC0 / Public-Domain samples. `fetch(item)` returns the
  raw WAV bytes.
- **`buildSampleSources({http})`** (`lib/features/library/source_registry.dart`)
  returns `[CommonsSource.audio(http)]` — the list to expose in a sample picker.
  It is deliberately **separate** from `buildSources()` (notation), because audio
  samples do NOT decode to MusicXML and must not go through the notation import
  pipeline.
- Tested: `test/library_connector_test.dart` — parses the WAV search JSON,
  asserts the `audio/wav` filemime, CC0/PD filtering, and `format:'wav'`.

## What's left (the consumer — Tracker's job)

Wire a "Browse free sounds" entry into the Tracker's existing **record & edit a
sample** sheet (the one that already assigns a `SampleInstrument` to a track):

1. `final sources = buildSampleSources();` → show `sources.first.browse(query)`
   in a searchable list (title · license · artist).
2. On pick: `final wavBytes = await source.fetch(item);`
3. Decode the WAV to PCM with the **existing** `wav_io.dart`
   (`lib/core/audio/wav_io.dart` — the PCM16 WAV reader already used by
   `bin/listen.dart`), then build a `SampleInstrument` from the PCM exactly as the
   record/trim path does today, and assign it to the track.
4. Record provenance: keep `item.declaredLicense` + `item.sourceUrl` with the
   instrument so the Sources & credits screen can show it (CC0/PD need no credit,
   but recording it is cheap and future-proofs a CC-BY opt-in).

### Notes / gotchas
- **Format**: Commons WAVs vary in sample rate / bit depth / channels. `wav_io`
  handles PCM16; resample/downmix to the engine's rate as the record path does.
  Some Commons "audio/wav" files are long recordings, not one-shots — cap length
  or trim, and prefer short results (the sheet already has trim handles).
- **Web/CORS**: the search URL sends `origin=*`; the `upload.wikimedia.org`
  download hosts also send permissive CORS, so this works on web too.
- **Licensing stays CC0/PD by default** — do not pass
  `LicensePolicy(allowAttributionLicenses: true)` unless the maintainer opts in
  (CC-BY-SA samples edited into a track become share-alike derivatives — the same
  editor risk documented in `LIBRARIES_AND_TAB_SCOPING.md` §1.5).

## Why not a standalone download-to-disk UI here
A browser that only saves a WAV to disk with no in-app instrument is low value,
and the real home for samples is the Tracker's instrument path — which
`libraries-and-tab` does not own. So the source ships now (reusable + tested) and
the ~30-line consumer is left to the Tracker owner, rather than duplicating a
sample-loading flow or editing hot Tracker files across an ownership boundary.
