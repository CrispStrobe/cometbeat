// WS-X6 slice 3b — the clipboard survives the app closing.
//
// A thing called a clipboard that forgets everything on restart is a surprise,
// not a feature. But the interesting half of this is what CANNOT be kept and
// what the store does about it, because the tempting answers are all worse than
// losing the entry:
//
//   * writing an instrument's PCM here would build a second, hidden library
//     that goes stale the moment the real entry is edited;
//   * saving it to the real library behind the player's back puts things in
//     their instrument list they never asked for.
//
// So an instrument with no library entry is dropped on save and COUNTED, which
// is the one honest option — a caller can then offer "save these to My
// Instruments first", the action that actually fixes it.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:comet_beat/core/services/tray_store.dart';
import 'package:comet_beat/core/tray/tray.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TrayStore> _store({InstrumentLibraryStore? library}) async =>
    TrayStore(await SharedPreferences.getInstance(), library: library);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetProjectDocumentCodecs();
  });

  group('documents come back', () {
    test('through the same codec registry a project save uses', () async {
      // No new serialisation: a kind that gains a codec later starts persisting
      // for free.
      final tray = TrayService()
        ..add(
          kind: AppMode.loop,
          label: 'Slow one',
          document: const GrooveSpec(enabled: {'bass'}, tempoBpm: 75),
        );
      final store = await _store();
      await store.save(tray);

      final restored = TrayService();
      expect(await store.load(restored), 0, reason: 'nothing was lost');
      expect(restored.length, 1);
      expect(restored.items.single.label, 'Slow one');
      expect((restored.items.single.document! as GrooveSpec).tempoBpm, 75);
    });

    test('in the same order they were put on', () async {
      final tray = TrayService();
      for (final label in ['first', 'second', 'third']) {
        tray.add(
          kind: AppMode.loop,
          label: label,
          document: const GrooveSpec(enabled: {'bass'}),
        );
      }
      final store = await _store();
      await store.save(tray);

      final restored = TrayService();
      await store.load(restored);
      expect(
        restored.items.map((i) => i.label),
        ['third', 'second', 'first'],
        reason: 'newest first, exactly as it was',
      );
    });

    test('a kind with no codec simply does not survive', () async {
      // Not an error — and NOT a reason to refuse the whole save.
      resetProjectDocumentCodecs();
      final tray = TrayService()
        ..add(kind: AppMode.audio, label: 'a recording', document: 'raw')
        ..add(
          kind: AppMode.loop,
          label: 'a groove',
          document: const GrooveSpec(enabled: {'bass'}),
        );
      final store = await _store();
      await store.save(tray);

      final restored = TrayService();
      await store.load(restored);
      expect(restored.items.map((i) => i.label), ['a groove']);
    });
  });

  group('instruments come back by NAME, or not at all', () {
    test('one from the library is restored from its library entry', () async {
      final library = InstrumentLibraryStore();
      await library.save(
        SavedInstrument.fromSampleClip(
          SampleClip(name: 'Rhodes', sampleRate: 8000, pcm: Float64List(8)),
        ),
      );
      final tray = TrayService()
        ..addInstrument(
          label: 'Rhodes',
          instrument: SampleInstrument('Rhodes', Float64List(8)),
          libraryName: 'Rhodes',
        );
      final store = await _store(library: library);
      await store.save(tray);
      expect(store.unsavedCount, 0);

      final restored = TrayService();
      expect(await store.load(restored), 0);
      expect(restored.items.single.isInstrument, isTrue);
      expect(restored.items.single.libraryName, 'Rhodes');
    });

    test('one with NO library entry is dropped, and counted', () async {
      // A voice lifted off a track, or a sample taken from an Audio Editor
      // clip. Writing its PCM here would be a second hidden library.
      final tray = TrayService()
        ..addInstrument(
          label: 'From a clip',
          instrument: SampleInstrument('x', Float64List(8)),
        );
      final store = await _store();
      await store.save(tray);

      expect(store.unsavedCount, 1, reason: 'a caller can say so');
      final restored = TrayService();
      await store.load(restored);
      expect(restored.isEmpty, isTrue);
    });

    test('and the rest of the clipboard is kept anyway', () async {
      final tray = TrayService()
        ..add(
          kind: AppMode.loop,
          label: 'a groove',
          document: const GrooveSpec(enabled: {'bass'}),
        )
        ..addInstrument(
          label: 'unsaveable',
          instrument: SampleInstrument('x', Float64List(8)),
        );
      final store = await _store();
      await store.save(tray);
      expect(store.unsavedCount, 1);

      final restored = TrayService();
      await store.load(restored);
      expect(restored.items.map((i) => i.label), ['a groove']);
    });

    test('a library entry deleted since costs that row, not the clipboard',
        () async {
      final library = InstrumentLibraryStore();
      await library.save(
        SavedInstrument.fromSampleClip(
          SampleClip(name: 'Gone', sampleRate: 8000, pcm: Float64List(8)),
        ),
      );
      final tray = TrayService()
        ..add(
          kind: AppMode.loop,
          label: 'a groove',
          document: const GrooveSpec(enabled: {'bass'}),
        )
        ..addInstrument(
          label: 'Gone',
          instrument: SampleInstrument('Gone', Float64List(8)),
          libraryName: 'Gone',
        );
      final store = await _store(library: library);
      await store.save(tray);
      await library.delete('Gone');

      final restored = TrayService();
      expect(await store.load(restored), 1, reason: 'one row could not return');
      expect(restored.items.map((i) => i.label), ['a groove']);
    });
  });

  group('a broken store does not take the app with it', () {
    test('nonsense reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'tray_v1': 'not json'});
      final store = await _store();
      final tray = TrayService();
      expect(await store.load(tray), 0);
      expect(tray.isEmpty, isTrue);
    });

    test('an unreadable row costs that row only', () async {
      SharedPreferences.setMockInitialValues({
        'tray_v1': '[{"kind":"loop","label":"ok","doc":{}},'
            '{"kind":"nonsense","label":"bad"},7]',
      });
      final store = await _store();
      final tray = TrayService();
      final lost = await store.load(tray);
      expect(lost, greaterThanOrEqualTo(2));
    });
  });

  test('attach loads first, THEN follows changes', () async {
    // Attaching the listener before the load would notify its way through a
    // save per restored item, and the first would write a half-loaded
    // clipboard over the full one.
    final first = TrayService()
      ..add(
        kind: AppMode.loop,
        label: 'kept',
        document: const GrooveSpec(enabled: {'bass'}),
      );
    final store = await _store();
    await store.save(first);

    final second = TrayService();
    await store.attach(second);
    expect(second.items.map((i) => i.label), ['kept']);

    // And from here on it saves itself.
    second.add(
      kind: AppMode.loop,
      label: 'added later',
      document: const GrooveSpec(enabled: {'drums'}),
    );
    await Future<void>.delayed(Duration.zero);

    final third = TrayService();
    await store.load(third);
    expect(third.items.map((i) => i.label), ['added later', 'kept']);
  });
}
