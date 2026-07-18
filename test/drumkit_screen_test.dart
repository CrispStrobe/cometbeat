// Drumkit / BoomBox — the step beat-grid over a shared DrumRowsPattern.
// Audio is a no-op in the headless binding; assertions are on the grid + state.

import 'package:comet_beat/core/audio/beat_capture.dart' show BeatFrame;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/features/games/drums/drumkit_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DrumkitTester _kit(WidgetTester tester) =>
    tester.state<State<DrumkitScreen>>(find.byType(DrumkitScreen))
        as DrumkitTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling grid cells builds the beat', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.steps, 16);
    expect(kit.hitCount, 0);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.kick, 8);
    kit.toggle(Drum.snare, 4);
    await tester.pump();

    expect(kit.hitCount, 3);
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 8), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.cellAt(Drum.hat, 0), isFalse);

    kit.toggle(Drum.kick, 0); // off again
    await tester.pump();
    expect(kit.hitCount, 2);
  });

  testWidgets('play/stop + clear + tempo + pad tap do not crash',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.toggle(Drum.kick, 0);
    kit.setTempo(120);
    expect(kit.tempo, 120);

    kit.tapPad(Drum.snare); // one-shot audition (no-op audio)
    kit.togglePlay();
    await tester.pump();
    kit.stop();
    await tester.pump();
    expect(kit.isPlaying, isFalse);

    kit.clear();
    await tester.pump();
    expect(kit.hitCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap-to-record quantises loose taps onto the eighth grid',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.setTempo(120); // beatMs 500 → an eighth step is 250 ms
    await tester.pump();

    // Loose taps: kick on beats 1 & 2 (with a stray near-duplicate), snare on
    // the "and of 1". Loop-relative ms.
    kit.debugRecordTaps([
      (drum: Drum.kick, ms: 12), // → step 0
      (drum: Drum.kick, ms: 28), // near-dup → collapses onto step 0
      (drum: Drum.snare, ms: 258), // → step 1 (not over-quantised to the beat)
      (drum: Drum.kick, ms: 505), // → step 2
    ]);
    await tester.pump();

    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 2), isTrue);
    expect(kit.cellAt(Drum.snare, 1), isTrue);
    // The stray double-kick collapsed → kick has just two hits.
    expect(kit.hitCount, 3);
    expect(kit.isRecording, isFalse);
  });

  testWidgets('beatbox capture classifies each hit and quantises onto the grid',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.setTempo(120); // beatMs 500 → eighth step 250 ms
    await tester.pump();

    // A quiet frame then a loud attack per hit (detectOnsets needs the rise).
    // kick @ 250 ms (low pitch), snare @ 1000 (mid zcr), hat @ 1500 (bright).
    kit.debugBeatboxFrames(const <BeatFrame>[
      (ms: 240, rms: 0.005, zcr: 0.0, pitchedLow: false),
      (ms: 250, rms: 0.30, zcr: 0.01, pitchedLow: true), // → kick, step 1
      (ms: 990, rms: 0.005, zcr: 0.0, pitchedLow: false),
      (ms: 1000, rms: 0.30, zcr: 0.45, pitchedLow: false), // → snare, step 4
      (ms: 1490, rms: 0.005, zcr: 0.0, pitchedLow: false),
      (ms: 1500, rms: 0.30, zcr: 0.67, pitchedLow: false), // → hat, step 6
    ]);
    await tester.pump();

    expect(kit.cellAt(Drum.kick, 1), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.cellAt(Drum.hat, 6), isTrue);
    expect(kit.hitCount, 3);
    expect(kit.isListening, isFalse);
  });

  testWidgets('the beat saves to the Song Book as a rhythm-line score',
      (tester) async {
    final songs = UserSongsService();
    await pumpGame(
      tester,
      const DrumkitScreen(),
      extraProviders: [
        ChangeNotifierProvider<UserSongsService>.value(value: songs),
      ],
    );
    final kit = _kit(tester);

    // Empty grid → nothing to save.
    expect(kit.debugMusicXml(), isNull);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.kick, 8);
    kit.toggle(Drum.hat, 4);
    await tester.pump();

    expect(songs.songs, isEmpty);
    final xml = kit.debugSaveToSongBook(songs);
    expect(xml, isNotNull);
    expect(xml, contains('<score-partwise'));
    expect(songs.songs, hasLength(1));
    expect(songs.songs.single.musicXml, contains('<score-partwise'));
  });
}
