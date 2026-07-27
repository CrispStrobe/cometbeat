# Cello fingering gold sets

Acceptance data for the bowed-string fingering arranger
(`lib/core/notation/bowed_arranger.dart`, harness
`test/bowed_arranger_accept_test.dart`). Two files, kept separate so the original
regression floor stays comparable.

## `cello_fingering_gold.json` — 4 parts, 193 labels

Derived from the four **CC0-1.0** PDMX scores in our music DB that carry
`<fingering>` marks on a cello part — Boccherini Quintet in C (Violoncello I),
Vivaldi Cello Sonata in A minor RV 44 (Largo), *Komm süsser Tod* arranged for cello
and piano, and Bach Cello Suite No. 3 BWV 1009 (Bourrée I). Source dataset:
<https://zenodo.org/records/15571083>. CC0 means no attribution is required; it is
recorded here because provenance is a project rule, not a licence condition.

Per part: the note sequence as MIDI pitch columns (a chord is one column), the
printed finger where the edition marks one (`null` otherwise), and a slur flag.
No `<string>` marks exist in any of the four files: printed editions give the finger
and leave string and position implicit.

## `cello_fingering_gold_pd.json` — 4 parts, 55 labels

From a streaming scan of the **full** PDMX release (`mxl.tar.gz`, 254,035 scores):
1,538 carry a fingering, 236 of those on a bowed part, and every part kept here
passed the **documented ship gate** — `composer_name` resolves via Wikidata to a
music person dead ≤1955 **and** `license_conflict == False`
(`bin/pdmx_pd_composer.py` on the VPS; see `docs/CORPUS_LICENSING.md`). Composers:
Sébastian Lee (d.1887), Vivaldi (d.1741), Ravel (d.1937). Deduped against the first
set, which the mine re-found.

**The gate is not ceremony.** PDMX's axis-2 is self-attested, and the licence field
alone let through — all tagged `publicdomain`/`cc-zero` by their own uploaders —
Hozier *Work Song*, John Williams *Star Wars Medley*, Howard Shore *LOTR Medley*,
Toby Fox *Spider Dance*, Chrono Trigger, Pokémon, and four in-copyright Kreisler
pieces. A licence field is a claim, not a clearance.

**Scale, measured:** the entire 254k-score corpus yielded **55 new cello labels**.
That is the answer to "can we get more data" — barely — and it is why the arc's
label-collection item is closed. See the root `PLAN.md`.

⚠ The gate is conservative in a fixable way: its UNKNOWN bucket contains obvious PD
composers that fail on **string formatting**, not copyright — `"J.S. BACH"`
(initials do not resolve) and `"Luigi Boccherini (1743-1805)"` (a string carrying its
own death year). Both are in gold set 1. A normalisation pass would recover rows
across the whole catalog, not just here; that belongs to whoever owns
`bin/pdmx_pd_composer.py`.

## `spd_cello01_measured.json` — 45 notes, a measured hand

Not an editor's marks: where a cellist's fingers physically **were**. Derived from
the **String Performance Dataset (SPD)** demo piece `cello01`, published at
<https://huggingface.co/datasets/shiyi098/string_performance_dataset-SPD> under
**Apache-2.0** (Yitong Jin et al., *Audio Matters Too! Enhancing Markerless Motion
Capture with Audio Signals for String Performance Capture*, ACM TOG 2024). Their
pipeline recovers a fingerboard contact point per frame from multi-view motion
capture plus audio-detected hand-string contacts.

**What we did to it (Apache-2.0 §4b, statement of changes):** read their published
keypoint layout (contact point at index 150, string endpoints 142–149, used-finger
joints 151–154), projected each contact point onto the four string segments to get
a string index and a length ratio, converted the ratio to semitones above the open
string, matched the used-finger tip to one of the four hand tips to recover a finger
number, and segmented consecutive agreeing frames into 45 note events. No SPD source
file is redistributed here — only this derived table.

⚠ Their string/position is itself derived from a Pitch-Finger model constrained by
the measured hand, so it is strong evidence of what the hand DID and weaker evidence
of what a teacher would WRITE. Used accordingly: to validate the geometry, not to
score fingering taste.

## What these are not

Training data. 248 labels total, one editor per score, and the labelled notes are
the *hard* ones — an editor marks a fingering exactly where the choice is not
obvious. They are regression floors: treat a drop as a bug and a rise as evidence,
never as a score to optimise into.
