#!/usr/bin/env python3
"""Internet Jukebox axis-2 promotion pass — held-by-default, 100%-ground only.

THE PROBLEM THIS SOLVES. Every Jukebox item is marked CC Public Domain Mark 1.0
by Public Resource. PDM is an assertion, not a warranty, and the Internet
Archive determines public domain on the US rule (published before 1930). Our
ship gate is the EU rule: life + 70, i.e. for 2026 every named author must have
died in 1955 or earlier. Those two rules disagree exactly where it hurts — a
1926 songbook whose arranger lived to 1970 is US-PD and EU-protected.

So the PDM tag settles axis 1 (the engraving/derivation layer). It says nothing
about axis 2, and this pass decides axis 2 independently.

PROMOTION RULES (a row ships only if one fires; otherwise it is HELD):
  P1  no named person at all AND a positive traditional/folk/anonymous signal
      AND a publication date <= 1930. (EU anonymous-work term is 70 years from
      publication, so a pre-1930 anonymous publication is clear. A bare missing
      creator does NOT qualify — absence of a name is not evidence of anonymity,
      and if the author is later identified the term reverts to life+70.)
  P2  an explicit lifespan in the metadata whose death year is <= 1955.
  P3  EVERY named person resolves on Wikidata, through the maintainer's
      occupation-gated check, to a death year <= 1955.

ARRANGERS AND EDITORS COUNT. An arrangement is separately protected in the EU
(§3 UrhG, life+70 of the arranger), so "Homer H. Harbour (Arranger)" of a
traditional folk tune gates the row just as hard as a composer would. An
editorial layer (§70 UrhG, 25 years from publication) is already expired on
these pre-1930 prints, but the editor is checked anyway — it costs one lookup
and keeps the rule uniform.

TWO GUARDS THE SHARED CHECKER DOES NOT HAVE:
  * ERROR != UNKNOWN. eu_pd_check swallows transport failures into UNKNOWN, so
    a rate-limited run reports a corpus of "unresolvable" authors that is really
    just throttling. wikidata_resolve raises instead, and a canary aborts the
    run if resolution is silently dead.
  * A CLEAR verdict must MATCH THE NAME WE ASKED ABOUT. eu_pd_check picks the
    earliest death year among occupation-matching search hits, which biases
    toward CLEAR — the dangerous direction. A namesake who died in 1890 would
    clear a 1950s arranger. So a CLEAR is only accepted when the matched label
    shares the surname and is first-initial compatible; otherwise it degrades to
    UNKNOWN and the row stays held. BLOCKED is never softened.
"""
import importlib
import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
# The repo mirror under tool/ carries the music_db_ prefix; the working copy
# does not. Accept either so one file runs in both places.
for _name in ("wikidata_resolve", "music_db_wikidata_resolve"):
    try:
        _wd = importlib.import_module(_name)
        break
    except ImportError:
        continue
else:
    raise SystemExit("wikidata_resolve.py not found beside this script")

canary, load_cache = _wd.canary, _wd.load_cache
resolve, save_cache = _wd.resolve, _wd.save_cache

CUTOFF = 1955          # died <= this => PD in the EU during 2026
ANON_PUB_CUTOFF = 1930  # anonymous works: 70y from publication

HARVEST = Path(sys.argv[1] if len(sys.argv) > 1 else "jukebox")
INDEX = HARVEST / "jukebox-index.json"

# The repo mirror under tool/ carries the music_db_ prefix and an underscored
# name; the working copy does not. Accept either.
_ALIASES_RAW = {}
for _cand in ("jukebox-aliases.json", "music_db_jukebox_aliases.json"):
    _p = Path(__file__).parent / _cand
    if _p.exists():
        _ALIASES_RAW = json.loads(_p.read_text())
        break
ALIASES = {k: v for k, v in _ALIASES_RAW.items() if not k.startswith("_")}

# Roles that are contribution credits on the DERIVATION, not authorship of the
# music. These people made the scan/OMR/post-processing and PD-dedicated it.
NOT_AUTHORS = {
    "public resource", "martin r. lucas", "martin lucas", "marty lucas",
    "soundslice", "internet archive", "carl malamud", "public.resource.org",
}
# Tokens that signal "no personal author", not a name.
NON_NAME = {
    "", "unse", "unknown", "anonymous", "anon", "traditional", "trad",
    "no author listed", "not listed", "[not listed]", "various", "n/a",
    "various artists", "unknown author",
}
TRAD_SIGNAL = re.compile(
    r"folk[- ]?song|folksong|traditional|anonymous|volkslied|nursery|"
    r"spiritual|carol|shanty|chantey", re.I)

ROLE_PREFIX = re.compile(
    r"^\s*(?:words?\s+and\s+music\s+by|music\s+by|words?\s+by|lyrics?\s+by|"
    r"composed\s+by|arranged\s+by|arr\.?\s+by|arr\.|edited\s+by|ed\.\s*by|"
    r"ed\.|english\s+version\s+by|translated\s+by|annotated\s+by|fingered\s+by|"
    r"collected\s+by|harmonized\s+by|revised\s+by|selected\s+by|by)\s+", re.I)
