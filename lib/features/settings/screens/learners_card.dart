// lib/features/settings/screens/learners_card.dart
//
// Settings ▸ Learners: who is playing on this device, and their progress
// backup. One row per learner (tap to switch), plus add / back up / restore.
// The storage side is `ProfileService`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/services/profile_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/file_delivery.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The name to show for [profile]: its own, or the localized placeholder for
/// the built-in first learner that nobody has named yet.
String learnerDisplayName(AppLocalizations l10n, LearnerProfile profile) =>
    profile.name.isNotEmpty ? profile.name : l10n.learnerDefaultName;

/// Asks for a learner's name. Null when cancelled or left empty.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final l10n = AppLocalizations.of(context)!;
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('learner-name-field'),
        controller: controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: l10n.learnerNameHint),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    ),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// The Settings section: heading + [LearnersCard]. Renders nothing when no
/// [ProfileService] is in scope (Settings mounted bare, without the app's
/// providers), so the screen does not depend on it to build.
class LearnersSection extends StatelessWidget {
  const LearnersSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.watch<ProfileService?>() == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.learnersTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const LearnersCard(),
        const SizedBox(height: 20),
      ],
    );
  }
}

class LearnersCard extends StatelessWidget {
  const LearnersCard({super.key});

  Future<void> _add(BuildContext context, ProfileService profiles) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askName(context, title: l10n.learnerAdd);
    if (name != null) await profiles.add(name);
  }

  Future<void> _rename(
    BuildContext context,
    ProfileService profiles,
    LearnerProfile profile,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askName(
      context,
      title: l10n.learnerRename,
      initial: profile.name,
    );
    if (name != null) await profiles.rename(profile.id, name);
  }

  Future<void> _delete(
    BuildContext context,
    ProfileService profiles,
    LearnerProfile profile,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          l10n.learnerDeleteConfirm(learnerDisplayName(l10n, profile)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('learner-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.learnerDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await profiles.delete(profile.id);
  }

  Future<void> _backUp(BuildContext context, ProfileService profiles) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final name = learnerDisplayName(l10n, profiles.active);
    final document = await profiles.exportActive(displayName: name);
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final result = await deliverBytes(
      bytes: Uint8List.fromList(utf8.encode(document)),
      suggestedName: 'cometbeat-${slug.isEmpty ? 'progress' : slug}.json',
      label: 'JSON',
      extension: 'json',
      mimeType: 'application/json',
    );
    if (result.kind == DeliveryKind.cancelled) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.learnerBackupSaved)));
  }

  Future<void> _restore(BuildContext context, ProfileService profiles) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;
      final profile = await profiles.importAsNew(await file.readAsString());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.learnerRestored(learnerDisplayName(l10n, profile)),
          ),
        ),
      );
    } on FormatException {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.learnerRestoreFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profiles = context.watch<ProfileService>();
    final activeName = learnerDisplayName(l10n, profiles.active);
    return Card(
      child: Column(
        children: [
          RadioGroup<String>(
            groupValue: profiles.active.id,
            onChanged: (id) {
              if (id != null) profiles.switchTo(id);
            },
            child: Column(
              children: [
                for (final profile in profiles.profiles)
                  RadioListTile<String>(
                    key: Key('learner-${profile.id}'),
                    value: profile.id,
                    title: Text(learnerDisplayName(l10n, profile)),
                    secondary: PopupMenuButton<String>(
                      key: Key('learner-menu-${profile.id}'),
                      tooltip:
                          MaterialLocalizations.of(context).showMenuTooltip,
                      onSelected: (action) => action == 'rename'
                          ? _rename(context, profiles, profile)
                          : _delete(context, profiles, profile),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text(l10n.learnerRename),
                        ),
                        if (profiles.canDelete(profile.id))
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l10n.learnerDelete),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 0),
          ListTile(
            key: const Key('learner-add'),
            leading: const Icon(Icons.person_add_alt_1),
            title: Text(l10n.learnerAdd),
            onTap: () => _add(context, profiles),
          ),
          ListTile(
            key: const Key('learner-backup'),
            leading: const Icon(Icons.save_alt),
            title: Text(l10n.learnerBackup),
            subtitle: Text(l10n.learnerBackupSubtitle(activeName)),
            onTap: () => _backUp(context, profiles),
          ),
          ListTile(
            key: const Key('learner-restore'),
            leading: const Icon(Icons.restore),
            title: Text(l10n.learnerRestore),
            subtitle: Text(l10n.learnerRestoreSubtitle),
            onTap: () => _restore(context, profiles),
          ),
        ],
      ),
    );
  }
}
