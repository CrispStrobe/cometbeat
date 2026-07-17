// test/module_convert_test.dart
//
// Cross-format conversion via the neutral ModuleDoc hub:
//   • sniff + parse each committed golden (.mod/.s3m/.xm/.it) into a ModuleDoc and
//     assert its known values (pitch as MIDI, normalized PCM, structure);
//   • round-trip an XM golden through the hub to a .mod and back, proving notes +
//     samples survive the neutral model + the MOD writer;
//   • a skip-if-absent live pass over any real wild_local.* modules.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/module_convert_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/mod_module.dart';
import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _read(String path) => File(path).readAsBytesSync();

void main() {
  group('sniffModuleFormat — each golden detected correctly', () {
    test('signatures', () {
      expect(
        sniffModuleFormat(_read('test/fixtures/golden.mod')),
        ModuleFormat.mod,
      );
      expect(
        sniffModuleFormat(_read('test/fixtures/golden.s3m')),
        ModuleFormat.s3m,
      );
      expect(
        sniffModuleFormat(_read('test/fixtures/golden.xm')),
        ModuleFormat.xm,
      );
      expect(
        sniffModuleFormat(_read('test/fixtures/golden.it')),
        ModuleFormat.it,
      );
      expect(sniffModuleFormat(Uint8List.fromList(List.filled(16, 0))), isNull);
    });
  });

  group('parseAnyModule — golden .mod (TESTMOD)', () {
    late ModuleDoc d;
    setUpAll(() => d = parseAnyModule(_read('test/fixtures/golden.mod')));

    test('structure + first note (period 428 = MIDI 60)', () {
      expect(d.sourceFormat, ModuleFormat.mod);
      expect(d.title, 'TESTMOD');
      expect(d.channelCount, 4);
      expect(d.order, [0]);
      final cell = d.patterns.first.rows[0][0];
      expect(cell.note, 60); // periodToMidi(428) == modNoteBaseMidi + 12
      expect(cell.instrument, 1);
      // instrument 1 → samples[0] "sine", pcm [0,64,127,64,0,-64,-128,-64]/128
      final s = d.samples[0];
      expect(s.name, 'sine');
      expect(s.pcm.length, 8);
      expect(s.pcm[1], closeTo(64 / 128, 1e-9));
      expect(s.pcm[2], closeTo(127 / 128, 1e-9));
      expect(s.pcm[6], closeTo(-128 / 128, 1e-9));
    });
  });

  group('parseAnyModule — golden .s3m (GOLDENS3M)', () {
    late ModuleDoc d;
    setUpAll(() => d = parseAnyModule(_read('test/fixtures/golden.s3m')));

    test('structure + first note (S3M C-5 = MIDI 72)', () {
      expect(d.sourceFormat, ModuleFormat.s3m);
      expect(d.title, 'GOLDENS3M');
      expect(d.channelCount, 1);
      final cell = d.patterns.first.rows[0][0];
      expect(cell.note, 72); // s3mNoteToMidi(0x50)
      expect(cell.instrument, 1);
      final s = d.samples[0];
      expect(s.pcm.length, 8);
      expect(s.pcm[0], closeTo(0, 1e-9));
      expect(s.pcm[3], closeTo(127 / 128, 1e-9));
      expect(s.pcm[7], closeTo(-128 / 128, 1e-9));
    });
  });

  group('parseAnyModule — golden .xm (GOLDENXM)', () {
    late ModuleDoc d;
    setUpAll(() => d = parseAnyModule(_read('test/fixtures/golden.xm')));

    test('structure + first note (XM C-4 = MIDI 60)', () {
      expect(d.sourceFormat, ModuleFormat.xm);
      expect(d.title, 'GOLDENXM');
      expect(d.channelCount, 1);
      final cell = d.patterns.first.rows[0][0];
      expect(cell.note, 60); // xmNoteToMidi(49)
      expect(cell.instrument, 1);
      final s = d.samples[0];
      expect(s.pcm.length, 5);
      expect(s.pcm[2], closeTo(20 / 128, 1e-9));
    });
  });

  group('parseAnyModule — golden .it (GOLDENIT)', () {
    late ModuleDoc d;
    setUpAll(() => d = parseAnyModule(_read('test/fixtures/golden.it')));

    test('structure + first note (IT C-5 = MIDI 60)', () {
      expect(d.sourceFormat, ModuleFormat.it);
      expect(d.title, 'GOLDENIT');
      expect(d.channelCount, 1);
      final cell = d.patterns.first.rows[0][0];
      expect(cell.note, 60); // itNoteToMidi(60)
      expect(cell.instrument, 1);
      // instrument 1 → samples[0] = 8-bit uncompressed [0,10,20,-10,-20]/128
      final s = d.samples[0];
      expect(s.pcm.length, 5);
      expect(s.pcm[2], closeTo(20 / 128, 1e-9));
      expect(s.pcm[3], closeTo(-10 / 128, 1e-9));
    });
  });

  group('convertToMod — XM golden round-trips through the hub to .mod', () {
    test('note + sample survive parseAnyModule → convertToMod → parseMod', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.xm'));
      final modBytes = convertToMod(doc);
      final back = parseMod(modBytes);
      expect(back.title, 'GOLDENXM');
      // note MIDI 60 → its Amiga period; instrument 1 preserved
      final cell = back.patterns.first.rows[0][0];
      expect(cell.sample, 1);
      expect(cell.period, midiToPeriod(60));
      // sample PCM survives the normalize→Int8 round-trip (small values are exact);
      // MOD word-pads the odd length 5 → 6 with a trailing zero.
      expect(
        back.samples[0].pcm.sublist(0, 5),
        Int8List.fromList([0, 10, 20, 10, 0]),
      );
    });
  });

  group('convertToXm — mod/it round-trip through the hub to .xm', () {
    test('MOD golden → .xm preserves note + sample', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.mod'));
      final back = parseXm(convertToXm(doc));
      expect(back.name, 'TESTMOD');
      expect(back.channelCount, 4);
      final cell = back.patterns.first.rows[0][0];
      expect(cell.note, 49); // MIDI 60 → XM note 49; instrument preserved
      expect(cell.instrument, 1);
      // sample "sine" [0,64,127,64,0,-64,-128,-64]/128 survives the 8-bit round-trip
      final pcm = back.instruments[0].samples.first.pcm;
      expect(pcm[1], closeTo(64 / 128, 1 / 128));
      expect(pcm[2], closeTo(127 / 128, 1 / 128));
      expect(pcm[6], closeTo(-1.0, 1 / 128));
    });

    test('IT golden → .xm preserves note + sample', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.it'));
      final back = parseXm(convertToXm(doc));
      expect(back.name, 'GOLDENIT');
      final cell = back.patterns.first.rows[0][0];
      expect(cell.note, 49); // MIDI 60 → XM note 49
      expect(cell.instrument, 1);
      final pcm = back.instruments[0].samples.first.pcm;
      expect(pcm.length, 5);
      expect(pcm[2], closeTo(20 / 128, 1 / 128));
      expect(pcm[3], closeTo(-10 / 128, 1 / 128));
    });
  });

  group('convertToS3m — mod/it round-trip through the hub to .s3m', () {
    test('MOD golden → .s3m preserves note + sample', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.mod'));
      final back = parseS3m(convertToS3m(doc));
      expect(back.title, 'TESTMOD');
      expect(back.channelCount, 4);
      final cell = back.patterns.first.rows[0][0];
      expect(cell.note, 0x40); // MIDI 60 → S3M note (oct4 semi0)
      expect(cell.instrument, 1);
      // sample "sine" survives the signed round-trip exactly (×128 inverts /128)
      expect(
        back.samples[0].pcm,
        Int8List.fromList([0, 64, 127, 64, 0, -64, -128, -64]),
      );
    });

    test('IT golden → .s3m preserves note + sample', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.it'));
      final back = parseS3m(convertToS3m(doc));
      expect(back.title, 'GOLDENIT');
      final cell = back.patterns.first.rows[0][0];
      expect(cell.note, 0x40); // MIDI 60
      expect(cell.instrument, 1);
      expect(back.samples[0].pcm, Int8List.fromList([0, 10, 20, -10, -20]));
    });
  });

  group('convertToIt — mod/xm round-trip through the hub to .it', () {
    test('MOD golden → .it preserves note + sample', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.mod'));
      final back = parseIt(convertToIt(doc));
      expect(back.name, 'TESTMOD');
      // NB: IT infers channelCount from USED channels — golden.mod only uses
      // channel 0, so it round-trips to 1 (musical content is fully preserved).
      final cell = back.patterns.first.rows[0][0];
      expect(cell.note, 60); // MIDI 60 → IT note 60 (identity)
      expect(cell.instrument, 1);
      // sample "sine" survives the signed round-trip exactly (×128 inverts /128)
      final pcm = back.samples[0].pcm;
      expect(pcm[1], closeTo(64 / 128, 1e-9));
      expect(pcm[2], closeTo(127 / 128, 1e-9));
      expect(pcm[6], closeTo(-1.0, 1e-9));
    });

    test('XM golden → .it preserves note + sample', () {
      final doc = parseAnyModule(_read('test/fixtures/golden.xm'));
      final back = parseIt(convertToIt(doc));
      expect(back.name, 'GOLDENXM');
      final cell = back.patterns.first.rows[0][0];
      expect(cell.note, 60); // MIDI 60 → IT note 60
      expect(cell.instrument, 1);
      final pcm = back.samples[0].pcm;
      expect(pcm.length, 5);
      expect(pcm[2], closeTo(20 / 128, 1e-9));
    });
  });

  group('parseAnyModule — live real modules (skipped if absent)', () {
    for (final entry in const [
      ['test/fixtures/wild_local.s3m', ModuleFormat.s3m],
      ['test/fixtures/wild_local.xm', ModuleFormat.xm],
      ['test/fixtures/wild_local.it', ModuleFormat.it],
    ]) {
      final path = entry[0] as String;
      final fmt = entry[1] as ModuleFormat;
      final present = File(path).existsSync();
      test(
        'parses $path as $fmt',
        () {
          final bytes = _read(path);
          expect(sniffModuleFormat(bytes), fmt);
          final d = parseAnyModule(bytes);
          expect(d.sourceFormat, fmt);
          expect(d.title, isNotEmpty);
          expect(d.channelCount, greaterThan(0));
          expect(d.patterns, isNotEmpty);
          expect(d.usedSamples, isNotEmpty);
        },
        skip: present ? false : '$path not present',
      );
    }
  });
}
