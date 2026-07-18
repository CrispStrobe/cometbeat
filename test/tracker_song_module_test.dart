// songFromModuleBytes — imports a real module (.mod/.s3m/.xm/.it) into a
// TrackerSong. Runs against the committed license-clean golden fixtures; asserts
// structure (channels/patterns/order) and that authored notes survive the
// row-major -> channel-major transpose. Pure Dart, no device audio.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  for (final name in ['golden.mod', 'golden.s3m', 'golden.xm', 'golden.it']) {
    test('$name imports into a consistent TrackerSong', () {
      final bytes = _fixture(name);
      final doc = parseAnyModule(bytes);
      final song = songFromModuleBytes(bytes);

      // Structure matches the module.
      expect(song.channelCount, doc.channelCount < 1 ? 1 : doc.channelCount);
      expect(song.patterns.length, doc.patterns.length);
      expect(song.order, isNotEmpty);

      // Every pattern is channel-major and row-sized (the model invariant).
      for (final p in song.patterns) {
        expect(p.cells.length, song.channelCount);
        for (final col in p.cells) {
          expect(col.length, song.rows);
        }
      }

      // The module's first authored note survives the import somewhere.
      final firstNote = _firstDocNote(doc);
      if (firstNote != null) {
        final found = song.patterns.any(
          (p) => p.cells.any((col) => col.any((c) => c.midi == firstNote)),
        );
        expect(found, isTrue, reason: 'first module note $firstNote not found');
      }

      // Rendering the imported song produces audio (no crash, non-trivial).
      expect(song.renderCurrentPatternWav().length, greaterThan(44));
    });
  }

  group('MOD effect column import (replayer feed)', () {
    test('effect nibble → tracker fxCmd/fxParam (note + effect-only cells)',
        () {
      final rows = <List<DocCell>>[
        // A note WITH a porta-up effect (1xx).
        [
          const DocCell(
            note: 60,
            instrument: 1,
            effect: 0x1,
            effectParam: 0x08,
          ),
        ],
        // An effect-ONLY cell (no note) — how a slide continues on a ring.
        [const DocCell(effect: 0x1)],
      ];
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.mod,
        channelCount: 1,
        order: [0],
        patterns: [DocPattern(rows, 1)],
        samples: [DocSample.empty()],
      );
      final song = songFromModuleDoc(doc);
      expect(song.usesCommands, isTrue); // routes through the replayer now

      final c0 = song.patterns[0].cells[0][0];
      expect(c0.midi, 60);
      expect(c0.fxCmd, 0x1);
      expect(c0.fxParam, 0x08);

      final c1 = song.patterns[0].cells[0][1];
      expect(c1.midi, isNull); // effect-only cell keeps no note
      expect(c1.hasCommand, isTrue);
      expect(c1.fxCmd, 0x1);

      // The whole chain (import → replayer) renders without throwing.
      expect(song.renderSongWav().length, greaterThan(44));
    });

    test('golden.mod: every parsed effect becomes a command, none invented',
        () {
      final bytes = _fixture('golden.mod');
      final doc = parseAnyModule(bytes);
      var docFx = 0;
      for (final p in doc.patterns) {
        for (final row in p.rows) {
          for (final dc in row) {
            if (dc.effect != 0 || dc.effectParam != 0) docFx++;
          }
        }
      }
      final song = songFromModuleBytes(bytes);
      var songCmd = 0;
      for (final p in song.patterns) {
        for (final col in p.cells) {
          for (final c in col) {
            if (c.hasCommand) songCmd++;
          }
        }
      }
      if (docFx > 0) {
        expect(songCmd, greaterThan(0), reason: 'MOD effects should carry');
      }
      expect(songCmd, lessThanOrEqualTo(docFx)); // never invents commands
    });

    test('golden.xm: nibble effects carry, letter effects (G+) drop', () {
      final bytes = _fixture('golden.xm');
      final doc = parseAnyModule(bytes);
      var docFx = 0;
      for (final p in doc.patterns) {
        for (final row in p.rows) {
          for (final dc in row) {
            // The XM carry filter kept only fxCmd-nibble effects (0x0..0xF).
            expect(dc.effect, lessThanOrEqualTo(0xF));
            if (dc.effect != 0 || dc.effectParam != 0) docFx++;
          }
        }
      }
      final song = songFromModuleBytes(bytes);
      var songCmd = 0;
      for (final p in song.patterns) {
        for (final col in p.cells) {
          for (final c in col) {
            if (c.hasCommand) songCmd++;
          }
        }
      }
      if (docFx > 0) {
        expect(songCmd, greaterThan(0), reason: 'XM effects should carry');
      }
      expect(songCmd, lessThanOrEqualTo(docFx));
    });

    test('import builds the instrument pool + carries per-cell instrument', () {
      final bytes = _fixture('golden.mod');
      final doc = parseAnyModule(bytes);
      final song = songFromModuleBytes(bytes);

      // The pool has one entry per module sample.
      expect(song.instruments.length, doc.samples.length);

      var docInst = 0;
      for (final p in doc.patterns) {
        for (final row in p.rows) {
          for (final dc in row) {
            if (dc.instrument != 0) docInst++;
          }
        }
      }
      var songInst = 0;
      for (final p in song.patterns) {
        for (final col in p.cells) {
          for (final c in col) {
            if (c.instrument != 0) songInst++;
          }
        }
      }
      // Per-cell instrument survives the import, and routes via the replayer.
      expect(songInst, lessThanOrEqualTo(docInst));
      if (docInst > 0) {
        expect(songInst, greaterThan(0));
        expect(song.usesInstruments, isTrue);
      }
    });

    test('S3M letter-commands map to the right fxCmd/fxParam on import', () {
      // Author a 1-channel S3M whose rows carry known S3M commands, write it,
      // import it, and assert the cross-format mapping (verified vs libopenmpt —
      // see docs/ORACLE.md).
      final rows = <List<S3mCell>>[
        [const S3mCell(note: 0x40, instrument: 1, volume: 64)], // C-5
        [const S3mCell(command: 6, info: 0x20)], // F — porta up  → 0x1
        [const S3mCell(command: 8, info: 0x34)], // H — vibrato   → 0x4
        [const S3mCell(command: 3, info: 0x08)], // C — break     → 0xD
        [const S3mCell(command: 20, info: 0x80)], // T — set tempo → 0xF
      ];
      final m = S3mModule(
        title: 'fxmap',
        channelCount: 1,
        order: [0],
        samples: [S3mSample.empty(), S3mSample(pcm: _sine())],
        patterns: [S3mPattern(rows)],
      );
      final song = songFromModuleBytes(writeS3m(m));
      final col = song.patterns[0].cells[0];
      expect((col[1].fxCmd, col[1].fxParam), (0x1, 0x20)); // porta up
      expect((col[2].fxCmd, col[2].fxParam), (0x4, 0x34)); // vibrato
      expect(col[3].fxCmd, 0xD); // pattern break
      expect((col[4].fxCmd, col[4].fxParam), (0xF, 0x80)); // tempo
    });
  });
}

Int8List _sine() {
  final s = Int8List(512);
  for (var i = 0; i < s.length; i++) {
    s[i] = (100 * sin(2 * pi * 4 * i / s.length)).round();
  }
  return s;
}

int? _firstDocNote(ModuleDoc doc) {
  for (final p in doc.patterns) {
    for (var r = 0; r < p.numRows; r++) {
      for (final cell in p.rows[r]) {
        if (cell.note >= 0) return cell.note;
      }
    }
  }
  return null;
}
