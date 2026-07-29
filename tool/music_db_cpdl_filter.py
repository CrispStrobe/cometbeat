#!/usr/bin/env python3
"""Filter the CPDL corpus to the licence-shippable EDITIONS and resolve their
symbolic files on disk.

WHY PER-EDITION. A CPDL page hosts one edition per contributor, and the licence
is declared per edition, not per page. "10 catches (Henry Purcell)" carries a
Public-Domain edition (Purcell_10Catches.mxl) AND a CPDL-licensed one
(Purc-sweet.mxl). A per-page filter would either ship the CPDL file or drop the
PD one. So the parse splits on {{CPDLno|...}} — every edition has exactly one —
and binds each block's {{Copy|...}} to the [[Media:...]] links in that block.

Block layout, verbatim from the corpus:

    *{{PostedDate|2007-10-14}} {{CPDLno|15186}} [[Media:X.pdf|{{pdf}}]] \
        [[Media:X.mxl|{{XML}}]] [[Media:X.MUS|{{mus}}]] (Finale 2002)
    {{Editor|Benoît Huwart|2007-10-14}}{{ScoreInfo|A4|6|144}}{{Copy|Public Domain}}

Each block is cut at the next "\n==" heading so a trailing edition cannot absorb
Media links from the General Information / lyrics sections below it.

SHIPPABLE licences are anchored exactly: "Creative Commons Attribution" must not
also match "Creative Commons Attribution Non-Commercial" or "... Share Alike".
CC BY-ND is deliberately NOT shippable — we convert formats, and a format
conversion is a derivative.

Filename resolution: wikitext writes underscores (Purcell_10Catches.mxl) while
the dump stores spaces ("Purcell 10Catches.mxl"), and extension case varies
(.MID/.mid, .MUS/.mus). Matching is underscore-normalised and case-folded.
"""
import collections
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = '{http://www.mediawiki.org/xml/export-0.10/}'

SHIPPABLE = re.compile(
    r'^(public domain|pd|creative commons zero|cc0|'
    r'creative commons attribution)\s*$', re.I)

CPDLNO = re.compile(r'\{\{\s*CPDLno\s*\|\s*(\d+)', re.I)
COPY = re.compile(r'\{\{\s*(?:Copy|Copyright|License)\s*\|\s*([^}|\n]+)', re.I)
MEDIA = re.compile(r'\[\[\s*Media\s*:\s*([^|\]\n]+)', re.I)
EDITOR = re.compile(r'\{\{\s*Editor\s*\|\s*([^}|\n]+)', re.I)
# Every rights-bearing layer, not just the composer. An arrangement is
# separately protected (§3 UrhG, life+70 of the arranger) and so is a text or a
# translation — the Internet Jukebox songbook was blocked by exactly this, where
# the "arrangers" turned out to be translators of the English words.
#
# ⚠️ These templates are MULTI-VALUE with a LEADING COUNT:
#     {{Lyricist|2|Sabine Baring-Gould|James Montgomery}}
# (238 Lyricist, 59 Composer, 2 Arranger uses). A naive
# `\{\{Lyricist\|([^}|\n]+)` captures "2" as the name AND silently drops both
# real lyricists — and dropping a rights-holder is the direction that wrongly
# CLEARS. So parse the whole template body, strip a leading integer count, and
# drop named parameters (connective=, composertype=, sort=).
ROLE_TPL = re.compile(
    r'\{\{\s*(Composer|Arranger|Lyricist|Translator)\s*\|([^}]*)\}\}', re.I)
_COUNT = re.compile(r'^\d+$')


def role_names(txt, role):
    """All personal names given for `role`, handling the leading-count form."""
    out = []
    for r, body in ROLE_TPL.findall(txt):
        if r.casefold() != role.casefold():
            continue
        parts = [p.strip() for p in body.split('|')]
        parts = [p for p in parts if p and '=' not in p]
        if parts and _COUNT.match(parts[0]):
            parts = parts[1:]          # leading count, not a name
        out.extend(parts)
    return out
TITLE = re.compile(r"\{\{\s*Title\s*\|\s*''?([^}|\n]+?)''?\s*\}\}", re.I)
PUB = re.compile(r'\{\{\s*Pub\s*\|\s*\d+\s*\|\s*(\d{3,4})', re.I)
VOICING = re.compile(r'\{\{\s*Voicing\s*\|\s*([^}|\n]+)\|\s*([^}|\n]+)', re.I)
LANG = re.compile(r'\{\{\s*Language\s*\|\s*([^}|\n]+)', re.I)

SYMBOLIC = {'mxl': 'mxl', 'musicxml': 'musicxml', 'xml': 'musicxml',
            'mscz': 'mscz', 'ly': 'ly', 'mid': 'midi', 'midi': 'midi'}
