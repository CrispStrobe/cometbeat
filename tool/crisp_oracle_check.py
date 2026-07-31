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
    payload = json.load(open(sys.argv[1]))
    results = {}
    for case in payload:
        name, fmt, oracle = case["name"], case["format"], case["oracle"]
        key = f"{fmt} via {oracle}"
        results.setdefault(key, {"tried": 0, "agreed": 0, "examples": []})
        results[key]["tried"] += 1
        with tempfile.TemporaryDirectory() as d:
            w = Path(d)
            ref = midi_notes(Path(case["our_midi"]))
            if oracle == "lilypond":
                got, err = via_lilypond(case["text"], w)
            elif oracle == "verovio":
                got, err = via_verovio(case["text"], w,
                                       "mei" if fmt == "mei" else "musicxml")
            else:
                got, err = via_music21(
                    case["text"],
                    {"musicxml": ".xml", "abc": ".abc", "kern": ".krn"}[fmt], w)
            if err:
                results[key]["examples"].append(f"{name}: ORACLE FAILED {err}")
                continue
            diff = compare(ref, got)
            if diff is None:
                results[key]["agreed"] += 1
            else:
                results[key]["examples"].append(f"{name}: {diff}")
    for k in sorted(results):
        r = results[k]
        print(f"  {k:28} {r['agreed']:4}/{r['tried']:4}"
              + ("" if r["agreed"] == r["tried"]
                 else f"   e.g. {r['examples'][0][:150]}"))
    json.dump(results, open(sys.argv[2], "w"), indent=1)


if __name__ == "__main__":
    main()
