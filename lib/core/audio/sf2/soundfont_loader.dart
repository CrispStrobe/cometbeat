// Headless "load a SoundFont" facade — the whole capability behind a UI's
// "Load SoundFont" button, with zero Flutter/screen deps so it's unit-testable
// and reusable from any screen.
//
// Pick bytes → [loadSoundFont] parses them (uncompressed `.sf2` directly, or a
// compressed `.sf3` via the platform glint Vorbis decoder, auto-selected) into
// a browsable [LoadedSoundFont]; the UI lists [LoadedSoundFont.presets], and
// [soundFontInstrument] turns a chosen preset into a playable tracker
// instrument (the same multi-sample, key/velocity-split voice the SF2 reader
// builds). Friendly, catchable [SoundFontLoadException]s replace the reader's
// raw FormatExceptions so the UI can just show `e.message`.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_capability.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';

/// A parsed SoundFont ready to browse: the backing [font] plus its presets in a
/// stable display order. [compressed] is true when it was a `.sf3` (decoded via
/// the Vorbis seam).
class LoadedSoundFont {
  LoadedSoundFont(this.font, {required this.compressed})
      : presets = _sorted(font.presets);

  final Sf2SoundFont font;
  final bool compressed;

  /// Presets sorted by bank then program (General MIDI order) so the browse
  /// list is stable and melodic voices precede the bank-128 drum kits.
  final List<Sf2Preset> presets;

  static List<Sf2Preset> _sorted(List<Sf2Preset> ps) {
    final out = [...ps];
    out.sort(
      (a, b) => a.bank != b.bank ? a.bank - b.bank : a.program - b.program,
    );
    return out;
  }
}

/// A load failure with a short, user-showable [message] (the UI shows it
/// directly — no stack traces or raw format details).
class SoundFontLoadException implements Exception {
  SoundFontLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parse SoundFont [bytes] into a browsable [LoadedSoundFont]. Handles both an
/// uncompressed `.sf2` and a compressed `.sf3`: for `.sf3` it uses [vorbis], or
/// (default) the platform glint decoder via [loadGlintVorbis]. If the bytes are
/// a `.sf3` and no decoder is available, throws a clear [SoundFontLoadException]
/// telling the user to try a `.sf2` — never garbage PCM.
/// [loadSoundFont] with the web Vorbis decoder loaded first.
///
/// **Prefer this from UI code.** On web the glint wasm is fetched lazily, so
/// until it resolves `loadGlintVorbis()` hands back a decoder that returns null
/// on every call — a `.sf3` would then parse into silence instead of either
/// working or giving the clear "needs a Vorbis decoder" message. Natively this
/// is a no-op. `ensureGlintVorbisReady` existed for exactly this and was never
/// actually called from anywhere.
Future<LoadedSoundFont> loadSoundFontAsync(
  Uint8List bytes, {
  VorbisDecode? vorbis,
}) async {
  if (vorbis == null && sf2IsCompressed(bytes)) {
    await ensureGlintVorbisReady();
  }
  return loadSoundFont(bytes, vorbis: vorbis);
}

LoadedSoundFont loadSoundFont(Uint8List bytes, {VorbisDecode? vorbis}) {
  final compressed = sf2IsCompressed(bytes);
  final decode = vorbis ?? (compressed ? loadGlintVorbis() : null);
  if (compressed && decode == null) {
    throw SoundFontLoadException(
      'This is a compressed .sf3 SoundFont, which needs a Vorbis decoder that '
      'is not available here. Try an uncompressed .sf2 file.',
    );
  }
  final Sf2SoundFont font;
  try {
    font = Sf2SoundFont.parse(bytes, vorbis: decode);
  } on FormatException catch (e) {
    throw SoundFontLoadException('Not a valid SoundFont: ${e.message}');
  }
  if (font.presets.isEmpty) {
    throw SoundFontLoadException('No instruments found in this SoundFont.');
  }
  return LoadedSoundFont(font, compressed: compressed);
}

/// Build a playable tracker instrument from a chosen [preset] of [loaded] — the
/// full key/velocity-split GM voice. [id] defaults to a stable per-preset id.
TrackerInstrument soundFontInstrument(
  LoadedSoundFont loaded,
  Sf2Preset preset, {
  String? id,
}) {
  return sf2InstrumentFromPreset(
    loaded.font,
    preset,
    id: id ?? soundFontInstrumentId(preset),
  );
}

/// A stable instrument id for a preset (bank/program keyed, so re-loading the
/// same font+preset yields the same id → a stable stem cache).
String soundFontInstrumentId(Sf2Preset p) =>
    'sf2.${p.bank}.${p.program}.${p.name}';

/// A short human label for a preset in a browse list, e.g. "GM 40 · Violin" or
/// "Drum · Standard" (bank 128 = the GM percussion bank).
String soundFontPresetLabel(Sf2Preset p) {
  final kind = p.bank == 128 ? 'Drum' : 'GM ${p.program}';
  final name = p.name.trim().isEmpty ? 'Preset ${p.program}' : p.name.trim();
  return '$kind · $name';
}

// ── Reference-based persistence (loaded SoundFont voices) ────────────────────
//
// A loaded GM voice is megabytes of multi-sample PCM — wrong to embed in a
// per-sound library entry. Instead persist a tiny [SoundFontRef] (the file +
// bank/program) and rebuild the instrument on demand with [resolveSoundFontRef]
// once the file's bytes are available again. [resolveInstrumentJson] lets a
// library hold BOTH embedded voices (via tracker_instrument_codec) and these
// references uniformly.

/// A lightweight, persistable pointer to a SoundFont preset (the file [path] +
/// its GM [bank]/[program]), stored instead of the voice's PCM.
class SoundFontRef {
  const SoundFontRef({
    required this.path,
    required this.bank,
    required this.program,
    this.name = '',
  });

