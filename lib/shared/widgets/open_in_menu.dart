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
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:flutter/material.dart';

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

    if (result.isUnsupported) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Cannot open in ${appModeLabel(target)}'),
          content: Text(result.unsupportedReason!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
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
        ),
      );
      if (proceed != true) return;
    }

    onConverted(target, result);
  }

  @override
  Widget build(BuildContext context) {
    final targets = ProjectBridge.targetsFrom(from);
    return PopupMenuButton<AppMode>(
      key: const ValueKey('open-in'),
      tooltip: tooltip,
      icon: icon,
      onSelected: (target) => _pick(context, target),
      itemBuilder: (context) => [
        // A mode with nowhere to go (Audio) must still explain itself — an
        // empty popup reads as a bug, and "why can't I?" is exactly the
        // question the user has at that moment.
        if (targets.isEmpty)
          PopupMenuItem<AppMode>(
            key: const ValueKey('open-in-none'),
            enabled: false,
            child: Text(
              'Audio is not notes yet — use Transcribe first.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final target in targets)
          PopupMenuItem<AppMode>(
            value: target,
            key: ValueKey('open-in-${target.name}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(appModeLabel(target)),
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
  const _LossDialog({required this.target, required this.report});

  final AppMode target;
  final ConversionReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('open-in-loss-dialog'),
      title: Text('Open in ${appModeLabel(target)}?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (report.lost.isNotEmpty) ...[
            Text(
              'This will not come across:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            for (final what in report.lost) Text('•  $what'),
            const SizedBox(height: 12),
          ],
          if (report.approximated.isNotEmpty) ...[
            Text('This will change:', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            for (final what in report.approximated) Text('•  $what'),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('open-in-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('open-in-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Open anyway'),
        ),
      ],
    );
  }
}
