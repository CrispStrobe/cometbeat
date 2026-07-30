#!/usr/bin/env python3
"""Screen the corpus for content that must not ship, independent of rights.

WHY THIS IS A SEPARATE PASS. Every other gate in this repo answers "who owns
it". None of them answers "should a child see it". Those come apart in both
directions and the licence tiers are silent on the second: Herms Niel died in
1954, so a Wehrmacht marching song clears axis 2 cleanly; a minstrel song from
1848 is spotless public domain and opens with a racial slur. Nothing upstream
would ever stop either one.

TITLES ARE NOT ENOUGH. A clean title routinely hides a slur in verse 3 — the
printed 19th-century texts of several standards do exactly that — so this reads
the FILE, not just the row. Text formats are read directly, zip containers
(.mxl/.mscz) are opened in memory, and MIDI is decoded latin-1 so track and
lyric meta events are searched too.

TWO OUTCOMES, DELIBERATELY. `hold` is for terms that are slurs in any context;
those come out of db.json automatically. `review` is for terms whose offence
depends entirely on context — "Mohr" in a Baroque libretto, "Indianer" in a
children's game song, the Deutschlandlied — and those are only ever LISTED.
Auto-holding them would quietly delete legitimate repertoire on a substring
match, which is its own kind of failure. A human decides that tier.

Over-holding is cheap and reversible; every held row keeps its manifest entry
and its file on disk. Under-holding ships a slur to a child.
"""
import io
import json
import os
import re
import sys
import zipfile
from collections import Counter, defaultdict

ROOT = "/mnt/volume1/music-db"

# --- terms that are slurs in any context -------------------------------------
# German and English. Word-boundary anchored, with the German compound forms
# spelled out rather than left to a prefix match, so "Negation" and "Zigarette"
# do not trip and "Negerlein"/"Zigeunerleben" do.
SLUR = {
    "de": [
        r"\bneger\w*", r"\bnegerlein\b", r"\bmohrenkopf\w*",
        r"\bzigeuner\w*", r"\bzigeinder\w*",
        r"\bhottentott?e?n?\w*", r"\bkaffern?\b", r"\bbimbo\b",
    ],
    "en": [
        r"\bnigg\w+", r"\bdarke?y\b", r"\bdarkies\b", r"\bpickaninn\w+",
        r"\bsambo\b", r"\bgypsy\b", r"\bgypsies\b", r"\bsquaw\w*",
        r"\bhalf-?breed\b", r"\bhottentot\w*",
    ],
}
# ⚠️ TWO PATTERNS WERE REMOVED AFTER THE FIRST RUN, and the reason generalises
# to any short term added later. `\bwog\b` and `\bcoons?\b` produced 7 hits and
# ALL SEVEN were false:
#   * LYRICS ARE SYLLABIFIED. A vocal score stores "wog-nia" and "co-on" as
#     separate syllables, so a word-boundary anchor matches a fragment that is
#     not a word at all. Polish and Czech vocal music trips this constantly.
#   * German has the ordinary word "wog" (past of wiegen) — it caught Schumann's
#     *Mondnacht*.
#   * MIDI is decoded latin-1 so lyric meta events are searchable, which means
#     binary bytes can spell any three-letter sequence; a 1915 Sousa march
#     matched "WOG".
# A term shorter than ~5 characters is not safe against this corpus. Prefer a
# longer, unambiguous form, or put it in REVIEW where a human sees it.
# --- National Socialist / Wehrmacht repertoire --------------------------------
# Named works plus the unmistakable textual markers. A marching song is not
# identifiable by vocabulary alone, so this is mostly a title list; the markers
# catch what the titles miss.
NS = [
    r"\bhorst[- ]wessel", r"\bpanzerlied\b", r"\bwesterwaldlied\b",
    r"\bes zittern die morschen knochen", r"\bvolk,? ans gewehr",
    r"\bbomben auf eng[e]?land", r"\bdeutschland erwache",
    r"\bsieg heil", r"\bhakenkreuz", r"\bjudenblut",
    r"\bdie fahne hoch", r"\bsa marschiert", r"\bss[- ]?marsch",
    r"\bunsere fahne flattert uns voran", r"\bvorw[äa]rts! vorw[äa]rts!",
    r"\bdenn heute geh[öo]rt uns deutschland",
    r"\berika\b(?=.*niel)", r"\bniel, herms", r"\bherms niel",
]
# --- context-dependent: LIST ONLY, never auto-hold ----------------------------
REVIEW = [
    r"\bmohr\w*", r"\bindianer\w*", r"\beskimo\w*", r"\blappen?l[äa]nder\w*",
    r"\bdeutschland[,]? deutschland [üu]ber alles", r"\bwenn die soldaten\b",
    r"\bein heller und ein batzen\b", r"\blili marleen\b",
    r"\bwildg[äa]nse rauschen\b", r"\bargonnerwald\b",
    r"\bminstrel\b", r"\bplantation\b", r"\bmassa\b",
    # The minstrel canon by WORK NAME. Learned the hard way: the screen caught
    # "My Old Kentucky Home" only because the word "darky" survived into that
    # particular printing, and "Massa's in the Cold Ground" only via a
    # review-tier term — while five siblings from the same repertoire stayed
    # shipped, because Foster and Emmett wrote the dialect into words no slur
    # list contains ("Gwine", "De", "ribber"). A keyword screen cannot see what
    # a work IS; naming the works is the only thing that closes it, and even
    # then a second edition under the full original title slipped through once.
    r"\bdixie(?:'?s)?\b", r"\bdixieland\b", r"\bswanee\b", r"\bcamptown\b",
    r"\bold folks at home\b", r"\bold black joe\b", r"\bkentucky home\b",
    r"\bgwine\b", r"\buncle tom\b", r"\bjim crow\b",
]

