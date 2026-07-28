// lib/shared/widgets/open_in_menu.dart
//
// C4 — "Open in…", the same menu in every mode.
//
// Each mode used to grow its own one-off hand-off ("Open in Tracker" on the
// Loop Mixer, and not much else), each knowing which converter to call and each
// silently dropping whatever the target could not hold. This menu asks
// [ProjectBridge] instead, so a mode gets every route that exists — including
// ones added later — without touching its screen.
//
// The part that matters is the WARNING. A conversion that quietly loses your
// fingering or your velocity is worse than one that refuses, because you find
// out later, after you have edited the copy. So a lossy conversion is shown as
// a confirmation with the [ConversionReport] spelled out; a lossless one goes
// straight through, because a dialog that always appears stops being read.

import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:flutter/material.dart';

/// A mode's name in the user's language. The pure-Dart [appModeLabel] cannot see
/// [AppLocalizations] (it is Flutter-free), so the localized name lives here,
/// where the menu and its dialogs have a [BuildContext]. English mirrors
/// [appModeLabel]; the per-edge loss REASONS still come from the bridge in
/// English (a deeper, follow-up localization).
String localizedModeLabel(AppLocalizations l10n, AppMode mode) =>
    switch (mode) {
      AppMode.tracker => l10n.appModeTracker,
      AppMode.loop => l10n.appModeLoop,
      AppMode.score => l10n.appModeScore,
      AppMode.tab => l10n.appModeTab,
      AppMode.audio => l10n.appModeAudio,
    };

/// A stable l10n key for a STATIC reason [message] produced by a sub-converter
/// that does not tag its own reasons at the call site (unlike the bridge, which
/// passes a key to `addLost`). Keyed by the exact English so the two cannot
/// drift — a test enumerates every edge's reasons and asserts each is either
/// keyed here / at its site, or a known dynamic one. Returns null for the
/// dynamic reasons (interpolated counts), which show English verbatim.
String? _staticReasonKey(String message) => switch (message) {
      'fingering chosen for you — a score does not say which string' =>
        'reasonFingeringChosen',
      'note lengths rounded to the nearest note value' =>
        'reasonLengthsRounded',
      'string and fret choice (a loop track carries pitches)' =>
        'reasonStringFretLoop',
      'the tab does not fill whole bars — the loop will not be a clean length' =>
        'reasonTabNotWholeBars',
      'tuning assumed — the song did not carry one' => 'reasonTuningAssumed',
      _ => null,
    };

/// The localized text for a [ConversionReport] reason. It resolves the reason's
/// l10n key in order — first a key the bridge tagged at the call site
/// ([ConversionReport.keyFor], which also carries [ConversionReport.argsFor] for
/// a DYNAMIC reason's counts), then the central static map ([_staticReasonKey])
/// for sub-converter reasons — and falls back to the English [message] only for a
/// reason with no key at all.
String localizedReason(
  AppLocalizations l10n,
  ConversionReport report,
  String message,
) {
  final key = report.keyFor(message) ?? _staticReasonKey(message);
  final a = report.argsFor(message);
  int arg(int i) => a[i] as int;
  return switch (key) {
    'reasonEffectColumns' => l10n.reasonEffectColumns,
    'reasonNoChannels' => l10n.reasonNoChannels,
    'reasonQuantizedPatternGrid' => l10n.reasonQuantizedPatternGrid,
    'reasonPartsBeyondFirst' => l10n.reasonPartsBeyondFirst,
    'reasonSnappedLoopGrid' => l10n.reasonSnappedLoopGrid,
    'reasonVelocityScore' => l10n.reasonVelocityScore,
    'reasonFingeringChosen' => l10n.reasonFingeringChosen,
    'reasonLengthsRounded' => l10n.reasonLengthsRounded,
    'reasonStringFretLoop' => l10n.reasonStringFretLoop,
    'reasonTabNotWholeBars' => l10n.reasonTabNotWholeBars,
    'reasonTuningAssumed' => l10n.reasonTuningAssumed,
    // Dynamic (interpolated counts): the args ride along on the report.
    'reasonClampedToNut' => l10n.reasonClampedToNut(arg(0)),
    'reasonOtherChannels' => l10n.reasonOtherChannels(arg(0)),
    'reasonChordsSpread' => l10n.reasonChordsSpread(arg(0)),
    'reasonFingeringChosenN' => l10n.reasonFingeringChosenN(arg(0)),
    'reasonPitchedChannels' => l10n.reasonPitchedChannels(arg(0)),
    'reasonChannelMismatch' => l10n.reasonChannelMismatch(arg(0), arg(1)),
    _ => message,
  };
}

