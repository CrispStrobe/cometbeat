#!/usr/bin/env python3
"""The single ship path: screen -> hold -> emit -> verify. Refuses on surprises.

WHY THIS EXISTS. The content screen was something a person RAN, not something the
pipeline ENFORCED. The denylist inside emit_catalog protects ids already held,
but a source ingested tomorrow reaches the catalog completely unscreened, and the
failure is silent — this session found slur-bearing rows live in the shipped
catalog three separate times, each after the previous pass was believed thorough.

So publishing now means running this, and this stops when it finds something:

  1. take the db.json lock, so no ingest can interleave with a publish;
  2. run the content screen over the CURRENT corpus;
  3. STOP if it produced holds that are neither already held nor explicitly
     exempt — a new hold is a decision for a human, never an automatic delete;
  4. apply the held ledger, emit the catalog;
  5. verify no held id and no held payload reached the catalog.

Step 3 is the whole point. Everything else was already possible; what was missing
was something that refuses to continue.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from music_db_lock import ROOT, db_lock  # noqa: E402

BIN = f"{ROOT}/bin"


def run(script, *args):
    print(f"\n$ {script} {' '.join(args)}", flush=True)
    r = subprocess.run([sys.executable, f"{BIN}/{script}", *args],
                       capture_output=True, text=True)
    sys.stdout.write(r.stdout[-4000:])
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-4000:])
        raise SystemExit(f"!! {script} failed ({r.returncode})")
    return r.stdout


def load(name, default):
    p = f"{ROOT}/{name}"
    return json.load(open(p)) if os.path.exists(p) else default


def main():
    skip_screen = "--skip-screen" in sys.argv   # only for a re-emit after review
    with db_lock():
        if not skip_screen:
            run("music_db_content_screen.py")
        screen = load("content-screen.json", {"hold": [], "review": []})
        held = {x.get("id") for x in load("content-held.json", [])}
        exempt = {x.get("id") for x in load("content-hold-exempt.json", [])}
        manual = {x.get("id") for x in load("content-hold-manual.json", [])}

        surprises = [h for h in screen["hold"]
                     if h.get("id") not in held | exempt | manual]
        if surprises:
            print(f"\n{'=' * 70}\nSTOP: {len(surprises)} new content hit(s) — "
                  "a human decides these, publishing is blocked.\n")
            for h in surprises:
                print(f"  {h.get('term','?'):22} {(h.get('title') or '')[:44]:44} "
                      f"{(h.get('source') or '')[:26]}")
            print("\nAdd each to content-hold-manual.json (hold) or "
                  "content-hold-exempt.json (keep, with the reason), then re-run.")
            raise SystemExit(2)

        print(f"\ncontent screen clean: {len(screen['hold'])} hit(s), all known "
              f"({len(held)} held, {len(exempt)} exempt). "
              f"{len(screen['review'])} in review (advisory).")

        run("music_db_apply_content_hold.py")
        run("emit_catalog.py")

        # Verify rather than trust: the gate above is only as good as the emit.
        held = {x.get("id") for x in load("content-held.json", [])}
        leaked, paths = [], []
        for kind in ("score", "instrument", "module", "sample", "soundfont"):
            p = f"{ROOT}/catalog/{kind}.json"
            if not os.path.exists(p):
                continue
            for i in json.load(open(p))["items"]:
                if i.get("id") in held:
                    leaked.append(i["id"])
                    paths.append(i.get("path"))
        ly = load("catalog/lyrics.json", {"items": {}})["items"]
        leaked_text = [k for k in ly if k in held]
        if leaked or leaked_text:
            raise SystemExit(
                f"!! {len(leaked)} held row(s) and {len(leaked_text)} held "
                f"lyric(s) reached the catalog: {(leaked + leaked_text)[:5]}")
        print(f"\nOK — 0 held rows and 0 held lyrics in the catalog.")
        print("Next: upload payloads FIRST, then ./catalog (see ../hf_ops.md).")


if __name__ == "__main__":
    main()
