// lib/core/services/settings_service.dart
//
// App settings, persisted in SharedPreferences: locale override (null = follow
// the system, the default) and the note-naming convention.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static const _localeKey = 'app_locale';
  static const _noteNamingKey = 'note_naming';
  static const _showTimerKey = 'show_timer';
  static const _colorScaffoldKey = 'color_scaffold';
  static const _instrumentKey = 'instrument';
  static const _handwrittenKey = 'handwritten_notes'; // legacy (pre-multi-font)
  static const _scoreFontKey = 'score_font';
  static const _soundOnKey = 'sound_on';

  Locale? _locale;
  NoteNaming _noteNaming = NoteNaming.auto;
  bool _showTimer = false;
  bool _colorScaffold = false;
  ScoreFont _scoreFont = ScoreFont.bravura;
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

  /// The SMuFL face used for all rendered notation. Applies to screens entered
  /// after changing it (games are pushed fresh). Bravura by default.
  ScoreFont get scoreFont => _scoreFont;

  /// Back-compat: the old boolean "handwritten notes" toggle mapped onto the
  /// Petaluma face. True iff Petaluma is selected.
  bool get handwrittenNotes => _scoreFont == ScoreFont.petaluma;

  void _applyScoreFont() => appScoreFont = musicFontFor(_scoreFont);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
    final naming = prefs.getString(_noteNamingKey);
    _noteNaming = NoteNaming.values.asNameMap()[naming] ?? NoteNaming.auto;
    _showTimer = prefs.getBool(_showTimerKey) ?? false;
    _colorScaffold = prefs.getBool(_colorScaffoldKey) ?? false;
    // New multi-font key; fall back to the legacy handwritten bool (→ Petaluma)
    // so an upgrading user keeps their choice.
    final fontName = prefs.getString(_scoreFontKey);
    _scoreFont =
        ScoreFont.values.asNameMap()[fontName] ??
        ((prefs.getBool(_handwrittenKey) ?? false)
            ? ScoreFont.petaluma
            : ScoreFont.bravura);
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

  Future<void> setScoreFont(ScoreFont font) async {
    _scoreFont = font;
    _applyScoreFont();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scoreFontKey, font.name);
    // Keep the legacy key in sync so a downgrade still reads a sane value.
    await prefs.setBool(_handwrittenKey, font == ScoreFont.petaluma);
  }

  /// Back-compat shim for the old boolean toggle: true → Petaluma, false →
  /// Bravura.
  Future<void> setHandwrittenNotes(bool value) =>
      setScoreFont(value ? ScoreFont.petaluma : ScoreFont.bravura);

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
