# Note-event models on the CrispASR (ggml) runtime

One C entry point, three models. `crispasr_session_piano` — surfaced in Dart as
`CrispasrSession.pianoNotes`, and in this app as
`lib/core/audio/transcription/crispasr_ffi_piano_io.dart` — serves
**basic-pitch**, **piano-transcription** and **mt3** alike. Its `pcm_16k`
parameter name is historical; the rate is per-model and is **queried**, never
assumed. So adding MT3 and Basic Pitch to the ggml polyphonic path is a choice
of *model*, expressed as `CrispasrNoteModel` in `engine_config.dart` — not a
third code path.

## The measurement this is based on

MusicNet standard test split (ten real classical recordings, 13,589 annotated
notes), scored by `mir_eval.transcription`'s rules — onset within 50 ms, pitch
within 50 cents. The harness agreed with the official reference implementations
to 0.2 F1 points.

| engine | precision | recall | **F1** | onset err p50 | cost / s of audio |
|---|---|---|---|---|---|
| Basic Pitch (the pure-Dart ONNX default) | 50.2% | 39.5% | 44.2% | 21.4 ms | 0.08× |
| piano-transcription (Kong) | 55.1% | 42.1% | 47.7% | 19.1 ms | 7.77× |
| **MT3** | **77.1%** | **75.9%** | **76.5%** | **16.8 ms** | **0.26×** |

Kong's aggregate understates it: on *solo piano* it reaches 71.2% (88.0% on one
piece) while emitting 9 notes against 551 references on solo violin — a piano
model correctly declining, not failing. That is why it stays a distinct choice
rather than being replaced: "decline on non-piano" is the right behaviour for a
piano lesson, and the wrong one for a mixed recording.

**None of these numbers were produced on this app's material.** They are an
offline transcription of whole classical recordings. That is the reason `auto`
still means piano-transcription (§ Defaults below), and the reason there is a
picker instead of a silent upgrade.

## What is wired

- `CrispasrNoteModel` in `lib/core/audio/transcription/engine_config.dart` —
  `auto | basicPitch | pianoTranscription | mt3`, with `registryBackend`,
  `approxDownloadBytes`, `needsExplicitDownloadConsent` and `sampleRate`.
  Persisted with the rest of the engine config; an older stored config with no
  such key reads back as `auto`, i.e. exactly today's behaviour.
- `loadCrispasrPianoFfi({download, model})` resolves the GGUF through
  **CrispASR's own registry and cache** (`registryLookup` → `cacheDir` →
  `cacheEnsureFile`, via `openCrispasrSession`), the same way
  `crispasr_ffi_pitch_io.dart` does for CREPE. No URLs are built here.
- `resolveEngines` threads `config.crispasrNoteModel` into the ggml probe and
  nowhere else.
- Settings → Transcription engine → Advanced: a "Note model" chip row under the
  "Chords & piano" step, native only, each label carrying its download size.

## Sample rates

`pianoSampleRate` is asked, not assumed: **22050** for basic-pitch, **16000**
for piano-transcription and MT3. It returns **0** when the opened backend has no
piano arm (or the dylib predates the API), which doubles as the capability
probe — and the loader now treats 0 as "unavailable" and returns null. Before
this change the rate was read but not checked, so a 0 would have reached
`resampleLinear(mono, sampleRate / 0)` as an infinite ratio.

## How it degrades

Every failure is a null, and null means the resolver falls to the next runtime
and finally to the pure-Dart ONNX Basic Pitch — no lib, no model, no network,
no throw:

| what is missing | where it is caught |
|---|---|
| no `libcrispasr` | `openCrispasrSession` → `DynamicLibrary.open` throws → null |
| a build without this backend registered | `registryLookup` → null |
| model not cached, and `download: false` | no `modelPath` → null |
| download fails | `cacheEnsureFile` → null |
| model opens but has no piano arm | `pianoSampleRate == 0` → session closed → null |
| the model runs and throws mid-transcription | caught → empty note list |
| web / no `dart:io` | the `_stub.dart` half of the conditional import |