TEXT_EXT = {".ly", ".abc", ".krn", ".xml", ".musicxml", ".mscx", ".gabc",
            ".txt", ".mei", ".json"}
ZIP_EXT = {".mxl", ".mscz", ".gp", ".gpx"}


def compile_all():
    return (
        [(re.compile(p, re.I), "slur:" + lang) for lang, ps in SLUR.items()
         for p in ps],
        [(re.compile(p, re.I), "ns") for p in NS],
        [(re.compile(p, re.I), "review") for p in REVIEW],
    )


# One alternation per tier instead of ~26 separate passes. Scanning a decoded
# .mxl body 26 times is what made the first run project to three hours; the
# combined form is a single pass and the per-tier verdict is all we need, since
# the exact term is recovered afterwards on the (tiny) set of matching rows.
def combined():
    def joined(pats):
        return re.compile("|".join(f"(?:{p})" for p in pats), re.I)
    return (joined([p for ps in SLUR.values() for p in ps] + NS),
            joined(REVIEW))


def file_text(path):
    """Best-effort searchable text for any corpus file, or '' if unreadable."""
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in ZIP_EXT:
            out = []
            with zipfile.ZipFile(path) as z:
                for n in z.namelist():
                    if os.path.splitext(n)[1].lower() in TEXT_EXT | {".xml"}:
                        out.append(z.read(n).decode("utf-8", "replace"))
            return "\n".join(out)
        raw = open(path, "rb").read()
        # MIDI is binary, but track names and lyric meta events are plain bytes;
        # latin-1 never throws, so a decoded scan is strictly better than none.
        return raw.decode("utf-8", "replace") if ext in TEXT_EXT \
            else raw.decode("latin-1", "replace")
    except Exception:                                    # noqa: BLE001
        return ""


_HOLD_RX, _REVIEW_RX = combined()


def _scan(row):
    """(tier, title) for one row — the cheap pass, run in a worker."""
    title = row[1] or ""
    p = row[2]
    full = os.path.join(ROOT, p) if p else None
    body = file_text(full) if full and os.path.exists(full) else ""
    hay = f"{title}\n{body}"
    if _HOLD_RX.search(hay):
        return "hold", row[0]
    if _REVIEW_RX.search(hay):
        return "review", row[0]
    return None, row[0]


def main():
    slur, ns, review = compile_all()
    db = json.load(open(f"{ROOT}/db.json"))
    scores = [e for e in db if (e.get("kind") or "score") == "score"]
    # --refine: re-judge only the rows a previous full run flagged. Valid ONLY
    # when patterns were removed or narrowed (that can lose hits, never gain
    # them). Widen a pattern and you must re-run the whole corpus.
    if "--refine" in sys.argv:
        prev = json.load(open(f"{ROOT}/content-screen.json"))
        keep = {r["id"] for tier in ("hold", "review") for r in prev[tier]}
        scores = [e for e in scores if e.get("id") in keep]
        print(f"refining {len(scores)} previously flagged rows")
    byid = {}
    work = []
    for i, e in enumerate(scores):
        byid[i] = e
        work.append((i, e.get("title"), e.get("path")))

    import multiprocessing as mp
    flagged = []
    with mp.Pool(2) as pool:
        for n, (tier, idx) in enumerate(
                pool.imap_unordered(_scan, work, chunksize=64), 1):
            if tier:
                flagged.append((tier, idx))
            if n % 2500 == 0:
                print(f"  [{n}/{len(work)}] flagged={len(flagged)}", flush=True)

    # Second pass, only over what matched: recover WHICH term fired and where.
    hits = defaultdict(list)
    stats = Counter()
    for tier, idx in flagged:
        e = byid[idx]
        title = e.get("title") or ""
        p = e.get("path")
        full = os.path.join(ROOT, p) if p else None
        body = file_text(full) if full and os.path.exists(full) else ""
        hay = f"{title}\n{body}"
        pats = (slur + ns) if tier == "hold" else review
        for rx, kind in pats:
            m = rx.search(hay)
            if m:
                hits[tier].append({
                    "id": e.get("id"), "title": title, "source": e.get("source"),
                    "term": m.group(0)[:40], "kind": kind,
                    "where": "title" if rx.search(title) else "lyrics",
                    "path": p})
                stats[f"{tier}/{kind}"] += 1
                break

    json.dump(hits, open(f"{ROOT}/content-screen.json", "w"), indent=1,
              ensure_ascii=False)
    print("\n=== content screen ===")
    for k, n in sorted(stats.items()):
        print("  %5d  %s" % (n, k))
    print(f"\n  hold {len(hits['hold'])} · review {len(hits['review'])}")
    for tier in ("hold", "review"):
        print(f"\n  --- {tier} (top terms) ---")
        for t, n in Counter(h["term"].lower() for h in hits[tier]).most_common(12):
            print("    %4d  %s" % (n, t))


if __name__ == "__main__":
    main()
