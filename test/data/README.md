# `cello_fingering_gold.json`

Acceptance gold set for the bowed-string fingering arranger
(`lib/core/notation/bowed_arranger.dart`, harness
`test/bowed_arranger_accept_test.dart`).

**Provenance.** Derived from the four **CC0-1.0** PDMX scores in our music DB that
carry `<fingering>` marks on a cello part — Boccherini Quintet in C (Violoncello
I), Vivaldi Cello Sonata in A minor RV 44 (Largo), *Komm süsser Tod* arranged for
cello and piano, and Bach Cello Suite No. 3 BWV 1009 (Bourrée I). Source dataset:
<https://zenodo.org/records/15571083>. CC0 means no attribution is required; it is
recorded here because provenance is a project rule, not a licence condition.

**Contents.** Per part: the note sequence as MIDI pitch columns (a chord is one
column), the printed finger where the edition marks one (`null` otherwise), and a
slur flag. 2,303 columns, **193 printed fingers** — that is the complete dense
cello-fingering supervision in a 42k-score corpus, which is the honest measure of
how scarce this label is. No `<string>` marks exist in any of the four files:
printed editions give the finger and leave string and position implicit.

**Not a training set.** 193 labels, one editor each, and biased toward hard notes
(an editor marks a fingering exactly where the choice is not obvious). It is a
regression floor. See `docs/PLAN.md` for the data avenues that could grow it.
