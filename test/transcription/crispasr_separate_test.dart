// CrispASR-CLI separator glue. The pure part — reading the `<base>_<stem>.wav`
// files the CLI writes back into Stems (incl. the roformer instrumental→other
// mapping) — is tested with real WAVs, no binary needed. The end-to-end run is
// skip-if-absent (needs the crispasr binary + a GGUF model).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/crispasr_separate_io.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _sineWav(double hz, {int n = 8000, int sr = 44100}) {
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = (0.5 * math.sin(2 * math.pi * hz * i / sr) * 32767).round();
  }
  return wavBytes(pcm, sampleRate: sr);
}

void main() {
  test('readStemsFromDir reads the CLI stem files back into Stems', () {
    final dir = Directory.systemTemp.createTempSync('cb_sep_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Simulate what `crispasr --separate` writes for htdemucs.
    File('${dir.path}/mix_vocals.wav').writeAsBytesSync(_sineWav(660));
    File('${dir.path}/mix_bass.wav').writeAsBytesSync(_sineWav(82));
    File('${dir.path}/mix_drums.wav').writeAsBytesSync(_sineWav(200));
    // No 'other' file → stays null (unless an instrumental exists).

    final stems = readStemsFromDir(dir.path, 'mix');
    expect(stems.vocals, isNotNull);
    expect(stems.bass, isNotNull);
    expect(stems.drums, isNotNull);
    expect(stems.other, isNull);
    expect(stems.vocals!.length, greaterThan(0));
  });

  test('roformer instrumental maps to the `other` stem', () {
    final dir = Directory.systemTemp.createTempSync('cb_sep_test2_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/mix_vocals.wav').writeAsBytesSync(_sineWav(440));
    File('${dir.path}/mix_instrumental.wav').writeAsBytesSync(_sineWav(150));

    final stems = readStemsFromDir(dir.path, 'mix');
    expect(stems.vocals, isNotNull);
    expect(stems.other, isNotNull); // instrumental → other
    expect(stems.drums, isNull);
  });

  test('missing files → all-null stems, no throw', () {
    final dir = Directory.systemTemp.createTempSync('cb_sep_test3_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final stems = readStemsFromDir(dir.path, 'mix');
    expect(stems.vocals, isNull);
    expect(stems.other, isNull);
  });

  test('separator with a non-existent binary yields empty stems, never throws',
      () async {
    final sep = crispasrCliSeparator(
      binary: '/no/such/crispasr',
      model: '/no/such/model.gguf',
    );
    final stems = await sep!(Float64List(1000), 44100);
    expect(stems.vocals, isNull);
    expect(stems.drums, isNull);
  });
}
