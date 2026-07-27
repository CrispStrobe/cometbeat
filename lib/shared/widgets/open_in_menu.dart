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
    this.tooltip = 'Open in…',
    this.targets,
    this.keyPrefix = '',
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
  final String tooltip;

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
      tooltip: tooltip,
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
                Text(localizedModeLabel(l10n, target)),
                // The static cost of the edge, so the user can choose before
                // committing rather than being warned after.
                Text(
                  ProjectBridge.describeEdge(from, target),
                  style: Theme.of(context).textTheme.bodySmall,
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
            // The per-edge reason strings themselves are still English (they are
            // generated in the Flutter-free bridge) — a documented follow-up.
            for (final what in report.lost) Text('•  $what'),
            const SizedBox(height: 12),
          ],
          if (report.approximated.isNotEmpty) ...[
            Text(l10n.openInLossChanged, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            for (final what in report.approximated) Text('•  $what'),
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