/// The localized one-line cost of the [from]→[to] edge, shown under each menu
/// item — the localized twin of [ProjectBridge.describeEdge]. The English values
/// MIRROR that method exactly (a widget test asserts the EN text it produces), so
/// the two must be kept in sync until the bridge exposes structured edge codes.
/// (The dynamic [ConversionReport] REASONS remain English — a deeper follow-up.)
String localizedEdgeSubtitle(AppLocalizations l10n, AppMode from, AppMode to) {
  if (from == to) return l10n.openInEdgeAlreadyHere;
  if (to == AppMode.audio) return l10n.openInEdgeToAudio;
  if (from == AppMode.audio) return l10n.openInEdgeFromAudio;
  return switch ((from, to)) {
    (AppMode.tab, AppMode.tracker) => l10n.openInEdgeTabTracker,
    (AppMode.tracker, AppMode.tab) => l10n.openInEdgeTrackerTab,
    (AppMode.tab, AppMode.score) => l10n.openInEdgeTabScore,
    (AppMode.score, AppMode.tab) => l10n.openInEdgeScoreTab,
    (AppMode.tab, AppMode.loop) ||
    (AppMode.score, AppMode.loop) =>
      l10n.openInEdgeToLoopGrid,
    (AppMode.loop, AppMode.tab) => l10n.openInEdgeLoopTab,
    (AppMode.loop, AppMode.score) => l10n.openInEdgeLoopScore,
    (AppMode.loop, AppMode.tracker) => l10n.openInEdgeLoopTracker,
    (AppMode.tracker, AppMode.score) => l10n.openInEdgeTrackerScore,
    (AppMode.score, AppMode.tracker) => l10n.openInEdgeScoreTracker,
    (AppMode.tracker, AppMode.loop) => l10n.openInEdgeTrackerLoop,
    _ => ProjectBridge.describeEdge(from, to),
  };
}

/// An "Open in…" overflow action.
///
/// [documentBuilder] is called lazily, only once a target is chosen — a mode
/// should not pay to assemble its document just to draw a menu.
class OpenInMenu extends StatelessWidget {
  const OpenInMenu({
    super.key,
    required this.from,
    required this.documentBuilder,
    required this.onConverted,
    this.tuning,
    this.capo = 0,
    this.annotations,
    this.icon = const Icon(Icons.open_in_new),
    this.tooltip,
    this.targets,
    this.keyPrefix = '',
    this.liveKind,
  });

  /// The mode this menu is shown in.
  final AppMode from;

  /// Builds the document to convert. Called on selection, not on build.
  final Object Function() documentBuilder;

  /// Called with a successful conversion. The host decides what "open" means —
  /// push a screen, replace the current document, start a new project.
  final void Function(AppMode target, ConversionResult result) onConverted;

  /// The tuning to use when a target needs one and the source has none.
  final Tuning? tuning;
  final int capo;

  /// A side-car from an earlier conversion of this material, so a round trip
  /// can restore what was parked in it.
  final SymbolicAnnotations? annotations;

  final Widget icon;

  /// The button's tooltip. Null falls back to the localized "Open in…" — a
  /// caller passes its own (e.g. "Open a copy in…") when the door means
  /// something more specific.
  final String? tooltip;

  /// Restricts the menu to these modes (still intersected with what the bridge
  /// can actually reach).
  ///
  /// A host needs this because CONVERTING and OPENING are different problems:
  /// the bridge can produce a document for every reachable mode, but a screen
  /// can only offer a destination it has a route to push. Offering one it
  /// cannot open would convert the user's work and then drop it.
  final List<AppMode>? targets;

  /// Prefixes every internal widget key (default ''), so two menus can coexist
  /// on one screen (e.g. a "copy" door and an in-place "replace" door) without
  /// colliding on `ValueKey('open-in')`. Empty keeps the original keys.
  final String keyPrefix;

