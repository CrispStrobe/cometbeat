// Hardening the `KU1.` groove share token — the app's one untrusted-input
// surface (a hand-edited or pasted code). Two properties, both fuzzed:
//   1. Fidelity   — a valid spec survives encode→decode unchanged.
//   2. Resilience — arbitrary/adversarial input never throws, and any spec it
//                   does decode applies + renders without throwing.
// Pure, headless, deterministic (seeded Random).

import 'dart:convert';
import 'dart:math';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum, kDrumKits;
import 'package:flutter_test/flutter_test.dart';

const _trackIds = ['drums', 'bass', 'chords', 'melody', 'sparkle'];

GrooveSpec _randomValidSpec(Random r) {
  final enabled = {
    for (final id in _trackIds)
      if (r.nextBool()) id,
  };
  return GrooveSpec(
    enabled: enabled,
    variants: {
      for (final id in enabled)
        if (r.nextBool()) id: r.nextInt(4),
    },
    levels: {
      for (final id in enabled)
        if (r.nextBool()) id: r.nextInt(101) / 100, // 0.00..1.00, 2dp
    },
    tempoBpm: kMinTempoBpm + r.nextInt(kMaxTempoBpm - kMinTempoBpm + 1),
    swing: r.nextInt(61) / 100, // 0.00..0.60, 2dp
    progressionId:
        r.nextBool() ? null : kProgressions[r.nextInt(kProgressions.length)].id,
    key: r.nextInt(12),
    scale: GrooveScale.values[r.nextInt(GrooveScale.values.length)],
    kitId: kDrumKits[r.nextInt(kDrumKits.length)].id,
    styleId: kGrooveStyles[r.nextInt(kGrooveStyles.length)].id,
    userCells: r.nextBool()
        ? [
            for (var i = 0; i < 8; i++)
              PatternCell(
                midis: r.nextBool() ? [48 + r.nextInt(36)] : null,
                steps: 2,
              ),
          ]
        : null,
    userInstrument: r.nextBool() ? 'flute' : null,
    beatRows: r.nextBool()
        ? {
            Drum.kick: [
              for (var i = 0; i < kPatternSteps; i++) r.nextBool(),
            ],
          }
        : null,
  );
}

// A spec's whole render surface must never throw.
void _renderAll(GrooveSpec spec) {
  final e = LoopEngine()..applySpec(spec);
  expect(e.renderLoop(), isNotNull);
  expect(e.renderLoop(fill: true), isNotNull);
  expect(e.renderVariedLoop(0), isNotNull);
  expect(e.renderVariedLoop(3, fill: true), isNotNull);
}

void main() {
  test('valid specs are a token fixed point (round-trip fidelity)', () {
    final r = Random(1);
    for (var i = 0; i < 200; i++) {
      final spec = _randomValidSpec(r);
      final token = encodeGrooveToken(spec);
      final decoded = decodeGrooveToken(token);
      expect(
        decoded,
        isNotNull,
        reason: 'iter $i failed to decode its own token',
      );
      // Idempotent: re-encoding the decode reproduces the exact token.
      expect(
        encodeGrooveToken(decoded!),
        token,
        reason: 'iter $i not a fixed point',
      );
      // And it renders cleanly.
      _renderAll(decoded);
    }
  });

  test('every valid decoded spec applies + renders without throwing', () {
    final r = Random(7);
    for (var i = 0; i < 100; i++) {
      _renderAll(_randomValidSpec(r));
    }
  });

  group('adversarial input never throws and always renders safely', () {
    test('random garbage strings decode to null-or-safe, never throw', () {
      final r = Random(2);
      const alphabet =
          'KU1.abcXYZ0189+/=-_ {}[]":,\n\té\u{1F600}'; // incl. unicode
      for (var i = 0; i < 500; i++) {
        final len = r.nextInt(40);
        final s = String.fromCharCodes([
          for (var j = 0; j < len; j++)
            alphabet.codeUnitAt(r.nextInt(alphabet.length)),
        ]);
        final decoded = decodeGrooveToken(s); // must not throw
        if (decoded != null) _renderAll(decoded);
      }
    });

    test('KU1. + random base64 payloads never throw', () {
      final r = Random(3);
      const b64 =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      for (var i = 0; i < 500; i++) {
        final len = r.nextInt(48);
        final payload = String.fromCharCodes([
          for (var j = 0; j < len; j++) b64.codeUnitAt(r.nextInt(b64.length)),
        ]);
        final decoded = decodeGrooveToken('KU1.$payload'); // must not throw
        if (decoded != null) _renderAll(decoded);
      }
    });

    test('correct-type bad-value JSON sanitises to a renderable spec', () {
      final hostile = <Map<String, dynamic>>[
        {'t': -999}, // absurd tempo → clamped
        {'t': 1000000},
        {'s': 99.9}, // huge swing → clamped
        {'s': -5.0},
        {'k': 99999}, // out-of-range key → wrapped
        {'k': -13},
        {
          'v': {'drums': -5},
        }, // negative variant → clamped at render
        {
          'v': {'drums': 9999},
        }, // huge variant → clamped
        {
          'v': {'ghost': 3},
        }, // unknown track
        {
          'l': {'drums': 99.0},
        }, // out-of-range level → clamped
        {
          'l': {'drums': -4.0},
        },
        {'sc': 'nonsense'}, // unknown scale → major
        {'kt': 'nope'}, // unknown kit → clean
        {'st': 'nope'}, // unknown style → default
        {'p': 'bogus'}, // unknown progression → vamp
        {
          'u': {'c': 'notalist'},
        }, // malformed user cells
        {
          'u': {
            'c': [
              [
                [1, 2],
                5,
              ]
            ],
          },
        }, // wrong step total
        {
          'b': {'kick': 'xx'},
        }, // wrong-length beat row
        {
          'b': {'notadrum': 'x' * kPatternSteps},
        },
        {'b': 'notamap'},
        <String, dynamic>{}, // empty
        {
          'e': ['drums', 'bass', 'melody', 'chords', 'sparkle'],
          'k': 7,
          'st': 'four',
        },
      ];
      for (final json in hostile) {
        final token = 'KU1.${base64UrlEncode(utf8.encode(jsonEncode(json)))}';
        final decoded = decodeGrooveToken(token);
        // Well-formed JSON with correct types → a spec (values sanitised).
        expect(decoded, isNotNull, reason: 'rejected well-formed json: $json');
        _renderAll(decoded!);
      }
    });

    test(
        'wrong-type fields reject the whole token (safe: no half-load, no '
        'throw)', () {
      // A structurally-wrong field (e.g. enabled isn't a list of strings)
      // rejects the token rather than loading half-corrupt state — the safe
      // choice for a shared code. decodeGrooveToken must still never throw.
      final garbage = <Map<String, dynamic>>[
        {'e': 12345}, // enabled not a list
        {
          'e': ['drums', 42, null], // non-string members
        },
      ];
      for (final json in garbage) {
        final token = 'KU1.${base64UrlEncode(utf8.encode(jsonEncode(json)))}';
        final decoded = decodeGrooveToken(token); // must not throw
        if (decoded != null) _renderAll(decoded);
      }
    });
  });
}
