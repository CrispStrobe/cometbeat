// Native (`dart:io`) implementation of the SoundFont-persist facade. See
// soundfont_persist.dart for the contract.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/features/library/soundfont_download.dart'
    show IoSoundFontCache;
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';

/// Native can cache fonts on disk, so soundfont voices are supported here.
bool get soundFontPersistSupported => true;

/// A stable id for [bytes] (FNV-1a over length + content) so the same font
/// re-uses one cached file.
String _fontId(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return 'user_${bytes.length}_${h.toRadixString(16)}';
}

/// Caches [fontBytes] to disk and saves a `soundfont_ref` library voice for its
/// [bank]/[program] preset. Returns the saved instrument.
Future<SavedInstrument?> persistSoundFontPreset({
  required Uint8List fontBytes,
  required int bank,
  required int program,
  required String presetName,
  required String saveName,
  required InstrumentLibraryStore store,
  String? cacheDir,
}) async {
  final cache = IoSoundFontCache(cacheDirOverride: cacheDir);
  final id = _fontId(fontBytes);
  await cache.write(id, fontBytes);
  final ref = SoundFontRef(
    path: cache.pathFor(id),
    bank: bank,
    program: program,
    name: presetName,
  );
  final saved = SavedInstrument(
    name: saveName,
    json: jsonEncode(ref.toJson()),
    source: 'SoundFont',
  );
  await store.save(saved);
  return saved;
}

/// Rebuilds [saved] into a playable voice: a `soundfont_ref` re-reads its cached
/// font file and rebuilds the preset; any other voice decodes its embedded JSON.
/// Returns null if the font file is gone or the preset can't be rebuilt.
Future<TrackerInstrument?> resolveSavedVoice(SavedInstrument saved) async {
  if (!saved.isReference) return saved.instrument;
  try {
    final json = jsonDecode(saved.json) as Map<String, dynamic>;
    return await resolveInstrumentJson(
      json,
      loadBytes: (path) => File(path).readAsBytes(),
    );
  } catch (_) {
    return null;
  }
}
