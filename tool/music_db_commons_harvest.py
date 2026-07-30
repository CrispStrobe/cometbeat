#!/usr/bin/env python3
"""Harvest Wikimedia Commons symbolic music, tiered from STRUCTURED DATA.

Two sources, both symbolic (the DB takes no rendered audio):
  * `--midi`  — Commons MIDI files (audio/midi), ~7k of them.
  * `--ly`    — LilyPond inside <score> blocks on de.wikipedia song articles.

WHY STRUCTURED DATA AND NOT THE LICENCE TEMPLATE. `extmetadata.LicenseShortName`
is a rendered STRING ("Public domain", "CC BY-SA 3.0") produced by whichever
template the uploader happened to use. Structured Data on Commons (SDC) instead
carries machine-readable claims — P6216 copyright status, P275 licence — as Q
ids. That is an unambiguous tier decision instead of string-matching prose, and
it is what makes a Tier A/B promotion defensible.

⚠️ Every Q id below was RESOLVED against Wikidata, not guessed. A first pass
guessed Q71979350 was "PD, author life+70"; it is in fact a person's name. Do
not extend these tables from memory — look the id up.

⚠️ AXIS 2 IS NOT DECIDED HERE. SDC describes the FILE (the engraving/rendering),
not the underlying composition. A PD-self MIDI of a 1960s song is Tier A on
axis 1 and still blocked. Feed the output through the life+70 pass before ingest.
"""
import argparse
import json
import re
import time

import requests

UA = ("CometBeat-corpus-harvest/1.0 (music education app; PD corpus ingest; "
      "contact stc.akrs@gmail.com)")
COMMONS = "https://commons.wikimedia.org/w/api.php"
DEWIKI = "https://de.wikipedia.org/w/api.php"

# --- resolved SDC vocabulary -------------------------------------------------
PD_STATUS = {
    "Q19652": "public domain",
    "Q88088423": "copyrighted, dedicated to the public domain by copyright holder",
    "Q98592850": "released into the public domain by the copyright holder",
}
# "no known copyright restrictions" (Q99263261) is deliberately NOT here: it
# records an absence of knowledge, not a grant.
CC0 = {"Q6938433": "CC0"}
CC_BY = {
    "Q20007257": "CC BY 4.0",
    "Q18810143": "CC BY 3.0",
    "Q18810333": "CC BY 2.5",
    "Q19125117": "CC BY 2.0",
}
# Everything share-alike / GFDL is Tier C for us — the catalog ships A and B.
EXCLUDED = {
    "Q18199165": "CC BY-SA 4.0", "Q14946043": "CC BY-SA 3.0",
    "Q6905323": "CC BY-SA 2.5", "Q29458182": "CC BY-SA 2.0",
    "Q75209430": "CC SA 1.0", "Q50829104": "GFDL 1.2+",
    "Q19113751": "CC BY-SA 2.5",
}


def _session():
    s = requests.Session()
    s.headers["User-Agent"] = UA
    return s


def _get(s, api, params, tries=5):
    for i in range(tries):
        r = s.get(api, params={**params, "format": "json"}, timeout=90)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(10 * (i + 1))
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError(f"giving up on {api}")


def tier_of(statements):
    """(tier, reason) from SDC claims. Tier A/B, or None when not shippable."""
    def qids(prop):
        out = []
        for c in statements.get(prop, []):
            v = c["mainsnak"].get("datavalue", {}).get("value", {})
            if isinstance(v, dict) and v.get("id"):
                out.append(v["id"])
        return out

    status, lic = qids("P6216"), qids("P275")
    # A share-alike or GFDL licence anywhere disqualifies, even if the file also
    # claims public domain — the most restrictive statement governs what we may
    # redistribute.
    bad = [q for q in lic if q in EXCLUDED]
    if bad:
        return None, "excluded licence: " + ", ".join(EXCLUDED[q] for q in bad)
    for q in status:
        if q in PD_STATUS:
            return "A", f"SDC P6216={PD_STATUS[q]}"
    for q in lic:
        if q in CC0:
            return "A", "SDC P275=CC0"
    for q in lic:
        if q in CC_BY:
            return "B", f"SDC P275={CC_BY[q]}"
    if not status and not lic:
        return None, "no SDC rights statements"
    return None, f"unrecognised rights claims: status={status} licence={lic}"


