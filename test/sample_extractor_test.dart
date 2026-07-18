// The module Sample Extractor — build a real .mod carrying a sample, extract
// it back, and drive the screen (batch load + add-to-library) via its seam.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertToMod;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

// A .mod with one non-empty sample (named [name]) referenced by one note.
Uint8List _moduleWith(String name, {int len = 64}) {
  final pcm = Float64List.fromList([
    for (var i = 0; i < len; i++) 0.6 * math.sin(2 * math.pi * i / 16),
  ]);
  final doc = ModuleDoc(
    title: 'FIXTURE',
    channelCount: 4,
    sourceFormat: ModuleFormat.mod,
    order: const [0],
    patterns: [
      const DocPattern(
        [
          [
            DocCell(note: 60, instrument: 1),
            DocCell.empty,
            DocCell.empty,
            DocCell.empty,
          ],
        ],
        4,
      ),
    ],
    samples: [DocSample(name: name, pcm: pcm)],
  );
  return convertToMod(doc);
}

SampleExtractorTester _screen(WidgetTester tester) =>
    tester.state<State<SampleExtractorScreen>>(
      find.byType(SampleExtractorScreen),
    ) as SampleExtractorTester;

void main() {
  group('extractModuleSamples (pure)', () {
    test('recovers a module\'s named sample as non-empty PCM', () {
      final out = extractModuleSamples(_moduleWith('sine'), moduleName: 'song');
      expect(out, isNotEmpty);
      final s = out.first;
      expect(s.displayName, 'sine');
      expect(s.moduleName, 'song');
      expect(s.pcm, isNotEmpty);
      expect(s.sampleRate, greaterThan(0));
    });

    test('empty sample slots are skipped', () {
      // A module whose only sample is empty yields nothing.
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.mod,
        order: const [0],
        patterns: [
          const DocPattern([[]], 4),
        ],
        samples: [DocSample.empty()],
      );
      expect(extractModuleSamples(convertToMod(doc)), isEmpty);
    });

    test('unrecognized bytes throw a FormatException', () {
      expect(
        () => extractModuleSamples(Uint8List.fromList([1, 2, 3, 4])),
        throwsFormatException,
      );
    });

    test('toClip prefixes the module name and carries the rate', () {
      final s =
          extractModuleSamples(_moduleWith('kick'), moduleName: 'demo').first;
      final clip = s.toClip();
      expect(clip.name, contains('demo'));
      expect(clip.name, contains('kick'));
      expect(clip.sampleRate, s.sampleRate);
    });
  });

  group('uniqueWavNames (pure)', () {
    test('sanitizes and de-duplicates collisions', () {
      final names = uniqueWavNames(['kick', 'kick', 'sn@re!', 'kick']);
      expect(names, ['kick.wav', 'kick-2.wav', 'snre.wav', 'kick-3.wav']);
    });

    test('blank/illegal names fall back to "sample"', () {
      expect(
        uniqueWavNames(['', '***', 'ok']),
        ['sample.wav', 'sample-2.wav', 'ok.wav'],
      );
    });
  });

  group('SampleExtractorScreen (seam)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('loads modules (batch), reports failures, adds to library',
        (tester) async {
      await pumpGame(tester, const SampleExtractorScreen());
      final s = _screen(tester);

      s.debugLoad(_moduleWith('one'), 'a');
      s.debugLoad(_moduleWith('two'), 'b');
      s.debugLoad(Uint8List.fromList([9, 9, 9]), 'broken'); // unreadable
      await tester.pump();

      expect(s.samples.length, 2);
      expect(s.failedFiles, ['broken']);

      expect(s.librarySize, 0);
      await s.addToLibrary(0);
      await tester.pump();
      expect(s.librarySize, 1);
    });
  });
}
