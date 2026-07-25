// A self-contained guide for the Audio Editor (DAW). The DAW's top toolbar is a
// row of icon-only buttons and its clip/FX surface is dense, so first-time users
// on web/mobile have little to orient them. This sheet explains the toolbar,
// building and editing clips, the four FX scopes, and the linked-editor
// round-trip — in one scrollable, touch-friendly overlay reachable from a single
// help button in the app bar. It owns no DAW state and takes no callbacks, so it
// stays decoupled from the (hot) daw_screen/daw_service internals.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Open the Audio Editor guide as a responsive modal bottom sheet.
Future<void> showDawHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Cap the height so it reflows/scrolls on short (phone-landscape / web)
    // viewports instead of overflowing.
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (ctx) => const _DawHelpSheet(),
  );
}

class _DawHelpSheet extends StatelessWidget {
  const _DawHelpSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.85;

    final sections = <_HelpSection>[
      _HelpSection(
        Icons.tune,
        l10n.dawHelpToolbarTitle,
        l10n.dawHelpToolbarBody,
      ),
      _HelpSection(
        Icons.add_box_outlined,
        l10n.dawHelpBuildTitle,
        l10n.dawHelpBuildBody,
      ),
      _HelpSection(
        Icons.content_cut,
        l10n.dawHelpClipsTitle,
        l10n.dawHelpClipsBody,
      ),
      _HelpSection(
        Icons.graphic_eq,
        l10n.dawHelpFxTitle,
        l10n.dawHelpFxBody,
      ),
      _HelpSection(
        Icons.open_in_new,
        l10n.dawHelpRoundTripTitle,
        l10n.dawHelpRoundTripBody,
      ),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.dawHelpTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Text(
                    l10n.dawHelpIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final s in sections) _HelpTile(section: s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection {
  const _HelpSection(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({required this.section});
  final _HelpSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(section.icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  section.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
