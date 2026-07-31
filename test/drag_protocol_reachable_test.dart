// WS-X2 / WS-X6 — the drag protocol must stay REACHABLE.
//
// This test exists because of a defect that took two days and three agents to
// notice, and that no ordinary test could have caught.
//
// WS-X2 shipped a drag-and-drop protocol and, over several sessions, four drop
// targets. Every one of them was correct, well tested, and found a real latent
// bug in the surface it was added to. But `Draggable<MusicDragPayload>` occurred
// ZERO times in `lib/`: there was no drag SOURCE anywhere in the app, and no two
// music surfaces were ever on screen together, so the gesture those targets
// accept could not be started by anyone. The card was even recorded as complete.
//
// Each author was looking at their own target, which was genuinely finished. The
// missing half was not in anyone's diff — it was in the space between them.
// **A note on a card did not travel; two more targets were wired after it.** A
// failing test would have.
//
// WS-X6's clipboard supplies the source, so the rule below is satisfiable today
// and this is a guard rather than a scold. If it ever goes red, the question to
// ask is not "which test broke" but "can a player still start this gesture at
// all" — and the answer, when a source is missing, is no.
//
// It reads SOURCE TEXT rather than the widget tree on purpose: the property is
// about the whole app, not about any one screen that a widget test could pump.
// `project_codec_test` already reads `lib/` this way.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `.dart` file under `lib/`, as text.
Map<String, String> _libSources() {
  final out = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    out[entity.path] = entity.readAsStringSync();
  }
  return out;
}

List<String> _filesContaining(Map<String, String> sources, String needle) => [
      for (final entry in sources.entries)
        if (entry.value.contains(needle)) entry.key,
    ]..sort();

void main() {
  late Map<String, String> sources;

  setUpAll(() {
    sources = _libSources();
    // If this ever finds nothing, the test is measuring its own bug rather than
    // the app's — a silent pass would be worse than useless here.
    expect(
      sources,
      isNotEmpty,
      reason: 'could not read lib/ — is the working directory the repo root?',
    );
  });

  test('a drop target implies a drag source somewhere in the app', () {
    final targets = _filesContaining(sources, 'DragTarget<MusicDragPayload>');
    final drags = _filesContaining(sources, 'Draggable<MusicDragPayload>');

    if (targets.isEmpty) return; // nothing to reach; nothing to guard.

    expect(
      drags,
      isNotEmpty,
      reason: 'These files accept a dragged document:\n'
          '  ${targets.join('\n  ')}\n'
          'and NOTHING in lib/ can start that drag, so a player cannot reach '
          'any of them. This is exactly the state WS-X2 shipped in and nobody '
          'saw for two days: four correct, tested drop targets wired to a '
          'gesture with no beginning.\n'
          'Adding a fifth target will not fix it. What is needed is a '
          '`Draggable<MusicDragPayload>` on a surface that is VISIBLE AT THE '
          'SAME TIME as a target — which is what the WS-X6 clipboard is: an '
          'inline band, not an overlay, so the chip and the target share one '
          'frame.',
    );
  });

  test('the drag source is co-visible with a target, not behind a route', () {
    // The subtler half, and the reason a menu or a bottom sheet would not do:
    // a source inside a pushed route or a modal cannot be dragged onto the
    // surface it covers. The clipboard band is a widget a host puts in its own
    // layout, so its file must not be reached through `showModalBottomSheet`.
    final drags = _filesContaining(sources, 'Draggable<MusicDragPayload>');
    if (drags.isEmpty) return; // the first test already reports this.

    for (final path in drags) {
      final source = sources[path]!;
      expect(
        source.contains('showModalBottomSheet'),
        isFalse,
        reason: '$path both starts a music drag and opens a modal sheet. If '
            'the draggable lives INSIDE that sheet, it cannot be dragged onto '
            'the surface behind it — the barrier is the whole reason WS-X2 '
            'could not be finished with a menu.',
      );
    }
  });

  test('the clipboard is the source, and it is a shared widget', () {
    // Named rather than left implicit: if this file moves or is deleted, the
    // failure should say what was lost, not just that a count changed.
    final drags = _filesContaining(sources, 'Draggable<MusicDragPayload>');
    expect(
      drags,
      contains('lib/shared/widgets/tray_panel.dart'),
      reason: 'The clipboard band is what makes every drop target reachable. '
          'If it has moved, update this test; if it has gone, the drop targets '
          'went with it.',
    );
  });
}