`resolveEngines` passes `download:` only when the user has **explicitly** chosen
`crispasr` for the polyphonic step. An `auto` resolution probes the cache and
never fetches, so neither the 77 MB nor the 96 MB model can arrive by accident.

## Defaults, and why they did not change

`auto` = piano-transcription, which is what the ggml path already loaded. MT3 is
better on MusicNet by a very large margin, but flipping a default on a
measurement taken elsewhere, on other material, is exactly the move the
A/B discipline forbids. What flips it is a CometBeat-side A/B — the harness
already exists (`test/transcription/note_metrics.dart`, `notePrf`) and the
material should be the app's own: short takes, monophonic singing, a phone mic
in a room, not a concert recording of a string quintet.

## Downloads

110 KB / 77 MB / 96 MB, fetched on first use of an explicitly chosen engine,
never bundled. 96 MB is a real cost on mobile data and on the iOS/Android
install story, but it is not a *surprise* cost here: the user picks the model in
Settings, the size is on the chip, and the fetch happens only after they also
point the polyphonic step at the ggml runtime. That is already the "explicit
user action" gate — no separate confirmation was added, because a second
dialogue in front of a choice the user just made reads as friction, not consent.
`needsExplicitDownloadConsent` exists so a future download-manager surface can
warn without re-deriving the threshold.

## Is MT3 right for the interactive path?

Short answer: the question turns out to be moot, because **CometBeat has no
streaming note-transcription path at all**. `NeuralTranscriber` is a batch seam
— `(Float64List mono, int sampleRate) → Future<List<NoteEvent>>`. The Transcribe
screen either picks a WAV or records a take to a buffer and then transcribes the
whole thing; the composition workshop's in-editor "transcribe a recording" is
deliberately pure-Dart with no engines injected at all. Nothing feeds audio to a
note model frame by frame, so MT3's autoregressive decode is not competing with
a real-time budget anywhere.

The cost that *is* real is that `transcribe_screen.dart` runs the engines
**inline on the UI isolate** whenever a neural engine is present (ONNX handles
cannot cross an isolate; the FFI session cannot either). So the whole
transcription blocks the UI. But note what that means for this change:

| ggml note model | cost / s of audio | a 4-minute song blocks the UI for |
|---|---|---|
| piano-transcription (what `auto` loads today) | 7.77× | ~31 min |
| MT3 | 0.26× | ~62 s |

MT3 is ~30× *cheaper* than the model this path already defaults to. Wiring it in
does not introduce a new class of blocking problem — it is the first ggml note
model that makes the ggml polyphonic path usable on a whole song. The UI-isolate
problem is real and pre-existing, and is its own card, not this one's.

## Carrying MT3's instrument: `NoteEvent.program` (2026-09-22)

MT3's reason for existing is that it is **multi-instrument**. That is most of
what separates its 76.5% from Kong's 47.7% on the table above — and until this
change, none of it reached the user. The program was decoded, crossed the C ABI
(`crispasr_session_piano_note_programs`, crispasr 0.8.35), arrived in Dart as
`pianoNotesWithPrograms` … and was dropped one line later, because CometBeat's
own `NoteEvent` had nowhere to put it. A wind trio came out as a single staff
of three-note chords: every pitch correct, and unreadable as music.

### Why the seam was widened and not wrapped

`contracts.dart` calls `NoteEvent` **the seam** and asks for a heads-up on the
board before it changes. The heads-up was there; the question was what shape to
use. Three options, and the language settles two of them:

1. **A superset record** — `({int midi, …, int program})` passed where
   `NoteEvent` is expected. **Impossible.** Dart records have no width
   subtyping: a five-field record is not a subtype of a four-field one. This is
   the option that *looks* free and is not available at all.
2. **A parallel channel** — `(List<NoteEvent> notes, List<int> programs)`,
   index-aligned. Possible, and the worst of the three. The pipeline sorts
   notes by onset in `notesFromPosteriorgrams`, filters them in
   `removeOctaveArtifacts`, groups them in `separateVoices` and quantises them
   in `quantizeToGrid`. Any one of those, written without remembering the side
   array, relabels every note *silently* — the failure mode is a bassoon line
   attributed to a clarinet, with nothing to catch it.
