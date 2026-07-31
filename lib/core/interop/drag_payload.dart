// WS-X2 step 1 — what travels when you drag music from one surface to another.
//
// The card asks for "one `DragTarget` protocol carrying (kind, document)", and
// the reason it is one protocol rather than a handler per pair is arithmetic:
// five modes is twenty ordered pairs, and writing twenty drop handlers is how
// nineteen of them end up subtly different. `ProjectBridge` already converts
// any pair and already reports what a conversion costs; this is the payload
// that carries a document to a drop target, plus the decision of what should
// happen when it lands.
//
// Pure Dart — no widgets — so the decision is testable without pumping a
// surface. The widget half is a thin wrapper over `dropDecisionFor`.
//
// ⚠️ BEFORE YOU ADD A DROP TARGET, KNOW WHERE THE DRAG COMES FROM.
//
// This protocol shipped with four drop targets and, for two days, **no drag
// source at all** — `Draggable<MusicDragPayload>` occurred zero times in `lib/`,
// and no two music surfaces were ever on screen together, so the gesture those
// targets accept could not be started by anyone. Every target was correct and
// tested; each author was looking at their own, which was genuinely finished.
// The missing half lived in the space between them, and the card was recorded
// as complete.
//
// The source is the WS-X6 clipboard (`shared/widgets/tray_panel.dart`), and the
// property that makes it work is one a menu or a bottom sheet cannot have: it
// is an INLINE band a host puts in its own layout, so the chip and the target
// share one frame with no barrier between them. A source behind a route or a
// modal can be looked at and never dragged onto anything.
//
// `test/drag_protocol_reachable_test.dart` now enforces this, because a note
// like the one you are reading did not travel: two more targets were wired
// after it was written. If that test is red, adding another target will not
// help — the app has lost its way in.

import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';

/// Music in flight between two surfaces.
///
/// [document]'s runtime type follows [kind], exactly as `ProjectBridge` defines
/// it — a `TrackerSong` for [AppMode.tracker], a `MultiPartScore` for
/// [AppMode.score], and so on.
class MusicDragPayload {
  const MusicDragPayload({
    required this.kind,
    required this.document,
    this.label,
    this.trackId,
  });

  final AppMode kind;
  final Object document;

  /// What to call it while it is being dragged ("Pattern 3", "Bass").
  final String? label;

  /// The project track it came from, when it came from one.
  ///
  /// Carried so a drop can tell "this is the same track arriving home" from
  /// "this is a copy of something else" — the same distinction WS-X1 draws
  /// between a live open and a converting one.
  final String? trackId;
}

/// What dropping [payload] on a [target] surface would do.
enum DropOutcome {
  /// Same kind: the document lands as it is. Nothing is converted, so nothing
  /// can be lost.
  exact,

  /// A different kind, and the conversion carries everything.
  converted,

  /// A different kind, and the conversion costs something the user should see
  /// BEFORE it commits — which is what the card means by "show the loss report
  /// on drop".
  lossy,

  /// The pair has no converter. Refused, with a reason.
  unsupported,
}

/// The answer to "what happens if I let go here?"
class DropDecision {
  const DropDecision({
    required this.outcome,
    required this.target,
    this.document,
    this.report,
    this.reason,
  });

  final DropOutcome outcome;
  final AppMode target;

  /// The document as the target would receive it — already converted when the
  /// kinds differ. Null when [outcome] is [DropOutcome.unsupported].
  final Object? document;

  /// What the conversion cost. Null for an exact drop, since nothing ran.
  final ConversionReport? report;

  /// Why it was refused, for [DropOutcome.unsupported].
  final String? reason;

  /// Whether a UI should confirm before committing.
  ///
  /// Only [DropOutcome.lossy] asks. A conversion that loses nothing does not
  /// need a dialog, and making people dismiss one for every drop is how they
  /// learn to dismiss the one that mattered.
  bool get needsConfirmation => outcome == DropOutcome.lossy;

  bool get canDrop => outcome != DropOutcome.unsupported;
}

