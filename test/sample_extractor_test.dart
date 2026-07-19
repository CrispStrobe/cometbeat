// The module Sample Extractor — build a real .mod carrying a sample, extract
// it back, and drive the screen (batch load + add-to-library) via its seam.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
      final out = extractModuleSamples(_moduleWith('sine'), sourceFile: 'song');
      expect(out, isNotEmpty);
      final s = out.first;
      expect(s.displayName, 'sine');
      expect(s.sourceFile, 'song');
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
          extractModuleSamples(_moduleWith('kick'), sourceFile: 'demo').first;
      final clip = s.toClip();
      expect(clip.name, contains('demo'));
      expect(clip.name, contains('kick'));
      expect(clip.sampleRate, s.sampleRate);
    });
  });

  group('extractArchiveSamples (sample packs)', () {
    // A real 16-bit mono WAV the reader will accept.
    Uint8List wavBytesFor(List<int> samples, {int rate = 22050}) {
      final b = BytesBuilder();
      void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
      void u32(int v) => b.add(
            [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff],
          );
      final data = <int>[
        for (final s in samples) ...[s & 0xff, (s >> 8) & 0xff],
      ];
      b.add('RIFF'.codeUnits);
      u32(36 + data.length);
      b.add('WAVE'.codeUnits);
      b.add('fmt '.codeUnits);
      u32(16);
      u16(1); // PCM
      u16(1); // mono
      u32(rate);
      u32(rate * 2);
      u16(2);
      u16(16);
      b.add('data'.codeUnits);
      u32(data.length);
      b.add(data);
      return b.toBytes();
    }

    Uint8List zipWith(Map<String, Uint8List> entries) {
      final a = Archive();
      entries.forEach(
        (name, bytes) => a.addFile(ArchiveFile.bytes(name, bytes)),
      );
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    test('pulls every WAV out of a zip, skipping non-WAV entries', () {
      final zip = zipWith({
        'kit/kick.wav': wavBytesFor([100, -100, 200]),
        'kit/snare.wav': wavBytesFor([1, 2, 3, 4]),
        'kit/readme.txt': Uint8List.fromList('hello'.codeUnits),
      });
      final out = extractArchiveSamples(zip, sourceFile: 'kit');
      expect(out.map((s) => s.displayName).toList()..sort(), ['kick', 'snare']);
      expect(out.first.sourceFile, 'kit');
      expect(out.first.sampleRate, 22050);
      expect(out.every((s) => s.pcm.isNotEmpty), isTrue);
    });

    test('an unreadable WAV entry is skipped, the rest survive', () {
      final zip = zipWith({
        'ok.wav': wavBytesFor([5, 6]),
        'broken.wav': Uint8List.fromList(List.filled(64, 0)), // not RIFF
      });
      final out = extractArchiveSamples(zip);
      expect(out.single.displayName, 'ok');
    });

    test('extracts WAVs from a real .7z (Delta:2 + BZip2 chain)', () {
      // Built by the 7-Zip CLI; same coder chain real Freepats packs use.
      final sevenZ = File('test/fixtures/sevenz/wavpack.7z').readAsBytesSync();
      expect(isSevenZip(sevenZ), isTrue);
      expect(looksLikeArchive(sevenZ), isTrue);

      final out = extractArchiveSamples(sevenZ, sourceFile: 'kit');
      expect(out.map((s) => s.displayName).toList()..sort(), ['hi', 'lo']);
      expect(out.every((s) => s.pcm.isNotEmpty), isTrue);
      expect(out.first.sourceFile, 'kit');
    });

    test('a truncated .7z fails as a FormatException', () {
      // Half a real archive: the signature header still points at a footer
      // that is no longer there.
      final full = File('test/fixtures/sevenz/wavpack.7z').readAsBytesSync();
      final truncated = Uint8List.sublistView(full, 0, full.length ~/ 2);
      expect(
        () => extractArchiveSamples(truncated),
        throwsA(isA<FormatException>()),
      );
    });

    test('magic with a zero-length header is a valid EMPTY archive', () {
      // Not an error: 7z encodes "no entries" as nextHeaderSize == 0.
      final empty = Uint8List.fromList(
        [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, ...List.filled(32, 0)],
      );
      expect(extractArchiveSamples(empty), isEmpty);
    });

    test('looksLikeArchive distinguishes packs from modules', () {
      final oneWav = wavBytesFor([1]);
      final pack = zipWith({'a.wav': oneWav});
      expect(looksLikeArchive(pack), isTrue);
      expect(looksLikeArchive(_moduleWith('sine')), isFalse);
    });

    test('a corrupt archive fails safely — no raw error escapes', () {
      final badZip = Uint8List.fromList([0x50, 0x4B, ...List.filled(40, 0xAB)]);
      // The zip reader scans for a central directory, so garbage usually just
      // yields no entries rather than throwing; either outcome is acceptable
      // as long as it isn't an unhandled non-FormatException.
      try {
        expect(extractArchiveSamples(badZip), isEmpty);
      } on FormatException {
        // Container rejected outright — also fine.
      }
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