3. **Widening the record.** Every construction site becomes a compile error
   until it states the instrument it identified. There were **22** of them, 5
   in `lib/`. That is the whole cost, and the errors *are* the audit.

(3) won. The cost was one afternoon and one line per producer; (2) would have
cost a class of bug that no test suite reliably catches.

### The sentinel: `-1`, never `0`

```dart
const int gmProgramUnknown = -1;     // no instrument identified
const int gmProgramPercussion = 128; // GM channel 10 — drum keys, not pitches
// 0..127 — a General MIDI program
```

`0` is *Acoustic Grand Piano*. A piano transcriber that reported `0` would be
right most of the time and would still be lying: it never computed an
instrument, and nothing downstream could tell its guess apart from MT3's
recognition. So **every producer that is not MT3 reports `-1`** — pYIN's
note-HMM, Basic Pitch, Kong's piano-transcription, the Score→notes helper in
`notation.dart`. `test/transcription/note_program_test.dart` pins this by
running the *real* decoders (a synthesised A4 through pYIN; a hand-built
posteriorgram through Basic Pitch's decoder) rather than stubs, because a stub
only pins what the test file already believes.

This matches `crispasr`'s own `PianoNoteWithProgram` contract exactly, which is
why `crispasr_ffi_piano_io.dart` needs no capability branch: against an old
dylib, or against piano-transcription/basic-pitch, `pianoNotesWithPrograms`
already returns `-1` throughout.

### What consumes it

`transcribeToParts` (`transcribe.dart`) groups notes by program and engraves
**one staff per instrument**, highest median pitch first (unidentified notes
sort last and stay unnamed). Each part picks its own clef — which is what puts
the bassoon on a bass staff — and carries
`ScoreMetadata(instrument:, midiProgram:, isPercussion:)`.

Nothing had to change in `crisp_notation_core`: it already writes that metadata
as a MusicXML `<part-name>` + `<midi-program>` and as a MIDI program change.
So a multi-instrument transcription now exports as a multi-part document that
plays back with the right instruments.

It surfaces as `TranscriptionResult.parts` (plus a `multiPart()` helper), and
the Transcribe screen's *open in score editor* hands the Workshop the several
named staves. **A single-instrument take yields exactly one part**, so every
pre-existing path — pYIN, Basic Pitch, Kong, and the whole web build — is
unchanged.

### Verification

`bin/transcribe_notes_ggml.dart` is the headless end-to-end check:

```
dart run bin/transcribe_notes_ggml.dart 1819_8s.wav --model mt3 \
    --musicxml 1819.musicxml
```

MusicNet test piece **1819** (wind trio), first 8 s. The annotation lists
instruments **61/71/72**; MusicNet numbers MIDI programs from 1, so those are
GM **60/70/71**.

Result (2026-09-22, this box, `libcrispasr.so.0.8.33` + `mt3-f16.gguf`):

```
49 notes  (31330 ms):
instruments:
program   60  French Horn              6 notes
program   70  Bassoon                  13 notes
program   71  Clarinet                30 notes
```

**Three instruments, all three correct, nothing spurious** — no fourth
program, no `-1`. The same run's `--musicxml` wrote three `<part>`s:

```xml
<score-part id="P1"><part-name>Clarinet</part-name>    <midi-program>72</midi-program>
<score-part id="P2"><part-name>French Horn</part-name> <midi-program>61</midi-program>
<score-part id="P3"><part-name>Bassoon</part-name>     <midi-program>71</midi-program>
```

MusicXML also numbers programs from 1, so those three numbers are literally the
annotation's own `61/71/72`. The bassoon staff picked an **F clef** on its own,
because the split happens before the clef choice — the whole point of splitting
first. Ordering is by register: clarinet, horn, bassoon, top to bottom.

The 31 s wall time for 8 s of audio is this shared box at load ~11, not a
figure for the model; the 0.26× in the table above was measured on a quiet
machine and is the one to quote.
