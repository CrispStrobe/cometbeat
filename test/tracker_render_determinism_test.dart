// What our offline render guarantees, and what it does NOT.
//
// GUARANTEED (this file): rendering the same module twice on the same machine
// produces byte-identical audio. Several suites already rely on that without
// stating it — every "renders byte-identical with the feature added" test
// compares two renders and would report a spurious pass or fail if the
// renderer itself wobbled. It is the foundation those gates stand on, so it
// deserves a test of its own rather than being assumed.
//
// NOT GUARANTEED: bit-identical audio ACROSS platforms. The limiter runs every
// sample through `_tanh`, which is built on `exp()`, and `exp` is the platform
// libm — glibc and Darwin round the last bit differently. An independent
// player that measured this (savage_modplayer) reports LSB shifts in ~0.01% of
// samples, about 115 dB below the signal and inaudible. We have not measured
// ours; the point is that the guarantee is per-platform and we should not
// pretend otherwise.
//
// THE RULE THAT FOLLOWS: never commit a golden RENDERED WAV and compare it
// byte-exactly. We develop on macOS and CI runs Linux, so such a fixture is an
// intermittent red waiting to happen. Compare two renders made in the SAME run
// (as here), or compare at signal level with test/support/audio_compare.dart.
//
// Committing golden module BYTES is fine and mod_codec_test does exactly that:
// parse→write is integer work with no libm anywhere near it.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fixtures we own and commit — one per format, so a determinism failure
/// points at a format rather than at "the renderer".
const _fixtures = [
  'golden.mod',
  'golden.xm',
  'golden.it',
  'golden.s3m',
];

void main() {
  test('the comparison can actually detect a difference', () {
    // Guards against the whole suite below passing vacuously. If the renders
    // were empty, or the loop never ran, every test above would be green while
    // checking nothing — so prove the same comparison separates two fixtures
    // that genuinely differ.
    final mod = File('test/fixtures/golden.mod');
    final xm = File('test/fixtures/golden.xm');
    if (!mod.existsSync() || !xm.existsSync()) {
      markTestSkipped('fixtures not present');
      return;
    }
    final a = songFromModuleBytes(
      Uint8List.fromList(mod.readAsBytesSync()),
    ).renderSongWav();
    final b = songFromModuleBytes(
      Uint8List.fromList(xm.readAsBytesSync()),
    ).renderSongWav();

    expect(a, isNotEmpty, reason: 'an empty render would compare equal to any');
    var differing = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) differing++;
    }
    expect(
      a.length != b.length || differing > 0,
      isTrue,
      reason: 'two different modules rendered identically — the comparison '
          'below is not measuring anything',
    );
  });

  group('offline render is deterministic within a platform', () {
    for (final name in _fixtures) {
      test(name, () {
        final path = 'test/fixtures/$name';
        if (!File(path).existsSync()) {
          markTestSkipped('$name not present');
          return;
        }
        final bytes = Uint8List.fromList(File(path).readAsBytesSync());

        // Parsed separately each time on purpose: this has to cover the whole
        // path, not just the mixer. A parser that carried state between runs —
        // or a renderer seeded from anything ambient — would show up here.
        final first = songFromModuleBytes(bytes).renderSongWav();
        final second = songFromModuleBytes(bytes).renderSongWav();

        expect(
          second.length,
          first.length,
          reason: '$name rendered to different lengths on two runs',
        );

        var differing = 0;
        var firstDiff = -1;
        for (var i = 0; i < first.length; i++) {
          if (first[i] != second[i]) {
            if (firstDiff < 0) firstDiff = i;
            differing++;
          }
        }
        expect(
          differing,
          0,
          reason: '$name: $differing of ${first.length} bytes differ between '
              'two renders of the same input (first at $firstDiff). Something '
              'in the render path is ambient — a clock, a random seed, or '
              'state surviving between songs. Every byte-identical gate in the '
              'suite is unreliable until this is true.',
        );
      });
    }
  });
}