/// Work out what a drop would do, without doing it.
///
/// Deliberately computes the conversion up front rather than at commit time:
/// the loss report IS the conversion's output, so there is no way to tell the
/// user what a drop will cost without performing it. The result is handed back
/// so the commit does not run it twice.
/// [acceptsDirectly] names kinds the target can HOLD without converting.
///
/// ⚠️ Needed because not every drop target is a mode. The Audio Editor's
/// timeline is a CONTAINER: it holds `ScoreSource`, `TrackerSource`,
/// `DrumSource` and `GrooveSource` clips as they are. Asking the bridge to
/// convert a score "to audio" correctly answers *unsupported* — a bounce is
/// one-way — but that is the wrong question for a container, and answering it
/// would refuse a drop the timeline handles natively.
///
/// I only found this on wiring the first consumer; the protocol alone looked
/// complete. Empty by default, so a pure mode target behaves exactly as before.
DropDecision dropDecisionFor(
  MusicDragPayload payload,
  AppMode target, {
  Set<AppMode> acceptsDirectly = const {},
}) {
  // Held as-is by a container target: no conversion, nothing to lose.
  if (acceptsDirectly.contains(payload.kind)) {
    return DropDecision(
      outcome: DropOutcome.exact,
      target: target,
      document: payload.document,
    );
  }

  // ⚠️ A container should also take what can BECOME something it holds.
  //
  // Found by probing the case rather than by reading this file: a TAB could not
  // be dropped on the Audio Editor's timeline at all. `acceptsDirectly` listed
  // the kinds the timeline holds as-is (score/tracker/loop), everything else
  // fell through to `convert(kind → audio)` — correctly unsupported, since a
  // bounce is one-way — and the refusal even quoted the bounce message, which is
  // the wrong sentence for the case. So the one mode that could put nothing on
  // the timeline was the one most likely to want to.
  //
  // The order of [acceptsDirectly] is the preference, and it is the CALLER's to
  // state: for a tab, `score` keeps the pitches and the string voicings while
  // `tracker` quantizes onto a grid. A documented order beats a cleverer rule
  // nobody can predict — and beats trying every conversion to compare costs,
  // which would run several conversions to throw all but one away.
  if (acceptsDirectly.isNotEmpty) {
    for (final held in acceptsDirectly) {
      if (held == payload.kind) continue;
      final viaResult = ProjectBridge.convert(
        from: payload.kind,
        to: held,
        document: payload.document,
      );
      if (viaResult.isUnsupported || viaResult.document == null) continue;
      return DropDecision(
        outcome: viaResult.report.lossless
            ? DropOutcome.converted
            : DropOutcome.lossy,
        target: target,
        document: viaResult.document,
        report: viaResult.report,
      );
    }
  }

  // Same kind: no conversion at all. This is the WS-X1 rule — a bridge round
  // trip on a same-kind drop would introduce loss that the drop did not need,
  // which is exactly the copy-instead-of-link bug in another shape.
  if (payload.kind == target) {
    return DropDecision(
      outcome: DropOutcome.exact,
      target: target,
      document: payload.document,
    );
  }

  final result = ProjectBridge.convert(
    from: payload.kind,
    to: target,
    document: payload.document,
  );

  if (result.isUnsupported || result.document == null) {
    return DropDecision(
      outcome: DropOutcome.unsupported,
      target: target,
      reason: result.unsupportedReason ??
          'A ${payload.kind.name} cannot become a ${target.name}.',
    );
  }

  return DropDecision(
    outcome: result.report.lossless ? DropOutcome.converted : DropOutcome.lossy,
    target: target,
    document: result.document,
    report: result.report,
  );
}

/// A one-line summary of what a drop costs, for a drag-over hint.
///
/// Short on purpose: this is read while a finger is held over a target, not
/// studied. The full report belongs in the confirmation.
String dropSummary(DropDecision decision) => switch (decision.outcome) {
      DropOutcome.exact => 'Moves here unchanged',
      DropOutcome.converted => 'Converts cleanly',
      DropOutcome.lossy => () {
          // A lossy decision always carries a report in practice, but a hint
          // is not the place to assert that — crashing a drag-over because a
          // caller built an odd decision would be a poor trade.
          final report = decision.report;
          if (report == null) return 'Converts — some detail changes';
          final lost = report.lost.length;
          final approximated = report.approximated.length;
          if (lost > 0 && approximated > 0) {
            return 'Converts — $lost lost, $approximated changed';
          }
          if (lost > 0) {
            return 'Converts — $lost thing${lost == 1 ? '' : 's'} lost';
          }
          return 'Converts — $approximated changed';
        }(),
      // The bridge's refusal is a full sentence; this is read while a finger
      // is held over a target, so it is clipped here rather than at each
      // caller. The whole reason belongs in the refusal message on drop.
      DropOutcome.unsupported => _clip(decision.reason ?? 'Cannot go here'),
    };

/// Keep a drag-over hint glanceable.
String _clip(String text, {int max = 52}) =>
    text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';
