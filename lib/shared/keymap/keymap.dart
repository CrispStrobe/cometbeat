// WS-T3 — the binding table: which key chord means which [AppIntent].
//
// Separate from the intents themselves because the two change for different
// reasons. A new verb is a code change every surface has to opt into; a
// rebinding is a preference one user makes on one device.
//
// The defaults are the tracker's, deliberately: they are the FT2 conventions
// several generations of tracker musicians already have in their fingers, and
// they were the best-considered interaction work in the app before this. The
// extraction moved them, it did not redesign them.

import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:flutter/services.dart';

/// A key plus the modifiers held with it.
///
/// Value-equal so it can key a map — which is the whole mechanism: resolving a
/// press is a single lookup rather than a ladder of `if`s.
class KeyChord {
  const KeyChord(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
  });

  final LogicalKeyboardKey key;

  /// Control OR Command. They are one modifier as far as bindings go: the same
  /// chord has to work on a Mac and on a PC keyboard, and no binding here
  /// wants to distinguish them.
  final bool ctrl;
  final bool shift;
  final bool alt;

  KeyChord copyWith({bool? ctrl, bool? shift, bool? alt}) => KeyChord(
        key,
        ctrl: ctrl ?? this.ctrl,
        shift: shift ?? this.shift,
        alt: alt ?? this.alt,
      );

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt);

  /// How the chord reads on a keymap sheet.
  String get label {
    final parts = [
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      _keyLabel(key),
    ];
    return parts.join('+');
  }

  /// Stable across runs, so a rebinding can be persisted.
  String get token =>
      '${ctrl ? 'c' : ''}${alt ? 'a' : ''}${shift ? 's' : ''}:${key.keyId}';

  static KeyChord? fromToken(String token) {
    final colon = token.indexOf(':');
    if (colon < 0) return null;
    final id = int.tryParse(token.substring(colon + 1));
    if (id == null) return null;
    final mods = token.substring(0, colon);
    return KeyChord(
      LogicalKeyboardKey(id),
      ctrl: mods.contains('c'),
      alt: mods.contains('a'),
      shift: mods.contains('s'),
    );
  }
}

String _keyLabel(LogicalKeyboardKey key) => switch (key) {
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.pageUp => 'PgUp',
      LogicalKeyboardKey.pageDown => 'PgDn',
      LogicalKeyboardKey.escape => 'Esc',
      LogicalKeyboardKey.delete => 'Del',
      LogicalKeyboardKey.backspace => 'Backspace',
      LogicalKeyboardKey.insert => 'Insert',
      LogicalKeyboardKey.space => 'Space',
      _ => key.keyLabel.isEmpty ? key.debugName ?? '?' : key.keyLabel,
    };

/// The default bindings — the tracker's, unchanged.
///
/// Several intents are bound to more than one chord (Delete and Backspace both
/// delete), which is why this is a list of pairs rather than a map from intent:
/// the lookup that matters is chord → intent.
const List<(KeyChord, AppIntent)> kDefaultBindings = [
  // FT2 function-key transport.
  (KeyChord(LogicalKeyboardKey.f5), AppIntent.transportPlaySong),
  (KeyChord(LogicalKeyboardKey.f6), AppIntent.transportPlayPattern),
  (KeyChord(LogicalKeyboardKey.f7), AppIntent.transportPlayFromCursor),
  (KeyChord(LogicalKeyboardKey.f8), AppIntent.transportStop),
  // Space is the universal one, and is what Loop Studio and the Audio Editor
  // get for free by hosting the same table.
  (KeyChord(LogicalKeyboardKey.space), AppIntent.transportToggle),

  // Block ops. Ctrl covers Command too.
  (KeyChord(LogicalKeyboardKey.keyC, ctrl: true), AppIntent.clipCopy),
  (KeyChord(LogicalKeyboardKey.keyX, ctrl: true), AppIntent.clipCut),
  (KeyChord(LogicalKeyboardKey.keyV, ctrl: true), AppIntent.clipPaste),
  (KeyChord(LogicalKeyboardKey.keyM, ctrl: true), AppIntent.clipPasteMix),
  (KeyChord(LogicalKeyboardKey.keyA, ctrl: true), AppIntent.selectAll),
  (KeyChord(LogicalKeyboardKey.keyI, ctrl: true), AppIntent.editInterpolate),
  (KeyChord(LogicalKeyboardKey.keyZ, ctrl: true), AppIntent.editUndo),
  (KeyChord(LogicalKeyboardKey.keyY, ctrl: true), AppIntent.editRedo),
  (KeyChord(LogicalKeyboardKey.escape), AppIntent.selectNone),

  // Transpose (Alt + arrows / pages).
  (KeyChord(LogicalKeyboardKey.arrowUp, alt: true), AppIntent.transposeUp),
  (KeyChord(LogicalKeyboardKey.arrowDown, alt: true), AppIntent.transposeDown),
  (KeyChord(LogicalKeyboardKey.pageUp, alt: true), AppIntent.transposeOctaveUp),
  (
    KeyChord(LogicalKeyboardKey.pageDown, alt: true),
    AppIntent.transposeOctaveDown
  ),

  // Navigation, and the same keys with Shift to extend a selection.
  (KeyChord(LogicalKeyboardKey.arrowUp), AppIntent.cursorUp),
  (KeyChord(LogicalKeyboardKey.arrowDown), AppIntent.cursorDown),
  (KeyChord(LogicalKeyboardKey.arrowLeft), AppIntent.cursorLeft),
  (KeyChord(LogicalKeyboardKey.arrowRight), AppIntent.cursorRight),
  (KeyChord(LogicalKeyboardKey.arrowUp, shift: true), AppIntent.selectUp),
  (KeyChord(LogicalKeyboardKey.arrowDown, shift: true), AppIntent.selectDown),
  (KeyChord(LogicalKeyboardKey.arrowLeft, shift: true), AppIntent.selectLeft),
  (KeyChord(LogicalKeyboardKey.arrowRight, shift: true), AppIntent.selectRight),

  // Rows.
  (KeyChord(LogicalKeyboardKey.insert), AppIntent.rowInsert),
  (KeyChord(LogicalKeyboardKey.delete, shift: true), AppIntent.rowDelete),
  (KeyChord(LogicalKeyboardKey.delete), AppIntent.editDelete),
  (KeyChord(LogicalKeyboardKey.backspace), AppIntent.editDelete),

  // Octave.
  (KeyChord(LogicalKeyboardKey.pageUp), AppIntent.octaveUp),
  (KeyChord(LogicalKeyboardKey.pageDown), AppIntent.octaveDown),

  // ── WS-A3 / WS-L1 ────────────────────────────────────────────────────────
  // Chosen to not collide with anything above. Every one of these was checked
  // against the existing table, because a duplicate chord is the one thing the
  // dispatch cannot resolve.
  (KeyChord(LogicalKeyboardKey.keyS, ctrl: true), AppIntent.clipSplit),
  (KeyChord(LogicalKeyboardKey.keyT, ctrl: true), AppIntent.trimToSelection),
  (KeyChord(LogicalKeyboardKey.keyD, ctrl: true), AppIntent.duplicate),
  // Comma/period: the standard "step by one frame" pair, and they are free.
  (KeyChord(LogicalKeyboardKey.comma), AppIntent.nudgeLeft),
  (KeyChord(LogicalKeyboardKey.period), AppIntent.nudgeRight),
  (KeyChord(LogicalKeyboardKey.bracketLeft), AppIntent.markerPrevious),
  (KeyChord(LogicalKeyboardKey.bracketRight), AppIntent.markerNext),
  // ⚠️ Plain M and S are the conventional mute/solo keys, and they are safe
  // here for one specific reason: the Tracker uses the classic QWERTY piano
  // layout, where **M and S are NOTE keys**, and it is only unharmed because it
  // does not dispatch these intents — an unhandled intent falls through to note
  // entry. If the Tracker ever handles mute/solo, these two must move first.
  // Pinned by `tracker_keymap_characterization_test`.
  (KeyChord(LogicalKeyboardKey.keyM), AppIntent.toggleMute),
  (KeyChord(LogicalKeyboardKey.keyS), AppIntent.toggleSolo),
];

