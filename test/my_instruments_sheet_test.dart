// The "My Instruments" browser — lists saved instruments, deletes, and (when
// pickable) resolves to a pick. Uses the real InstrumentLibraryStore seeded via
// the engine codec, so it exercises the whole save→browse path.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/features/games/songs/song_book.dart' show kSongs;
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/instrument_play_screen.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

SavedInstrument _saved(String name) {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SavedInstrument(
    name: name,
    json: instrumentToJsonString(SampleInstrument(name, pcm)),
    source: 'Voice Lab',
  );
}

MyInstrumentsTester _sheet(WidgetTester tester) =>
    tester.state<State<MyInstrumentsSheet>>(find.byType(MyInstrumentsSheet))
        as MyInstrumentsTester;

Widget _hosted(Widget child) => Scaffold(body: child);

class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this.file);

  final XFile file;
  bool opened = false;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opened = true;
    return file;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists saved instruments with source + kind', (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('bell'));
    await store.save(_saved('pluck'));
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();

    expect(_sheet(tester).instruments.map((s) => s.name), ['bell', 'pluck']);
    expect(find.text('bell'), findsOneWidget);
    expect(find.textContaining('Voice Lab'), findsWidgets); // source shown
  });

  testWidgets('deleting removes it from the store', (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('one'));
    await store.save(_saved('two'));
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();

    await _sheet(tester).deleteAt(0);
    await tester.pumpAndSettle();

    expect(_sheet(tester).instruments.map((s) => s.name), ['two']);
    expect((await InstrumentLibraryStore().load()).map((s) => s.name), ['two']);
  });

  testWidgets('empty library explains how to fill it', (tester) async {
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();
    expect(_sheet(tester).instruments, isEmpty);
    expect(find.textContaining('No saved instruments'), findsOneWidget);
  });

  test('renderInstrumentNote is non-silent across an octave', () {
    final inst = _saved('x').instrument!;
    for (final midi in const [60, 62, 64, 65, 67, 69, 71, 72]) {
      final pcm = renderInstrumentNote(inst, midi);
      var peak = 0.0;
      for (final s in pcm) {
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, greaterThan(0.01), reason: 'silent at midi $midi');
    }
    // a higher note is genuinely different audio, not the same buffer
    expect(
      renderInstrumentNote(inst, 72),
      isNot(renderInstrumentNote(inst)),
    );
  });

  testWidgets('the 🎹 button opens the live-play keyboard screen',
      (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('bell'));
    await pumpGame(
      tester,
      _hosted(MyInstrumentsSheet(store: InstrumentLibraryStore())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.piano));
    await tester.pumpAndSettle();

    expect(find.byType(InstrumentPlayScreen), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
  });

  testWidgets('New FX generates and saves an sfxr instrument into the library',
      (tester) async {
    final store = InstrumentLibraryStore();
    await pumpGame(tester, _hosted(MyInstrumentsSheet(store: store)));
    await tester.pumpAndSettle();

    // Open the "create" menu, then the FX generator, pick a preset, then save.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'laser'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final fx = (await store.load()).where((s) => s.kind == 'sfxr').toList();
    expect(fx, isNotEmpty);
    expect(fx.any((s) => s.name == 'laser' && s.category == 'FX'), isTrue);
  });

  testWidgets('Tracker module import uses the caller module destination',
      (tester) async {
    final previous = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final moduleBytes = Uint8List.fromList(const [1, 2, 3]);
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(moduleBytes, path: 'lesson.xm'),
    );
    Uint8List? received;

    await pumpGame(
      tester,
      _hosted(
        MyInstrumentsSheet(
          store: InstrumentLibraryStore(),
          onModuleSelected: (bytes) async => received = bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();

    expect((FileSelectorPlatform.instance as _FakeFileSelector).opened, isTrue);
    expect(
      (FileSelectorPlatform.instance as _FakeFileSelector).file.name,
      'lesson.xm',
    );
    expect(received, orderedEquals(moduleBytes));
  });

  testWidgets('rubric tabs filter the list by category', (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('bell')); // kind sample -> Samples
    await store.save(
      SavedInstrument(
        name: 'blip',
        json: instrumentToJsonString(
          SfxrInstrument('blip', kSfxrPresets['blip']!(math.Random(1))),
        ),
        source: 'FX',
      ),
    );
    await pumpGame(tester, _hosted(MyInstrumentsSheet(store: store)));
    await tester.pumpAndSettle();

    // Both visible under "All".
    expect(find.text('bell'), findsOneWidget);
    expect(find.text('blip'), findsOneWidget);
    // Tapping the FX tab hides the sample.
    await tester.tap(find.widgetWithText(ChoiceChip, 'FX'));
    await tester.pumpAndSettle();
    expect(find.text('blip'), findsOneWidget);
    expect(find.text('bell'), findsNothing);
  });

  testWidgets('saved samples expose an explicit audio-track insertion action',
      (tester) async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('voice'));
    SampleClip? inserted;
    await pumpGame(
      tester,
      _hosted(
        MyInstrumentsSheet(
          store: store,
          onSampleInsert: (clip) async => inserted = clip,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.playlist_add), findsOneWidget);
    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();

    expect(inserted, isNotNull);
    expect(inserted!.name, 'voice');
    expect(find.byType(MyInstrumentsSheet), findsNothing);
  });

  testWidgets('Sound Library exposes the music browser for Songs',
      (tester) async {
    var selected = false;
    await pumpGame(
      tester,
      _hosted(
        MyInstrumentsSheet(
          store: InstrumentLibraryStore(),
          onMusicSelected: (_) async => selected = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.library_music), findsOneWidget);
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
    expect(find.text('Add music'), findsOneWidget);

    await tester.tap(find.text(kSongs.first.title));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });
}
