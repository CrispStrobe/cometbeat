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
        # NOT `\bnigg\w+`: "niggard" / "niggardly" is an ordinary English word
        # meaning miserly, from Old Norse, etymologically unrelated to the slur.
        # The broad prefix held Elgar's "The River" — "On thy narrowed, niggard
        # strand" — which is a false accusation against the text, not caution.
        r"\bnigger\w*", r"\bnigga\b", r"\bniggas\b", r"\bniggah\w*",
        r"\bdarke?y\b", r"\bdarkies\b", r"\bpickaninn\w+",
        r"\bsambo\b", r"\bgypsy\b", r"\bgypsies\b", r"\bsquaw\w*",
        r"\bhalf-?breed\b", r"\bhottentot\w*",
    ],
    # The corpus is not German and English. 8,181 Polish rows, plus Italian,
    # French, Dutch and Czech — a two-language list was never going to be an
    # answer to "is it clean". Cygan/cigány/cikán are the exact cognates of
    # Zigeuner and belong at the same tier; the classical-repertoire question
    # they raise is handled by the exemption ledger, not by a weaker pattern.
    "other": [
        r"\bcygan\w*", r"\bcyg[aá]n\w*", r"\bcik[aá]n\w*", r"\bcig[aá]ny\w*",
        r"\bn[eè]gre\w*", r"\bn[eè]gresse\w*", r"\bnegerin\w*",
        r"\bmoricaud\w*", r"\bnegrillon\w*",
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
    # A marching song is not identifiable by vocabulary, so the only reliable
    # handle is WHO WROTE IT. These are the house composers of the NS song
    # apparatus — Wehrmacht marches, HJ and BDM songbooks. Norbert Schultze is
    # included knowingly: he also wrote Lili Marleen, which is not NS material,
    # so anything of his that trips this needs reading before it is held.
    r"\bhans baumann\b", r"\bheinrich spitta\b", r"\bgeorg blumensaat\b",
    r"\bnorbert schultze\b", r"\bhans-?otto borgmann\b",
    r"\bes ist so sch[öo]n soldat zu sein\b", r"\bpanzer rollen in afrika\b",
    r"\bwir fahren gegen eng[e]?land\b", r"\bdie braune kompanie\b",
    r"\bhitlerjugend\b", r"\bhitler-?jugend\b", r"\bbund deutscher m[äa]del\b",
    r"\bblut und boden\b", r"\bheiliges vaterland\b(?=.*193[3-9]|.*194[0-5])",
    r"\bnun lasst die fahnen fliegen\b", r"\bes pfeift von allen d[äa]chern\b",
    r"\bvorw[äa]rts, vorw[äa]rts, schmettern die hellen fanfaren\b",
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


# ⚠️ SYLLABIFICATION CUTS BOTH WAYS, and the second edge is the dangerous one.
# A vocal score stores lyrics one syllable per note: "dark ey", "Mas sa",
# "Zi geu ner". Earlier this produced false POSITIVES (a fragment matching a
# short pattern). It also produces false NEGATIVES, which no amount of
# reviewing the hit list can reveal — "Carry Me Back to Old Virginny" sailed
# through a full-corpus scan carrying "this old dark ey's heart" because \b
# split the word in two.
#
# So every body is ALSO searched with whitespace and hyphens removed, against
# bare substrings (no \b — the anchors are meaningless once words are joined).
# That over-matches by design; the hits land in a report a human reads, which
# is the same bargain the review tier makes.
# --- lyric reconstruction: the single most important part of this file --------
#
# A vocal score does not store "darkey"; it stores <text>dark</text> in one
# <lyric> element and <text>ey's</text> in the NEXT ONE, roughly 200 characters
# of XML markup apart. So no pattern with a \b anchor — and no amount of
# whitespace collapsing — can see the word. A full-corpus scan therefore passed
# "Carry Me Back to Old Virginny" as clean while it carried "this old dark ey's
# heart", and would have passed anything else spelled across two notes.
#
# Reconstructing words is what makes the scan meaningful on vocal music, which
# is most of this corpus. MusicXML/MuseScore state it exactly via <syllabic>
# (begin/middle continue a word, end/single close it), so that path is precise.
# The others mark continuation in the text itself: LilyPond `dark -- ey`, ABC
# `w:dark-ey`, kern `dark-` in a **text spine.
# `\b` is NOT enough after "lyric": it also matches `<lyric-font …/>` and
# `<lyric-language …/>` in the MusicXML <defaults> block, which then open a
# bogus element that runs to the next real </lyric> and swallow font metadata
# into the sung text. Require the next char to end the tag name.
_LYRIC_BLOCK = re.compile(
    r"<(?:lyric|Lyrics)(?=[\s>])([^>]*)>(.*?)</(?:lyric|Lyrics)>", re.S | re.I)
# The verse identifier is a TOKEN, not a number — MusicXML allows any value and
# real exporters write `number="part1verse1"`. Demanding \d+ meant every verse
# fell into one bucket and four stanzas interleaved into gibberish.
_VERSE = re.compile(r'(?:number|no)\s*=\s*"([^"]+)"', re.I)
# MuseScore: `<Lyrics><no>1</no><syllabic>…` — the verse is a child element, so
# an attribute-only regex put every stanza in one bucket and welded them.
# NB 0-BASED: MuseScore omits <no> for verse 1 and writes <no>1</no> for
# verse 2, so an absent verse must default to "0" or the two collide.
_VERSE_EL = re.compile(r"<no>\s*(\d+)\s*</no>", re.I)
_NOTE_BLOCK = re.compile(r"<(?:note|Chord|Rest)\b.*?</(?:note|Chord|Rest)>",
                         re.S | re.I)
_VOICE = re.compile(r"<voice>\s*(\d+)\s*</voice>", re.I)


def _join_syllables(blocks):
    """Rejoin one voice/verse stream's syllables into words."""
    words, cur = [], ""
    for b in blocks:
        syl = (_SYLLABIC.search(b).group(1).lower()
               if _SYLLABIC.search(b) else "single")
        txt = "".join(_TEXTEL.findall(b))
        for k, v in _ENT.items():
            txt = txt.replace(k, v)
        txt = txt.strip()
        if not txt:
            continue
        cur += txt
        if syl in ("end", "single"):
            words.append(cur)
            cur = ""
    if cur:
        words.append(cur)
    return " ".join(words)
_SYLLABIC = re.compile(r"<syllabic>\s*(\w+)\s*</syllabic>", re.I)
_TEXTEL = re.compile(r"<text>(.*?)</text>", re.S | re.I)
_ENT = {"&apos;": "'", "&amp;": "&", "&quot;": '"', "&lt;": "<", "&gt;": ">"}


def _language_or_empty(text):
    """Text if it plausibly contains WORDS, else ''.

    Every extraction path can yield structure that survives as whitespace or
    punctuation — empty syllable slots in a string-quartet .mscx came back as
    6,381 characters of spaces and were counted as lyrics. Require a handful of
    real alphabetic runs before calling something sung text.
    """
    if not text:
        return ""
    runs = re.findall(r"[^\W\d_]{2,}", text, re.UNICODE)
    letters = sum(len(r) for r in runs)
    if len(runs) < 3 or letters < 12 or letters / len(text) < 0.25:
        return ""
    return text


def lyric_words(raw):
    """The sung text with syllables rejoined into words, or '' if none found.

    A thin gate over the per-format extraction. Gating each `return` inside the
    implementation was tried and failed: the recursive staff/voice branches join
    N empty strings with a space, so a string quartet produced 6,760 characters
    of pure whitespace that passed for lyrics. One boundary, one check.
    """
    return _language_or_empty(_lyric_words_impl(raw))


def _lyric_words_impl(raw):
    # Group by VOICE and verse, not document order. An SATB psalm setting is
    # commonly ONE <part> containing four <voice>s, so neither document order nor
    # a part split helps: grouping by verse alone welds syllables across voices
    # into gibberish. Stephenson's "Attend, O Earth" reconstructed as "my most
    # the reare Son, liLord venge they this mits" and coined the non-word
    # "negreheir", which then matched as a French slur. Words only mean anything
    # when they come from one voice at a time.
    # MuseScore states voices STRUCTURALLY — `<Staff id=..>` per singer and
    # `<voice>…</voice>` as a container — where MusicXML uses a per-note leaf
    # `<voice>1</voice>`. Both have to be handled or an SATB .mscz still welds
    # four singers into one stream. Recurse into each structural segment first.
    if re.search(r"<Staff\b[^>]*>", raw):
        segs = re.split(r"<Staff\b[^>]*>", raw)
        if len(segs) > 1:
            return " ".join(_lyric_words_impl(s) for s in segs if s)
    if re.search(r"<voice>\s*<", raw):
        segs = re.split(r"<voice>", raw)
        if len(segs) > 1:
            return " ".join(_lyric_words_impl(s) for s in segs if s)

    notes = _NOTE_BLOCK.findall(raw)
    if notes and any("<lyric" in n.lower() for n in notes):
        streams = defaultdict(list)
        for n in notes:
            if "<lyric" not in n.lower():
                continue
            v = _VOICE.search(n)
            voice = v.group(1) if v else "1"
            for attrs, b in _LYRIC_BLOCK.findall(n):
                num = _VERSE.search(attrs) or _VERSE_EL.search(b)
                streams[(voice, num.group(1) if num else "0")].append(b)
        out = []
        for key in sorted(streams):
            out.append(_join_syllables(streams[key]))
        return (" ".join(out))

    blocks = _LYRIC_BLOCK.findall(raw)
    if blocks:
        # Verses are INTERLEAVED in the file — verse 1 and verse 2 of the same
        # note sit next to each other — so reconstructing in document order
        # welds syllables from different verses together ("BeauSounds tiof ful").
        # Grouping by the verse number keeps each stanza's words intact, which
        # both reduces garbage and stops a spurious cross-verse join from
        # inventing a word nobody sang.
        verses = defaultdict(list)
        for attrs, b in blocks:
            v = _VERSE.search(attrs) or _VERSE_EL.search(b)
            verses[v.group(1) if v else "0"].append(b)
        out = []
        for v in sorted(verses):
            cur = ""
            for b in verses[v]:
                syl = (_SYLLABIC.search(b).group(1).lower()
                       if _SYLLABIC.search(b) else "single")
                txt = "".join(_TEXTEL.findall(b))
                for k, val in _ENT.items():
                    txt = txt.replace(k, val)
                txt = txt.strip()
                if not txt:
                    continue
                cur += txt
                if syl in ("end", "single"):
                    out.append(cur)
                    cur = ""
            if cur:
                out.append(cur)
        return (" ".join(out))
    # ⚠️ The fallback used to return the WHOLE raw document whenever no lyric
    # element was found. For an XML score that means the markup itself became
    # the "sung text" — the OpenScore Lieder `.mscx` above has 166 <Lyrics>
    # elements yet came back as 139 KB starting `<?xml version=`, because the
    # pre-<Staff> header segment has no lyrics and dumped itself. For a MIDI it
    # means binary soup, which is how a 1915 Sousa march once matched "WOG".
    # So: an XML document with no lyric elements has no sung text. Say so.
    # GABC (Gregorian chant) interleaves text with neumes: the sung syllables are
    # OUTSIDE the parentheses — `AL(dc~)le(c/e'gF'EC'd)lú(dc/fg)` is "Alleluia".
    # 18,684 GregoBase rows are chant, so without this the largest text-bearing
    # source in the corpus reads as unsearchable notation.
    if re.search(r"^\s*name:", raw, re.M) or "%%\n" in raw[:2000]:
        body = raw.split("%%", 1)[1] if "%%" in raw else raw
        body = re.sub(r"\([^)]*\)", "", body)      # drop neume groups
        body = re.sub(r"<[^>]*>", "", body)        # gabc inline markup (<i>ij.</i>)
        body = re.sub(r"[{}<>*|~]", "", body)
        return (re.sub(r"\s+", " ", body).strip())

    if "<" in raw[:400] and re.search(r"<[a-zA-Z?][^>]*>", raw[:4000]):
        return ""

    # MIDI: only `FF 05` LYRIC events. `FF 01` is generic text and carries track
    # names and "creator: GNU LilyPond 2.18.2", which is metadata, not something
    # anyone sings — counting it made every instrumental Mutopia MIDI look like it
    # had words.
    if raw[:4] == "MThd":
        out = [raw[m.end():m.end() + ord(m.group(1))]
               for m in re.finditer(r"\xff\x05([\x00-\x7f])", raw)]
        return (re.sub(r"\s+", " ", " ".join(out)).strip())

    # Humdrum kern: the sung text is a `**text` SPINE, addressed by column. Any
    # other spine is notation. Returning the whole file made Chopin's first
    # editions report 23,853 characters of "lyrics" — they are solo piano.
    if "**kern" in raw[:4000] or raw.lstrip().startswith("!!!"):
        cols = None
        percol = defaultdict(list)
        for line in raw.splitlines():
            if line.startswith("!") or not line.strip():
                continue
            f = line.split("\t")
            if line.startswith("**"):
                cols = [i for i, x in enumerate(f) if x.strip() == "**text"]
                continue
            if not cols:
                continue
            for i in cols:
                if i >= len(f):
                    continue
                tok = f[i]
                if tok[:1] in (".", "*", "=", "!", "-") or not tok.strip():
                    continue
                percol[i].append(tok)
        joined = "  ".join(" ".join(percol[i]) for i in sorted(percol))
        joined = re.sub(r"(\w)-\s+(\w)", r"\1\2", joined)   # syllable continuation
        return (re.sub(r"\s+", " ", joined).strip())

    # LilyPond: only \addlyrics / \lyricmode bodies. The rest is notation, and a
    # whole-file dump also swept up the engraver's header comments.
    if "\\relative" in raw or "\\version" in raw or "\\score" in raw:
        out = []
        for m in re.finditer(r"\\(?:addlyrics|lyricmode|lyricsto)\b", raw):
            i = raw.find("{", m.end())
            if i < 0:
                continue
            depth, j = 0, i
            while j < len(raw):
                if raw[j] == "{":
                    depth += 1
                elif raw[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            body = raw[i + 1:j]
            body = re.sub(r"\\[a-zA-Z]+", " ", body)     # \set stanza etc.
            body = re.sub(r"\b(?:stanza|set)\b\s*=?\s*\"?[^\"\s]*\"?",
                          " ", body)                    # the \set stanza residue
            body = re.sub(r"\s*--\s*", "", body)         # syllable joins
            out.append(re.sub(r"[{}#\"]", " ", body))
        return (re.sub(r"\s+", " ", " ".join(out)).strip())

    # ABC: the `w:` / `W:` lyric lines only.
    if re.search(r"^X:", raw, re.M):
        out = [m.group(1) for m in re.finditer(r"^[wW]:(.*)$", raw, re.M)]
        joined = " ".join(out)
        joined = re.sub(r"(\w)-\s*", r"\1", joined)       # ABC syllable hyphens
        return (re.sub(r"[\s*|~]+", " ", joined).strip())

    return ""


COLLAPSED = [
    "nigger", "nigga", "darkey", "darky", "darkie", "pickaninn", "sambo",
    "hottentot", "gypsy", "gypsies", "squaw",
    "neger", "zigeuner", "mohrenkopf", "kaffern",
    "cygan", "cikan", "cigany", "negre", "negresse",
    "horstwessel", "hakenkreuz", "siegheil", "judenblut",
    "hitlerjugend", "blutundboden", "panzerlied",
]
_COLLAPSE_RX = re.compile("|".join(re.escape(t) for t in COLLAPSED), re.I)
_WS = re.compile(r"[\s­\-]+")


def collapsed_hit(hay):
    """Match against a de-syllabified copy of the text. Returns the term or None."""
    m = _COLLAPSE_RX.search(_WS.sub("", hay))
    return m.group(0) if m else None


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
    # Three haystacks, in order of precision: the raw file, the reconstructed
    # sung text (real words, so \b anchors mean something), and a crude
    # whitespace-collapsed copy as a last wide net. The third over-matches
    # across word boundaries by design — "Pois ambos nós" reads as `sambo`,
    # "hath done great" as `negre` — which is why it must reach a human rather
    # than be applied.
    hay = f"{title}\n{body}"
    words = lyric_words(body)
    if _HOLD_RX.search(hay) or _HOLD_RX.search(words):
        return "hold", row[0]
    if collapsed_hit(hay) or _REVIEW_RX.search(hay) or _REVIEW_RX.search(words):
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
        words = lyric_words(body)
        pats = (slur + ns) if tier == "hold" else review
        for rx, kind in pats:
            m = rx.search(hay) or rx.search(words)
            if m:
                hits[tier].append({
                    "id": e.get("id"), "title": title, "source": e.get("source"),
                    "term": m.group(0)[:40], "kind": kind,
                    "where": "title" if rx.search(title) else "lyrics",
                    "path": p})
                stats[f"{tier}/{kind}"] += 1
                break
        else:
            # Flagged only by the crude whitespace-collapsed net. Record it with
            # that provenance rather than dropping it — a row that trips a
            # matcher and then vanishes from the report is the worst outcome.
            c = collapsed_hit(hay)
            hits["review"].append({
                "id": e.get("id"), "title": title, "source": e.get("source"),
                "term": c or "(unattributed)", "kind": "collapsed-net",
                "where": "whitespace-collapsed text — expect false positives",
                "path": p})
            stats["review/collapsed-net"] += 1

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
