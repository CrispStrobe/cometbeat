// lib/features/harmony/chart_library_sheet.dart
//
// The charts you saved, and the way back to them.
//
// Deliberately small: name it, open it, delete it. A chart is cheap to retype
// compared with a recording, so the useful thing is fast recall, not a file
// manager. The working chart autosaves separately (see `ChartStore`), so this
// list holds only charts the user chose to keep.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user did in the library.
sealed class ChartLibraryResult {
  const ChartLibraryResult();
}

/// Open this chart.
class ChartOpened extends ChartLibraryResult {
  const ChartOpened(this.chart, this.name);
  final Chart chart;
  final String name;
}

/// Opens the library. Returns null unless a chart was opened — saving and
/// deleting happen in place and need no answer from the host.
Future<ChartLibraryResult?> showChartLibrary(
  BuildContext context, {
  required Chart current,
  String? currentName,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return null;
  return showModalBottomSheet<ChartLibraryResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ChartLibrarySheet(
      store: ChartStore(prefs),
      current: current,
      currentName: currentName,
    ),
  );
}

class _ChartLibrarySheet extends StatefulWidget {
  const _ChartLibrarySheet({
    required this.store,
    required this.current,
    required this.currentName,
  });

  final ChartStore store;
  final Chart current;
  final String? currentName;

  @override
  State<_ChartLibrarySheet> createState() => _ChartLibrarySheetState();
}

class _ChartLibrarySheetState extends State<_ChartLibrarySheet> {
  late List<SavedChart> _saved = widget.store.list();
  late final TextEditingController _name = TextEditingController(
    // The chart's own title is the name the user already chose; making them
    // type it again is the fastest way to end up with "Untitled".
    text: widget.currentName ?? widget.current.title,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await widget.store.save(_name.text, widget.current);
    if (!mounted) return;
    setState(() => _saved = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.chartSaved(_name.text)),
      ),
    );
  }

  Future<void> _delete(SavedChart chart) async {
    final saved = await widget.store.remove(chart.name);
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  void _open(SavedChart saved) {
    final chart = saved.chart;
    // A row whose stored text no longer decodes is reported, not silently
    // ignored — a tap that does nothing reads as a broken app.
    if (chart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.chartUnreadableSaved),
        ),
      );
      return;
    }
    Navigator.of(context).pop(ChartOpened(chart, saved.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canSave = !widget.current.isEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chartSaveName'),
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: l10n.chartSaveAs,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('chartSaveButton'),
                  // An empty chart is refused by the store anyway; disabling
                  // the button says so before the tap instead of after.
                  onPressed: canSave ? _save : null,
                  child: Text(l10n.chartSave),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_saved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l10n.chartNoneSaved,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _saved.length,
                  itemBuilder: (context, i) {
                    final saved = _saved[i];
                    final chart = saved.chart;
                    return ListTile(
                      key: Key('chartRow_${saved.name}'),
                      title: Text(saved.name),
                      subtitle: Text(
                        chart == null
                            ? l10n.chartUnreadableSaved
                            : l10n.chartBarCount(chart.totalBars),
                      ),
                      onTap: () => _open(saved),
                      trailing: IconButton(
                        tooltip: l10n.chartDelete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(saved),
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
