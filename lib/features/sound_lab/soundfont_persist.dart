// Persist / resolve a SoundFont-preset library voice — web-safe facade.
//
// A SoundFont preset can't be embedded in the library like a formula synth or a
// PCM sample: fonts are megabytes. Instead we cache the font FILE and save a
// tiny `soundfont_ref` (file path + bank/program). This is inherently a
// `dart:io` operation (there's no place to keep a font on web), so the real
// implementation lives in the `_io` file and web gets a no-op stub.
//
//   soundFontPersistSupported  — false on web
//   persistSoundFontPreset(...) — cache the font + save a soundfont_ref voice
//   resolveSavedVoice(saved)    — rebuild ANY saved voice, re-reading the font
//                                 file for a soundfont_ref (else the embedded voice)
export 'soundfont_persist_stub.dart'
    if (dart.library.io) 'soundfont_persist_io.dart';
