// lib/shared/widgets/project_browser_sheet.dart
//
// WS-W6 slice 1 — the projects half of the browser.
//
// The card describes one panel over six content types (projects · templates ·
// instruments · samples · FX presets · the licensed asset catalog) that you can
// drag onto any surface. The drag needs WS-X2, which does not exist, and the
// instrument/sample/catalog tabs belong to the Sound Library's owner. So this
// is the projects tab, on its own, doing the thing that unblocks the rest:
// making a project openable again after the app has closed.
//
// A SHEET RATHER THAN A PANEL. A docked panel would need a home on a surface,
// and all four authoring surfaces are somebody else's live work right now. A
// sheet can be raised from anywhere, and if the browser later becomes a panel
// this list is what goes inside it.
//
// THE CONFIRMATION RULE. Opening a project REPLACES what is loaded, and
// deleting one is not undoable, so both ask first when there is something to
// lose — and neither asks when there is not. A confirmation that appears every
// time stops being read, which is the same reasoning the Open-in menu uses for
// lossless conversions.

import 'package:comet_beat/core/project/project_templates.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/project_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows the projects browser. Returns the name that was opened, or null.
Future<String?> showProjectBrowserSheet(
  BuildContext context, {
  required ProjectService service,
  ProjectStore? store,
}) async {
  final resolved = store ?? ProjectStore(await SharedPreferences.getInstance());
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => _ProjectBrowser(service: service, store: resolved),
  );
}

class _ProjectBrowser extends StatefulWidget {
  const _ProjectBrowser({required this.service, required this.store});

  final ProjectService service;
  final ProjectStore store;

  @override
  State<_ProjectBrowser> createState() => _ProjectBrowserState();
}

class _ProjectBrowserState extends State<_ProjectBrowser> {
  late List<SavedProject> _saved = widget.store.list();

  /// Which tab is showing. Starts on projects: a returning player is the common
  /// case, and templates are one tap away.
  bool _showTemplates = false;

  /// One controller for the whole sheet, disposed with it.
  ///
  /// NOT created per dialog and disposed when the dialog returns, which is the
  /// obvious shape and is wrong: the dialog is still animating out when the
  /// await resumes, and the frame it paints on the way rebuilds the `TextField`
  /// against a controller that has just been disposed. It throws, and it throws
  /// only in the exit frame, which is why the pattern survives casual testing.
  final TextEditingController _nameField = TextEditingController();

  @override
  void dispose() {
    _nameField.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _saved = widget.store.list());

  Future<void> _saveCurrent() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askForName(
      title: l10n.projectSave,
      initial: widget.service.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await widget.store.save(name, widget.service.project);
    // The saved name becomes the project's name, so the next save offers it
    // rather than "Untitled" — the browser and the project agree on what this
    // thing is called.
    widget.service.rename(name.trim());
    _refresh();
  }

  Future<void> _open(SavedProject saved) async {
    final l10n = AppLocalizations.of(context)!;
    // Only ask when there is work to lose. An empty project is not work.
    if (widget.service.tracks.isNotEmpty) {
      final ok = await _confirm(
        title: l10n.projectOpen,
        message: l10n.projectOpenConfirm(saved.name),
      );
      if (ok != true) return;
    }
    final project = widget.store.open(saved.name);
    if (!mounted) return;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectOpenFailed(saved.name))),
      );
      return;
    }
    widget.service.project = project;
    Navigator.pop(context, saved.name);
  }

  Future<void> _delete(SavedProject saved) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await _confirm(
      title: l10n.projectDelete,
      message: l10n.projectDeleteConfirm(saved.name),
    );
    if (ok != true) return;
    await widget.store.delete(saved.name);
    _refresh();
  }

  Future<void> _rename(SavedProject saved) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askForName(
      title: l10n.projectRename,
      initial: saved.name,
    );
    if (name == null) return;
    final ok = await widget.store.rename(saved.name, name);
    if (!mounted) return;
    if (!ok) {
      // The store refuses a name that is already taken rather than silently
      // replacing that save; say so instead of appearing to do nothing.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectRenameFailed)),
      );
      return;
    }
    _refresh();
  }

  /// Starts from a template. Confirms first only when there is work to lose —
  /// the same rule as opening a saved project, and for the same reason.
  Future<void> _startFrom(ProjectTemplate template, String label) async {
    final l10n = AppLocalizations.of(context)!;
    if (widget.service.tracks.isNotEmpty) {
      final ok = await _confirm(
        title: l10n.projectTemplates,
        message: l10n.projectOpenConfirm(label),
      );
      if (ok != true) return;
    }
    // `build()` per tap, never a shared instance — see the templates header.
    widget.service.project = template.build();
    if (!mounted) return;
    Navigator.pop(context, label);
  }

  /// Template names live in the ARBs, not in the template list — the list is
  /// pure Dart so it can be tested without Flutter, and a name is the one part
  /// of a template a translator needs.
  String _templateLabel(AppLocalizations l10n, String id) => switch (id) {
        'empty' => l10n.projectTemplateEmpty,
        'beat' => l10n.projectTemplateBeat,
        'band' => l10n.projectTemplateBand,
        'slow' => l10n.projectTemplateSlowBand,
        // A template added without a name still shows SOMETHING findable
        // rather than an empty row.
        _ => id,
      };

  Future<String?> _askForName({
    required String title,
    required String initial,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    _nameField.text = initial;
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('project-name-field'),
          controller: _nameField,
          autofocus: true,
          maxLength: 60,
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.loopMixerCancel),
          ),
          TextButton(
            key: const Key('project-name-ok'),
            onPressed: () => Navigator.pop(dialog, _nameField.text),
            child: Text(l10n.loopMixerSave),
          ),
        ],
      ),
    );
    return name;
  }

  Future<bool?> _confirm({required String title, required String message}) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('project-confirm-no'),
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(l10n.loopMixerCancel),
          ),
          TextButton(
            key: const Key('project-confirm-yes'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(title),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  // NOT `projectBrowser` ("Projects") any more: that was an
                  // accurate heading while this sheet held only projects, and
                  // became a duplicate of the tab beneath it the moment a
                  // second tab existed.
                  child: Text(
                    l10n.projectBrowserTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const Key('project-save'),
                  onPressed: _saveCurrent,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(l10n.projectSave),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Two tabs rather than one long list: a template is a thing you do
            // ONCE, at the start, and a saved project is what you come back to
            // — mixing them would put the rarely-wanted rows permanently above
            // the often-wanted ones.
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.projectBrowser),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.projectTemplates),
                ),
              ],
              selected: {_showTemplates},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _showTemplates = s.first),
            ),
            const SizedBox(height: 8),
            if (_showTemplates)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: kProjectTemplates.length,
                  itemBuilder: (context, i) {
                    final template = kProjectTemplates[i];
                    final label = _templateLabel(l10n, template.id);
                    return ListTile(
                      key: Key('project-template-${template.id}'),
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: Text(label),
                      onTap: () => _startFrom(template, label),
                    );
                  },
                ),
              )
            else if (_saved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.projectNone),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _saved.length,
                  itemBuilder: (context, i) {
                    final saved = _saved[i];
                    return ListTile(
                      key: Key('project-row-${saved.name}'),
                      title: Text(saved.name),
                      onTap: () => _open(saved),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('project-rename-${saved.name}'),
                            tooltip: l10n.projectRename,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _rename(saved),
                          ),
                          IconButton(
                            key: Key('project-delete-${saved.name}'),
                            tooltip: l10n.projectDelete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _delete(saved),
                          ),
                        ],
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
