// The five-surface interop MATRIX, as a test.
//
// Every hole this session closed was found by building this matrix by hand and
// none of them was written down anywhere as missing: the Score Workshop could
// neither receive music from another mode nor put its own on the shelf; a TAB
// could not be dropped on the Audio Editor's timeline at all; the ADVANCED
// Tracker had no FX rack while the beginner one did. A feature list says what
// exists — only a matrix says what is absent.
//
// So the matrix is executable now. It reads the SOURCE rather than pumping five
// screens, deliberately: three of them run continuous tickers (so
// `pumpAndSettle` hangs), mounting all five would be minutes of CI for a
// structural question, and what is being asserted is "this surface offers the
// affordance at all" — exactly the thing that is invisible from inside any one
// screen.
//
// ⚠️ It is a WIRING guard, not a behaviour guard. Each affordance has its own
// suite proving it works (`drag_payload_test`, `tray_hosts_test`,
// `fx_preset_sheet_test`, `daw_project_link_test`, …). This one catches the
// failure those cannot see: a surface that quietly never joins.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The five authoring surfaces, by the file that owns each.
const _surfaces = <String, String>{
  'Score Workshop':
      'lib/features/workshop/screens/composition_workshop_screen.dart',
  'Tab Workshop': 'lib/features/games/composition/tab_workshop_screen.dart',
  'Advanced Tracker':
      'lib/features/games/composition/advanced_tracker_screen.dart',
  'Loop Studio': 'lib/features/games/composition/loop_mixer_screen.dart',
  'Audio Editor': 'lib/features/games/composition/daw_screen.dart',
};

/// What each surface must offer, and the call that proves it does.
///
/// A marker is the API call, not a widget name: a screen can rename its own
/// helpers freely, but it cannot claim the affordance without calling the
/// shared entry point.
const _affordances = <String, String>{
  'a drop target (WS-X2)': 'DragTarget<MusicDragPayload>',
  'a clipboard host (WS-X6)': 'TrayPanel(',
  'the FX-preset shelf': 'showFxPresetSheet(',
  'a live project link (WS-X1)': 'openProjectTrack',
};

void main() {
  group('every surface offers every interop affordance', () {
    for (final surface in _surfaces.entries) {
      final source = File(surface.value).readAsStringSync();
      for (final affordance in _affordances.entries) {
        test('${surface.key} — ${affordance.key}', () {
          expect(
            source,
            contains(affordance.value),
            reason:
                '${surface.key} does not offer ${affordance.key}. If that is '
                'deliberate, say why here rather than deleting the row — the '
                'holes this file exists for were all invisible until someone '
                'wrote the matrix out.',
          );
        });
      }
    }
  });

  test('the matrix covers the surfaces that exist', () {
    // Guards the guard: a sixth authoring surface must be added here, or this
    // file quietly stops describing the app. Screens are counted by the tester
    // interface every one of them exposes.
    final screens = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_screen.dart'))
        .where((f) =>
            f.readAsStringSync().contains('DragTarget<MusicDragPayload>'))
        .map((f) => f.path)
        .toSet();

    expect(
      screens.difference(_surfaces.values.toSet()),
      isEmpty,
      reason: 'a screen accepts music drops but is not in the matrix above',
    );
  });
}
