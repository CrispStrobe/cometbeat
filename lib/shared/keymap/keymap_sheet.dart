// WS-T3 — the keymap sheet. An unlisted shortcut does not exist.
//
// The tracker had 33 keyboard bindings and no way to discover any of them: you
// either already knew the FT2 conventions or the feature was invisible. That is
// the actual reason this card exists — the bindings were never the weak part.
//
// Grouped by what the intent is FOR rather than alphabetically, because someone
// opens this asking "how do I move around", not "what does Alt+PgDn do".

import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:comet_beat/shared/keymap/keymap_service.dart';
import 'package:flutter/material.dart';

/// Show the keyboard reference.
///
/// [supported] is the subset of intents THIS surface actually handles — the
/// Audio Editor does not have pattern rows, and listing shortcuts that do
/// nothing here would be worse than listing none. Null means "show everything",
/// which is what a global reference wants.
Future<void> showKeymapSheet(
  BuildContext context, {
  required Keymap keymap,
  Set<AppIntent>? supported,
  KeymapService? service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => KeymapSheetBody(
        keymap: keymap,
        supported: supported,
        service: service,
        controller: controller,
      ),
    ),
  );
}

/// The sheet's contents, separated so a test can pump it without a route.
class KeymapSheetBody extends StatelessWidget {
  const KeymapSheetBody({
    super.key,
    required this.keymap,
    this.supported,
    this.service,
    this.controller,
  });

  final Keymap keymap;
  final Set<AppIntent>? supported;
  final KeymapService? service;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only intents this surface handles AND that have a key on them: an intent
    // whose chord the user removed has nothing to show.
    final shown = [
      for (final intent in AppIntent.values)
        if (supported == null || supported!.contains(intent))
          if (keymap.chordsFor(intent).isNotEmpty) intent,
    ];

    final groups = <AppIntentGroup, List<AppIntent>>{};
    for (final intent in shown) {
      groups.putIfAbsent(appIntentGroup(intent), () => []).add(intent);
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Keyboard', style: theme.textTheme.titleMedium),
            ),
            if (service != null && service!.isCustomised)
              TextButton(
                onPressed: () => service!.reset(),
                child: const Text('Reset'),
              ),
          ],
        ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No keyboard shortcuts on this screen yet.'),
          ),
        for (final group in AppIntentGroup.values)
          if (groups[group] case final intents? when intents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                appIntentGroupLabel(group),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            for (final intent in intents)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(appIntentLabel(intent))),
                    // Every chord bound to it, not just the first: Delete and
                    // Backspace both delete, and a reference that showed one
                    // would be teaching half the truth.
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final chord in keymap.chordsFor(intent))
                          _KeyCap(label: chord.label),
                      ],
                    ),
                  ],
                ),
              ),
          ],
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
