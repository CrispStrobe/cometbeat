// SoundFont 2 sample extraction: build a minimal valid RIFF/sfbk buffer (one
// sample, with a loop), parse it, and turn it into a tracker SampleInstrument.
// Proves the parser + the SF2→SampleInstrument bridge with no external asset.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Assemble the smallest SF2 our extractor reads: a `smpl` sample pool + a
/// `shdr` header table (one real sample + the terminal EOS record). Real
/// soundfonts also carry INFO/phdr/pbag/pgen/inst/ibag/igen, which the
/// sample extractor doesn't need — so this fixture targets exactly what we parse.
Uint8List _minimalSf2({
  required Int16List pcm,
  required int sampleRate,
  required int rootKey,
  required int loopStart,
  required int loopEnd,
}) {
  Uint8List tag(String s) => Uint8List.fromList(s.codeUnits);
  Uint8List u32(int v) =>
      (Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));

  Uint8List chunk(String id, Uint8List body) {
    final b = BytesBuilder()
      ..add(tag(id))
      ..add(u32(body.length))
      ..add(body);
    if (body.length.isOdd) b.addByte(0); // word alignment
    return b.toBytes();
  }

  // smpl: raw little-endian int16 pool.
  final smpl = Uint8List(pcm.length * 2);
  final sd = ByteData.sublistView(smpl);
  for (var i = 0; i < pcm.length; i++) {
    sd.setInt16(i * 2, pcm[i], Endian.little);
  }
  final sdta = chunk(
    'LIST',
    (BytesBuilder()
          ..add(tag('sdta'))
          ..add(chunk('smpl', smpl)))
        .toBytes(),
  );

  // shdr: one 46-byte record + one EOS terminator.
  Uint8List shdrRecord(
    String name,
    int start,
    int end,
    int ls,
    int le,
    int sr,
    int pitch,
  ) {
    final r = Uint8List(46);
    final d = ByteData.sublistView(r);
    final nm = name.codeUnits;
    for (var i = 0; i < nm.length && i < 20; i++) {
      r[i] = nm[i];
    }
    d.setUint32(20, start, Endian.little);
    d.setUint32(24, end, Endian.little);
    d.setUint32(28, ls, Endian.little);
    d.setUint32(32, le, Endian.little);
    d.setUint32(36, sr, Endian.little);
    r[40] = pitch;
    return r;
  }

  final shdrBody = BytesBuilder()
    ..add(
      shdrRecord(
        'TestTone',
        0,
        pcm.length,
        loopStart,
        loopEnd,
        sampleRate,
        rootKey,
      ),
    )
    ..add(shdrRecord('EOS', 0, 0, 0, 0, 0, 0));
  final pdta = chunk(
    'LIST',
    (BytesBuilder()
          ..add(tag('pdta'))
          ..add(chunk('shdr', shdrBody.toBytes())))
        .toBytes(),
  );

  final riffBody = BytesBuilder()
    ..add(tag('sfbk'))
    ..add(sdta)
    ..add(pdta);
  return chunk('RIFF', riffBody.toBytes());
}

void main() {
  group('SF2 sample extraction', () {
    Int16List sine(int n, double periods) {
      final s = Int16List(n);
      for (var i = 0; i < n; i++) {
        s[i] = (12000 * sin(2 * pi * periods * i / n)).round();
      }
      return s;
    }

    test('parses one sample with its rate, root key and loop', () {
      final pcm = sine(880, 20); // 20 clean periods → loop seam is clean
      final bytes = _minimalSf2(
        pcm: pcm,
        sampleRate: 22050,
        rootKey: 60,
        loopStart: 44,
        loopEnd: 836,
      );
      final sf = Sf2SoundFont.parse(bytes);
      expect(sf.samples.length, 1); // EOS record skipped
      final s = sf.samples.single;
      expect(s.name, 'TestTone');
      expect(s.sampleRate, 22050);
      expect(s.originalPitch, 60);
      expect(s.pcm.length, 880);
      expect(s.loops, isTrue);
      expect(s.loopStart, 44);
      expect(s.loopEnd, 836);
    });

    test(
        'builds a looping, pitched SampleInstrument (resampled to engine rate)',
        () {
      final pcm = sine(880, 20);
      final bytes = _minimalSf2(
        pcm: pcm,
        sampleRate: 22050,
        rootKey: 60,
        loopStart: 44,
        loopEnd: 836,
      );
      final s = Sf2SoundFont.parse(bytes).samples.single;
      final inst = sampleInstrumentFromSf2(s, id: 'sf2tone');
      expect(inst.id, 'sf2tone');
      expect(inst.baseMidi, 60);
      expect(inst.loops, isTrue); // loop carried → held notes sustain
      expect(soundCategoryOf(inst), SoundCategory.recorded);

      // A held note sustains past the (short) sample length thanks to the loop.
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
      ];
      final buf = inst.renderChannel(cells, timing);
      final probe = inst.sample.length + 20000;
      expect(buf.length, timing.totalSamples);
      expect(
        buf.sublist(probe, probe + 500).any((v) => v.abs() > 1e-3),
        isTrue,
      );
    });

    test('rejects a non-SoundFont buffer', () {
      expect(
        () => Sf2SoundFont.parse(Uint8List.fromList('not an sf2!!'.codeUnits)),
        throwsFormatException,
      );
    });
  });
}
