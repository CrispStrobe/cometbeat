#!/usr/bin/env python3
"""Axis-2 (EU life+70) pass over Tier-A Commons files.

SDC settles axis 1 — the FILE. This settles axis 2 — the COMPOSITION. They are
independent: a PD-self MIDI of a 1960s song is Tier A and still blocked.

Commons is unusual in that a large share of its Tier-A MIDI is not repertoire at
all but GENERATED THEORY MATERIAL — scales, hexachords, equal-temperament steps,
chord inversions, uploaded by one prolific editor. For those the uploader IS the
author and has dedicated the file to the public domain; there is no long-dead
composer to find, and a C-major scale is not a copyrightable composition in the
first place. Treating them like repertoire would hold ~a third of the set for a
composer who does not exist.

So the rules, strictest first:
  T   theory//generated example, no separate composer  -> clear
  P2  an explicit lifespan in the credit, death <= 1955 -> clear
  P1c the credit dates the melody to a century <= 19th  -> clear
  P3  every named person resolves via Wikidata life+70  -> clear
  else -> held
"""
import collections
import importlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
for _n in ("wikidata_resolve", "music_db_wikidata_resolve"):
    try:
        _wd = importlib.import_module(_n)
        break
    except ImportError:
        continue
else:
    raise SystemExit("wikidata_resolve.py not found beside this script")

CUTOFF = 1955

# Titles that are theory demonstrations rather than pieces. Deliberately narrow:
# it must look generated, not merely short.
#
# `\w*chord` rather than `chord`: the set-theory uploads are "5-3B pentachord on
# C", "10-4 decachord on C" — one word, so a \bchord\b anchor misses every one
# of them and they fall through to "no composer" and get held for a composer
# who does not exist.
THEORY = re.compile(
    r"\b(\d+\s*-?\s*(et|tet|edo)|equal temperament|\w*chord|"
    r"scale|mode|inversion|interval|triad|seventh|ninth|eleventh|"
    r"thirteenth|cadence|tuning|comma|semitone|whole tone|overtone|harmonic|"
    r"arpeggio|drone|metronome|tone row|cluster|glissando|tremolo|"
    r"voice leading|\d+ against \d+|steps on [A-G]\b)",
    re.I)
# "Melodie: <origin>; Satz und Tondatei: <arranger>" — the house style of one
# prolific Commons contributor, and the shape that matters most here: axis 2
# turns on the MELODY, not on the living arranger who dedicated the setting.
# Splitting the credit is the difference between clearing a 1529 Wittenberg
# chorale and holding it because a 21st-century name appears in the same line.
MELODY_OF = re.compile(r"\bmelod(?:ie|y)\s*:\s*(.+?)(?:;|$)", re.I | re.S)
TRAD = re.compile(r"\b(trad\.?|traditional|traditionell|volkst[üu]mlich|anon|"
                  r"folk|volkslied|spiritual|afroamerican|from [A-Z]\w+|"
                  r"aus (?:der |dem )?[A-Z]\w+)", re.I)
YEAR = re.compile(r"\b(1[0-9]{3})\b")
LIFESPAN = re.compile(r"\((?:c\.?\s*)?(1[0-9]{3})\s*[-–—]\s*(1[0-9]{3}|20[0-2][0-9])\)")
CENTURY = re.compile(r"\b(1[0-9]|20)\s*\.?\s*(?:Jh\.?|Jahrhundert|century)", re.I)
NAME = re.compile(r"[A-ZÄÖÜ][\wäöüß.'-]+(?:\s+[A-ZÄÖÜ][\wäöüß.'-]+){1,3}")
NOT_PEOPLE = {"user", "created", "own work", "the original uploader", "wikipedia",
              "commons", "melodie", "text", "public", "domain", "unknown"}