  /// The `.sf2`/`.sf3` file location (or any stable key the caller can re-read).
  final String path;
  final int bank;
  final int program;

  /// The preset name (display / instrument id); optional.
  final String name;

  Map<String, dynamic> toJson() => {
        'type': 'soundfont_ref',
        'path': path,
        'bank': bank,
        'program': program,
        'name': name,
      };

  factory SoundFontRef.fromJson(Map<String, dynamic> m) => SoundFontRef(
        path: (m['path'] as String?) ?? '',
        bank: (m['bank'] as num?)?.toInt() ?? 0,
        program: (m['program'] as num?)?.toInt() ?? 0,
        name: (m['name'] as String?) ?? '',
      );

  /// The reference to the [preset] of a font at [path].
  factory SoundFontRef.ofPreset(String path, Sf2Preset preset) => SoundFontRef(
        path: path,
        bank: preset.bank,
        program: preset.program,
        name: preset.name,
      );
}

/// The preset in [loaded] matching [bank]/[program], or null if the font no
/// longer has it.
Sf2Preset? findPreset(LoadedSoundFont loaded, int bank, int program) {
  for (final p in loaded.presets) {
    if (p.bank == bank && p.program == program) return p;
  }
  return null;
}

/// Rebuild the instrument [ref] points at, from the SoundFont's [bytes] (the
/// caller re-reads them from `ref.path`). Throws [SoundFontLoadException] if the
/// font can't be parsed or no longer has that preset.
TrackerInstrument resolveSoundFontRef(
  SoundFontRef ref,
  Uint8List bytes, {
  VorbisDecode? vorbis,
  String? id,
}) {
  final loaded = loadSoundFont(bytes, vorbis: vorbis);
  final preset = findPreset(loaded, ref.bank, ref.program);
  if (preset == null) {
    throw SoundFontLoadException(
      'preset ${ref.bank}/${ref.program} not found in ${ref.path}',
    );
  }
  return soundFontInstrument(loaded, preset, id: id);
}

/// Resolve any persisted instrument JSON uniformly: a `soundfont_ref` is
/// rebuilt asynchronously ([loadBytes] re-reads the referenced file, then
/// [resolveSoundFontRef]); every other type is an embedded voice decoded by
/// [instrumentFromJson]. So a mixed sound library round-trips through one path.
Future<TrackerInstrument> resolveInstrumentJson(
  Map<String, dynamic> json, {
  required Future<Uint8List> Function(String path) loadBytes,
  VorbisDecode? vorbis,
}) async {
  if (json['type'] == 'soundfont_ref') {
    final ref = SoundFontRef.fromJson(json);
    return resolveSoundFontRef(ref, await loadBytes(ref.path), vorbis: vorbis);
  }
  return instrumentFromJson(json);
}
