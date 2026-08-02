// Persistence coverage for SettingsService — defaults on a fresh install and
// round-trips through SharedPreferences (a new instance reloads what was set).
// #3 of the TTS follow-up queue; there was no settings-persistence test before.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/harmony/chart_level.dart';
import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsService> _loaded() async {
  final s = SettingsService();
  await s.load();
  return s;
}

/// A fresh SettingsService that reloads the current SharedPreferences store.
Future<SettingsService> _reload() => _loaded();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults on a fresh install', () async {
    final s = await _loaded();
    expect(s.soundOn, isTrue);
    expect(s.narrationOn, isTrue);
    expect(s.autoReadTutorials, isFalse); // opt-in
    expect(s.showTimer, isFalse);
    expect(s.showNoteNames, isFalse);
    expect(s.smartTabFingering, isTrue);
    expect(s.colorScaffold, isFalse);
    expect(s.locale, isNull); // follow the system
    expect(s.noteNaming, NoteNaming.auto);
    expect(s.scoreFont, ScoreFont.bravura);
    expect(s.instrument, Instrument.piano);
  });

  test('the sound / narration / auto-read booleans round-trip', () async {
    final s = await _loaded();
    await s.setSoundOn(false);
    await s.setNarrationOn(false);
    await s.setAutoReadTutorials(true);
    // A brand-new instance reads the persisted values back.
    final r = await _reload();
    expect(r.soundOn, isFalse);
    expect(r.narrationOn, isFalse);
    expect(r.autoReadTutorials, isTrue);
  });

  test('narration is independent of sound in storage', () async {
    final s = await _loaded();
    await s.setSoundOn(true);
    await s.setNarrationOn(false);
    final r = await _reload();
    expect(r.soundOn, isTrue);
    expect(r.narrationOn, isFalse); // the two flags persist separately
  });

  test('the other UI booleans round-trip', () async {
    final s = await _loaded();
    await s.setShowTimer(true);
    await s.setShowNoteNames(true);
    await s.setSmartTabFingering(false);
    await s.setColorScaffold(true);
    final r = await _reload();
    expect(r.showTimer, isTrue);
    expect(r.showNoteNames, isTrue);
    expect(r.smartTabFingering, isFalse);
    expect(r.colorScaffold, isTrue);
  });

  test('enums round-trip: note naming + score font', () async {
    final s = await _loaded();
    await s.setNoteNaming(NoteNaming.germanH);
    await s.setScoreFont(ScoreFont.leland);
    final r = await _reload();
    expect(r.noteNaming, NoteNaming.germanH);
    expect(r.scoreFont, ScoreFont.leland);
    expect(r.handwrittenNotes, isFalse); // only Petaluma reads as handwritten
  });

  test('the handwritten-notes shim maps onto the score font', () async {
    final s = await _loaded();
    await s.setHandwrittenNotes(true);
    expect(s.scoreFont, ScoreFont.petaluma);
    expect(s.handwrittenNotes, isTrue);
    final r = await _reload();
    expect(r.scoreFont, ScoreFont.petaluma);
    expect(r.handwrittenNotes, isTrue);
  });

  test('locale round-trips and can be cleared back to system', () async {
    final s = await _loaded();
    await s.setLocale(const Locale('de'));
    expect((await _reload()).locale, const Locale('de'));
    await s.setLocale(null);
    expect((await _reload()).locale, isNull);
  });

  test('the voice id round-trips (and resolves an instrument)', () async {
    final s = await _loaded();
    await s.setVoiceId(Instrument.cello.name);
    final r = await _reload();
    expect(r.voiceId, Instrument.cello.name);
    expect(r.instrument, Instrument.cello);
  });

  test('the chart level round-trips, and defaults to learner', () async {
    // BB-U6. Stored as the NAME, so a future reordering of the enum cannot
    // reinterpret someone's saved setting as a different level.
    expect((await _loaded()).chartLevel, ChartLevel.learner);

    final s = await _loaded();
    await s.setChartLevel(ChartLevel.beginner);
    expect((await _reload()).chartLevel, ChartLevel.beginner);
    await s.setChartLevel(ChartLevel.expert);
    expect((await _reload()).chartLevel, ChartLevel.expert);
  });

  test('an unreadable stored level falls back to learner, not to beginner',
      () async {
    // A corrupt or future value must not silently drop an experienced player
    // onto the most restricted surface.
    // First prove the mechanism reads the store at all — otherwise the
    // fallback assertion below would pass for the wrong reason.
    SharedPreferences.setMockInitialValues({'chart_level': 'expert'});
    expect((await _loaded()).chartLevel, ChartLevel.expert);

    SharedPreferences.setMockInitialValues({'chart_level': 'wizard'});
    expect((await _loaded()).chartLevel, ChartLevel.learner);
  });
}
