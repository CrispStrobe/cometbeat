// Persisting a SoundFont preset as a `soundfont_ref` library voice, and
// resolving it back — the native (dart:io) round-trip that lets a chosen
// SoundFont preset become a reusable library / global voice. Uses a real
// minimal SF2 (sf2_fixture) and a temp cache dir (no ~/.cache pollution).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/soundfont_persist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sf2_fixture.dart';

void main() {
  test('soundFontPersistSupported is true on native', () {
    expect(soundFontPersistSupported, isTrue);
  });

  test(
      'persist a preset → soundfont_ref voice → resolves back to an instrument',
      () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('sf_persist');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final bytes = oneSampleSf2(
      pcm: sineI16(440, 20),
      sampleRate: 44100,
      rootKey: 60,
      loopStart: 0,
      loopEnd: 0,
    );
    final preset = loadSoundFont(bytes).presets.first;
    final store = InstrumentLibraryStore();

    final saved = await persistSoundFontPreset(
      fontBytes: bytes,
      bank: preset.bank,
      program: preset.program,
      presetName: preset.name,
      saveName: 'My SoundFont',
      store: store,
      cacheDir: tmp.path,
    );

    expect(saved, isNotNull);
    expect(
        saved!.isReference, isTrue); // saved as a soundfont_ref, not embedded
    expect(saved.category, 'SoundFonts');
    // it landed in the library
    expect((await store.load()).any((s) => s.name == 'My SoundFont'), isTrue);

    // and it rebuilds into a playable voice (re-reads the cached font file)
    final voice = await resolveSavedVoice(saved);
    expect(voice, isNotNull);
  });

  test('resolveSavedVoice returns an embedded (non-ref) voice directly',
      () async {
    SharedPreferences.setMockInitialValues({});
    final saved = SavedInstrument.fromSampleClip(
      SampleClip(
          name: 'clip',
          sampleRate: 22050,
          pcm: Float64List.fromList(const [0.0, 0.2, -0.2, 0.0])),
    );
    expect(saved.isReference, isFalse);
    expect(await resolveSavedVoice(saved), isNotNull);
  });
}
