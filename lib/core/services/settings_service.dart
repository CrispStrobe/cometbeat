// lib/core/services/settings_service.dart
//
// App settings, persisted in SharedPreferences: locale override (null = follow
// the system, the default) and the note-naming convention.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_profile.dart';
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static const _localeKey = 'app_locale';
  static const _noteNamingKey = 'note_naming';
  static const _showTimerKey = 'show_timer';
  static const _colorScaffoldKey = 'color_scaffold';
  static const _instrumentKey =
      'instrument'; // legacy 4-way enum (kept in sync)
  static const _voiceIdKey = 'voice_id'; // the full-palette voice selection
  static const _handwrittenKey = 'handwritten_notes'; // legacy (pre-multi-font)
  static const _scoreFontKey = 'score_font';
  static const _soundOnKey = 'sound_on';
  static const _narrationOnKey = 'narration_on';
  static const _autoReadTutorialsKey = 'auto_read_tutorials';
  static const _showNoteNamesKey = 'show_note_names';
  static const _smartTabFingeringKey = 'smart_tab_fingering';
  static const _authenticSlidesKey = 'tracker_authentic_slides';

  Locale? _locale;
  NoteNaming _noteNaming = NoteNaming.auto;
  bool _showTimer = false;
  bool _colorScaffold = false;
  ScoreFont _scoreFont = ScoreFont.bravura;
  bool _soundOn = true;
  bool _narrationOn = true;
  bool _autoReadTutorials = false;
  bool _showNoteNames = false;
  bool _smartTabFingering = true;
  bool _authenticSlides = true;
  Instrument _instrument = Instrument.piano;
  String _voiceId = Instrument.piano.name;
  TrackerInstrument? _voice;

  /// Master sound switch. When off, all synthesized playback (notes, chords,
  /// SFX, ticks, backing) is silenced via [AudioService]; the microphone is
  /// unaffected, so intonation games still work. On by default.
  bool get soundOn => _soundOn;

  /// Read-aloud narration switch — independent of [soundOn], so a child can keep
  /// game sounds while turning the spoken lesson/how-to text off (or vice versa).
  /// Narration also still obeys [soundOn] (off ⇒ everything is silent). On by
  /// default. Gates [TtsService.speak] via the mirror in main.dart.
  bool get narrationOn => _narrationOn;

  /// Auto-read tutorials: when on, each tutorial step is narrated aloud as it
  /// becomes visible (hands-free for a pre-reader). Opt-in — **off by default**
  /// so narration is never a surprise; still obeys [narrationOn]/[soundOn].
  bool get autoReadTutorials => _autoReadTutorials;

  /// The additive timbre for pitched playback (the classic 4-way choice; also
  /// the fallback when a richer [voice] is selected).
  Instrument get instrument => _instrument;

  /// The selected voice id — an additive id (piano/cello/flute/musicBox), a
  /// procedural [kTrackerInstruments] id (chiptune/pluck/FM/…), or a library
  /// ref. Drives AudioService in main.dart.
  String get voiceId => _voiceId;

  /// The resolved procedural/sampled voice override, or null for the four
  /// additive voices (which play the classic path). Wired to AudioService.voice.
  TrackerInstrument? get voice => _voice;

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

  /// Note-name reading scaffold: when on, the note's letter is drawn under each
  /// notehead in games where naming isn't the task (rhythm/articulation/beaming)
  /// and in the Workshop — a fade-away aid for a child still learning the staff,
  /// spelled per the [noteNaming] setting. Off by default; sibling of
  /// [colorScaffold]. Never shown on the note-naming quizzes (it would reveal the
  /// answer).
  bool get showNoteNames => _showNoteNames;

  /// Back-compat: the old boolean "handwritten notes" toggle mapped onto the
  /// Petaluma face. True iff Petaluma is selected.
  bool get handwrittenNotes => _scoreFont == ScoreFont.petaluma;

  /// Whether the Tab Workshop uses the small on-device AI model to finger a
  /// score→tab conversion more like a human (a ~1 MB download on first use).
  /// On by default; when OFF, tab conversion runs purely on the built-in
  /// heuristic arranger — no model download, no ONNX inference.
  bool get smartTabFingering => _smartTabFingering;

  /// Whether imported MOD/S3M modules bend pitch the way the Amiga hardware
  /// did — a fixed step in PERIOD, so a slide accelerates as it rises — rather
  /// than by a fixed musical interval.
  ///
  /// On by default because it is the measurably correct reading: libopenmpt,
  /// libxmp and micromod all do it, and it took our portamento fixtures from
  /// 0.55 to 1.000 against them. Off is the gentler reading, which some prefer
  /// on material never written for an Amiga.
  ///
  /// XM and IT are unaffected — they bend linearly by definition — and so are
  /// songs made in the app, which have their own profile.
  bool get authenticSlides => _authenticSlides;

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
    _scoreFont = ScoreFont.values.asNameMap()[fontName] ??
        ((prefs.getBool(_handwrittenKey) ?? false)
            ? ScoreFont.petaluma
            : ScoreFont.bravura);
    _soundOn = prefs.getBool(_soundOnKey) ?? true;
    _narrationOn = prefs.getBool(_narrationOnKey) ?? true;
    _autoReadTutorials = prefs.getBool(_autoReadTutorialsKey) ?? false;
    _showNoteNames = prefs.getBool(_showNoteNamesKey) ?? false;
    _smartTabFingering = prefs.getBool(_smartTabFingeringKey) ?? true;
    _authenticSlides = prefs.getBool(_authenticSlidesKey) ?? true;
    trackerAuthenticSlidesDefault = _authenticSlides;
    _applyScoreFont();
    // Voice: prefer the new full-palette key; migrate from the legacy 4-way
    // enum key when absent (old installs keep their chosen additive voice).
    _voiceId = prefs.getString(_voiceIdKey) ??
        prefs.getString(_instrumentKey) ??
        Instrument.piano.name;
    final resolved = resolveVoiceSync(_voiceId);
    _instrument = resolved.instrument;
    _voice = resolved.voice;
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

  Future<void> setAuthenticSlides(bool value) async {
    _authenticSlides = value;
    // Mirrored into the audio layer so module import stays a pure function
    // rather than reaching for a service. See [trackerAuthenticSlidesDefault].
    trackerAuthenticSlidesDefault = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authenticSlidesKey, value);
  }

  Future<void> setSmartTabFingering(bool value) async {
    _smartTabFingering = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_smartTabFingeringKey, value);
  }

  Future<void> setColorScaffold(bool value) async {
    _colorScaffold = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_colorScaffoldKey, value);
  }

  Future<void> setShowNoteNames(bool value) async {
    _showNoteNames = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showNoteNamesKey, value);
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

  Future<void> setNarrationOn(bool value) async {
    _narrationOn = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_narrationOnKey, value);
  }

  Future<void> setAutoReadTutorials(bool value) async {
    _autoReadTutorials = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoReadTutorialsKey, value);
  }

  Future<void> setInstrument(Instrument instrument) =>
      setVoiceId(instrument.name);

  /// Selects the global playback voice. A built-in id (additive or procedural)
  /// resolves itself; a library/asset voice passes its already-built
  /// [resolvedVoice] (and the id is persisted so it can be re-resolved later).
  Future<void> setVoiceId(
    String voiceId, {
    TrackerInstrument? resolvedVoice,
  }) async {
    _voiceId = voiceId;
    if (resolvedVoice != null) {
      _voice = resolvedVoice;
      _instrument = Instrument.piano; // fallback timbre; the override plays
    } else {
      final r = resolveVoiceSync(voiceId);
      _instrument = r.instrument;
      _voice = r.voice;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceIdKey, voiceId);
    // Keep the legacy enum key sane for any old consumer / downgrade.
    await prefs.setString(_instrumentKey, _instrument.name);
  }
}
