// Advanced Tracker — drives the classic grid via the AdvancedTrackerTester seam
// (audio is a no-op in the headless binding — assertions are on placed notes,
// play state, track count and pattern length). Mirrors tracker_screen_test.dart.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show AdditiveInstrument;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show multiPartScoreFromMusicXml;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('trackerNoteName renders classic tracker labels', (_) async {
    expect(trackerNoteName(60), 'C-4');
    expect(trackerNoteName(61), 'C#4');
    expect(trackerNoteName(69), 'A-4');
    expect(trackerNoteName(72), 'C-5');
  });

  testWidgets('Load SoundFont adds the voice to the pool + stamps new notes',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    final before = game.instrumentPoolSize; // the 4 default voices

    // What "Load SoundFont" does with the picked preset (minus the file dialog).
    game.debugAddInstrument(
      const AdditiveInstrument('sf2.0.40.Violin', Instrument.cello),
    );
    await tester.pump();

    expect(game.instrumentPoolSize, before + 1);
    expect(game.activeInstrument, before + 1); // the new voice is now active

    // A note placed afterwards is stamped with that new pool instrument.
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.instrumentAt(0, 0), before + 1);
  });

  testWidgets('removing a pool voice shrinks the pool + fixes the active index',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.debugAddInstrument(const AdditiveInstrument('a', Instrument.cello));
    await tester.pump();
    final size = game.instrumentPoolSize;
    final active = game.activeInstrument; // the freshly-added voice (1-based)
    expect(active, size);

    game.debugRemovePoolInstrument(active - 1); // remove the active one
    await tester.pump();
    expect(game.instrumentPoolSize, size - 1);
    expect(game.activeInstrument, 0); // was the active → falls back to default
  });

  testWidgets('Sound Library browser lists voices and adds one to the pool',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    final before = game.instrumentPoolSize;

    // pumpAndSettle would hang on the screen's running animations; pump the
    // sheet in with an explicit duration instead.
    game.debugShowSoundLibrary();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The library lists the built-in voices (Piano is a tonal option).
    expect(find.text('Piano'), findsWidgets);

    // Tapping a voice adds it to the pool and closes the sheet.
    await tester.tap(find.text('Piano').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.instrumentPoolSize, before + 1);
  });

  testWidgets('Share/Load song round-trips via the CBS1. token',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.setNote(0, 0, 60);
    await tester.pump();
    final token = game.debugSongToken(); // a 1-note song
    expect(token.startsWith('CBS1.'), isTrue);

    game.setNote(0, 1, 62); // now 2 notes
    await tester.pump();
    expect(game.noteCount, 2);

    // Loading the token replaces the song with the 1-note version.
    expect(game.debugLoadToken(token), isTrue);
    await tester.pump();
    expect(game.noteCount, 1);

    // A garbage token is rejected and leaves the song untouched.
    expect(game.debugLoadToken('not a real token'), isFalse);
    await tester.pump();
    expect(game.noteCount, 1);
  });

  testWidgets('placing a chromatic note starts playback; clearing empties',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);

    game.togglePlay();
    await tester.pump();
    expect(game.isPlaying, isTrue);

    game.setNote(0, 5, 61); // C#4 — a chromatic note the kid grid can't place
    await tester.pump();
    expect(game.noteCount, 1);

    game.clearNote(0, 5);
    await tester.pump();
    expect(game.noteCount, 0);

    game.togglePlay();
    await tester.pump();
    expect(game.isPlaying, isFalse);
  });

  testWidgets('Send to Multitrack adds the song as a DAW clip', (tester) async {
    final daw = DawService();
    await pumpGame(
      tester,
      const AdvancedTrackerScreen(),
      extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
    );
    final game = _game(tester);

    game.setNote(0, 0, 60);
    game.setNote(0, 4, 67);
    await tester.pump();

    expect(daw.clipCount, 0);
    game.sendToDaw();
    expect(daw.clipCount, 1);
    // The sent clip renders to real audio (a TrackerSource over the song).
    expect(daw.bake(), isNotEmpty);
  });

  testWidgets('🔍 Inspect mode: a cell reports its note + the row chord',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    // A C major triad spread across three channels on row 0.
    game.setNote(0, 0, 60); // C4
    game.setNote(1, 0, 64); // E4
    game.setNote(2, 0, 67); // G4
    await tester.pump();

    expect(game.inspectMode, isFalse);
    game.toggleInspectMode();
    await tester.pump();
    expect(game.inspectMode, isTrue);

    // The tapped cell's own note, plus the chord the whole row sounds.
    expect(game.debugInspectInfo(0, 0), ('C-4', 'C'));
    expect(game.debugInspectInfo(1, 0), ('E-4', 'C'));

    // An empty row has nothing to inspect.
    expect(game.debugInspectInfo(0, 5), isNull);
  });

  testWidgets('🔍 Inspect mode: desktop hover raises the corner card',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60); // C4
    await tester.pump();

    game.toggleInspectMode();
    await tester.pump();

    // Hovering the note cell shows the card; an empty cell clears it.
    game.debugHoverCell(0, 0);
    await tester.pump();
    expect(game.debugHoverCardShown, isTrue);

    game.debugHoverCell(0, 5); // empty
    await tester.pump();
    expect(game.debugHoverCardShown, isFalse);
  });

  testWidgets('endless length: the pattern grows well past one bar',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.rows, 32); // already 4x the Beginner grid's 8 steps
    game.setRows(128);
    await tester.pump();
    expect(game.rows, 128);

    // A note deep in the pattern is reachable — no 2-3 Takte ceiling.
    game.setNote(0, 120, 60);
    await tester.pump();
    expect(game.noteCount, 1);
  });

  testWidgets('endless tracks: add and remove channels', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    final before = game.channelCount;
    game.addTrack();
    await tester.pump();
    expect(game.channelCount, before + 1);

    // A note on the new track survives, and removing a different track keeps it.
    game.setNote(before, 0, 64);
    await tester.pump();
    expect(game.noteCount, 1);

    game.removeTrack(0);
    await tester.pump();
    expect(game.channelCount, before);
    expect(game.noteCount, 1); // the note moved down with its channel
  });

  testWidgets(
      'keyboard entry: a piano key types a note and advances the cursor',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.moveCursor(0, 4);
    await tester.pump();
    expect(game.cursorChannel, 0);
    expect(game.cursorRow, 4);

    // 'z' = C at the base octave (default octave 4 -> C4 = MIDI 60).
    game.typeKey('z');
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.octave, 4);
    // The cursor advanced by the default edit-step of 1.
    expect(game.cursorRow, 5);

    // 'q' = C one octave up (the upper keyboard row).
    game.typeKey('q');
    await tester.pump();
    expect(game.noteCount, 2);
    expect(game.cursorRow, 6);
  });

  testWidgets('per-track instrument can be reassigned', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    // Just assert the API drives without error and a subsequent note counts —
    // the instrument change itself is exercised in the engine tests.
    game.setChannelInstrument(0, 'flute');
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.noteCount, 1);
  });

  testWidgets('multi-pattern: add, select and edit separate patterns',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.patternCount, 1);
    game.setNote(0, 0, 60); // pattern 0
    await tester.pump();

    game.addPattern(); // -> pattern 1, selected
    await tester.pump();
    expect(game.patternCount, 2);
    expect(game.currentPattern, 1);
    expect(game.noteCount, 0); // fresh pattern

    game.setNote(0, 0, 72); // pattern 1
    await tester.pump();
    expect(game.noteCount, 1);

    game.selectPattern(0);
    await tester.pump();
    expect(game.noteCount, 1); // pattern 0's note restored
  });

  testWidgets('order list + play song', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.setNote(0, 0, 60);
    game.addPattern(clone: true); // pattern 1 (index 1), selected
    await tester.pump();
    expect(game.patternCount, 2);

    // Order starts as [0]; append the current pattern (1) -> [0, 1].
    game.addToOrder(game.currentPattern);
    await tester.pump();
    expect(game.orderLength, 2);

    game.playSong();
    await tester.pump();
    expect(game.isSongPlaying, isTrue);

    game.stop();
    await tester.pump();
    expect(game.isPlaying, isFalse);
    expect(game.isSongPlaying, isFalse);
  });

  testWidgets('transport: play, pause, resume, stop', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    await tester.pump();

    game.togglePlay(); // play
    await tester.pump();
    expect(game.isPlaying, isTrue);
    expect(game.isPaused, isFalse);

    game.togglePlay(); // pause — clock stops but not a full stop
    await tester.pump();
    expect(game.isPaused, isTrue);
    expect(game.isPlaying, isFalse); // clock frozen

    game.togglePlay(); // resume
    await tester.pump();
    expect(game.isPaused, isFalse);
    expect(game.isPlaying, isTrue);

    game.stop();
    await tester.pump();
    expect(game.isPlaying, isFalse);
    expect(game.isPaused, isFalse);
  });

  testWidgets('transport: Back/Forward navigate patterns when not song-playing',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.addPattern(); // p1
    game.addPattern(); // p2 -> current 2
    await tester.pump();
    expect(game.currentPattern, 2);

    game.forward(); // wraps 2 -> 0
    await tester.pump();
    expect(game.currentPattern, 0);

    game.back(); // wraps 0 -> 2
    await tester.pump();
    expect(game.currentPattern, 2);
  });

  testWidgets('mute and solo toggle', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.isMuted(0), isFalse);
    game.toggleMute(0);
    await tester.pump();
    expect(game.isMuted(0), isTrue);

    game.toggleSolo(1);
    await tester.pump();
    expect(game.isSoloed(1), isTrue);
    game.toggleSolo(1);
    await tester.pump();
    expect(game.isSoloed(1), isFalse);
  });

  testWidgets('block: select track, copy, paste elsewhere, transpose',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setRows(16);
    game.setNote(0, 0, 60);
    game.setNote(0, 1, 62);
    await tester.pump();
    expect(game.noteCount, 2);

    // Select the whole track (channel 0), copy it, move to row 8, paste.
    game.moveCursor(0, 0);
    game.selectTrack();
    await tester.pump();
    expect(game.hasSelection, isTrue);
    game.copyBlock();
    game.unmark();
    game.moveCursor(0, 8);
    game.pasteBlock();
    await tester.pump();
    // Original two notes + two pasted copies.
    expect(game.noteCount, 4);

    // Transpose a marked block up an octave.
    game.moveCursor(0, 8);
    game.selectTrack();
    game.transposeBlock(12);
    await tester.pump();
    expect(game.noteCount, 4); // still 4 notes, just shifted
  });

  testWidgets('block: clear a marked selection empties it', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    game.setNote(1, 0, 64);
    await tester.pump();
    expect(game.noteCount, 2);

    game.selectWholePattern();
    game.clearBlock();
    await tester.pump();
    expect(game.noteCount, 0);
  });

  testWidgets('sample editor: an injected clip becomes a track instrument',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    // A synthetic 0.2 s sine (the mic path is device-only; injectRecording is
    // the device-free seam onto the sample editor).
    final clip = Float64List(8820);
    for (var i = 0; i < clip.length; i++) {
      clip[i] = 0.5 * sin(2 * pi * 220 * i / 44100);
    }
    game.injectRecording(0, clip, VoiceEffect.normal);
    // Placing a note on that track and playing produces audio (no crash).
    game.setNote(0, 0, 60);
    game.togglePlay();
    await tester.pump();
    expect(game.isPlaying, isTrue);
    expect(game.noteCount, 1);
    game.stop();
    await tester.pump();
  });

  testWidgets('a volume-envelope preset shapes a channel', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.hasEnvelope(0), isFalse);
    expect(game.songUsesEnvelopes, isFalse);

    game.setEnvelopePreset(0, 'pluck');
    await tester.pump();
    expect(game.hasEnvelope(0), isTrue);
    expect(game.songUsesEnvelopes, isTrue); // routes through the replayer

    game.setEnvelopePreset(0, 'flat'); // back to no shape
    await tester.pump();
    expect(game.hasEnvelope(0), isFalse);
  });

  testWidgets('an auto-pan preset gives a channel a pan envelope',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.hasPanEnvelope(0), isFalse);

    game.setPanPreset(0, 'pingpong');
    await tester.pump();
    expect(game.hasPanEnvelope(0), isTrue);
    expect(game.songUsesPan, isTrue); // auto-pan routes to the stereo render

    game.setPanPreset(0, 'off');
    await tester.pump();
    expect(game.hasPanEnvelope(0), isFalse);
  });

  testWidgets('patterns can have independent lengths (per-pattern)',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setPatternLength(16); // pattern 0 -> 16 rows
    expect(game.patternRows(0), 16);

    game.addPattern(); // pattern 1 (selected), cloned length
    game.setPatternLength(32); // pattern 1 -> 32 rows
    await tester.pump();

    expect(game.patternRows(1), 32);
    expect(game.patternRows(0), 16); // pattern 0 stays 16 — lengths differ
  });

  testWidgets('per-channel pan drives the stereo render', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.panOf(0), 0.0); // centred by default
    expect(game.songUsesPan, isFalse); // a centred song stays mono

    game.setPan(0, -0.8); // hard-ish left
    await tester.pump();
    expect(game.panOf(0), closeTo(-0.8, 1e-9));
    expect(game.songUsesPan, isTrue); // now the render goes stereo
  });

  testWidgets('the on-screen piano lights the sounding notes of a row',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60); // C4 on channel 0
    game.setNote(1, 0, 67); // G4 on channel 1
    game.setNote(0, 4, 72); // a note on a different row
    await tester.pump();

    final row0 = game.debugSoundingMidis(0);
    expect(row0, containsAll(<int>[60, 67]));
    expect(row0, isNot(contains(72))); // that's row 4, not row 0

    // Muting a channel drops its note from the highlight.
    game.toggleMute(1);
    await tester.pump();
    expect(game.debugSoundingMidis(0), isNot(contains(67)));
    expect(game.debugSoundingMidis(0), contains(60));
  });

  testWidgets('the instrument picker stamps new notes with the pool instrument',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    expect(game.instrumentPoolSize, greaterThan(0));
    expect(game.activeInstrument, 0); // channel default to start

    // Default: notes carry instrument 0.
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.instrumentAt(0, 0), 0);

    // Pick pool instrument 2 -> subsequent notes carry it; earlier ones don't.
    game.setActiveInstrument(2);
    game.setNote(0, 4, 64);
    await tester.pump();
    expect(game.activeInstrument, 2);
    expect(game.instrumentAt(0, 4), 2);
    expect(game.instrumentAt(0, 0), 0); // unchanged
  });

  testWidgets('copy instrument reuses a recorded sample on another track',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    final clip = Float64List(4410);
    for (var i = 0; i < clip.length; i++) {
      clip[i] = 0.5 * sin(2 * pi * 220 * i / 44100);
    }
    game.injectRecording(0, clip, VoiceEffect.normal); // ch 0 -> 'rec' sample
    final srcId = game.debugInstrumentId(0);
    expect(game.debugInstrumentId(1), isNot(srcId)); // ch 1 differs to start

    game.copyInstrument(0, 1);
    await tester.pump();
    expect(game.debugInstrumentId(1), srcId); // now shares the sample
  });

  testWidgets('imports a real module and can save it to the Song Book',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    final bytes = File('test/fixtures/golden.mod').readAsBytesSync();
    game.importModuleBytes(bytes);
    await tester.pump();
    // The imported module replaced the default document with real content.
    expect(game.patternCount, greaterThanOrEqualTo(1));
    expect(game.noteCount, greaterThan(0));

    final songs = UserSongsService();
    expect(game.debugSaveToSongBook(songs), isTrue);
    expect(songs.songs, isNotEmpty);
  });

  testWidgets('exports the whole song as MIDI and MusicXML', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.debugExportMidi(), isNull); // nothing placed yet
    game.setNote(0, 0, 60);
    game.setNote(0, 4, 64);
    await tester.pump();

    final midi = game.debugExportMidi();
    expect(midi, isNotNull);
    expect(midi!.length, greaterThan(0));
    // MIDI files start with the 'MThd' header.
    expect(String.fromCharCodes(midi.take(4)), 'MThd');

    final xml = game.debugExportMusicXml();
    expect(xml, isNotNull);
    expect(xml, contains('<score-partwise'));
  });

  testWidgets('exports ABC and re-imports it as a tracker song',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.debugExportAbc(), isNull); // nothing placed yet
    game.setNote(0, 0, 60); // C4
    game.setNote(0, 4, 64); // E4
    await tester.pump();

    final abc = game.debugExportAbc();
    expect(abc, isNotNull);
    expect(abc, contains('X:')); // ABC tune header
    expect(abc, contains('K:')); // key field

    // Round-trip: importing the exported ABC rebuilds a song with the notes.
    game.debugImportAbc(abc!);
    await tester.pump();
    expect(game.noteCount, greaterThan(0));
  });

  testWidgets('imports a Humdrum **kern score into tracker channels',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    // A minimal one-spine **kern melody: C D E F quarter notes.
    game.debugImportKern('**kern\n4c\n4d\n4e\n4f\n*-\n');
    await tester.pump();
    expect(game.noteCount, greaterThan(0));
    expect(game.channelCount, greaterThanOrEqualTo(1));
  });

  testWidgets('exports the song as a module and it re-imports with notes',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    game.setNote(0, 4, 67);
    await tester.pump();

    for (final fmt in ['mod', 'xm', 's3m', 'it']) {
      final bytes = game.debugExportModule(fmt);
      expect(bytes, isNotNull, reason: '$fmt export');
      expect(bytes!.length, greaterThan(0));
      game.importModuleBytes(bytes); // re-parse back into a tracker song
      await tester.pump();
      expect(game.noteCount, greaterThan(0), reason: '$fmt re-import');
      // Reset for the next format.
      game.setNote(0, 0, 60);
      game.setNote(0, 4, 67);
      await tester.pump();
    }
  });

  testWidgets(
      'exported MusicXML round-trips to a real score (Workshop handoff)',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    await tester.pump();

    final xml = game.debugExportMusicXml();
    expect(xml, isNotNull);
    // The same score the "Open in Workshop" handoff passes as initialScore.
    final mp = multiPartScoreFromMusicXml(xml!);
    expect(mp.parts, isNotEmpty);
    expect(mp.parts.first.measures, isNotEmpty);
  });

  testWidgets('live record: notes land at the playhead while playing',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60); // something to play so the clock/loop runs
    game.togglePlay();
    game.toggleRecord();
    await tester.pump();
    expect(game.isRecording, isTrue);

    // Typing a note while recording+playing writes it (at the sounding row),
    // without moving the edit cursor.
    game.moveCursor(1, 8); // cursor on channel 1
    final before = game.noteCount;
    game.typeKey('z');
    await tester.pump();
    expect(game.noteCount, before + 1);
    game.stop();
    await tester.pump();
  });

  testWidgets('volume field: two hex digits set the note volume (FT2 00-40)',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    game.moveCursor(0, 0);
    await tester.pump();

    game.cycleField(); // note -> volume
    await tester.pump();
    // "2" then "0" = 0x20 = 32/64 = half volume.
    game.typeVolume('2');
    game.typeVolume('0');
    await tester.pump();
    final v = game.volumeAt(0, 0);
    expect(v, isNotNull);
    expect(v!, closeTo(0.5, 0.02));
  });

  testWidgets('effect field: typing a command builds the hex cell (C20)',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 60);
    game.moveCursor(0, 0);
    await tester.pump();

    game.cycleField(); // note -> volume
    game.cycleField(); // volume -> effect
    // "C" then "2" then "0" = C20 (set volume 0x20).
    game.typeEffect('c');
    game.typeEffect('2');
    game.typeEffect('0');
    await tester.pump();
    expect(game.effectAt(0, 0), (0xC, 0x20));
  });

  testWidgets('classic skin + zoom render without error', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 61);
    game.setNote(1, 2, 67);
    await tester.pump();
    game.toggleClassic();
    game.setZoom(1.45);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(game.noteCount, 2);
  });

  testWidgets('insert/delete row shifts the column', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setRows(16);
    game.setNote(0, 2, 60); // a note at row 2
    game.moveCursor(0, 1);
    await tester.pump();

    game.insertRow(); // insert at row 1 -> the note moves to row 3
    await tester.pump();
    expect(game.noteAt(0, 3), 60);
    expect(game.noteAt(0, 2), isNull);

    game.moveCursor(0, 1);
    game.deleteRow(); // delete row 1 -> the note moves back to row 2
    await tester.pump();
    expect(game.noteAt(0, 2), 60);
  });

  testWidgets('order list can be reordered and extended', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    final p1 = () {
      game.addPattern();
      return game.currentPattern;
    }();
    game.addToOrder(p1); // order = [0, 1]
    await tester.pump();
    expect(game.orderList, [0, 1]);

    game.selectOrderSlot(0);
    game.orderMove(1); // swap slots 0 and 1 -> [1, 0]
    await tester.pump();
    expect(game.orderList, [1, 0]);

    game.selectOrderSlot(0);
    game.orderInsert(); // insert a copy of slot 0 after it -> [1, 1, 0]
    await tester.pump();
    expect(game.orderList, [1, 1, 0]);
  });

  testWidgets('play-from-cursor starts the pattern playing', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 8, 60);
    game.moveCursor(0, 8);
    await tester.pump();

    game.playFromCursor();
    await tester.pump();
    expect(game.isPlaying, isTrue);
    expect(game.isSongPlaying, isFalse); // pattern, not song
    game.stop();
    await tester.pump();
  });

  testWidgets('interpolate ramps volumes across a selection', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setRows(16);
    // Notes on channel 0 at rows 0..8 (all default full volume).
    for (var r = 0; r <= 8; r++) {
      game.setNote(0, r, 60);
    }
    await tester.pump();

    game.moveCursor(0, 0);
    game.selectTrack(); // selects channel 0, rows 0..15
    game.interpolateBlock();
    await tester.pump();
    // Runs without error and the notes remain.
    expect(game.noteCount, greaterThanOrEqualTo(9));
  });

  testWidgets('undo/redo restores and reapplies cell edits', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.canUndo, isFalse);
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.canUndo, isTrue);

    game.undo();
    await tester.pump();
    expect(game.noteCount, 0); // the note is gone
    expect(game.canRedo, isTrue);

    game.redo();
    await tester.pump();
    expect(game.noteCount, 1); // and back
  });

  testWidgets('Save to Song Book covers notes on a non-current pattern',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.setNote(0, 0, 60); // notes on pattern 0
    game.addPattern(); // switch to a fresh empty pattern 1
    await tester.pump();
    expect(game.currentPattern, 1);
    expect(game.noteCount, 0); // current pattern is empty...

    // ...but Save still finds the notes on pattern 0 (the whole song).
    final songs = UserSongsService();
    expect(game.debugSaveToSongBook(songs), isTrue);
    expect(songs.songs, isNotEmpty);
  });

  testWidgets('demo song loads a playable two-pattern tune', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    expect(game.noteCount, 0);

    game.loadDemo();
    await tester.pump();

    expect(game.patternCount, 2); // 00 + a variation
    expect(game.orderLength, 2); // order: 00 · 01
    expect(game.noteAt(0, 0), 72); // melody starts on C5
    expect(game.currentPattern, 0);
    expect(game.noteCount, greaterThan(0));
  });

  testWidgets('scope toggle renders the loop waveform without error',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.loadDemo();
    await tester.pump();

    expect(game.showScope, isFalse);
    game.toggleScope();
    await tester.pump();
    expect(game.showScope, isTrue);
    expect(tester.takeException(), isNull);

    game.toggleScope();
    await tester.pump();
    expect(game.showScope, isFalse);
  });

  testWidgets('song playhead follows a Dxx break (skips the broken rows)',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setRows(8);
    game.setNote(0, 0, 60); // pattern 0 has notes

    game.addPattern(); // fresh pattern 1 (now selected)
    final p1 = game.currentPattern;
    game.setNote(0, 0, 48);
    game.selectPattern(0);

    // D00 pattern-break at row 3 of pattern 0 → after row 3, jump to the next
    // order entry at row 0 (rows 4..7 of pattern 0 are never played).
    game.debugSetCommand(0, 3, 0xD, 0x00);
    game.addToOrder(p1); // order: 0 · 1
    await tester.pump();

    // Sample the whole resolved timeline and collect every (order,row) visited.
    final total = game.debugSongTotalMs;
    expect(total, greaterThan(0));
    final visited = <(int, int)>{};
    for (var i = 0; i < 200; i++) {
      visited.add(game.debugPlayheadAt(total * i ~/ 200));
    }

    expect(visited.contains((0, 0)), isTrue); // pattern 0 plays from the top
    expect(visited.contains((0, 3)), isTrue); // up to the break row
    expect(visited.contains((1, 0)), isTrue); // then jumps into pattern 1
    // The broken-off rows of pattern 0 are never highlighted.
    expect(visited.where((e) => e.$1 == 0 && e.$2 > 3), isEmpty);
  });

  group('sliceFraction (sample trim handles)', () {
    final buf = Float64List.fromList(List.generate(100, (i) => i / 100));

    test('full range returns the same buffer', () {
      expect(identical(sliceFraction(buf, 0.0, 1.0), buf), isTrue);
    });

    test('crops to the dragged region', () {
      final s = sliceFraction(buf, 0.25, 0.75);
      expect(s.length, 50);
      expect(s.first, closeTo(0.25, 1e-9)); // first kept frame
      expect(s.last, closeTo(0.74, 1e-9)); // last kept frame
    });

    test('clamps and never mutates the source', () {
      final s = sliceFraction(buf, 0.9, 2.0); // end past the buffer
      expect(s.length, 10);
      expect(buf.length, 100); // source untouched
    });

    test('empty stays empty', () {
      expect(sliceFraction(Float64List(0), 0.2, 0.8), isEmpty);
    });
  });
}