def classify(row, cache):
    title = row.get("title", "")[5:]
    # Names come from the CREDIT only, never the title. A work title is not a
    # credit: "Da Jesus an dem Kreuze stund" yields the name-shaped "Da Jesus",
    # and feeding that to a resolver invites a coincidental clear.
    credit = row.get("artist") or ""

    if THEORY.search(title):
        return "cleared", "T", (
            "generated theory example (scale/chord/temperament); the uploader is "
            "the author and dedicated it PD — no separate composition to clear")

    m = LIFESPAN.search(credit)
    if m:
        y = int(m.group(2))
        if y <= CUTOFF:
            return "cleared", "P2", f"explicit lifespan in credit, death {y} <= {CUTOFF}"
        return "held", None, f"explicit lifespan: death {y} > {CUTOFF}"

    c = CENTURY.search(credit)
    if c:
        cent = int(c.group(1))
        if cent <= 19:
            return "cleared", "P1c", f"credit dates the melody to the {cent}th century"
        return "held", None, f"credit dates the melody to the {cent}th century"

    # A split credit narrows the question to the melody alone.
    mel = MELODY_OF.search(credit)
    if mel:
        origin = mel.group(1).strip()
        if TRAD.search(origin):
            return "cleared", "P1g", (
                f"melody credited as traditional/anonymous ('{origin[:60]}'); the "
                "setting is a separate, freely-licensed contribution")
        years = [int(y) for y in YEAR.findall(origin)]
        if years and max(years) <= 1900:
            return "cleared", "P1g", (
                f"melody dated {max(years)} at source ('{origin[:60]}')")
        if years:
            return "held", None, f"melody dated {max(years)} — inside life+70 reach"
        credit = origin  # a named melody composer: resolve that person, not the setter

    names = [n for n in NAME.findall(credit)
             if not any(b in n.lower() for b in NOT_PEOPLE)]
    # A credit that IS just a name ("Ludwig van Beethoven", "Josquin des Prez")
    # never matches a two-capitals pattern, because the nobiliary particle is
    # lowercase. Fall back to the whole string — but only when it looks like a
    # personal name, so Commons usernames stay out of the resolver. A mononym is
    # excluded deliberately: "Hyacinth" is an uploader here, and a one-word label
    # is exactly what an all-candidates rule can clear by coincidence.
    if not names:
        # "J.S.Bach" -> "J. S. Bach"; unspaced initials are common in credits
        # and leave the string a single token that no name rule can see.
        cand = re.sub(r"\.(?=[A-ZÄÖÜ])", ". ", credit.strip())
        wordy = len(cand.split()) in (2, 3, 4)
        if (wordy and not re.search(r"\d|user|talk|wikipedia|commons|project",
                                    cand, re.I)):
            names = [cand]
    names = list(dict.fromkeys(names))[:3]
    if not names:
        return "held", None, "no identifiable composer in the credit"

    verdicts = {}
    for n in names:
        st, yr, lbl, q = _wd.resolve(n, cache)
        if st == "UNKNOWN":
            st, yr, lbl, q = _wd.all_candidates_pd(n, cache)
        verdicts[n] = (st, yr)
    if all(v[0] == "CLEAR" for v in verdicts.values()):
        return "cleared", "P3", f"life+70 via Wikidata: {dict(verdicts)}"
    return "held", None, f"unresolved/blocked: {dict(verdicts)}"


def main():
    src = Path(sys.argv[1])
    rows = [r for r in json.loads(src.read_text()) if r.get("tier") in ("A", "B")]
    cache = _wd.load_cache()
    _wd.canary(cache)
    cleared, held = [], []
    stats = collections.Counter()
    try:
        for i, r in enumerate(rows, 1):
            status, rule, why = classify(r, cache)
            r["clearance"], r["rule"], r["axis2_reason"] = status, rule, why
            (cleared if status == "cleared" else held).append(r)
            stats[rule or "held"] += 1
            if i % 50 == 0:
                _wd.save_cache(cache)
                print(f"  [{i}/{len(rows)}] cleared={len(cleared)} held={len(held)}",
                      flush=True)
    finally:
        _wd.save_cache(cache)
    out = src.with_name(src.stem + "-axis2.json")
    out.write_text(json.dumps({"cleared": cleared, "held": held}, indent=1,
                              ensure_ascii=False))
    print(f"\n=== cleared {len(cleared)} · held {len(held)} (of {len(rows)}) ===")
    print("  by rule:", dict(stats))
    print("\n  sample cleared repertoire (non-theory):")
    for r in [x for x in cleared if x["rule"] != "T"][:10]:
        print("    %-46s %s" % (r["title"][5:50], r["axis2_reason"][:44]))


if __name__ == "__main__":
    main()
