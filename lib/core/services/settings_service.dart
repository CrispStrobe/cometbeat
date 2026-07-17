// lib/core/services/settings_service.dart
//
// App settings, persisted in SharedPreferences: locale override (null = follow
// the system, the default) and the note-naming convention.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart' show MusicFont;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static const _localeKey = 'app_locale';
  static const _noteNamingKey = 'note_naming';
  static const _showTimerKey = 'show_timer';
  static const _colorScaffoldKey = 'color_scaffold';
  static const _instrumentKey = 'instrument';
  static const _handwrittenKey = 'handwritten_notes';
  static const _soundOnKey = 'sound_on';

  Locale? _locale;
  NoteNaming _noteNaming = NoteNaming.auto;
  bool _showTimer = false;
  bool _colorScaffold = false;
  bool _handwrittenNotes = false;
  bool _soundOn = true;
  Instrument _instrument = Instrument.piano;

  /// Master sound switch. When off, all synthesized playback (notes, chords,
  /// SFX, ticks, backing) is silenced via [AudioService]; the microphone is
  /// unaffected, so intonation games still work. On by default.
  bool get soundOn => _soundOn;

  /// The voice used for pitched playback across the app.
  Instrument get instrument => _instrument;

  /// Forced app locale; null follows the system locale.
  Locale? get locale => _locale;

  /// How note letters are spelled (auto follows the app language).
  NoteNaming get noteNaming => _noteNaming;

  /// Whether games show your completion time and personal best (off = no
  /// timing shown at all, keeping the no-time-pressure default).
  bool get showTimer => _showTimer;

  /// Pre-reader colour scaffold: when on, noteheads and answer choices in the
  /// reading games are tinted by pitch class (a Boomwhacker-style aid).
  /// Off by default and parent-removable — it "peels away" as the child learns
  /// the staff.
  bool get colorScaffold => _colorScaffold;

  /// Render notation in the handwritten Petaluma face instead of Bravura. A
  /// cosmetic "jazz chart" look; applies to screens entered after toggling.
  bool get handwrittenNotes => _handwrittenNotes;

  void _applyScoreFont() =>
      appScoreFont = _handwrittenNotes ? kPetalumaFont : MusicFont.bravura;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
    final naming = prefs.getString(_noteNamingKey);
    _noteNaming = NoteNaming.values.asNameMap()[naming] ?? NoteNaming.auto;
    _showTimer = prefs.getBool(_showTimerKey) ?? false;
    _colorScaffold = prefs.getBool(_colorScaffoldKey) ?? false;
    _handwrittenNotes = prefs.getBool(_handwrittenKey) ?? false;
    _soundOn = prefs.getBool(_soundOnKey) ?? true;
    _applyScoreFont();
    _instrument =
        Instrument.values.asNameMap()[prefs.getString(_instrumentKey)] ??
            Instrument.piano;
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale?.languageCode ?? '');
  }

  Future<void> setNoteNaming(NoteNaming naming) async {
    _noteNaming = naming;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteNamingKey, naming.name);
  }

  Future<void> setShowTimer(bool value) async {
    _showTimer = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTimerKey, value);
  }

  Future<void> setColorScaffold(bool value) async {
    _colorScaffold = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_colorScaffoldKey, value);
  }

  Future<void> setHandwrittenNotes(bool value) async {
    _handwrittenNotes = value;
    _applyScoreFont();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_handwrittenKey, value);
  }

  Future<void> setSoundOn(bool value) async {
    _soundOn = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundOnKey, value);
  }

  Future<void> setInstrument(Instrument instrument) async {
    _instrument = instrument;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_instrumentKey, instrument.name);
  }
}
