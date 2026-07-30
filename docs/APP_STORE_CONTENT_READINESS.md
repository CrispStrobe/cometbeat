# App Store readiness — the content and rights answers

What App Review and App Store Connect will ask about the music corpus, and what
our answer is. Written 2026-07-30. **Not legal advice**, and the questionnaire
changes — confirm the live wording in App Store Connect at submission.

The point of this file is that these answers already exist as artefacts. None of
it should have to be reconstructed under submission pressure.

---

## 0. Decisions already made

| | |
|---|---|
| Kids Category | **No** — 4+ and child-suitable, but not filed there (§5) |
| Expected rating | **4+**, every descriptor "None" (§1) |
| Content screen | enforced in the pipeline, not by diligence (§3) |

## 1. Age rating — this corpus does not raise it

Counter-intuitive but worth being precise about: **Apple's rating questionnaire
has no descriptor for racial slurs or extremist material.** The categories are
violence, profanity/crude humour, sexual content, horror, alcohol/drugs,
gambling, medical, contests (plus the 2025 additions on user-generated content,
messaging and ads).

Slurs and NS repertoire are therefore not *rated*, they are **prohibited** under
**Guideline 1.1.1 (Objectionable Content)** — *"Defamatory, discriminatory, or
mean-spirited content, including references or commentary about religion, race,
sexual orientation, gender…"*.

So the content screen is not protecting a rating; it is protecting against
**rejection or post-release removal**. Expected rating: **4+, every descriptor
"None"** — the corpus is folk song, classical, and chant.

⚠️ Apple restructured the tiers in 2025 (4+/9+/13+/16+/18+) and expanded the
questionnaire. Re-read it rather than assuming this still matches.

## 2. What we actually verified, stated precisely

Overclaiming here would be worse than saying less. What the content screen
establishes:

> No shipped row matches a multilingual slur list (German, English, French,
> Polish/Czech/Hungarian cognates) or a named National-Socialist repertoire and
> composer list, in its title or in its file body, whether or not the lyric is
> syllable-split. No shipped row is by an NS-apparatus composer.

Ledgers: `content-held.json` · `content-hold-manual.json` ·
`content-hold-exempt.json` · `content-screen.json`. Every hold records the term,
where it matched, and why — and every exemption records the reasoning, because
"we looked and decided to keep it" is a different claim from "we never looked".

**What it does NOT establish:** that nothing under Guideline 1.1.1 remains. That
guideline is broader than race and NS repertoire, and the corpus includes 18,684
Latin chants and 8,181 Polish scores nobody has read. This is a strong filter,
not a proof. If App Review ever challenges a specific item, the ledgers show a
documented process rather than a claim of completeness.

## 3. The structural point: the catalog is fetched at runtime

App Review approves a binary; the content arrives afterwards from the published
dataset. Two questions follow, and both have concrete answers:

* **Is this user-generated content?** No — it is a first-party curated catalog.
  This matters: UGC would trigger **Guideline 1.2** (a published moderation
  method, a report mechanism, the ability to block abusive users). Our answer is
  curation, and the ledgers are the evidence that curation exists.

* **Can it regress after approval?** No. `emit_catalog.py` refuses to emit any id
  in `content-held.json`, and `bin/music_db_publish.py` refuses to publish at all
  when the screen finds a hit that is not already a recorded decision. Both are
  tested, including the negative case. This matters because every ingest APPENDS
  from a manifest — without the gate, re-running one would silently republish a
  held row into an already-approved app.

## 4. Content Rights declaration

App Store Connect asks whether the app contains, displays or accesses
third-party content, and requires confirmation that you hold the rights.

Evidence: `docs/CORPUS_LICENSING.md` plus per-row provenance in `db.json` — every
row carries source, specific source URL, SPDX licence, rights status, and an
axis-1/axis-2 note. Tier B rows carry attribution, which the app surfaces in
"Sources & credits" (`music_source_credits.dart`) — that is also the
**Guideline 5.2 (Intellectual Property)** answer.

## 5. ✅ DECIDED (maintainer, 2026-07-30) — NOT in the Kids Category

**We stay out.** Rated 4+ and child-suitable, but not filed under the Kids
Category. Recorded here with the reasoning so it is not re-litigated at
submission.

**The decision does NOT rest on compliance cost, which was measured and is
small.** The expensive parts of **Guideline 1.3** are already satisfied by
construction: no advertising, no third-party analytics, no in-app purchase, no
accounts — none of it in `pubspec.yaml`. The only work would be a parental gate
on **4 `launchUrl` call sites** (`about_screen`, `attribution_screen`,
`modarchive_sheet`, `catalog_browse_sheet`). That is a shared helper and an
afternoon.

**It rests on what the category DECLARES.** Apple's Kids Category is for apps
*"primarily directed at children"*. CometBeat deliberately is not: it follows the
Scratch model, scaling to students and hobbyists, and features are explicitly not
scoped down because the audience skews young (auto-memory
`cometbeat-audience-scratch-model`). Opting in would declare something that is
not quite true, and the age bands stop at **11**, putting a public ceiling on the
app's identity that contradicts how it is built. That cost is not cheaply
reversible; the compliance work would have been.

**What we give up, stated fairly** — this is a real trade, not a free win:

* **Discovery.** The Kids Category is its own browsable surface with age bands
  and high parental intent. Outside it we compete in Education/Music against
  everything. This is the only pro that plausibly moves installs.
* **Editorial featuring.** Apple curates Kids collections (back-to-school,
  holiday); you generally cannot appear in them from outside the category.
* **A third-party trust credential.** Category membership means Apple checked us
  against 1.3 — verification we now have to assert ourselves.
* **Some institutional procurement** filters on an explicit age designation.

Mitigation: a 4+ rating plus Education/Music search still reaches parents
searching for children's music apps; we simply do not get the curated shelf.

**What would reverse this:** evidence that Kids-tab browsing is a primary
acquisition channel for this kind of app. The price of switching is 4 parental
gates — genuinely cheap — so the blocker would remain the age-band
misrepresentation, not the engineering.

⚠️ **Consequence to keep in mind:** because we are NOT in the Kids Category,
nothing external audits our child-suitability. That is exactly why the content
gate (§2, §3) is enforced in the pipeline rather than left to diligence.

## 6. Pre-submission checklist

- [x] ~~Decide the Kids Category~~ — **decided: NOT in it** (§5).
- [ ] Run `bin/music_db_publish.py` — it must exit 0. A non-zero exit means an
      unreviewed content hit; resolve it into a ledger, do not bypass.
- [ ] Upload payloads FIRST, then `./catalog` (`../hf_ops.md`) — a catalog
      advertising payloads that were never uploaded makes every import 404.
- [ ] Confirm the live catalog: `dart run bin/musicdb.dart stats --live score`.
- [ ] Re-read the age-rating questionnaire in App Store Connect rather than
      assuming §1 still matches.
- [ ] Confirm "Sources & credits" lists every Tier B source currently shipping.

## 7. Note for Germany

Two NS-era songs in the review pass were held on the maintainer's call. For
completeness: the *Horst-Wessel-Lied* is **criminal** under §86a StGB, whereas
*Erika* and the *Westerwaldlied* are lawful but contentious. The screen holds all
of them regardless, because the standard here is "belongs in a children's music
app", not "is it prosecutable".

The *Deutschlandlied* is handled by stanza: the edition carrying **stanza 1**
("Deutschland über alles") is held, and a note-identical **stanza-3** SATB
derivation ships in its place. Only the third stanza is the official anthem text.
