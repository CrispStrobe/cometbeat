// Facade for the CrispASR-CLI source separator (native only, behind a
// conditional import so a web build still compiles). The IO impl shells out to
// the CrispASR `--separate` command (ggml HTDemucs / mel-band-roformer, MIT —
// fully parity + fast as of §248); the stub returns null (web / no binary), so
// transcribeSong falls back to a single part.

export 'crispasr_separate_stub.dart'
    if (dart.library.io) 'crispasr_separate_io.dart';
