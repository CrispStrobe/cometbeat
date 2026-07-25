// lib/features/games/composition/custom_progressions.dart
//
// Persisted "make your own harmony" presets for the Loop Mixer (LM-UX7). A
// custom [Progression] is just a list of [ChordDegree]s the kid picked; every
// degree the app offers (I · IV · V · vi) is consonant with the C-pentatonic
// melodies, so ANY combination stays in tune (the colour-melody invariant holds
// for free). Stored as one SharedPreferences string; the encode/decode pair is
// pure so it's testable without a platform.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serialise custom progressions as `name,name,…;name,name,…` using the
/// [ChordDegree] enum NAMES (`i,v` — not ordinals).
///
/// ⚠ This used to store `ChordDegree.values.indexOf(...)`, which silently
/// re-interprets every saved harmony the moment anyone inserts a value into the
/// middle of the enum — and that happened: `ii` and `iii` were added between `i`
/// and `iv`, so a stored `0,2` that meant **I–V** started decoding as **I–iii**.
/// Names are stable under insertion, so this can't recur.
String encodeCustomProgressions(List<Progression> ps) =>
    ps.map((p) => p.degrees.map((d) => d.name).join(',')).join(';');

/// Parse [encodeCustomProgressions] output; skips malformed entries, never
/// throws, and re-assigns stable `custom-N` ids by position.
///
/// Also reads the LEGACY numeric form so nobody's saved harmonies vanish.
/// Note the honest limit: an old ordinal can't be dated, so a legacy `2` is read
/// against today's enum. Harmonies saved before `ii`/`iii` were added therefore
/// still shift — that data was already ambiguous the moment the enum changed,
/// and there is nothing in the stored string that could tell the two eras apart.
List<Progression> decodeCustomProgressions(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final byName = {for (final d in ChordDegree.values) d.name: d};
  final out = <Progression>[];
  for (final part in raw.split(';')) {
    if (part.trim().isEmpty) continue;
    final degrees = <ChordDegree>[];
    var ok = true;
    for (final tok in part.split(',')) {
      final token = tok.trim();
      final named = byName[token];
      if (named != null) {
        degrees.add(named);
        continue;
      }
      final i = int.tryParse(token); // legacy ordinal
      if (i == null || i < 0 || i >= ChordDegree.values.length) {
        ok = false;
        break;
      }
      degrees.add(ChordDegree.values[i]);
    }
    if (ok && degrees.length >= 2) {
      out.add(Progression('custom-${out.length}', degrees));
    }
  }
  return out;
}

/// SharedPreferences-backed store for the kid's own harmonies.
class CustomProgressionStore {
  static const _key = 'loop_mixer_custom_progressions';

  Future<List<Progression>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeCustomProgressions(prefs.getString(_key));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Progression> ps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encodeCustomProgressions(ps));
    } catch (_) {
      // Best-effort; the in-memory list still applies this session.
    }
  }
}
