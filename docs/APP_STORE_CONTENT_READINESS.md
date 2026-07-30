# App Store readiness — the content and rights answers

What App Review and App Store Connect will ask about the music corpus, and what
our answer is. Written 2026-07-30. **Not legal advice**, and the questionnaire
changes — confirm the live wording in App Store Connect at submission.

The point of this file is that these answers already exist as artefacts. None of
it should have to be reconstructed under submission pressure.

---

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

## 5. ⬜ OPEN DECISION — the Kids Category

**This is the one thing here that is not decided, and it is not a technical
call.**

Opting in (ages 5 and under / 6–8 / 9–11) triggers **Guideline 1.3**: no
third-party analytics or advertising without verified parental consent, a
parental gate before external links and purchases, and COPPA / GDPR-K
compliance.

The project's own positioning argues for staying **out**: this is explicitly not
a 6+ app — it scales to students and hobbyists (the "Scratch model"), and
features are deliberately not scoped down because the audience skews young.
Staying out of the Kids Category avoids 1.3 entirely while the app remains
perfectly suitable for children.

**Decide before submission**, because it changes the questionnaire, the privacy
disclosures, and possibly the analytics stack.

## 6. Pre-submission checklist

- [ ] Decide the Kids Category (§5).
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
