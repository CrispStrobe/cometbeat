// End-to-end test for the `bin/modconv.dart` module-converter CLI: it reads a
// real module file, converts it to another format, and writes it out — and the
// conversion now carries the effect column and 16-bit sample precision (the
// fidelity fixes this crate shipped) all the way through the CLI, not just the
// in-process converters. Also covers `--extract-samples`. Uses a temp dir; the
// CLI is Flutter-free so `dart:io` file I/O works under `flutter test`.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bin/modconv.dart' as modconv;

/// A `.mod` byte stream: one channel, a note carrying a vibrato (4xy) effect,
/// backed by one sample — enough to check note + effect + sample survive.
Uint8List _srcMod() {
  final pcm = Float64List(64);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  final doc = ModuleDoc(
    title: 'CLI',
    channelCount: 1,
    sourceFormat: ModuleFormat.mod,
    order: [0],
    patterns: const [
      DocPattern(
        [
          [DocCell(note: 60, instrument: 1, effect: 0x4, effectParam: 0x82)],
        ],
        1,
      ),
    ],
    samples: [DocSample(pcm: pcm)],
  );
  return convertToMod(doc);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('modconv_test'));
  tearDown(() {
    dir.deleteSync(recursive: true);
    exitCode = 0; // the CLI sets the process exitCode; reset between tests
  });

  test('converts a module and preserves note + effect through the CLI', () {
    final inPath = '${dir.path}/in.mod';
    final outPath = '${dir.path}/out.it';
    File(inPath).writeAsBytesSync(_srcMod());

    modconv.main([inPath, outPath]);

    expect(File(outPath).existsSync(), isTrue);
    final back = parseAnyModule(
      Uint8List.fromList(File(outPath).readAsBytesSync()),
    );
    expect(back.sourceFormat, ModuleFormat.it);
    final c = back.patterns.first.rows.first.first;
    expect(c.note, 60);
    expect(c.effect, 0x4, reason: 'the vibrato effect survives conversion');
    expect(c.effectParam, 0x82);
  });

  test('the target format follows the output extension (.xm)', () {
    final inPath = '${dir.path}/in.mod';
    final outPath = '${dir.path}/out.xm';
    File(inPath).writeAsBytesSync(_srcMod());

    modconv.main([inPath, outPath]);

    final back = parseAnyModule(
      Uint8List.fromList(File(outPath).readAsBytesSync()),
    );
    expect(back.sourceFormat, ModuleFormat.xm);
    expect(back.patterns.first.rows.first.first.note, 60);
  });

  test('--extract-samples writes a WAV per used sample', () {
    final inPath = '${dir.path}/in.mod';
    File(inPath).writeAsBytesSync(_srcMod());

    modconv.main([inPath, '--extract-samples', dir.path]);

    final wavs = dir
        .listSync()
        .where((f) => f.path.toLowerCase().endsWith('.wav'))
        .toList();
    expect(wavs, isNotEmpty);
    // A WAV has the 'RIFF' magic + is non-trivial in size.
    final bytes = File(wavs.first.path).readAsBytesSync();
    expect(bytes.length, greaterThan(44));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  });

  test('a non-module input is reported, not crashed', () {
    final inPath = '${dir.path}/notamod.bin';
    File(inPath).writeAsBytesSync(Uint8List(100)); // all zeros
    modconv.main([inPath, '${dir.path}/out.it']);
    expect(exitCode, 1); // data error, handled cleanly
  });
}
