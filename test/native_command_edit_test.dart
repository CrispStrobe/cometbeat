// native_command_edit_test.dart
//
// The RAW native-command view/edit helpers (tracker_native_command.dart):
//   * describeNativeEffect / nativeEffectMnemonic format a known command;
//   * setNativeEffect writes provenance onto a cell that SURVIVES a same-format
//     S3M and IT export → re-import round-trip (the native command is preserved);
//   * the native S3M-header helpers (setGlobalVolume / setInitialSpeed) edit a
//     RETAINED field that round-trips through moduleDocFromSong → docToS3m →
//     parseS3m.
// Pure Dart, no device audio.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertToIt, convertToS3m, docToS3m, parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart' show ModuleFormat;
import 'package:comet_beat/core/audio/mod/s3m_reader.dart' show parseS3m;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_native_command.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Float64List buzz(int n) {
    final s = Float64List(n);
    for (var i = 0; i < n; i++) {
      s[i] = i % 40 < 20 ? 0.6 : -0.6;
    }
    return s;
  }

  /// A one-channel song whose row-0 cell carries [cell].
  TrackerSong songWithCell(TrackerCell cell) {
    final ch = TrackerChannel(
      id: 's',
      instrument: SampleInstrument('rec', buzz(400)),
      rows: 8,
    );
    final song = TrackerSong.fromParts(
      channels: [ch],
      timing: const TrackerTiming(rows: 8),
      patterns: [
        TrackerPattern.empty(name: '00', channels: 1, rows: 8),
      ],
      order: const [0],
    );
    song.engine.setCell(0, 0, cell);
    song.syncCurrent();
    return song;
  }

  group('describeNativeEffect / nativeEffectMnemonic', () {
    test('decodes a known S3M volume-slide command', () {
      // S3M letter-command 4 = D (volume slide), param 0x12.
      final cell = setNativeEffect(
        const TrackerCell(midi: 60),
        format: 's3m',
        effect: 4,
        param: 0x12,
      );
      expect(nativeEffectMnemonic('s3m', 4), 'D — Volume slide');
      final decode = describeNativeEffect(cell);
      expect(decode, contains('S3M'));
      expect(decode, contains('D — Volume slide'));
      expect(decode, contains('0412')); // \$command,param in hex
    });

    test('decodes MOD nibble and IT letter commands', () {
      expect(nativeEffectMnemonic('mod', 0xC), 'C — Set volume');
      expect(nativeEffectMnemonic('it', 20), 'T — Set tempo');
    });

    test('a cell with no provenance describes as an em dash', () {
      expect(describeNativeEffect(const TrackerCell(midi: 60)), '—');
      expect(hasNativeProvenance(const TrackerCell(midi: 60)), isFalse);
    });
  });

  group('setNativeEffect provenance', () {
    test('writes native bytes without touching the normalized column', () {
      const base = TrackerCell(midi: 60, fxCmd: 0x1, fxParam: 0x04);
      final cell = setNativeEffect(base, format: 's3m', effect: 4, param: 0x12);
      expect(cell.nativeFormat, 's3m');
      expect(cell.nativeEffect, 4);
      expect(cell.nativeEffectParam, 0x12);
      // Normalized effect column untouched.
      expect(cell.fxCmd, 0x1);
      expect(cell.fxParam, 0x04);
    });

    test('survives a same-format S3M export → re-import', () {
      final cell = setNativeEffect(
        const TrackerCell(midi: 60),
        format: 's3m',
        effect: 4, // D — volume slide
        param: 0x12,
      );
      final song = songWithCell(cell);
      final bytes =
          convertToS3m(moduleDocFromSong(song, targetFormat: ModuleFormat.s3m));
      final reDoc = parseAnyModule(bytes);
      final reCell = reDoc.patterns[0].rows[0][0];
      expect(reDoc.sourceFormat, ModuleFormat.s3m);
      expect(reCell.nativeEffect, 4);
      expect(reCell.nativeEffectParam, 0x12);

      // And through the full TrackerSong import too.
      final reSong = songFromModuleDoc(reDoc);
      final imported = reSong.engine.cellAt(0, 0);
      expect(imported.nativeFormat, 's3m');
      expect(imported.nativeEffect, 4);
      expect(imported.nativeEffectParam, 0x12);
    });

    test('survives a same-format IT export → re-import', () {
      final cell = setNativeEffect(
        const TrackerCell(midi: 60),
        format: 'it',
        effect: 4, // D — volume slide
        param: 0x0A,
      );
      final song = songWithCell(cell);
      final bytes =
          convertToIt(moduleDocFromSong(song, targetFormat: ModuleFormat.it));
      final reDoc = parseAnyModule(bytes);
      final reCell = reDoc.patterns[0].rows[0][0];
      expect(reDoc.sourceFormat, ModuleFormat.it);
      expect(reCell.nativeEffect, 4);
      expect(reCell.nativeEffectParam, 0x0A);
    });

    test('a mismatched target format does NOT re-emit the native command', () {
      // Provenance tagged s3m, exported as IT → the native command is dropped
      // (documented: same-format only).
      final cell = setNativeEffect(
        const TrackerCell(midi: 60),
        format: 's3m',
        effect: 4,
        param: 0x12,
      );
      final song = songWithCell(cell);
      final doc = moduleDocFromSong(song, targetFormat: ModuleFormat.it);
      expect(doc.patterns[0].rows[0][0].nativeEffect, -1);
    });

    test('clearNativeProvenance removes the native bytes', () {
      final cell = setNativeEffect(
        const TrackerCell(midi: 60),
        format: 's3m',
        effect: 4,
        param: 0x12,
      );
      final cleared = clearNativeProvenance(cell);
      expect(cleared.nativeEffect, -1);
      expect(cleared.nativeVolpan, -1);
    });
  });

  group('native S3M header helpers', () {
    test('setGlobalVolume round-trips through S3M export/parse', () {
      final song = songWithCell(const TrackerCell(midi: 60));
      song.setGlobalVolume(0.5); // 0.5 → doc 64 → S3M byte 32 → back to 0.5

      final doc = moduleDocFromSong(song, targetFormat: ModuleFormat.s3m);
      expect(doc.globalVolume, 64);

      final s3m = docToS3m(doc);
      expect(s3m.globalVolume, 32);

      final reParsed = parseS3m(convertToS3m(doc));
      expect(reParsed.globalVolume, 32);

      // Re-imported onto a TrackerSong the edited value survives.
      final reSong = songFromModuleDoc(parseAnyModule(convertToS3m(doc)));
      expect(reSong.globalVolume, closeTo(0.5, 0.01));
    });

    test('setInitialSpeed round-trips through S3M export/parse', () {
      final song = songWithCell(const TrackerCell(midi: 60));
      song.setInitialSpeed(9);

      final doc = moduleDocFromSong(song, targetFormat: ModuleFormat.s3m);
      final reParsed = parseS3m(convertToS3m(doc));
      expect(reParsed.initialSpeed, 9);
    });

    test('helpers clamp to their writable ranges', () {
      expect(normalizeGlobalVolume(1.5), 1.0);
      expect(normalizeGlobalVolume(-0.2), 0.0);
      expect(normalizeInitialSpeed(0), 1);
      expect(normalizeInitialSpeed(99), 31);

      final song = songWithCell(const TrackerCell(midi: 60));
      song.setInitialSpeed(99);
      expect(song.initialSpeed, 31);
      song.setGlobalVolume(2.0);
      expect(song.globalVolume, 1.0);
    });

    test('describeModuleHeader summarizes the editable fields', () {
      final song = songWithCell(const TrackerCell(midi: 60));
      song.setGlobalVolume(0.5);
      song.setInitialSpeed(6);
      final s = describeModuleHeader(song);
      expect(s, contains('50%'));
      expect(s, contains('Speed 6'));
      expect(s, contains('BPM'));
    });
  });

  test('kSampleRate is available for song construction', () {
    expect(kSampleRate, greaterThan(0));
  });
}
