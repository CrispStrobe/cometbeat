// lib/core/services/transcription_config_service.dart
//
// App-wide holder + persistence for the transcription engine config (which
// backend / model quality runs each step). Mirrors SettingsService: a
// ChangeNotifier over SharedPreferences, the whole config stored as one JSON
// string. Registered in main.dart; the Settings screen edits it and the
// transcription pipeline reads it via `config.resolve(step, …)`.

import 'dart:convert';

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/f0_decode_options.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranscriptionConfigService with ChangeNotifier {
  static const _key = 'transcription_engine_config';

  TranscriptionEngineConfig _config = const TranscriptionEngineConfig();
  TranscriptionEngineConfig get config => _config;

  /// Load the persisted config (call once at startup). Never throws on bad data.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, Object?>) {
          _config = TranscriptionEngineConfig.fromJson(json);
        }
      } on Object {
        // keep the default on any parse error
      }
    }
    _applyF0Viterbi();
    notifyListeners();
  }

  Future<void> setQuality(ModelQuality quality) =>
      _update(_config.copyWith(quality: quality));

  Future<void> setBackend(TranscriptionStep step, Backend backend) => _update(
        _config.copyWith(backends: {..._config.backends, step: backend}),
      );

  Future<void> setF0Viterbi(bool on) =>
      _update(_config.copyWith(f0Viterbi: on));

  /// Which note model the `crispasr` runtime loads for the polyphonic step.
  /// Takes effect the next time engines are resolved; changing it does not
  /// download anything on its own.
  Future<void> setCrispasrNoteModel(CrispasrNoteModel m) =>
      _update(_config.copyWith(crispasrNoteModel: m));

  /// Push the config's F0-Viterbi choice to the process-wide override the neural
  /// F0 model stores read. Enabling forces it on; leaving it off defers to the
  /// per-model `COMET_*_VITERBI` env gates (so a dev env var still works).
  void _applyF0Viterbi() =>
      F0DecodeOptions.viterbi = _config.f0Viterbi ? true : null;

  Future<void> _update(TranscriptionEngineConfig next) async {
    _config = next;
    _applyF0Viterbi();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_config.toJson()));
  }
}
