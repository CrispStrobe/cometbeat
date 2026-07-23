// Web stub of the SoundFont-persist facade — there's no place to cache a
// multi-megabyte font, so soundfont voices are unsupported on web. See
// soundfont_persist.dart for the contract.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';

/// Web can't keep a font file, so soundfont voices are unsupported here.
bool get soundFontPersistSupported => false;

Future<SavedInstrument?> persistSoundFontPreset({
  required Uint8List fontBytes,
  required int bank,
  required int program,
  required String presetName,
  required String saveName,
  required InstrumentLibraryStore store,
  String? cacheDir,
}) async =>
    null;

/// Embedded voices still resolve; a `soundfont_ref` can't (no font file on web).
Future<TrackerInstrument?> resolveSavedVoice(SavedInstrument saved) async =>
    saved.isReference ? null : saved.instrument;
