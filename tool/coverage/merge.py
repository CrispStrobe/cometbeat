#!/usr/bin/env python3
"""Merge the lcov parts from tool/coverage/run.sh and report line coverage.

Merges DA (line) and BRDA (branch, if --branch-coverage was used) records by max
hit across all parts, writes coverage/merged.info, and prints:
  * the overall line-coverage percentage,
  * the worst-covered LOADED files (real gaps inside tested code), and
  * files no test loads at all (split from the untestable ffi/stub/gen shells).

Run from the repo root after tool/coverage/run.sh:  python3 tool/coverage/merge.py
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PARTS = os.path.join(ROOT, "coverage", "parts")
MERGED = os.path.join(ROOT, "coverage", "merged.info")

da = {}    # sf -> {line: max count}
brda = {}  # sf -> {(line, block, branch): max count} (-1 = never taken)


def add_part(path):
    sf = None
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        if line.startswith("SF:"):
            sf = line[3:]
            da.setdefault(sf, {})
            brda.setdefault(sf, {})
        elif line.startswith("DA:") and sf:
            m = re.match(r"DA:(\d+),(-?\d+)", line)
            if m:
                ln, c = int(m.group(1)), int(m.group(2))
                da[sf][ln] = max(da[sf].get(ln, 0), c)
        elif line.startswith("BRDA:") and sf:
            m = re.match(r"BRDA:(\d+),(\d+),(\d+),(-|\d+)", line)
            if m:
                key = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
                c = -1 if m.group(4) == "-" else int(m.group(4))
                brda[sf][key] = max(brda[sf].get(key, -1), c)
        elif line == "end_of_record":
            sf = None


def untestable(rel):
    base = os.path.basename(rel)[:-5]
    if any(base.endswith(p) for p in ("_ffi", "_stub", "_io", "_web", "_platform")):
        return True
    if "/generated" in rel or base.startswith("app_localizations"):
        return True
    return False


def main():
    parts = sorted(glob.glob(os.path.join(PARTS, "*.info")))
    if not parts:
        print("no coverage parts; run tool/coverage/run.sh first", file=sys.stderr)
        sys.exit(1)
    for p in parts:
        add_part(p)

    with open(MERGED, "w", encoding="utf-8") as out:
        for sf in sorted(da):
            out.write(f"SF:{sf}\n")
            for ln in sorted(da[sf]):
                out.write(f"DA:{ln},{da[sf][ln]}\n")
            for (ln, blk, br) in sorted(brda[sf]):
                c = brda[sf][(ln, blk, br)]
                out.write(f"BRDA:{ln},{blk},{br},{'-' if c < 0 else c}\n")
            lf = len(da[sf])
            lh = sum(1 for c in da[sf].values() if c > 0)
            out.write(f"LF:{lf}\nLH:{lh}\n")
            out.write("end_of_record\n")

    all_lib = []
    for root, _, files in os.walk(os.path.join(ROOT, "lib")):
        for fn in files:
            if fn.endswith(".dart"):
                all_lib.append(os.path.relpath(os.path.join(root, fn), ROOT))
    all_lib.sort()
    covered = set(da)

    total_lf = sum(len(d) for d in da.values())
    total_lh = sum(1 for d in da.values() for c in d.values() if c > 0)

    print("=" * 74)
    print("COVERAGE SUMMARY (lib/)")
    print("=" * 74)
    print(f"parts merged   : {len(parts)}")
    print(f"lib .dart files: {len(all_lib)}   with coverage: {len(covered)}")
    if total_lf:
        print(f"overall line   : {total_lh}/{total_lf} = {100.0*total_lh/total_lf:.1f}%")

    def pct(rel):
        d = da.get(rel)
        if not d:
            return None
        return 100.0 * sum(1 for c in d.values() if c > 0) / len(d)

    loaded = [(pct(f), f) for f in all_lib if f in covered]
    loaded = [(p, f) for p, f in loaded if p is not None]
    loaded.sort()
    print("\nWORST-COVERED LOADED FILES (line% asc, >=15 lines):")
    for p, f in loaded[:40]:
        lf = len(da[f])
        if p < 90 and lf >= 15:
            lh = sum(1 for c in da[f].values() if c > 0)
            print(f"  {p:5.1f}%  {lh:4d}/{lf:<4d}  {f}")

    never = [f for f in all_lib if f not in covered and not untestable(f)]
    print(f"\nNEVER-LOADED (non-ffi/stub/gen) — {len(never)} files "
          "(mostly export-shell barrels/enums):")
    for f in never:
        print(f"  {f}")


if __name__ == "__main__":
    main()