/// A resolved set of bindings: the defaults, plus whatever the user changed.
class Keymap {
  Keymap([List<(KeyChord, AppIntent)>? bindings])
      : _byChord = {
          for (final (chord, intent) in bindings ?? kDefaultBindings)
            chord: intent,
        };

  final Map<KeyChord, AppIntent> _byChord;

  /// What this chord means, or null if nothing is bound to it.
  AppIntent? intentFor(KeyChord chord) => _byChord[chord];

  /// Every chord bound to [intent] — an intent may have more than one (Delete
  /// and Backspace), and the sheet should show both.
  List<KeyChord> chordsFor(AppIntent intent) => [
        for (final entry in _byChord.entries)
          if (entry.value == intent) entry.key,
      ];

  /// Everything, for the sheet.
  Map<KeyChord, AppIntent> get bindings => Map.unmodifiable(_byChord);

  /// A copy with [chord] bound to [intent], replacing whatever held that chord.
  ///
  /// The chord is what is unique, not the intent: binding a second key to
  /// "undo" is reasonable, but one chord meaning two things is not resolvable.
  Keymap rebound(KeyChord chord, AppIntent intent) => Keymap([
        for (final entry in _byChord.entries)
          if (entry.key != chord) (entry.key, entry.value),
        (chord, intent),
      ]);

  /// A copy with [chord] unbound.
  Keymap without(KeyChord chord) => Keymap([
        for (final entry in _byChord.entries)
          if (entry.key != chord) (entry.key, entry.value),
      ]);

  /// Only what DIFFERS from the defaults, so a stored keymap does not freeze
  /// the defaults in place — a later release that improves a default binding
  /// should reach a user who never rebound it.
  Map<String, String> toJson() {
    final defaults = Keymap();
    final out = <String, String>{};
    for (final entry in _byChord.entries) {
      if (defaults.intentFor(entry.key) != entry.value) {
        out[entry.key.token] = entry.value.name;
      }
    }
    // A default binding the user REMOVED has to be recorded too, or it comes
    // back on the next launch.
    for (final entry in defaults.bindings.entries) {
      if (!_byChord.containsKey(entry.key)) out[entry.key.token] = '';
    }
    return out;
  }

  /// Rebuild from [json] on top of the current defaults. Anything unreadable is
  /// skipped rather than throwing: a keymap that will not load would lock
  /// someone out of their own keyboard.
  static Keymap fromJson(Object? json) {
    var map = Keymap();
    if (json is! Map) return map;
    for (final entry in json.entries) {
      final chord = KeyChord.fromToken('${entry.key}');
      if (chord == null) continue;
      final name = '${entry.value}';
      if (name.isEmpty) {
        map = map.without(chord);
        continue;
      }
      final intent = AppIntent.values.where((i) => i.name == name).firstOrNull;
      if (intent != null) map = map.rebound(chord, intent);
    }
    return map;
  }
}

/// Read the modifiers currently held, collapsing Control and Command.
KeyChord chordOf(LogicalKeyboardKey key, HardwareKeyboard keyboard) => KeyChord(
      key,
      ctrl: keyboard.isControlPressed || keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
