"""Differential oracle: does a THIRD PARTY read our output the way we do?

A round trip only ever proves self-consistency. A writer and a reader that share
the same misconception round-trip perfectly and are both wrong, and no amount of
chaining or permuting our own codecs can see it — that is the single class this
exists to catch.

The shared currency is sounding pitch+onset+duration, which every one of these
tools can express: we emit our own reference from `scoreToMidi`, and ask each
oracle to render the SAME score from the format under test.

  format      oracle              path
  lilypond    LilyPond 2.24       .ly  -> midi   (the reference implementation)
  musicxml    music21             .xml -> midi
  abc         music21             .abc -> midi
  kern        music21             .krn -> midi
  musicxml    verovio             .xml -> midi   (second opinion on the same file)
  mei         verovio             .mei -> midi

Disagreement is not automatically our bug — these tools differ from each other
too — so the report keeps the note lists and leaves the judgement to a human.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def midi_notes(path):
    """(onset_quarters, midi_pitch, duration_quarters) from a MIDI file."""
    import music21
    s = music21.converter.parse(str(path))
    out = []
    out.extend(_events(s))
    out.sort()
    return out


def _events(stream):
    """(onset, midi, duration) per sounding pitch.

    `.pitches` for everything, never `.pitch`: an Unpitched (percussion) note
    has no `.pitch` at all and raises, which killed the first run on a corpus
    file with a drum staff.
    """
    out = []
    for n in stream.flatten().notes:
        for p in getattr(n, "pitches", ()):
            out.append((round(float(n.offset), 4), p.midi,
                        round(float(n.quarterLength), 4)))
    return out


def via_lilypond(ly_text, workdir):
    src = workdir / "a.ly"
    # LilyPond only emits MIDI when the score asks for it.
    text = ly_text
    if "\\midi" not in text:
        text = text.replace("\\layout { }", "\\layout { }\n  \\midi { }", 1)
        if "\\midi" not in text:
            text = text.rstrip().rstrip("}") + "\n  \\midi { }\n}\n"
    src.write_text(text)
    r = subprocess.run(["lilypond", "-dno-point-and-click", "-o", str(workdir / "a"),
                        str(src)], capture_output=True, timeout=120)
    mid = workdir / "a.midi"
    if not mid.exists():
        return None, (r.stderr.decode()[-300:] or "no midi produced")
    return midi_notes(mid), None


def via_music21(text, suffix, workdir):
    import music21
    src = workdir / f"a{suffix}"
    src.write_text(text)
    try:
        s = music21.converter.parse(str(src))
    except Exception as e:  # noqa: BLE001 - the oracle failing IS a result
        return None, f"music21: {type(e).__name__}: {e}"[:300]
    out = _events(s)
    out.sort()
    return out, None


VEROVIO_CHILD = r'''
import sys, verovio, json
text = open(sys.argv[1]).read()
tk = verovio.toolkit()
tk.setInputFrom(sys.argv[3])
if not tk.loadData(text):
    print("LOADFAIL"); sys.exit(0)
print("OK" if tk.renderToMIDIFile(sys.argv[2]) else "RENDERFAIL")
'''


def via_verovio(text, workdir, fmt):
    """Run verovio in a CHILD process.

    It segfaulted the whole run on a real corpus file, taking every result with
    it. An oracle that can crash must not be able to end the experiment — and a
    crash is itself a finding worth recording rather than losing.
    """
    src = workdir / "v_in"
    src.write_text(text)
    child = workdir / "child.py"
    child.write_text(VEROVIO_CHILD)
    mid = workdir / "v.mid"
    try:
        r = subprocess.run([sys.executable, str(child), str(src), str(mid), fmt],
                           capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return None, "verovio: timed out"
    if r.returncode != 0:
        return None, f"verovio: CRASHED (signal/exit {r.returncode})"
    tag = r.stdout.decode().strip().splitlines()[-1] if r.stdout else "?"
    if tag != "OK" or not mid.exists():
        return None, f"verovio: {tag}"
    return midi_notes(mid), None


def compare(ours, theirs):
    """Pitch multiset first — the least contentious comparison there is."""
    a = sorted(p for _, p, _ in ours)
    b = sorted(p for _, p, _ in theirs)
    if a == b:
        return None
    i = 0
    while i < min(len(a), len(b)) and a[i] == b[i]:
        i += 1
    return f"{len(a)} vs {len(b)} notes; first pitch diff at {i}: " \
           f"{a[i] if i < len(a) else '-'} vs {b[i] if i < len(b) else '-'}"


def main():
    """Compare the oracles against EACH OTHER, never against our own MIDI.

    The first version of this used `scoreToMidi` as the reference and every cell
    scored badly on the same files — which is the signature of a bad REFERENCE,
    not of six independently broken writers. It was: our own MIDI round trip is
    not note-preserving (324 -> 349 notes on one corpus file), so each cell was
    measuring our MIDI behaviour as much as the format under test.

    So: for one source score we hand the SAME music to several independent
    readers, each via a different one of our writers, and require THEM to agree
    with each other. Our MIDI never enters it. A format that disagrees with the
    majority is one our writer got wrong; when the oracles disagree among
    themselves the file is simply reported as contested, because that is a fact
    about them and not about us.
    """
    payload = json.load(open(sys.argv[1]))
    by_file = {}
    for case in payload:
        by_file.setdefault(case["name"], []).append(case)

    stats = {}
    contested = 0
    for name, cases in by_file.items():
        readings = {}
        for case in cases:
            fmt, oracle = case["format"], case["oracle"]
            with tempfile.TemporaryDirectory() as d:
                w = Path(d)
                if oracle == "lilypond":
                    got, err = via_lilypond(case["text"], w)
                elif oracle == "verovio":
                    got, err = via_verovio(case["text"], w,
                                           "mei" if fmt == "mei" else "musicxml")
                else:
                    got, err = via_music21(
                        case["text"],
                        {"musicxml": ".xml", "abc": ".abc", "kern": ".krn"}[fmt],
                        w)
            key = f"{fmt} via {oracle}"
            stats.setdefault(key, {"tried": 0, "agreed": 0, "examples": []})
            stats[key]["tried"] += 1
            if err:
                stats[key]["examples"].append(f"{name}: ORACLE FAILED {err}")
                continue
            readings[key] = sorted(p for _, p, _ in got)

        if len(readings) < 2:
            continue
        # The majority pitch multiset. With no majority the file is contested
        # and nobody is scored on it.
        tally = {}
        for key, pitches in readings.items():
            tally.setdefault(tuple(pitches), []).append(key)
        winner, holders = max(tally.items(), key=lambda kv: len(kv[1]))
        if len(holders) * 2 <= len(readings):
            contested += 1
            continue
        for key, pitches in readings.items():
            if tuple(pitches) == winner:
                stats[key]["agreed"] += 1
            else:
                stats[key]["examples"].append(
                    f"{name}: {len(pitches)} notes vs majority {len(winner)} "
                    f"({', '.join(holders)})")

    print(f"files {len(by_file)}, contested (no majority) {contested}")
    for k in sorted(stats):
        r = stats[k]
        mark = "" if r["agreed"] == r["tried"] else \
            f"   e.g. {r['examples'][0][:130]}" if r["examples"] else ""
        print(f"  {k:24} {r['agreed']:4}/{r['tried']:4}{mark}")
    json.dump(stats, open(sys.argv[2], "w"), indent=1)


if __name__ == "__main__":
    main()
