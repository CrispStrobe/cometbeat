// lib/core/audio/groove_change_label.dart
//
// WS-W4 (Loop fold-in) — what to CALL an edit, worked out from the edit itself.
//
// The shared history's whole point is that a row says what you did. Loop Studio
// has no idea: every content edit funnels through one hook (`_syncPlayback` →
// `_recordHistory`), which is exactly why a single hook could cover all of them
// in the first place — it sees that the groove changed, never what changed.
//
// THE OBVIOUS FIX IS THE WRONG ONE. Setting a label at each edit site means
// roughly twenty call sites must each remember to set one, and every future
// edit site must remember too. The one that forgets does not fail — it files
// its edit under whatever the previous edit left behind, or under a generic
// fallback. That is the shape of inert seam this codebase keeps producing (a
// field nothing carries, a method nothing calls): the mechanism tests green and
// the drift shows up only in the product.
//
// So the label is DERIVED by diffing the two snapshots the history already
// holds — and specifically their `toJson()`, not their fields:
//
//   * `toJson` is the CANONICAL form. It sorts every map, rounds every scalar,
//     and omits everything sitting at its default. `cacheKey` is a `jsonEncode`
//     of it, and `cacheKey` is already what decides whether an edit gets
//     recorded at all — so the label is derived from exactly the same view of
//     the groove that decided there was something to label.
//   * Comparing FIELDS would be wrong here, not merely inconvenient:
//     `userCells`, `beatRows` and the three override maps are nullable deep
//     structures, so `!=` compares identity for most of them and would report a
//     change on any rebuild — mislabelling a tempo edit as "Sung track".
//   * It cannot drift. A new `GrooveSpec` field arrives as a new json key and
//     falls through to the generic label until someone names it below, which is
//     a MISSING label rather than a wrong one.
//
// ORDER IS SIGNIFICANT. One gesture usually moves several keys at once (adding
// a track writes `xt` AND `e`), so the most structural difference is reported
// first: a player who added a track wants to read "Add track", not "Turn on t1".

import 'dart:convert';

import 'package:comet_beat/core/audio/loop_engine.dart';

/// The generic label, used when nothing below recognises the change.
const String kGenericGrooveEditLabel = 'Edit groove';

/// A short, human description of what changed between [before] and [after].
///
/// English only, matching the labels the mixer console already pushes: these
/// are history rows, and the app's other undo labels are not localized either.
/// Worth revisiting for the whole history at once rather than for one surface.
String describeGrooveChange(GrooveSpec before, GrooveSpec after) {
  final a = before.toJson();
  final b = after.toJson();

  // --- Structural: tracks appearing, going, or being renamed ---------------
  if (_differs(a, b, 'xt')) {
    final added = _sub(b, 'xt').length - _sub(a, 'xt').length;
    if (added > 0) return 'Add track';
    if (added < 0) return 'Remove track';
    // Same count, different content: a track was replaced by another, which
    // only happens when one is removed and another added in one step.
    return 'Change tracks';
  }
  if (_differs(a, b, 'xn')) return 'Rename track';

  // --- The band: which tracks are sounding ---------------------------------
  if (_differs(a, b, 'e')) {
    final was = _list(a, 'e');
    final now = _list(b, 'e');
    final turnedOn = now.where((id) => !was.contains(id)).toList();
    final turnedOff = was.where((id) => !now.contains(id)).toList();
    if (turnedOn.length == 1 && turnedOff.isEmpty) {
      return 'Turn on ${turnedOn.single}';
    }
    if (turnedOff.length == 1 && turnedOn.isEmpty) {
      return 'Turn off ${turnedOff.single}';
    }
    return 'Change which tracks play';
  }

  // --- Per-track settings ---------------------------------------------------
  // Each names the track: "Level" alone, in a history shared with other
  // surfaces, is not enough to tell two tracks' edits apart.
  const perTrack = {
    'v': 'Pattern',
    'l': 'Level',
    'pn': 'Pan',
    'fl': 'Filter',
    'ts': 'Length',
    'tw': 'Swing',
    'iv': 'Voice',
  };
  for (final entry in perTrack.entries) {
    if (!_differs(a, b, entry.key)) continue;
    final id = _changedSubKey(_sub(a, entry.key), _sub(b, entry.key));
    return id == null ? entry.value : '${entry.value}: $id';
  }

  // --- Lanes, hand-edited grids and captured takes -------------------------
  if (_differs(a, b, 'au')) return 'Automation';
  if (_differs(a, b, 'o')) return 'Edit notes';
  if (_differs(a, b, 'dr') || _differs(a, b, 'drv')) return 'Edit beat';
  if (_differs(a, b, 'u')) return 'Sung track';
  if (_differs(a, b, 'b') || _differs(a, b, 'bv')) return 'Beatbox track';

  // --- Whole-groove settings ------------------------------------------------
  // Tempo carries its numbers: it is the one a player most often steps back
  // through, and "Tempo" alone does not say which way it went.
  if (_differs(a, b, 't')) {
    return 'Tempo ${before.tempoBpm} → ${after.tempoBpm}';
  }
  if (_differs(a, b, 's')) return 'Swing';
  if (_differs(a, b, 'k')) return 'Key';
  if (_differs(a, b, 'sc')) return 'Scale';
  if (_differs(a, b, 'kt')) return 'Drum kit';
  if (_differs(a, b, 'st')) return 'Band style';
  if (_differs(a, b, 'p')) return 'Chords';

  return kGenericGrooveEditLabel;
}

/// Whether one canonical key differs. Absent and default are the same thing —
/// `toJson` omits anything sitting at its default, so a value returning to its
/// default shows up here as the key disappearing.
bool _differs(Map<String, dynamic> a, Map<String, dynamic> b, String key) =>
    jsonEncode(a[key]) != jsonEncode(b[key]);

Map<String, dynamic> _sub(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is Map ? value.cast<String, dynamic>() : const {};
}

List<String> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is List ? [for (final v in value) '$v'] : const [];
}

/// The single track id whose value differs, or null when several do.
///
/// Several at once stays unnamed on purpose: that is a bulk change, and naming
/// one of the tracks it touched would be actively misleading.
String? _changedSubKey(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  String? found;
  for (final key in {...before.keys, ...after.keys}) {
    if (jsonEncode(before[key]) == jsonEncode(after[key])) continue;
    if (found != null) return null;
    found = key;
  }
  return found;
}
