// WS-W6 — one sheet for saved effect chains, hosted by every rack.
//
// The pattern is `keymap_sheet.dart`'s: ONE shared sheet, several hosts, each
// passing what it has. A panel per surface would drift within a week, and the
// whole point of a preset is that it is not tied to the surface it was made on —
// a chain saved off a tab track should be applicable to a score part.
//
// The host supplies the chain currently in its rack (so "save this" means
// something) and receives the chain the user picked. It does not have to know
// anything about storage, and the sheet does not have to know anything about
// racks.

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/services/fx_preset_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Show the saved-chain sheet.
///
/// [current] is what the host's rack holds right now; pass an empty list and the
/// save control is simply absent — offering to save nothing is worse than not
/// offering.
///
/// Returns the chain the user chose to apply, or null if they applied nothing
/// (dismissed, or only saved/deleted). The host decides what "apply" means for
/// its own model, which is the only part it can know.
Future<List<FxSpec>?> showFxPresetSheet(
  BuildContext context, {
  List<FxSpec> current = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return null;
  final store = FxPresetStore(prefs);
  return showModalBottomSheet<List<FxSpec>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _FxPresetSheet(store: store, current: current),
  );
}

class _FxPresetSheet extends StatefulWidget {
  const _FxPresetSheet({required this.store, required this.current});

  final FxPresetStore store;
  final List<FxSpec> current;

  @override
  State<_FxPresetSheet> createState() => _FxPresetSheetState();
}

class _FxPresetSheetState extends State<_FxPresetSheet> {
  late List<SavedFxPreset> _presets = widget.store.list();

  /// ⚠️ Owned by the STATE, not created per dialog.
  ///
  /// The obvious shape — a controller made when the dialog opens and disposed
  /// when it returns — is wrong, and WS-W6 slice 1 hit it: the dialog is still
  /// animating out when the await resumes, and that exit frame rebuilds the
  /// `TextField` against a controller that has just been disposed. It throws
  /// only on that one frame, which is why it survives casual use.
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveCurrent() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fxPresetSaveTitle),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.fxPresetNameHint),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_nameController.text),
            child: Text(l10n.fxPresetSave),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final saved = await widget.store.save(name, widget.current);
    if (!mounted) return;
    _nameController.clear();
    setState(() => _presets = saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // ⚠️ A chain string cannot carry per-param automation, so a chain that has
    // any would be saved flattened. Said out loud rather than discovered on the
    // next open.
    final lossy =
        widget.current.isNotEmpty && !fxChainStringIsLossless(widget.current);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fxPresetsTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.fxPresetsHint, style: theme.textTheme.bodySmall),
            if (widget.current.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('fx-preset-save'),
                    onPressed: _saveCurrent,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: Text(l10n.fxPresetSaveCurrent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatFxChain(widget.current),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (lossy)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.fxPresetAutomationDropped,
                    key: const ValueKey('fx-preset-lossy'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            if (_presets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l10n.fxPresetsEmpty,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _presets.length,
                  itemBuilder: (context, i) {
                    final preset = _presets[i];
                    return ListTile(
                      key: ValueKey<String>('fx-preset-${preset.name}'),
                      dense: true,
                      title: Text(preset.name),
                      // The chain itself, because it IS readable — that is half
                      // the reason presets are stored as text.
                      subtitle: Text(
                        preset.chain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(preset.specs),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: () async {
                          final left = await widget.store.remove(preset.name);
                          if (!context.mounted) return;
                          setState(() => _presets = left);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
