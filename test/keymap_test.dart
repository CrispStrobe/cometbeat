// WS-T3 — the binding table itself.
//
// The tracker's behaviour is pinned by `tracker_keymap_characterization_test`;
// this covers what the table has to get right on its own, and the two things
// that would quietly cost a user their setup: a stored rebinding that cannot be
// read back, and a stored keymap that freezes today's defaults forever.

import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chords', () {
    test('a chord is value-equal, so it can key a map', () {
      // The whole mechanism: resolving a press is one lookup rather than a
      // ladder of ifs.
      const a = KeyChord(LogicalKeyboardKey.keyC, ctrl: true);
      const b = KeyChord(LogicalKeyboardKey.keyC, ctrl: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a: 1}[b], 1);
    });

    test('modifiers are part of the identity', () {
      const plain = KeyChord(LogicalKeyboardKey.arrowUp);
      const withAlt = KeyChord(LogicalKeyboardKey.arrowUp, alt: true);
      expect(plain, isNot(withAlt));
    });

    test('a chord round-trips through its token', () {
      // Rebindings are persisted by token, so a token that cannot be read back
      // silently loses the user's setup on the next launch.
      for (final chord in [
        const KeyChord(LogicalKeyboardKey.keyZ, ctrl: true),
        const KeyChord(LogicalKeyboardKey.arrowDown, shift: true, alt: true),
        const KeyChord(LogicalKeyboardKey.f5),
      ]) {
        expect(KeyChord.fromToken(chord.token), chord, reason: chord.label);
      }
    });

    test('a damaged token reads as null rather than throwing', () {
      for (final token in ['', 'nonsense', 'c:', ':', 'c:abc']) {
        expect(KeyChord.fromToken(token), isNull, reason: token);
      }
    });

    test('the label reads the way a keymap sheet should', () {
      expect(const KeyChord(LogicalKeyboardKey.arrowUp).label, '↑');
      expect(
        const KeyChord(LogicalKeyboardKey.keyC, ctrl: true).label,
        'Ctrl+C',
      );
      expect(
        const KeyChord(LogicalKeyboardKey.pageDown, alt: true).label,
        'Alt+PgDn',
      );
    });
  });

  group('the default table', () {
    test('it carries the tracker bindings the extraction moved', () {
      final map = Keymap();
      expect(
        map.intentFor(const KeyChord(LogicalKeyboardKey.f5)),
        AppIntent.transportPlaySong,
      );
      expect(
        map.intentFor(const KeyChord(LogicalKeyboardKey.keyC, ctrl: true)),
        AppIntent.clipCopy,
      );
      expect(
        map.intentFor(const KeyChord(LogicalKeyboardKey.arrowUp, alt: true)),
        AppIntent.transposeUp,
      );
      expect(
        map.intentFor(const KeyChord(LogicalKeyboardKey.pageUp)),
        AppIntent.octaveUp,
      );
    });

    test('an unbound chord is null, not a guess', () {
      expect(
        Keymap().intentFor(const KeyChord(LogicalKeyboardKey.f12)),
        isNull,
      );
    });

    test('no chord means two things', () {
      // The one invariant that cannot be resolved at dispatch time. An intent
      // may have several chords; a chord may not have several intents.
      final seen = <KeyChord>{};
      for (final (chord, _) in kDefaultBindings) {
        expect(seen.add(chord), isTrue, reason: 'duplicate ${chord.label}');
      }
    });

    test('Delete and Backspace both delete — one intent, two chords', () {
      final map = Keymap();
      expect(
        map.chordsFor(AppIntent.editDelete).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('Space is bound, which is what the other surfaces gain', () {
      // Loop Studio had NO keyboard support at all — not even space-to-play.
      // Hosting this table is what gives it one.
      expect(
        Keymap().intentFor(const KeyChord(LogicalKeyboardKey.space)),
        AppIntent.transportToggle,
      );
    });
  });

  group('rebinding', () {
    test('a rebound chord takes the new meaning', () {
      final map = Keymap().rebound(
        const KeyChord(LogicalKeyboardKey.f9),
        AppIntent.transportStop,
      );
      expect(
        map.intentFor(const KeyChord(LogicalKeyboardKey.f9)),
        AppIntent.transportStop,
      );
      // …and the default is untouched, because a Keymap is a value.
      expect(
        Keymap().intentFor(const KeyChord(LogicalKeyboardKey.f9)),
        isNull,
      );
    });

    test('rebinding an occupied chord REPLACES it', () {
      final map = Keymap().rebound(
        const KeyChord(LogicalKeyboardKey.f5),
        AppIntent.transportStop,
      );
      expect(
        map.intentFor(const KeyChord(LogicalKeyboardKey.f5)),
        AppIntent.transportStop,
      );
    });

    test('a chord can be removed', () {
      final map = Keymap().without(const KeyChord(LogicalKeyboardKey.f5));
      expect(map.intentFor(const KeyChord(LogicalKeyboardKey.f5)), isNull);
    });
  });

  group('persistence', () {
    test('an untouched keymap stores NOTHING', () {
      // The load-bearing property: storing the whole table would freeze
      // today's defaults on the user's device, so a later release that
      // improves a binding would never reach anyone who had opened the sheet.
      expect(Keymap().toJson(), isEmpty);
    });

    test('only the difference is stored, and it round-trips', () {
      final map = Keymap().rebound(
        const KeyChord(LogicalKeyboardKey.f9),
        AppIntent.transportStop,
      );
      final json = map.toJson();
      expect(json, hasLength(1));

      final back = Keymap.fromJson(json);
      expect(
        back.intentFor(const KeyChord(LogicalKeyboardKey.f9)),
        AppIntent.transportStop,
      );
      // …and every default the user did not touch is still there.
      expect(
        back.intentFor(const KeyChord(LogicalKeyboardKey.f5)),
        AppIntent.transportPlaySong,
      );
    });

    test('a REMOVED default stays removed across a reload', () {
      // Otherwise a binding the user deliberately cleared comes back on the
      // next launch, which reads as the app ignoring them.
      final map = Keymap().without(const KeyChord(LogicalKeyboardKey.f5));
      final back = Keymap.fromJson(map.toJson());
      expect(back.intentFor(const KeyChord(LogicalKeyboardKey.f5)), isNull);
    });

    test('malformed stored data degrades to the defaults, never a crash', () {
      // A keymap that will not load would lock someone out of their own
      // keyboard, so every failure here has to be survivable.
      for (final raw in [
        null,
        42,
        'nope',
        <Object?>[],
        {'not-a-token': 'clipCopy'},
        {'c:99999999': 'noSuchIntent'},
      ]) {
        final map = Keymap.fromJson(raw);
        expect(
          map.intentFor(const KeyChord(LogicalKeyboardKey.f5)),
          AppIntent.transportPlaySong,
          reason: '$raw',
        );
      }
    });
  });

  group('the sheet has something to show for every intent', () {
    test('every intent has a label and a group', () {
      // An unlisted shortcut does not exist — so a new intent must not be able
      // to appear without the sheet knowing how to describe it.
      for (final intent in AppIntent.values) {
        expect(appIntentLabel(intent), isNotEmpty, reason: intent.name);
        expect(
          appIntentGroupLabel(appIntentGroup(intent)),
          isNotEmpty,
          reason: intent.name,
        );
      }
    });
  });
}
