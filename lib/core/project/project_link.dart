// lib/core/project/project_link.dart
//
// WS-X1 — live links, not copies.
//
// THE GAP THIS CLOSES. Every "Open in…" in the app goes through
// `ProjectBridge.convert`, which is right for a KIND CHANGE — a tracker pattern
// becoming notation genuinely is a new document, and the loss report has to be
// shown before the user commits. But it was also the only door, so opening a
// tracker song *in the Tracker* produced a converted copy too, and the edit had
// nowhere to go back to. That is the difference between five editors and one
// workstation.
//
// THE RULE, and it is one line: a SAME-KIND open needs no conversion at all.
// The document is already the type that mode edits. Hand it over, take it back
// when the mode is done, and put it in the same track — keeping the track's id,
// name and MIX, because a link that silently reset the level and pan on return
// would be worse than the copy it replaces.
//
// WHAT IS DELIBERATELY UNCHANGED. A different-kind open still converts and
// still produces a copy with `ProjectBridge`'s loss report. Nothing here makes
// a lossy conversion pretend to be a link.

import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/core/services/project_service.dart';

/// A document handed to a mode, and whether edits can travel back.
class ProjectLink {
  const ProjectLink({
    required this.document,
    required this.trackId,
    required this.live,
    this.report,
    this.unsupportedReason,
  });

  /// What the mode should open. Null when the pair has no route.
  final Object? document;

  /// The track this came from, or null when the open produced a copy that
  /// belongs to nothing.
  final String? trackId;

  /// Whether [ProjectLinker.writeBack] will land — i.e. whether this was a
  /// same-kind open. A caller should show "editing the project track" versus
  /// "editing a copy" from this, because the difference is the whole feature.
  final bool live;

  /// The conversion's cost, when a conversion happened. Null for a live link,
  /// because nothing was lost.
  final ConversionReport? report;

  /// Why there is no document, in a sentence fit to show a user.
  final String? unsupportedReason;
}

/// Opens project tracks in a mode, and takes the edits back.
class ProjectLinker {
  const ProjectLinker(this.projects);

  final ProjectService projects;

  /// Opens [trackId] for editing in [mode].
  ///
  /// Same kind → a LIVE link: the track's own document, unconverted.
  /// Different kind → a converted copy plus its loss report, exactly as before.
  ProjectLink open(
    String trackId,
    AppMode mode, {
    SymbolicAnnotations? annotations,
  }) {
    final track = projects.track(trackId);
    if (track == null) {
      return const ProjectLink(
        document: null,
        trackId: null,
        live: false,
        unsupportedReason: 'That track is no longer in the project.',
      );
    }

    // A track carried verbatim because no codec could read it must not be
    // handed to an editor — the editor would be given raw JSON. It is still
    // SAFE in the project (that is the point of `unreadable`), just not
    // editable here.
    if (!track.isReadable || track.document == null) {
      return ProjectLink(
        document: null,
        trackId: trackId,
        live: false,
        unsupportedReason: track.unknownKind != null
            ? 'This track was made by a newer version '
                '(${track.unknownKind}) and is kept as-is.'
            : 'This track has no editable document.',
      );
    }

    if (track.kind == mode) {
      // The whole point: no converter, no report, no copy.
      return ProjectLink(
        document: track.document,
        trackId: trackId,
        live: true,
      );
    }

    final converted = ProjectBridge.convert(
      from: track.kind,
      to: mode,
      document: track.document!,
      annotations: annotations,
    );
    return ProjectLink(
      document: converted.document,
      // A conversion produces a copy; it belongs to no track, and saying so is
      // what stops a caller writing a lossily-converted document back over the
      // original.
      trackId: null,
      live: false,
      report: converted.report,
      unsupportedReason: converted.unsupportedReason,
    );
  }

  /// Puts an edited document back into its track.
  ///
  /// Returns false when [link] was not live or the track has since gone —
  /// never throws, because this is called on the way out of a screen and a
  /// throw there would lose the edit AND crash the pop.
  bool writeBack(ProjectLink link, Object? document) {
    if (!link.live || link.trackId == null) return false;
    return projects.updateDocument(link.trackId!, document);
  }

  /// Puts [document] into the project as a new track and returns its id.
  ///
  /// The other half of "live": a mode needs a way to put its work IN the
  /// project before there is anything to link to.
  String add({
    required AppMode kind,
    required Object? document,
    String? name,
  }) =>
      projects.addTrack(kind: kind, document: document, name: name);
}
