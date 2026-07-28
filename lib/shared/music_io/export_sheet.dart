// WS-X6 — one export door.
//
// ⚠️ The card says "every mode exports differently". That was true when it was
// written and is now only half true: `showAudioExportSheet` is already shared
// by eight screens and `showMusicExportSheet` by the notation ones. So this is
// NOT another unification of format handling — that already happened, and
// redoing it would be churn.
//
// The gap that is actually left is discoverability. They are two separate
// doors: someone in the Audio Editor is offered audio and never learns their
// arrangement can leave as MusicXML; someone in the Workshop is offered
// notation and never learns it can leave as a WAV. And the two things that
// belong to neither sheet — the project ARCHIVE you reopen later, and the
// SHARE TOKEN you paste to a friend — appear in no export UI at all.
//
// So: one sheet, grouped by what you are trying to do, listing only what THIS
// surface can really produce. A surface passes the categories it has; nothing
// here knows how to build any of them.

import 'package:flutter/material.dart';

/// What kind of thing an export produces — the question a person is actually
/// asking when they open this.
enum ExportKind {
  /// A sound file. What most people mean by "export".
  audio,

  /// Notation or another symbolic score — MusicXML, MIDI, a module.
  symbolic,

  /// The editable project itself, to reopen later. Not a delivery format.
  project,

  /// A short token or link that carries the piece to someone else.
  share,
}

String exportKindLabel(ExportKind kind) => switch (kind) {
      ExportKind.audio => 'Sound',
      ExportKind.symbolic => 'Notes',
      ExportKind.project => 'Project',
      ExportKind.share => 'Share',
    };

String exportKindBlurb(ExportKind kind) => switch (kind) {
      ExportKind.audio => 'A sound file anyone can play.',
      ExportKind.symbolic => 'The notes themselves, for another music program.',
      ExportKind.project => 'Your work, to open and keep editing later.',
      ExportKind.share => 'A short code to send to someone else.',
    };

IconData exportKindIcon(ExportKind kind) => switch (kind) {
      ExportKind.audio => Icons.graphic_eq,
      ExportKind.symbolic => Icons.music_note,
      ExportKind.project => Icons.folder_zip,
      ExportKind.share => Icons.link,
    };

/// One thing this surface can export.
///
/// [run] does the work — building bytes, opening the format picker, whatever
/// that surface already does. This file deliberately knows none of it.
class ExportOption {
  const ExportOption({
    required this.kind,
    required this.label,
    required this.run,
    this.detail,
    this.enabled = true,
    this.disabledReason,
  });

  final ExportKind kind;
  final String label;

  /// A line under the label, for when the label alone would not tell someone
  /// what they are choosing between (stems versus the mix, say).
  final String? detail;

  final Future<void> Function() run;

  /// Offered but not available right now — an empty timeline has no stems.
  final bool enabled;

  /// Why it is unavailable. Shown in place of [detail]: an option greyed out
  /// with no explanation reads as a bug.
  final String? disabledReason;
}

/// Show everything [options] can produce, grouped by [ExportKind].
///
/// An empty list is not an error — a surface with nothing to export yet says
/// so, rather than opening an empty sheet.
Future<void> showExportSheet(
  BuildContext context, {
  required List<ExportOption> options,
  String title = 'Export',
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: ExportSheetBody(options: options, title: title),
    ),
  );
}

/// The sheet's contents, separated so a test can pump it without a route.
class ExportSheetBody extends StatelessWidget {
  const ExportSheetBody({
    super.key,
    required this.options,
    this.title = 'Export',
  });

  final List<ExportOption> options;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byKind = <ExportKind, List<ExportOption>>{};
    for (final option in options) {
      byKind.putIfAbsent(option.kind, () => []).add(option);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (options.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nothing to export yet.'),
          ),
        for (final kind in ExportKind.values)
          if (byKind[kind] case final group? when group.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 2),
              child: Row(
                children: [
                  Icon(
                    exportKindIcon(kind),
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    exportKindLabel(kind),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Text(
                exportKindBlurb(kind),
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final option in group)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 26),
                title: Text(option.label),
                subtitle: option.enabled
                    ? (option.detail == null ? null : Text(option.detail!))
                    // A greyed-out row with no explanation reads as a bug, so
                    // the reason replaces the detail rather than hiding.
                    : Text(option.disabledReason ?? 'Not available yet'),
                enabled: option.enabled,
                onTap: option.enabled
                    ? () async {
                        Navigator.of(context).pop();
                        await option.run();
                      }
                    : null,
              ),
          ],
      ],
    );
  }
}
