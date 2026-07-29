#!/usr/bin/env python3
"""Turn the CLEARED CPDL editions into db.json rows.

Runs after: cpdl_filter.py (axis 1, per edition) -> parse sweep (crisp_notation)
-> cpdl_promote.py (axis 2, life+70 over composer/arranger/lyricist/translator).

TIERING. Unlike every previous source this one is genuinely mixed:
  * "Public Domain" / "CC0"                 -> Tier A, attribution None
  * "Creative Commons Attribution" (CC BY)  -> Tier B, attribution REQUIRED
The ship gate is `tier A ∨ ((B ∨ C) ∧ attribution != null)`, so a CC BY row with
a null attribution would be silently dropped from the catalog. The attribution
is the EDITOR — they made the engraving that the licence covers, not the
long-dead composer.

Only rows whose parse-sweep status is "ok" are emitted: these are third-party
engravings of wildly varying vintage, and a file that does not read is not
shippable content regardless of its licence.
"""
import collections
import hashlib
import json
import re
import sys
from pathlib import Path

HARVEST = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
FILES_ROOT = Path(sys.argv[2] if len(sys.argv) > 2 else 'files')
DEST_PREFIX = sys.argv[3] if len(sys.argv) > 3 else 'cpdl/files'

SOURCE = 'CPDL (Choral Public Domain Library)'
TIER_A = re.compile(r'^(public domain|pd|creative commons zero|cc0)\s*$', re.I)


def slug(s):
    return re.sub(r'-+', '-', re.sub(r'[^a-z0-9]+', '-', (s or '').lower())).strip('-')[:70]


def main():
    cleared = json.loads((HARVEST / 'cpdl-clearance.json').read_text())
    report_path = HARVEST / 'cpdl-parse-report.json'
    parsed = {}
    if report_path.exists():
        parsed = {r['id']: r for r in json.loads(report_path.read_text())['rows']}
    else:
        print('!! no parse report — emitting without the parse gate')

    rows, skipped = [], collections.Counter()
    for e in cleared:
        st = parsed.get(e['id'])
        if parsed and (not st or st.get('status') != 'ok'):
            skipped[st.get('status') if st else 'not_in_report'] += 1
            continue
        primary = e.get('format')
        rel = (e.get('files') or {}).get(primary)
        if not rel:
            skipped['no_primary_file'] += 1
            continue
        src = FILES_ROOT / rel
        if not src.exists():
            skipped['missing_on_disk'] += 1
            continue

        is_a = bool(TIER_A.match(e['licence']))
        attribution = None if is_a else (e.get('editor') or None)
        if not is_a and not attribution:
            # Tier B with no attributable editor would fail the ship gate
            # silently; hold it rather than emit an unshippable row.
            skipped['cc_by_without_editor'] += 1
            continue

        files = {f: f'{DEST_PREFIX}/{p}' for f, p in (e.get('files') or {}).items()}
        people = e.get('people') or []
        rows.append({
            'id': e['id'],
            'title': e.get('title'),
            'author': '; '.join(e.get('composers') or []) or e.get('composer'),
            'poet': '; '.join(e.get('lyricists') or []) or None,
            'year': e.get('year'),
            'instrument': None,
            'instruments': None,
            'editor': e.get('editor'),
            'ensemble': True,
            'licence': e['licence'],
            'source': SOURCE,
            'source_url': e.get('source_url'),
            'attribution': attribution,
            'format': primary,
            'rights_status': 'PD' if is_a else 'CC_BY_ORIGINAL',
            'rights_method': (
                f"axis1=per-EDITION {{{{Copy|{e['licence']}}}}} declared by the "
                f"engraver on CPDL (licence is per edition, not per page); "
                f"axis2={e['rule']}: {e['axis2_reason']}"
            )[:900],
            'path': f'{DEST_PREFIX}/{rel}',
            'kind': 'score',
            'sha256': hashlib.sha256(src.read_bytes()).hexdigest(),
            'bytes': src.stat().st_size,
            'files_extra': files,
            'voicing': e.get('voicing'),
            'language': e.get('language'),
            'people_checked': people,
        })

    out = HARVEST / 'cpdl-manifest.json'
    out.write_text(json.dumps(rows, indent=1, ensure_ascii=False))
    print(f'cpdl-manifest.json: {len(rows)} rows')
    print('  skipped:', dict(skipped))
    print('  by tier:', dict(collections.Counter(
        'A' if TIER_A.match(r['licence']) else 'B' for r in rows)))
    print('  by format:', dict(collections.Counter(r['format'] for r in rows)))
    print('  top composers:', collections.Counter(
        r['author'] for r in rows).most_common(8))


if __name__ == '__main__':
    main()
