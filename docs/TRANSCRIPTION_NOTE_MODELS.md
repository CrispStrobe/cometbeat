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
