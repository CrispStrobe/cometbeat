// WS-W6 — the effect chains you built, saved by name.
//
// Five surfaces host an FX rack (the Audio Editor, the Tracker, the Tab
// Workshop, Loop Studio and — since WS-X3 — Score), and until now none of them
// could keep a chain. `fx_presets.dart` offers a fixed enum of factory sounds;
// there was no way to save the one you just dialled in, let alone use it on a
// different surface. So the useful unit here is not "a preset for the Tracker",
// it is a chain that travels.
//
// It stores CHAIN STRINGS rather than serialised `FxSpec`s, for three reasons
// that all point the same way: the string is already the interchange format
// (`fx_chain_codec.dart`), it is already what the Audio Editor puts on the
// clipboard, and it is human-readable — so a stored preset survives a schema
// change, can be pasted into the CLI, and can be read in a bug report.
//
// ⚠️ The cost of that choice, and it must not be silent: a chain string has no
// syntax for per-param AUTOMATION. `fxChainStringIsLossless` is how a caller
// asks before saving, and the UI is expected to say so rather than flatten a
// chain quietly.
//
// Shape borrowed wholesale from `ProjectStore` (WS-W6 slice 1): a
// SharedPreferences list, newest first, capped with the OLDEST dropped. Two
// stores of the same shape are easier to reason about than two clever ones.

import 'dart:convert';

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved chain.
class SavedFxPreset {
  const SavedFxPreset({
    required this.name,
    required this.chain,
    required this.savedAtMs,
  });

  /// What the user called it.
  final String name;

  /// The chain string, e.g. `highpass freq=120 | reverb mix=20%`.
  final String chain;

  final int savedAtMs;

  /// The effects this preset describes; empty when the stored text no longer
  /// parses (an older build, a hand-edited value).
  List<FxSpec> get specs => parseFxChain(chain).chain;

  Map<String, Object?> toJson() => {
        'name': name,
        'chain': chain,
        'savedAtMs': savedAtMs,
      };

  /// Null when [raw] is not a preset — a corrupt entry is skipped rather than
  /// throwing, so one bad row cannot cost the whole list.
  static SavedFxPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final chain = raw['chain'];
    if (name is! String || chain is! String || name.isEmpty) return null;
    final savedAt = raw['savedAtMs'];
    return SavedFxPreset(
      name: name,
      chain: chain,
      savedAtMs: savedAt is int ? savedAt : 0,
    );
  }
}

/// Saved effect chains, newest first.
class FxPresetStore {
  FxPresetStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'fx_presets_v1';

  /// How many are kept, oldest dropped. Same reasoning as `ProjectStore`:
  /// SharedPreferences is not a database, and a list nobody can scroll is not a
  /// browser.
  static const maxPresets = 40;

  /// Every saved preset, newest first. Never throws: a corrupt store reads as
  /// empty, which is recoverable, where a throw at start-up is not.
  List<SavedFxPreset> list() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SavedFxPreset>[
        for (final entry in decoded)
          if (SavedFxPreset.fromJson(entry) case final saved?) saved,
      ];
      out.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// The preset called [name], or null.
  SavedFxPreset? find(String name) {
    for (final preset in list()) {
      if (preset.name == name) return preset;
    }
    return null;
  }

  /// Save [chain] under [name], replacing any preset with that name.
  ///
  /// An EMPTY chain is refused: "no effects" is what you get by not applying a
  /// preset, and a list of empty entries is a list you stop reading.
  ///
  /// [nowMs] is injected rather than read from the clock so a test can assert
  /// ordering without sleeping.
  Future<List<SavedFxPreset>> save(
    String name,
    List<FxSpec> chain, {
    int? nowMs,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || chain.isEmpty) return list();
    final text = formatFxChain(chain);
    if (text.trim().isEmpty) return list();
    final entry = SavedFxPreset(
      name: trimmed,
      chain: text,
      savedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    final kept = [
      entry,
      for (final preset in list())
        if (preset.name != trimmed) preset,
    ]..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return _write(kept.take(maxPresets).toList());
  }

  /// Forget the preset called [name].
  Future<List<SavedFxPreset>> remove(String name) => _write([
        for (final preset in list())
          if (preset.name != name) preset,
      ]);

  Future<List<SavedFxPreset>> _write(List<SavedFxPreset> presets) async {
    await _prefs.setString(
      _key,
      jsonEncode([for (final preset in presets) preset.toJson()]),
    );
    return presets;
  }
}
