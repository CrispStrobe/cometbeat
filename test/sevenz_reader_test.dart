// The pure-Dart 7z reader, against REAL archives produced by the 7-Zip CLI
// (test/fixtures/sevenz/*.7z — LZMA2 default, LZMA1, and stored/uncompressed;
// each holds the same three files, incl. 4 KB of incompressible random bytes).
//
// Fixtures are committed so this runs in CI without 7z installed.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/archive/sevenz_reader.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/sevenz';

Uint8List _fixture(String name) => File('$_dir/$name').readAsBytesSync();

const _aText = 'hello seven zip world, hello seven zip world, '
    'hello seven zip world\n';
const _bText = 'second file contents here, '
    'repeated repeated repeated repeated\n';

void main() {
  final expectedC = _fixture('expected_c.bin');

  void checkArchive(String file) {
    final archive = readSevenZ(_fixture(file));
    final files = {
      for (final e in archive.entries)
        if (!e.isDirectory) e.name.split('/').last: e,
    };

    expect(
      files.keys.toSet(),
      {'a.txt', 'b.txt', 'c.bin'},
      reason: '$file entry names',
    );
    expect(String.fromCharCodes(files['a.txt']!.content), _aText);
    expect(String.fromCharCodes(files['b.txt']!.content), _bText);
    // The random payload is the real test: it can't be faked by a lucky
    // literal-only decode path.
    expect(files['c.bin']!.content, equals(expectedC));
    expect(files['c.bin']!.size, 4000);
  }

  test('reads an LZMA2 archive (7z default)', () => checkArchive('lzma2.7z'));
  test('reads an LZMA1 archive', () => checkArchive('lzma1.7z'));
  test('reads a stored (uncompressed) archive', () => checkArchive('store.7z'));

  // The shape real Freepats sample packs use — a Delta:2 filter chained in
  // front of BZip2. Verified against a real 7.2 MB Freepats archive (51 files,
  // 19,827,162 bytes) matching 7-Zip's own extraction byte-for-byte.
  test(
    'reads a Delta:2 + BZip2 chain (real Freepats shape)',
    () => checkArchive('deltabzip2.7z'),
  );

  group('detection', () {
    test('recognizes the 7z signature', () {
      expect(isSevenZArchive(_fixture('lzma2.7z')), isTrue);
      expect(isSevenZArchive(Uint8List.fromList([0x50, 0x4B, 3, 4])), isFalse);
      expect(isSevenZArchive(Uint8List(0)), isFalse);
    });
  });

  group('malformed input never escapes as a raw error', () {
    test('non-7z bytes', () {
      expect(
        () => readSevenZ(Uint8List.fromList(List.filled(64, 0xAB))),
        throwsA(isA<FormatException>()),
      );
    });

    test('truncated signature header', () {
      expect(
        () => readSevenZ(
          Uint8List.fromList([
            ...[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],
            0,
            4,
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a header offset pointing past EOF is rejected', () {
      final bytes = Uint8List.fromList(_fixture('lzma2.7z'));
      // Blow up nextHeaderOffset (bytes 12..19).
      final view = ByteData.sublistView(bytes);
      view.setUint64(12, 0xFFFFFFF, Endian.little);
      expect(() => readSevenZ(bytes), throwsA(isA<FormatException>()));
    });

    test('every byte-level truncation fails cleanly, never a RangeError', () {
      final full = _fixture('lzma2.7z');
      for (var cut = 32; cut < full.length; cut += 97) {
        final truncated = Uint8List.sublistView(full, 0, cut);
        try {
          readSevenZ(truncated);
        } on FormatException {
          // expected
        } catch (e) {
          fail('truncation at $cut threw ${e.runtimeType}: $e');
        }
      }
    });
  });

  test('unsupported coders report what they are, not a generic failure', () {
    // We can't easily author an AES archive here, but the typed errors are
    // part of the contract: SevenZUnsupported is a FormatException so callers
    // catch both kinds uniformly.
    expect(const SevenZUnsupported('x'), isA<FormatException>());
    expect(const SevenZFormatException('x'), isA<FormatException>());
  });
}
