#!/usr/bin/env python3
"""Apply the content screen: move `hold` rows out of db.json, reversibly.

Idempotent. The row is moved, never deleted — it keeps its full manifest entry
in `content-held.json` with the term that caught it, and the file stays on disk.
Restoring is a maintainer decision, and they need to see WHY each one was
caught to make it.

Only the `hold` tier is applied. `review` is listed and left alone: those terms
are offensive only in context ("Mohr" in a Baroque libretto, "Indianer" in a
children's game song), and auto-deleting legitimate repertoire on a substring
match is its own failure mode.
"""
import json
import os
import sys
from collections import Counter

ROOT = "/mnt/volume1/music-db"


def main():
    screen = json.load(open(f"{ROOT}/content-screen.json"))
    hold = {h["id"]: h for h in screen["hold"] if h.get("id")}
    # Manual additions: rows the automatic tier cannot reach because the offence
    # is in what the song IS, not in a word it contains. "Dixie" and "Massa's in
    # the Cold Ground" carry no slur token — they are blackface-minstrel and
    # Confederate repertoire, which no keyword list identifies. The reverse also
    # lives here: nothing is ever auto-held on a name, which is why every "Mohr"
    # hit (Joseph Mohr, the lyricist of Stille Nacht) stayed in review.
    manual = f"{ROOT}/content-hold-manual.json"
    if os.path.exists(manual):
        for m in json.load(open(manual)):
            hold[m["id"]] = {**m, "kind": m.get("kind", "manual"),
                             "where": m.get("where", "work")}
    # Exemptions: a keyword says the word is present, it cannot say what the
    # work IS. "Contains a slur" and "inappropriate to ship" are different
    # questions, and for canonical art song and opera the exonym is the
    # historical title of a literary work rather than an invitation to sing a
    # stereotype (maintainer, 2026-07-30). An exempt row is RESTORED to db.json
    # if a previous run already moved it out — the decision has to be
    # reversible in both directions or the ledger drifts from the corpus.
    exempt = {}
    epath = f"{ROOT}/content-hold-exempt.json"
    if os.path.exists(epath):
        exempt = {x["id"]: x for x in json.load(open(epath))}
        for i in exempt:
            hold.pop(i, None)
    db = json.load(open(f"{ROOT}/db.json"))

    prev = []
    if os.path.exists(f"{ROOT}/content-held.json"):
        prev = json.load(open(f"{ROOT}/content-held.json"))
    kept, moved = [], {h["id"]: h for h in prev if h.get("id")}
    for e in db:
        h = hold.get(e.get("id"))
        if h:
            moved[e["id"]] = {**e, "content_hold": {
                "term": h["term"], "kind": h["kind"], "where": h["where"],
                "reason": ("racial slur" if h["kind"].startswith("slur")
                           else h.get("reason") if h["kind"] == "manual"
                           else "National Socialist / Wehrmacht repertoire")
                + f" — matched '{h['term']}' in the {h['where']}. Rights are not "
                  "the issue; every one of these passes the licence gates. "
                  "Restoring is a maintainer call."}}
        else:
            kept.append(e)

    restored = []
    for i in list(moved):
        if i in exempt:
            row = {k: v for k, v in moved.pop(i).items() if k != "content_hold"}
            kept.append(row)
            restored.append(i)

    out = list(moved.values())
    json.dump(out, open(f"{ROOT}/content-held.json", "w"), indent=1,
              ensure_ascii=False)
    dangling = sum(1 for x in kept if x.get("path")
                   and not os.path.exists(os.path.join(ROOT, x["path"])))
    assert dangling == 0, f"{dangling} dangling paths — aborting write"
    json.dump(kept, open(f"{ROOT}/db.json", "w"), indent=1)

    print(f"db.json {len(db)} -> {len(kept)}  "
          f"({len(db) - len(kept) + len(restored)} moved out, "
          f"{len(restored)} restored by exemption)")
    print(f"content-held.json now {len(out)} rows")
    print("held by source:", dict(Counter(
        x.get("source") for x in out).most_common(10)))
    # Rows held by an earlier/parallel pass are merged through verbatim and may
    # predate the content_hold annotation — another agent had already pulled
    # three antisemitic 18th-century dance titles out of the TradArchiv
    # manuscripts. Preserve them rather than assuming this script wrote every
    # row in the file.
    print("held by kind:", dict(Counter(
        (x.get("content_hold") or {}).get("kind", "pre-existing") for x in out)))


if __name__ == "__main__":
    main()