  /// WS-X1 — the KIND OF THE PROJECT TRACK this document came from.
  ///
  /// The entry for that mode opens **live** (no conversion, edits travel back,
  /// see `ProjectLinker.open`); every other entry opens a copy. Null (the
  /// default) keeps the pre-project behaviour exactly: every entry is a
  /// conversion and the menu says what it costs.
  ///
  /// ⚠️ It is the TRACK's kind, not the current screen's: [from] is never
  /// offered as a target (a mode does not convert to itself), so a `liveKind`
  /// equal to [from] marks nothing — it only turns every other entry's
  /// subtitle into "opens a copy", which is still true and still worth saying.
  final AppMode? liveKind;

  /// Whether [from] can reach anywhere at all.
  ///
  /// Audio cannot (see [ProjectBridge.canConvert]), so a host may prefer to
  /// hide the action entirely there rather than show a menu whose only content
  /// is an explanation.
  static bool hasTargets(AppMode from) =>
      ProjectBridge.targetsFrom(from).isNotEmpty;

  Future<void> _pick(BuildContext context, AppMode target) async {
    final result = ProjectBridge.convert(
      from: from,
      to: target,
      document: documentBuilder(),
      annotations: annotations,
      tuning: tuning,
      capo: capo,
    );

    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    if (result.isUnsupported) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            l10n.openInCannotTitle(localizedModeLabel(l10n, target)),
          ),
          content: Text(result.unsupportedReason!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.openInOk),
            ),
          ],
        ),
      );
      return;
    }

    // Lossless conversions go straight through. A confirmation that always
    // appears is a confirmation nobody reads, which would defeat the warning
    // for the conversions that genuinely need one.
    if (!result.lossless) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => _LossDialog(
          target: target,
          report: result.report,
          keyPrefix: keyPrefix,
        ),
      );
      if (proceed != true) return;
    }

    onConverted(target, result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reachable = ProjectBridge.targetsFrom(from);
    final allowed = this.targets;
    final targets = allowed == null
        ? reachable
        : [
            for (final mode in reachable)
              if (allowed.contains(mode)) mode,
          ];
    return PopupMenuButton<AppMode>(
      key: ValueKey('${keyPrefix}open-in'),
      tooltip: tooltip ?? l10n.openInTooltip,
      icon: icon,
      onSelected: (target) => _pick(context, target),
      itemBuilder: (context) => [
        // A mode with nowhere to go (Audio) must still explain itself — an
        // empty popup reads as a bug, and "why can't I?" is exactly the
        // question the user has at that moment.
        if (targets.isEmpty)
          PopupMenuItem<AppMode>(
            key: ValueKey('${keyPrefix}open-in-none'),
            enabled: false,
            child: Text(
              l10n.openInAudioNotNotes,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final target in targets)
          PopupMenuItem<AppMode>(
            value: target,
            key: ValueKey('${keyPrefix}open-in-${target.name}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (target == liveKind) ...[
                      Icon(
                        Icons.link,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(localizedModeLabel(l10n, target)),
                  ],
                ),
                // The static cost of the edge, so the user can choose before
                // committing rather than being warned after — or, for a live
                // target, that there is no cost because nothing converts.
                Text(
                  liveKind == null
                      ? localizedEdgeSubtitle(l10n, from, target)
                      : target == liveKind
                          ? l10n.openInLiveTrack
                          : l10n.openInMakesCopy,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: target == liveKind
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LossDialog extends StatelessWidget {
  const _LossDialog({
    required this.target,
    required this.report,
    this.keyPrefix = '',
  });

  final AppMode target;
  final ConversionReport report;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      key: ValueKey('${keyPrefix}open-in-loss-dialog'),
      title: Text(l10n.openInLossTitle(localizedModeLabel(l10n, target))),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (report.lost.isNotEmpty) ...[
            Text(l10n.openInLossLost, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            // Static reasons localize via the key the bridge tagged them with;
            // a dynamic/one-off reason (an interpolated count) has no key and
            // shows verbatim — a documented remainder.
            for (final what in report.lost)
              Text('•  ${localizedReason(l10n, report, what)}'),
            const SizedBox(height: 12),
          ],
          if (report.approximated.isNotEmpty) ...[
            Text(l10n.openInLossChanged, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            for (final what in report.approximated)
              Text('•  ${localizedReason(l10n, report, what)}'),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: ValueKey('${keyPrefix}open-in-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.openInCancel),
        ),
        FilledButton(
          key: ValueKey('${keyPrefix}open-in-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.openInConfirm),
        ),
      ],
    );
  }
}