PRIMARY = ['mxl', 'musicxml', 'mscz', 'ly', 'midi']   # preference order


def norm(name):
    return name.replace('_', ' ').strip().casefold()


def build_disk_index(root):
    """{normalised filename -> path relative to the cpdl dir}."""
    idx = {}
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            full = os.path.join(dirpath, f)
            idx.setdefault(norm(f), full)
    return idx


def parse_page(txt):
    """Yield one dict per edition."""
    parts = re.split(r'(?=\{\{\s*CPDLno\s*\|)', txt, flags=re.I)
    if len(parts) < 2:
        return
    for chunk in parts[1:]:
        cut = re.search(r'\n==', chunk)
        block = chunk[:cut.start()] if cut else chunk
        lic = COPY.search(block)
        no = CPDLNO.search(block)
        ed = EDITOR.search(block)
        yield {
            'cpdlno': no.group(1) if no else None,
            'licence': lic.group(1).strip() if lic else None,
            'editor': ed.group(1).strip() if ed else None,
            'media': [m.strip() for m in MEDIA.findall(block)],
        }


def main():
    xml_path, files_root, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    print('indexing extracted files...', flush=True)
    disk = build_disk_index(files_root)
    print(f'  {len(disk)} files on disk')

    rows = []
    stats = collections.Counter()
    lic_hist = collections.Counter()
    fmt_hist = collections.Counter()

    for ev, el in ET.iterparse(xml_path, events=('end',)):
        if el.tag != NS + 'page':
            continue
        if el.findtext(NS + 'ns') != '0':
            el.clear()
            continue
        txt = el.findtext(f'{NS}revision/{NS}text') or ''
        title = el.findtext(NS + 'title') or ''
        composers = role_names(txt, 'Composer')
        ttl = TITLE.search(txt)
        pub = PUB.search(txt)
        voi = VOICING.search(txt)
        lang = LANG.search(txt)

        for e in parse_page(txt):
            stats['editions'] += 1
            if not e['licence']:
                stats['no_licence'] += 1
                continue
            lic_hist[e['licence']] += 1
            if not SHIPPABLE.match(e['licence']):
                stats['licence_excluded'] += 1
                continue
            stats['licence_ok'] += 1

            files = {}
            for m in e['media']:
                ext = m.rsplit('.', 1)[-1].casefold() if '.' in m else ''
                fmt = SYMBOLIC.get(ext)
                if not fmt:
                    continue
                path = disk.get(norm(m))
                if not path:
                    stats['file_missing_on_disk'] += 1
                    continue
                files.setdefault(fmt, os.path.relpath(path, files_root))
            if not files:
                stats['no_symbolic_file'] += 1
                continue
            stats['KEPT'] += 1
            for f in files:
                fmt_hist[f] += 1
            primary = next((f for f in PRIMARY if f in files), None)
            rows.append({
                'id': f"cpdl-{e['cpdlno']}",
                'cpdlno': e['cpdlno'],
                'page': title,
                'title': (ttl.group(1).strip() if ttl else title),
                'composer': composers[0] if composers else None,
                'composers': sorted(set(composers)),
                'arrangers': sorted(set(role_names(txt, 'Arranger'))),
                'lyricists': sorted(set(role_names(txt, 'Lyricist'))),
                'translators': sorted(set(role_names(txt, 'Translator'))),
                'editor': e['editor'],
                'licence': e['licence'],
                'year': pub.group(1) if pub else None,
                'voicing': (f'{voi.group(1)} / {voi.group(2)}'.strip()
                            if voi else None),
                'language': lang.group(1).strip() if lang else None,
                'format': primary,
                'files': files,
                'source_url': ('https://www.cpdl.org/wiki/index.php/'
                               + title.replace(' ', '_')),
            })
        el.clear()

    with open(out_path, 'w') as fh:
        json.dump(rows, fh, indent=1, ensure_ascii=False)

    print(f'\n=== editions parsed: {stats["editions"]} ===')
    for k in ('no_licence', 'licence_excluded', 'licence_ok',
              'no_symbolic_file', 'file_missing_on_disk', 'KEPT'):
        print(f'  {stats[k]:7}  {k}')
    print(f'\nwrote {len(rows)} shippable editions -> {out_path}')
    print('  primary formats:', dict(collections.Counter(
        r['format'] for r in rows)))
    print('  files by format:', dict(fmt_hist))
    print('\n  licences seen on parsed editions (top 12):')
    for k, v in lic_hist.most_common(12):
        mark = 'SHIP' if SHIPPABLE.match(k) else '    '
        print(f'    {mark} {v:6}  {k[:52]}')
    print('\n  top composers in the kept set:')
    for k, v in collections.Counter(
            r['composer'] for r in rows).most_common(10):
        print(f'    {v:5}  {k}')


if __name__ == '__main__':
    main()
