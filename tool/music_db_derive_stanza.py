#!/usr/bin/env python3
"""Derive a single-stanza edition of a MusicXML score by dropping lyric verses.

Written for one specific, maintainer-approved case: the SATB "Das Lied der
Deutschen" carries stanzas 1–3, and only the third is wanted. Holding the file
lost the corpus's only FOUR-VOICE setting (E major, 4/2) — the surviving
stanza-3 edition is three parts in D — so the music is worth keeping even though
that particular text is not.

⚠️ THIS IS NOT THE MELODY-STRIP THAT WAS DECLINED FOR THE JUKEBOX ITEMS, and the
difference is the whole reason it is allowed here. There, removing an
accompaniment meant asserting our own public-domain call on a melody that sat
under a publisher's rights statement. Here both layers are unambiguously PD —
Haydn d.1809, Hoffmann von Fallersleben d.1874 — so this is an editorial choice
about which verse to print, with no rights question attached.

The MUSIC is untouched: only `<lyric>` elements are removed, and the kept verse
is renumbered to 1 so it renders as the only stanza.
"""
import argparse
import re
import zipfile


def derive(src, dst, keep, title=None):
    zin = zipfile.ZipFile(src)
    score = [n for n in zin.namelist()
             if n.endswith(".xml") and "META-INF" not in n][0]
    xml = zin.read(score).decode("utf-8")

    dropped = [0]

    def strip(m):
        num = re.search(r'number="([^"]+)"', m.group(1))
        n = num.group(1) if num else None
        if n != keep:
            dropped[0] += 1
            return ""            # not our verse (or unnumbered stray)
        # Renumber the kept verse to 1 so it prints as the only stanza.
        attrs = re.sub(r'number="[^"]+"', 'number="1"', m.group(1))
        body = m.group(2)
        # Drop the printed stanza marker ("3." glued to the first syllable).
        body = re.sub(r"<text>\s*%s\.\s*" % re.escape(keep), "<text>", body, 1)
        return f"<lyric{attrs}>{body}</lyric>"

    # ⚠️ `<lyric\b` ALSO MATCHES `<lyric-font .../>` in the <defaults> block —
    # the same trap already fixed once in music_db_content_screen.py and
    # reintroduced here. Left unguarded it opens a bogus element that runs to the
    # next real </lyric>, deleting `</defaults>`, `<credit>` and everything
    # between, and the result does not parse at all. Require the tag name to end.
    out = re.sub(r"<lyric(?=[\s>])([^>]*)>(.*?)</lyric>", strip, xml, flags=re.S)
    if title:
        out = re.sub(r"<work-title>.*?</work-title>",
                     f"<work-title>{title}</work-title>", out, 1, flags=re.S)
        out = re.sub(r"<movement-title>.*?</movement-title>",
                     f"<movement-title>{title}</movement-title>", out, 1,
                     flags=re.S)

    kept = len(re.findall(r"<lyric\b", out))
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for n in zin.namelist():
            zout.writestr(n, out.encode("utf-8") if n == score else zin.read(n))
    zin.close()
    return dropped[0], kept


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--keep", default="3", help="verse number to retain")
    ap.add_argument("--title")
    a = ap.parse_args()
    dropped, kept = derive(a.src, a.dst, a.keep, a.title)
    print(f"dropped {dropped} lyric element(s); kept {kept} (verse {a.keep})")


if __name__ == "__main__":
    main()
