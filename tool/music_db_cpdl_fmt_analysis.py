#!/usr/bin/env python3
"""How much of the shippable CPDL subset actually needs format conversion?

Answers the practical question before any converter is written: we already read
mxl/musicxml/ly/mscz/mid through crisp_notation, so conversion only matters for
pages whose ONLY symbolic file is something else. Editors usually upload a
proprietary source AND an .mxl/.mid export, which would make the proprietary
files redundant rather than a gap.
"""
import collections
import re
import sys
import xml.etree.ElementTree as ET

NS = '{http://www.mediawiki.org/xml/export-0.10/}'
SHIP = re.compile(
    r'^(public domain|pd|creative commons zero|creative commons attribution)\s*$',
    re.I)
LICRE = re.compile(r'\{\{\s*(?:Copy|Copyright|License)\s*\|\s*([^}|\n]+)', re.I)
EXT = re.compile(
    r'\.(mxl|musicxml|ly|mscz|mid|midi|mus|sib|nwc|cap|capx|ove|abc|pdf)\b', re.I)

NATIVE = {'mxl', 'musicxml', 'ly', 'mscz', 'mid', 'midi'}  # crisp_notation reads
CONVERTIBLE = {'cap', 'capx', 'ove', 'abc'}                # MuseScore CLI imports
OPAQUE = {'mus', 'sib', 'nwc'}                             # no open converter

path = sys.argv[1] if len(sys.argv) > 1 else 'cpdlorg_wiki-20201112-current.xml'
tot = native = conv_only = opaque_only = nothing = 0
combo = collections.Counter()
native_fmt = collections.Counter()

for ev, el in ET.iterparse(path, events=('end',)):
    if el.tag != NS + 'page':
        continue
    if el.findtext(NS + 'ns') == '0':
        txt = el.findtext(f'{NS}revision/{NS}text') or ''
        if any(SHIP.match(l.strip()) for l in LICRE.findall(txt)):
            tot += 1
            f = {x.lower() for x in EXT.findall(txt)}
            if f & NATIVE:
                native += 1
                for x in f & NATIVE:
                    native_fmt[x] += 1
            elif f & CONVERTIBLE:
                conv_only += 1
                combo[tuple(sorted(f & CONVERTIBLE))] += 1
            elif f & OPAQUE:
                opaque_only += 1
                combo[tuple(sorted(f & OPAQUE))] += 1
            else:
                nothing += 1
    el.clear()

print(f'shippable-licence pages:              {tot}')
print(f'  already readable, NO conversion:    {native}  ({100*native/max(tot,1):.1f}%)')
print(f'  need conversion (MuseScore CLI):    {conv_only}')
print(f'  opaque (.mus/.sib/.nwc only):       {opaque_only}')
print(f'  no symbolic file at all (PDF only): {nothing}')
print(f'  native formats present: {dict(native_fmt)}')
print(f'  non-native breakdown:   {dict(combo)}')