# Bare role words that survive as a whole "name" when no person follows them.
ROLE_ONLY = re.compile(
    r"^(?:arranged|edited|collected|annotated|fingered|harmonized|revised|"
    r"selected|compiled|transcribed|words|music|lyrics)$", re.I)
PARENS = re.compile(r"\([^)]*\)")
LIFESPAN = re.compile(
    r"\((?:c\.?\s*)?(1[0-9]{3})\s*[-–—]\s*(?:c\.?\s*)?(1[0-9]{3}|20[0-2][0-9])\)")
SPLIT = re.compile(r";|\band\b|&|/|\+", re.I)
YEAR = re.compile(r"\b(1[5-9][0-9]{2}|20[0-2][0-9])\b")


def strip_accents(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def extract_names(item):
    """Named people plausibly holding rights in the MUSIC (not the scan).

    Includes the PARENT BOOK's compiler/editor. Public Resource split multi-song
    books into one item per song, and the child credits only that song's
    arranger — so judging a child on its own metadata silently ignores whoever
    compiled and edited the volume. 133 of our 204 items come from one 1922
    E. C. Schirmer songbook edited by Archibald T. Davison (d. 1961), who is EU-
    protected until the end of 2031; several of those songs cleared on the
    arranger alone before the parent was consulted.
    """
    raw = []
    creators = list(as_list(item.get("creator")))
    parent = item.get("parent") or {}
    creators += list(as_list(parent.get("creator")))
    for c in creators:
        for chunk in SPLIT.split(str(c)):
            # A comma is ambiguous: it joins two people ("Nathan Haskell Dole,
            # Friedrich Silcher") but also inverts one ("Dole, Nathan") and
            # separates role words ("Collected, Edited"). Only split when BOTH
            # sides are plausible full names, so the ambiguous cases fall
            # through as one unresolvable chunk and the row stays held.
            parts = [p.strip() for p in chunk.split(",")]
            if len(parts) == 2 and all(len(p.split()) >= 2 for p in parts):
                raw.extend(parts)
            else:
                raw.append(chunk)
    names, lifespans = [], []
    for chunk in raw:
        span = LIFESPAN.search(chunk)
        if span:
            lifespans.append(int(span.group(2)))
        chunk = PARENS.sub(" ", chunk)
        chunk = ROLE_PREFIX.sub("", chunk)
        chunk = re.sub(r"[\"'“”]", "", chunk)
        chunk = re.sub(r"\s+", " ", chunk).strip(" .,;:-")
        low = strip_accents(chunk).lower().strip()
        if low in NON_NAME or low in NOT_AUTHORS:
            continue
        if not chunk or YEAR.fullmatch(chunk):
            continue
        # "Arranged", "Edited", "Collected, Edited" reached the resolver as if
        # they were people and came back UNKNOWN, inflating the unresolvable
        # count with pipeline noise rather than data. A bare role word carries
        # no authorship claim of its own — the person, if any, was already
        # captured by ROLE_PREFIX — so drop it.
        if all(ROLE_ONLY.match(w) for w in re.split(r"[,\s]+", chunk) if w):
            continue
        # A resolvable personal name needs at least a forename and a surname.
        # One-word chunks ("Herbert", "Young" — from "Young & Herbert") are real
        # people but unidentifiable without context, so they are kept and WILL
        # fail the match guard. They are a human-resolvable residue, not a
        # ceiling; classify() reports them separately so they can be worked.
        names.append(chunk)
    return names, lifespans


def pub_year(item):
    for field in ("date", "year"):
        for v in as_list(item.get(field)):
            m = YEAR.search(str(v))
            if m:
                return int(m.group(1))
    for v in as_list(item.get("title")):
        m = YEAR.search(str(v))
        if m:
            return int(m.group(1))
    return None


def surname_key(s):
    parts = [p for p in re.split(r"[\s.]+", strip_accents(s).lower()) if p]
    parts = [p for p in parts if p not in {"jr", "sr", "ii", "iii", "de", "van",
                                           "von", "der", "den", "di", "du"}]
    return parts[-1] if parts else ""


def first_initial(s):
    parts = [p for p in re.split(r"[\s.]+", strip_accents(s).lower()) if p]
    return parts[0][0] if parts else ""


def match_ok(query, label):
    """Guard a CLEAR: the entity we found must be the person we asked about."""
    if not label:
        return False
    if surname_key(query) != surname_key(label):
        return False
    qi, li = first_initial(query), first_initial(label)
    return not (qi and li) or qi == li


PDM = "creativecommons.org/publicdomain/mark"


def classify(item, cache):
    # AXIS 1 FIRST. Not every item in the collection is marked: 23 of 204 (the
    # ORCH-* silent-film orchestral set) carry NO licenceurl at all. A faithful
    # transcription of a PD print probably attracts no new copyright anyway, but
    # that is a legal argument, not a grant — and our standard is a positive
    # rights basis per row. No statement, no ship, whatever axis 2 says.
    lic = " ".join(str(x) for x in as_list(item.get("licenseurl")))
    if PDM not in lic:
        return ("held", None,
                f"axis1 unresolved: no licence statement on the item "
                f"(licenseurl={item.get('licenseurl')!r}) — the rest of the "
                f"collection is CC PDM 1.0, so this is likely an untagged item "
                f"rather than a reserved one, but we do not infer a dedication",
                [], {})

    names, lifespans = extract_names(item)
    year = pub_year(item)
    title = " ".join(str(x) for x in as_list(item.get("title")))
    creator_txt = " ".join(str(x) for x in as_list(item.get("creator")))
    subj = " ".join(str(x) for x in as_list(item.get("subject")))
    trad = bool(TRAD_SIGNAL.search(f"{title} {creator_txt} {subj}"))

    # P1 — genuinely anonymous/traditional, pre-1930 publication, nobody named.
    if not names:
        if trad and year and year <= ANON_PUB_CUTOFF:
            return ("cleared", "P1",
                    f"no named author; traditional/folk signal; published {year} "
                    f"<= {ANON_PUB_CUTOFF} (EU anonymous term 70y from publication)",
                    names, {})
        return ("held", None,
                "no named author, but no positive traditional/anonymous signal "
                f"(or no pre-{ANON_PUB_CUTOFF} date) — absence of a credit is not "
                "evidence of anonymity", names, {})

    # P2 — an explicit lifespan in the metadata beats any name search.
    if lifespans and len(lifespans) >= len(names):
        if max(lifespans) <= CUTOFF:
            return ("cleared", "P2",
                    f"explicit lifespan(s) in metadata, latest death "
                    f"{max(lifespans)} <= {CUTOFF}", names, {})
        return ("held", None,
                f"explicit lifespan: death {max(lifespans)} > {CUTOFF}", names, {})

    # P3 — every named person must resolve CLEAR on Wikidata.
    verdicts = {}
    for n in names:
        # A human may have identified who a source spelling actually refers to
        # (typos, initials, nicknames, bare surnames). The alias supplies only
        # the IDENTIFICATION; the death year still comes from Wikidata below.
        alias = ALIASES.get(f"{item['identifier']}::{n}") or ALIASES.get(n)
        query = alias["canonical"] if alias else n
        status, yr, label, qid = resolve(query, cache)
        if status == "CLEAR" and not match_ok(query, label):
            status = "UNKNOWN"
            label = f"{label} (rejected: name mismatch)"
            yr = None
        verdicts[n] = {"status": status, "death": yr, "label": label, "qid": qid}
        if alias:
            verdicts[n]["alias_of"] = query
            verdicts[n]["alias_why"] = alias["why"]

    if all(v["status"] == "CLEAR" for v in verdicts.values()):
        deaths = {n: v["death"] for n, v in verdicts.items()}
        return ("cleared", "P3",
                f"Wikidata life+70: every named author died <= {CUTOFF} {deaths}",
                names, verdicts)

    blocked = {n: v["death"] for n, v in verdicts.items() if v["status"] == "BLOCKED"}
    unknown = [n for n, v in verdicts.items() if v["status"] == "UNKNOWN"]
    why = []
    if blocked:
        why.append(f"death after {CUTOFF}: {blocked}")
    if unknown:
        why.append(f"unresolvable: {unknown}")
    return "held", None, "; ".join(why), names, verdicts


def main():
    if not INDEX.exists():
        raise SystemExit(f"missing {INDEX} — run jukebox_harvest.py first")
    items = json.loads(INDEX.read_text())
    cache = load_cache()
    canary(cache)

    cleared, held = [], []
    try:
        for n, it in enumerate(items, 1):
            status, rule, reason, names, verdicts = classify(it, cache)
            rec = dict(it)
            rec.update({"clearance": status, "rule": rule,
                        "axis2_reason": reason, "names": names,
                        "wikidata": verdicts})
            (cleared if status == "cleared" else held).append(rec)
            tag = f"{rule}" if rule else "HELD"
            print(f"[{n}/{len(items)}] {tag:5} {str(it.get('title'))[:46]:46} "
                  f"{reason[:70]}", flush=True)
    finally:
        save_cache(cache)

    HARVEST.joinpath("jukebox-clearance.json").write_text(
        json.dumps(cleared, indent=1, ensure_ascii=False))
    HARVEST.joinpath("jukebox-probation.json").write_text(
        json.dumps(held, indent=1, ensure_ascii=False))

    print(f"\n=== cleared {len(cleared)} · held {len(held)} "
          f"(of {len(items)}) ===")
    by_rule = {}
    for c in cleared:
        by_rule[c["rule"]] = by_rule.get(c["rule"], 0) + 1
    print("cleared by rule:", by_rule)


if __name__ == "__main__":
    main()
