#!/usr/bin/env python3
"""CPDL axis-2 pass — EU life+70 over every rights-bearing person on the page.

Axis 1 is already settled per edition by the {{Copy|...}} field (Public Domain /
CC0 / CC BY only reach this script). Axis 2 is independent and gates here.

WHO COUNTS. Composer, arranger, lyricist AND translator. CPDL records all four,
and each holds a separate life+70 term: an arrangement is a Bearbeitung (§3
UrhG), a text is its own work, and a translation is a protected adaptation of
one. The Internet Jukebox songbook was blocked by precisely this — its credited
"arrangers" were translators of the English words, and the MusicXML embedded
those words. CPDL is choral: nearly every page HAS a text, so ignoring lyricists
would be the same mistake at 10x the scale.

Reuses the throttled resolver and the same guards as the Jukebox pass:
transport errors raise rather than becoming UNKNOWN, and a CLEAR must match the
name it was asked about (eu_pd_check picks the earliest death among hits, which
biases toward CLEAR — the dangerous direction).

Cheap because CPDL names repeat: ~375 distinct composers cover 3,791 editions,
and every lookup is cached to disk.
"""
import collections
import importlib
import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
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

CUTOFF = 1955
ANON = re.compile(r'^(anonymous|anon\.?|traditional|trad\.?|unknown|various)$', re.I)
# CPDL composer values are wiki page names; some carry a disambiguator.
PARENS = re.compile(r'\([^)]*\)')
LIFESPAN = re.compile(r'\b(1[0-9]{3})\s*[-–—]\s*(1[0-9]{3}|20[0-2][0-9])\b')


def strip_accents(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def surname_key(s):
    parts = [p for p in re.split(r"[\s.,]+", strip_accents(s).lower()) if p]
    parts = [p for p in parts if p not in {"jr", "sr", "ii", "iii", "de", "van",
                                           "von", "der", "den", "di", "du",
                                           "la", "le", "el"}]
    return parts[-1] if parts else ""


def first_initial(s):
    parts = [p for p in re.split(r"[\s.,]+", strip_accents(s).lower()) if p]
    return parts[0][0] if parts else ""


def match_ok(query, label):
    if not label:
        return False
    if surname_key(query) != surname_key(label):
        return False
    qi, li = first_initial(query), first_initial(label)
    return not (qi and li) or qi == li


def people(row):
    """Every named rights-holder on the page, de-duplicated."""
    names = []
    for key in ('composers', 'arrangers', 'lyricists', 'translators'):
        names.extend(row.get(key) or [])
    out, seen = [], set()
    for n in names:
        n = PARENS.sub(' ', str(n))
        n = re.sub(r'\s+', ' ', n).strip(' .,;:')
        if not n or ANON.match(n):
            continue
        # A bare year is a stray template parameter, not a person.
        if re.fullmatch(r'\d{3,4}', n):
            continue
        if n.casefold() in seen:
            continue
        seen.add(n.casefold())
        out.append(n)
    return out


def main():
    src = Path(sys.argv[1] if len(sys.argv) > 1 else 'cpdl-candidates.json')
    rows = json.loads(src.read_text())
    cache = load_cache()
    canary(cache)

    cleared, held = [], []
    stats = collections.Counter()
    try:
        for i, r in enumerate(rows, 1):
            names = people(r)
            verdicts = {}
            if not names:
                # Anonymous/traditional only. CPDL is historical repertoire and
                # every kept edition has a publication year in the corpus or a
                # long-PD composer page; require a pre-1900 first publication
                # before treating anonymity as clearance.
                y = int(r['year']) if (r.get('year') or '').isdigit() else None
                if y and y < 1900:
                    r['clearance'], r['rule'] = 'cleared', 'P1'
                    r['axis2_reason'] = (f'no named rights-holder (anonymous/'
                                         f'traditional); first published {y} < 1900')
                    cleared.append(r); stats['P1'] += 1; continue
                r['clearance'], r['rule'] = 'held', None
                r['axis2_reason'] = ('no named rights-holder and no pre-1900 '
                                     'publication date to rest anonymity on')
                held.append(r); stats['held_anon'] += 1; continue

            for n in names:
                m = LIFESPAN.search(n)
                if m:
                    y = int(m.group(2))
                    verdicts[n] = {'status': 'CLEAR' if y <= CUTOFF else 'BLOCKED',
                                   'death': y, 'label': n, 'qid': 'inline'}
                    continue
                status, yr, label, qid = resolve(n, cache)
                if status == 'CLEAR' and not match_ok(n, label):
                    status, yr = 'UNKNOWN', None
                    label = f'{label} (rejected: name mismatch)'
                verdicts[n] = {'status': status, 'death': yr,
                               'label': label, 'qid': qid}

            r['people'] = names
            r['wikidata'] = verdicts
            if all(v['status'] == 'CLEAR' for v in verdicts.values()):
                r['clearance'], r['rule'] = 'cleared', 'P3'
                r['axis2_reason'] = ('EU life+70: every named rights-holder '
                                     f'died <= {CUTOFF} '
                                     + str({n: v["death"] for n, v in verdicts.items()}))
                cleared.append(r); stats['P3'] += 1
            else:
                blocked = {n: v['death'] for n, v in verdicts.items()
                           if v['status'] == 'BLOCKED'}
                unknown = [n for n, v in verdicts.items() if v['status'] == 'UNKNOWN']
                why = []
                if blocked:
                    why.append(f'died after {CUTOFF}: {blocked}')
                if unknown:
                    why.append(f'unresolvable: {unknown}')
                r['clearance'], r['rule'] = 'held', None
                r['axis2_reason'] = '; '.join(why)
                held.append(r)
                stats['held_blocked' if blocked else 'held_unknown'] += 1
            if i % 250 == 0:
                print(f'  [{i}/{len(rows)}] cleared={len(cleared)} '
                      f'held={len(held)}', flush=True)
    finally:
        save_cache(cache)

    Path('cpdl-clearance.json').write_text(
        json.dumps(cleared, indent=1, ensure_ascii=False))
    Path('cpdl-probation.json').write_text(
        json.dumps(held, indent=1, ensure_ascii=False))
    print(f'\n=== cleared {len(cleared)} · held {len(held)} (of {len(rows)}) ===')
    print('  ', dict(stats))
    print('  cleared by licence:',
          dict(collections.Counter(r['licence'] for r in cleared)))
    print('  cleared by format:',
          dict(collections.Counter(r['format'] for r in cleared)))
    top = collections.Counter(r['composer'] for r in cleared).most_common(8)
    print('  top cleared composers:', top)


if __name__ == '__main__':
    main()
