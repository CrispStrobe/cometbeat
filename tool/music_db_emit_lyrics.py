#!/usr/bin/env python3
"""Extract sung text for every corpus row -> lyrics-index.json.

Two consumers, both in emit_catalog.py:
  * a short `textIncipit` on each main-shard item, so "find the song by its
    words" works without a second fetch;
  * `catalog/lyrics.json(.gz)`, the full text, fetched only when someone
    actually searches lyrics — keeping the browse path at ~2 MB.

Reuses `lyric_words` from the content screen rather than reimplementing it. That
function is the product of getting this wrong three times — 28% coverage when it
dumped raw markup, 73% when Chopin's solo piano "had" 23,853 characters of
lyrics, 35% once each format was handled properly — so there must be exactly one
implementation and this is not the place for a second.

Writes id -> text for rows that have text. Rows without sung text are simply
absent, which is the honest encoding: a string quartet has no lyrics, and an
empty string would suggest we looked and found silence.
"""
import json
import multiprocessing as mp
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music_db_content_screen as S  # noqa: E402

ROOT = "/mnt/volume1/music-db"
OUT = f"{ROOT}/lyrics-index.json"


def _one(job):
    rid, path = job
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return rid, ""
    try:
        return rid, S.lyric_words(S.file_text(full)).strip()
    except Exception:                                    # noqa: BLE001
        # A single unreadable file must not abort a 46k-row pass.
        return rid, ""


def main():
    db = json.load(open(f"{ROOT}/db.json"))
    jobs = [(e["id"], e["path"]) for e in db
            if e.get("id") and e.get("path")
            and (e.get("kind") or "score") == "score"]
    print(f"extracting lyrics from {len(jobs)} score rows", flush=True)

    out = {}
    with mp.Pool(2) as pool:
        for n, (rid, text) in enumerate(
                pool.imap_unordered(_one, jobs, chunksize=64), 1):
            if len(text) >= 25:
                out[rid] = text
            if n % 5000 == 0:
                print(f"  [{n}/{len(jobs)}] with text: {len(out)}", flush=True)

    json.dump(out, open(OUT, "w"), ensure_ascii=False)
    chars = sum(len(v) for v in out.values())
    print(f"\nrows with sung text: {len(out)} / {len(jobs)} "
          f"({100 * len(out) / len(jobs):.0f}%)")
    print(f"total characters: {chars:,}  ({chars / 1e6:.1f} MB raw)")
    print(f"mean length: {chars // max(len(out), 1)}")
    print(f"-> {OUT} ({os.path.getsize(OUT) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
