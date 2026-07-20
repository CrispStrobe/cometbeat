// Validates the module parser against a corpus of REAL tracker modules that
// live (gitignored) under test/fixtures/wild/ — fetched by
// bin/fetch_wild_modules.dart. Unlike our tiny self-authored goldens, these are
// files real trackers actually wrote, so they exercise header quirks, feature
// combinations and edge cases our synthetic fixtures don't.
//
// The invariant (same as the blackbox fuzz test, now over REAL bytes): parsing
// untrusted input must NEVER throw a Dart Error — only a clean Exception
// (FormatException / ItFormatException / …) is acceptable. When a file DOES
// parse, the result must be structurally sane and re-convert to its own format
// without an Error. Skips cleanly in CI where the corpus is absent.

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Directory('test/fixtures/wild');
  final files = dir.existsSync()
      ? (dir
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => RegExp(
              r'\.(mod|xm|s3m|it)$',
              caseSensitive: false,
            ).hasMatch(f.path),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  if (files.isEmpty) {
    test(
      'wild corpus',
      () {},
      skip: 'no test/fixtures/wild/ modules — run '
          'dart run bin/fetch_wild_modules.dart',
    );
    return;
  }

  test('the wild corpus has files across formats', () {
    expect(files.length, greaterThan(4));
  });

  group('real tracker modules parse without a Dart Error', () {
    for (final f in files) {
      final label = f.path.replaceFirst('test/fixtures/wild/', '');
      test(label, () {
        final bytes = f.readAsBytesSync();
        ModuleDoc doc;
        try {
          doc = parseAnyModule(bytes);
        } catch (e) {
          // A clean rejection (Exception) is fine; a Dart Error is a parser bug.
          expect(
            e,
            isNot(isA<Error>()),
            reason: '$label: rejected with an Error, not an Exception',
          );
          return;
        }

        // Parsed → structurally sane.
        expect(doc.channelCount, greaterThanOrEqualTo(0), reason: label);
        expect(doc.patterns, isNotNull, reason: label);
        expect(doc.samples, isNotNull, reason: label);

        // Re-converting to its own format must not Error either.
        try {
          convertDocTo(doc, doc.sourceFormat);
        } catch (e) {
          expect(
            e,
            isNot(isA<Error>()),
            reason: '$label: re-convert threw an Error',
          );
        }
      });
    }
  });
}
