// module_convert.dart — parseAnyModule sniffs the format and dispatches. The
// existing module_convert_test asserts sniffModuleFormat(garbage) == null but
// never drives parseAnyModule down its unknown-format branch, so the throw at
// the end of the dispatch went unexercised.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseAnyModule throws on an unrecognized format', () {
    // 64 zero bytes: no MOD/XM/S3M/IT signature → sniff returns null.
    final garbage = Uint8List(64);
    expect(sniffModuleFormat(garbage), isNull);
    expect(() => parseAnyModule(garbage), throwsA(isA<ArgumentError>()));
  });
}
