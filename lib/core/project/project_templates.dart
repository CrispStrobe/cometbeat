// lib/core/project/project_templates.dart
//
// WS-W6 slice 2 — something to start FROM.
//
// Slice 1 made a project survive the app closing, which is what the browser
// needed to exist at all. But it left the browser's first impression as an
// empty list with a Save button: a player who has never saved anything opens it
// and there is nothing there, so the panel reads as broken rather than empty.
// Templates are the fix, and they are the cheapest of the remaining five tabs —
// the instrument/sample/catalog tabs are the Sound Library owner's, and none of
// them can be dragged anywhere until the browser is a docked panel.
//
// WHY A `Project` AND NOT A GROOVE. A template could have been "a starter
// GrooveSpec", which is smaller. But then it would only ever open in Loop
// Studio, and the whole point of `Project` (WS-W1) is that one document holds
// several tracks of different kinds. A template that is a `Project` can grow a
// second track later without changing anything here or in the browser.
//
// TEMPLATES ARE BUILT, NOT STORED. Each is a function, so a template is always
// a fresh object — hand out a shared `const` and two players (or two opens)
// would be editing the same tracks. `Project` is deeply immutable, which makes
// that safe today, and a function keeps it safe when it stops being.
//
// PURE DART. No Flutter import, so the whole set is testable without pumping a
// widget — and the names are the one thing here a translator would want, which
// is why they are l10n KEYS resolved by the caller rather than strings baked in.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';

/// A starting point offered in the browser.
class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.build,
  });

  /// Stable — used as a widget key and, if templates are ever remembered, as
  /// the thing remembered. Never shown.
  final String id;

  /// Makes a FRESH project. See the header: never a shared instance.
  final Project Function() build;
}

/// The built-in templates, in the order the browser shows them.
///
/// Deliberately few. A long list of starting points is its own decision to
/// make, and the player came here to play something, not to choose.
final List<ProjectTemplate> kProjectTemplates = [
  ProjectTemplate(
    id: 'empty',
    // A blank project is a real starting point, not a no-op: it is how you put
    // down what you were doing and begin something else, and without it the
    // only route to an empty desk is deleting tracks one by one.
    build: () => Project(name: 'Untitled'),
  ),
  ProjectTemplate(
    id: 'beat',
    // Drums alone: the smallest thing that sounds like music and the usual
    // first move — something to play along to.
    build: () => Project(
      name: 'Beat',
      tracks: [
        ProjectTrack(
          id: 'loop-1',
          kind: AppMode.loop,
          name: 'Groove',
          document: const GrooveSpec(enabled: {'drums'}),
        ),
      ],
    ),
  ),
  ProjectTemplate(
    id: 'band',
    // Drums + bass + chords is the "band" the Loop Studio was built around, and
    // its default tempo/key, so this opens on familiar ground rather than on
    // somebody's idea of a nicer preset.
    build: () => Project(
      name: 'Band',
      tracks: [
        ProjectTrack(
          id: 'loop-1',
          kind: AppMode.loop,
          name: 'Band',
          document: const GrooveSpec(enabled: {'drums', 'bass', 'chords'}),
        ),
      ],
    ),
  ),
  ProjectTemplate(
    id: 'slow',
    // The same band, slower. Tempo is the single control a learner reaches for
    // first, and 75 is one of the three tempos whose eighth-steps stay integral
    // in BOTH milliseconds and samples — the invariant the whole loop engine
    // rests on — so a template must not quietly pick a value outside it.
    build: () => Project(
      name: 'Slow band',
      tracks: [
        ProjectTrack(
          id: 'loop-1',
          kind: AppMode.loop,
          name: 'Band',
          document: const GrooveSpec(
            enabled: {'drums', 'bass', 'chords'},
            tempoBpm: 75,
          ),
        ),
      ],
    ),
  ),
];

/// The template with [id], or null.
ProjectTemplate? projectTemplateById(String id) {
  for (final template in kProjectTemplates) {
    if (template.id == id) return template;
  }
  return null;
}
