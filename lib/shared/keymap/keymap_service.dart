// WS-T3 — the app's live keymap, and the one place it is stored.
//
// A `Keymap` is a value; this owns the current one and persists the difference
// from the defaults. Kept apart from the table itself so the table stays pure
// and testable without a preferences plugin in the way.

import 'dart:convert';

import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the difference-from-defaults is stored.
const String kKeymapPrefsKey = 'keymap.overrides.v1';

/// The current bindings, shared by every surface that hosts them.
class KeymapService extends ChangeNotifier {
  KeymapService({Keymap? initial}) : _keymap = initial ?? Keymap();

  Keymap _keymap;
  Keymap get keymap => _keymap;

  /// Whether anything has been changed from the defaults — what the sheet needs
  /// in order to decide whether "reset" is worth offering.
  bool get isCustomised => _keymap.toJson().isNotEmpty;

  /// Load the stored overrides. Never throws: a keymap that will not load would
  /// lock someone out of their own keyboard, so a damaged store silently gives
  /// them the defaults back.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kKeymapPrefsKey);
      if (raw == null || raw.isEmpty) return;
      _keymap = Keymap.fromJson(jsonDecode(raw));
      notifyListeners();
    } catch (_) {
      // Keep the defaults.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = _keymap.toJson();
      if (json.isEmpty) {
        await prefs.remove(kKeymapPrefsKey);
      } else {
        await prefs.setString(kKeymapPrefsKey, jsonEncode(json));
      }
    } catch (_) {
      // A failed save costs this session's rebinding, not the app.
    }
  }

  /// Bind [chord] to [intent], replacing whatever held that chord.
  Future<void> rebind(KeyChord chord, AppIntent intent) async {
    _keymap = _keymap.rebound(chord, intent);
    notifyListeners();
    await _save();
  }

  /// Unbind [chord].
  Future<void> unbind(KeyChord chord) async {
    _keymap = _keymap.without(chord);
    notifyListeners();
    await _save();
  }

  /// Back to the shipped defaults.
  Future<void> reset() async {
    _keymap = Keymap();
    notifyListeners();
    await _save();
  }
}
