// "Authentic Amiga pitch slides" — the one genuine PREFERENCE in the replayer.
//
// Everything else the audit settled has a right answer measurable against the
// reference players. This does not: MOD/S3M bending the Amiga period is what
// the hardware and every reference do (it took the portamento fixtures from
// 0.55 to 1.000), but a fixed period step bends further the higher the note, so
// a long slide accelerates. The evenly-spaced reading is gentler on material
// never written for an Amiga. Neither is a bug, which is why it is a setting.
//
// What the tests below pin is the SHAPE of that choice, because the shape is
// what makes it safe:
//
//   * it changes the pitch domain and nothing else;
//   * it reaches MOD and S3M only — XM and IT are linear by definition and our
//     own authored songs have their own profile;
//   * it is resolved at IMPORT, into the song's profile, so the replayer holds
//     no global state and a song already open keeps the rules it was opened
//     with.
//
// That last point is why the compile-time `PORTA_PERIOD` gate is gone rather
// than merely re-defaulted: a global switch could not be right for a library
// holding all four formats at once.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_profile.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * i / n);
  }
  return out;
}

/// A one-channel module with a sustained `1xx` portamento — the effect the
/// preference actually changes.
ModuleDoc _sliding() {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'slides',
    channelCount: 4,
    order: const [0],
    samples: [DocSample(name: 'sine', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < 16; r++)
            [
              if (r == 0)
                const DocCell(note: 60, instrument: 1, volume: 64)
              else
                const DocCell(effect: 0x1, effectParam: 0x04),
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        4,
      ),
    ],
  );
}

Uint8List _bytes(ModuleFormat fmt) {
  final doc = _sliding();
  return switch (fmt) {
    ModuleFormat.mod => convertToMod(doc),
    ModuleFormat.xm => convertToXm(doc),
    ModuleFormat.s3m => convertToS3m(doc),
    ModuleFormat.it => convertToIt(doc),
  };
}

PitchDomain _domainOf(ModuleFormat fmt, {required bool authentic}) {
  final song = songFromModuleBytes(_bytes(fmt), authenticSlides: authentic);
  final domains = song.channels.map((c) => c.profile.pitch).toSet();
  expect(domains, hasLength(1), reason: 'all channels agree');
  return domains.single;
}

void main() {
  final original = trackerAuthenticSlidesDefault;
  tearDown(() => trackerAuthenticSlidesDefault = original);

  group('the preference reaches MOD and S3M', () {
    for (final fmt in [ModuleFormat.mod, ModuleFormat.s3m]) {
      test('${fmt.name}: on → period, off → linear', () {
        expect(
          _domainOf(fmt, authentic: true),
          PitchDomain.amigaPeriod,
          reason: 'authentic means the hardware model',
        );
        expect(
          _domainOf(fmt, authentic: false),
          PitchDomain.linearFrequency,
          reason: 'off means the evenly-spaced model',
        );
      });
    }
  });

  group('and does NOT reach the formats with no choice to make', () {
    for (final fmt in [ModuleFormat.xm, ModuleFormat.it]) {
      test('${fmt.name} is linear either way', () {
        // XM and IT bend linearly by definition. If the preference could
        // change them it would be breaking those formats, not offering a
        // choice — which is the whole reason the old global gate was wrong.
        expect(_domainOf(fmt, authentic: true), PitchDomain.linearFrequency);
        expect(_domainOf(fmt, authentic: false), PitchDomain.linearFrequency);
      });
    }
  });

  test('it changes the pitch domain and nothing else', () {
    final on =
        songFromModuleBytes(_bytes(ModuleFormat.mod), authenticSlides: true)
            .channels
            .first
            .profile;
    final off =
        songFromModuleBytes(_bytes(ModuleFormat.mod), authenticSlides: false)
            .channels
            .first
            .profile;
    expect(on.pitch, isNot(off.pitch));
    expect(off.latchPortaParam, on.latchPortaParam);
    expect(off.latchVolSlideParam, on.latchVolSlideParam);
    expect(off.volumeSlideOnTick0, on.volumeSlideOnTick0);
  });

  test('the default is the measurably correct one', () {
    // Not a taste call: period slides are what libopenmpt, libxmp and micromod
    // all do, and what took the portamento fixtures to 1.000 against them.
    expect(trackerAuthenticSlidesDefault, isTrue);
    expect(
      _domainOf(ModuleFormat.mod, authentic: trackerAuthenticSlidesDefault),
      PitchDomain.amigaPeriod,
    );
  });

  test('an explicit argument overrides the app-wide default', () {
    // The importer stays a pure function tools and tests can call without
    // wiring up settings; the default is only consulted when nobody says.
    trackerAuthenticSlidesDefault = false;
    expect(
      songFromModuleBytes(_bytes(ModuleFormat.mod))
          .channels
          .first
          .profile
          .pitch,
      PitchDomain.linearFrequency,
      reason: 'null follows the app default',
    );
    expect(
      _domainOf(ModuleFormat.mod, authentic: true),
      PitchDomain.amigaPeriod,
      reason: 'an explicit true still wins',
    );
  });
}
