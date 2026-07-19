// Fuzz-robustness lock for the module readers. `parseAnyModule` is fed
// untrusted files (ModArchive downloads, user imports), and its contract is to
// throw a *FormatException (an Exception) — never a bare Error (RangeError,
// StateError, …) and never to hang — on malformed input. mod_decode_bomb_test
// covers the allocation bombs (crafted huge counts); this covers ARBITRARY
// bytes, including inputs stamped with a real signature so the fuzz reaches deep
// into each format's parse path. A probe run of 2000 inputs found 0 Errors;
// this pins that. Pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

void _stamp(Uint8List b, int at, String sig) {
  for (var i = 0; i < sig.length && at + i < b.length; i++) {
    b[at + i] = sig.codeUnitAt(i);
  }
}

/// Runs [input] through parseAnyModule; passes iff it returns or throws an
/// Exception (never a bare Error).
void _mustNotError(Uint8List input) {
  try {
    parseAnyModule(input);
  } on Exception {
    // A clean data error — the contract.
  } catch (e) {
    fail('parseAnyModule threw a non-Exception ${e.runtimeType}: $e');
  }
}

void main() {
  group('module reader fuzz (untrusted input never throws an Error)', () {
    test('400 random + signature-stamped inputs stay Exception-only', () {
      final rng = Random(20260719);
      for (var iter = 0; iter < 400; iter++) {
        final len = 8 + rng.nextInt(2500);
        final b = Uint8List(len);
        for (var i = 0; i < len; i++) {
          b[i] = rng.nextInt(256);
        }
        switch (rng.nextInt(5)) {
          case 0:
            _stamp(b, 1080, 'M.K.'); // MOD
          case 1:
            _stamp(b, 44, 'SCRM'); // S3M
          case 2:
            _stamp(b, 0, 'Extended Module: '); // XM
          case 3:
            _stamp(b, 0, 'IMPM'); // IT
          // case 4: leave as pure random (usually rejected by the sniffer)
        }
        _mustNotError(b);
      }
    });

    test('empty and tiny inputs throw cleanly', () {
      for (final n in const [0, 1, 4, 8, 44, 45]) {
        _mustNotError(Uint8List(n));
      }
    });

    test('a valid signature over an all-zero body does not Error', () {
      // Zero counts / lengths are a common crash trigger (div-by-zero, empty
      // ranges); each format parser must degrade cleanly.
      for (final (at, sig, len) in const [
        (1080, 'M.K.', 1084),
        (44, 'SCRM', 200),
        (0, 'Extended Module: ', 400),
        (0, 'IMPM', 400),
      ]) {
        final b = Uint8List(len);
        _stamp(b, at, sig);
        _mustNotError(b);
      }
    });
  });
}