def harvest_midi(limit):
    s = _session()
    titles, off = [], 0
    while len(titles) < limit:
        d = _get(s, COMMONS, {"action": "query", "list": "search",
                              "srsearch": "filemime:audio/midi", "srnamespace": 6,
                              "srlimit": 50, "sroffset": off})
        got = [m["title"] for m in d.get("query", {}).get("search", [])]
        if not got:
            break
        titles += got
        off += len(got)
        if not d.get("continue"):
            break
        time.sleep(0.5)
    titles = titles[:limit]
    print(f"MIDI file pages found: {len(titles)}")

    rows = []
    for i in range(0, len(titles), 25):
        batch = titles[i:i + 25]
        q = _get(s, COMMONS, {"action": "query", "titles": "|".join(batch),
                              "prop": "imageinfo", "iiprop": "url|size|extmetadata"})
        pages = {int(k): v for k, v in q["query"]["pages"].items() if int(k) > 0}
        ent = _get(s, COMMONS, {"action": "wbgetentities",
                                "ids": "|".join(f"M{p}" for p in pages)})
        for pid, page in pages.items():
            st = ent.get("entities", {}).get(f"M{pid}", {}).get("statements", {})
            tier, why = tier_of(st)
            ii = (page.get("imageinfo") or [{}])[0]
            em = ii.get("extmetadata", {})
            rows.append({
                "title": page["title"],
                "url": ii.get("url"),
                "bytes": ii.get("size"),
                "tier": tier,
                "rights_method": f"axis1={why} (Structured Data on Commons)",
                # kept for the axis-2 pass, NOT used for the tier decision
                "artist": re.sub(r"<[^>]+>", "",
                                 em.get("Artist", {}).get("value", "")).strip(),
                "template_licence": em.get("LicenseShortName", {}).get("value"),
            })
        time.sleep(0.6)
    return rows


def harvest_ly(limit):
    """<score> LilyPond from de.wikipedia song articles — Tier C by default.

    Wiki text is CC BY-SA, so the ENGRAVING is share-alike. Whether a faithful
    transcription of a public-domain melody carries any new authorship at all is
    a maintainer call; until then these are held at Tier C (local only).
    """
    s = _session()
    titles, off = [], 0
    while len(titles) < limit:
        d = _get(s, DEWIKI, {"action": "query", "list": "search",
                             "srsearch": 'insource:"<score" incategory:"Volkslied"',
                             "srnamespace": 0, "srlimit": 50, "sroffset": off})
        got = [m["title"] for m in d.get("query", {}).get("search", [])]
        if not got:
            break
        titles += got
        off += len(got)
        if not d.get("continue"):
            break
        time.sleep(0.5)
    titles = titles[:limit]
    print(f"de.wikipedia articles with <score>: {len(titles)}")

    rows = []
    for t in titles:
        d = _get(s, DEWIKI, {"action": "parse", "page": t, "prop": "wikitext",
                             "redirects": 1})
        wt = d.get("parse", {}).get("wikitext", {}).get("*", "")
        blocks = [b for b in re.findall(r"<score[^>]*>(.*?)</score>", wt, re.S)
                  if re.search(r"\\relative|\\new\s+(Staff|Voice)", b)]
        if not blocks:
            continue
        src = blocks[0]
        # Keep the source WHOLE, lyrics included.
        #
        # An earlier version stripped \addlyrics/\lyricmode to avoid copying
        # text. That backfired twice: a song corpus needs its words, and the
        # strip left DANGLING assignments (`verse = ` with no value) which then
        # swallowed the following \score block — 23 of 127 harvested melodies
        # read as empty purely because of it.
        #
        # The text author is instead handled where it belongs: the axis-2 pass
        # gates on lyricist/translator exactly as it does on composer, so a
        # protected text blocks the row rather than being silently discarded.
        rows.append({
            "title": t,
            "source_url": f"https://de.wikipedia.org/wiki/{t.replace(' ', '_')}",
            "tier": "C",
            "rights_method": ("axis1=CC BY-SA 4.0 (wiki text) — Tier C, local "
                              "only; a faithful transcription of a PD melody may "
                              "carry no new authorship, but that is unresolved"),
            "lilypond": src,
        })
        time.sleep(0.5)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--midi", action="store_true")
    ap.add_argument("--ly", action="store_true")
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    rows = harvest_midi(a.limit) if a.midi else harvest_ly(a.limit)
    with open(a.out, "w") as fh:
        json.dump(rows, fh, indent=1, ensure_ascii=False)

    import collections
    print(f"\nwrote {len(rows)} rows -> {a.out}")
    print("tiers:", dict(collections.Counter(r.get("tier") for r in rows)))
    if a.midi:
        for why, n in collections.Counter(
                r["rights_method"] for r in rows).most_common(8):
            print("   %4d  %s" % (n, why[:88]))


if __name__ == "__main__":
    main()
