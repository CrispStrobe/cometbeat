// lib/features/harmony/setlist_screen.dart
//
// BB-U4b — the setlist surface. The model, its codec and `SetlistStore` were
// built first (BB-U4); this is the UI over them.
//
// ⚠️ THE ONE RULE, and the card says it will look like a simplification: the
// per-song key and tempo live in the SETLIST ENTRY, never on the chart. The
// same tune can sit in two sets at two keys and the saved chart is untouched
// by either. Everything here goes through `resolveEntry`, which returns a NEW
// chart — nothing in this file may write an override back to `ChartStore`.
//
// ⚠️ A missing chart stays VISIBLE. `SetlistStore.missingCharts` reports it
// and the entry is deliberately not pruned: on a gig night, a song silently
// vanishing from the set is the worst possible response.
library;

import 'package:comet_beat/core/harmony/chart_codec.dart';
import 'package:comet_beat/core/harmony/setlist.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/harmony/chart_screen.dart';
import 'package:comet_beat/features/harmony/gig_mode_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The list of saved setlists.
class SetlistScreen extends StatefulWidget {
  const SetlistScreen({super.key});

  @override
  State<SetlistScreen> createState() => _SetlistScreenState();
}

class _SetlistScreenState extends State<SetlistScreen> {
  SetlistStore? _store;
  ChartStore? _charts;
  var _rows = <({Setlist setlist, int savedAtMs})>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final store = SetlistStore(prefs);
    setState(() {
      _store = store;
      _charts = ChartStore(prefs);
      _rows = store.list();
    });
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askForName(context, l10n.setlistNamePrompt);
    final store = _store;
    if (name == null || name.isEmpty || store == null) return;
    final rows = await store.save(Setlist(name: name));
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _open(Setlist setlist) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SetlistDetailScreen(name: setlist.name),
      ),
    );
    // The detail screen edits through the same store, so re-read on return
    // rather than trying to thread changes back.
    final store = _store;
    if (store == null || !mounted) return;
    setState(() => _rows = store.list());
  }

  Future<void> _delete(Setlist setlist) async {
    final store = _store;
    if (store == null) return;
    final rows = await store.remove(setlist.name);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final charts = _charts;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setlistTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('setlistNew'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l10n.setlistNew),
      ),
      body: _rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.setlistEmpty, textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final setlist = _rows[i].setlist;
                // Surfaced on the LIST, not only inside the set: a player
                // scanning their sets before a gig should see the problem
                // without opening each one.
                final missing = charts == null
                    ? const <SetlistEntry>[]
                    : _store!.missingCharts(setlist, charts);
                return Card(
                  key: ValueKey('setlist_${setlist.name}'),
                  child: ListTile(
                    title: Text(setlist.name),
                    subtitle: Text(
                      l10n.setlistSongCount(setlist.entries.length),
                    ),
                    leading: missing.isEmpty
                        ? const Icon(Icons.queue_music)
                        : Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.setlistDelete,
                      onPressed: () => _delete(setlist),
                    ),
                    onTap: () => _open(setlist),
                  ),
                );
              },
            ),
    );
  }
}

/// One setlist: its songs, their order, and each song's gig overrides.
class SetlistDetailScreen extends StatefulWidget {
  const SetlistDetailScreen({required this.name, super.key});

  final String name;

  @override
  State<SetlistDetailScreen> createState() => _SetlistDetailScreenState();
}

class _SetlistDetailScreenState extends State<SetlistDetailScreen> {
  SetlistStore? _store;
  ChartStore? _charts;
  Setlist? _setlist;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final store = SetlistStore(prefs);
    setState(() {
      _store = store;
      _charts = ChartStore(prefs);
      _setlist = _find(store, widget.name);
    });
  }

  Setlist? _find(SetlistStore store, String name) {
    for (final row in store.list()) {
      if (row.setlist.name == name) return row.setlist;
    }
    return null;
  }

  Future<void> _persist(Setlist next) async {
    final store = _store;
    if (store == null) return;
    await store.save(next);
    if (!mounted) return;
    setState(() => _setlist = next);
  }

  Future<void> _addSongs() async {
    final charts = _charts;
    final setlist = _setlist;
    if (charts == null || setlist == null) return;
    final names = await _pickCharts(context, charts);
    if (names == null || names.isEmpty) return;
    var next = setlist;
    for (final name in names) {
      next = next.add(SetlistEntry(chartName: name));
    }
    await _persist(next);
  }

  /// Opens the entry at [index] as the SET asks for it.
  Future<void> _play(int index) async {
    final charts = _charts;
    final setlist = _setlist;
    if (charts == null || setlist == null) return;
    final entry = setlist.entries[index];
    final saved = _savedChart(charts, entry.chartName);
    if (saved == null) return; // Missing charts are shown, not playable.

    // ⚠️ `chartFromJsonString`, not `chartFromJson` — the latter takes an
    // ALREADY-DECODED object and returns null for a String, silently. Passing
    // the raw text made this tap do nothing at all, with no error anywhere.
    final chart = chartFromJsonString(saved.json);
    if (chart == null) {
      // A chart that will not parse is a real problem the player must see;
      // returning quietly is what hid the bug above.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.chartOpenFailed)),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // ⚠️ `resolveEntry` returns a NEW chart. The saved one is untouched,
        // which is the whole point of keeping the override on the entry.
        builder: (_) => ChartScreen(initialChart: resolveEntry(chart, entry)),
      ),
    );
  }

  SavedChart? _savedChart(ChartStore charts, String name) {
    for (final saved in charts.list()) {
      if (saved.name == name) return saved;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final setlist = _setlist;
    final charts = _charts;
    if (setlist == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final missing = charts == null
        ? const <String>{}
        : {
            for (final entry in _store!.missingCharts(setlist, charts))
              entry.chartName,
          };

    return Scaffold(
      appBar: AppBar(
        title: Text(setlist.name),
        actions: [
          IconButton(
            key: const ValueKey('setlistAdd'),
            icon: const Icon(Icons.playlist_add),
            tooltip: l10n.setlistAdd,
            onPressed: _addSongs,
          ),
          // Gig mode is only offered once there is a set to play.
          if (setlist.entries.isNotEmpty && charts != null)
            IconButton(
              key: const ValueKey('setlistGigMode'),
              icon: const Icon(Icons.play_circle_outline),
              tooltip: l10n.gigMode,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GigModeScreen(
                    setlist: setlist,
                    charts: charts,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: setlist.entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.setlistNoSongs, textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: setlist.entries.length,
              // `onReorderItem` already adjusts the target for the removed
              // item, so the model's `reorder` gets the index it expects. The
              // older `onReorder` reports it BEFORE the removal and would need
              // the off-by-one undone by hand.
              onReorderItem: (from, to) => _persist(setlist.reorder(from, to)),
              itemBuilder: (context, i) {
                final entry = setlist.entries[i];
                final isMissing = missing.contains(entry.chartName);
                return Card(
                  key: ValueKey('setlistEntry_${i}_${entry.chartName}'),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(entry.chartName),
                    subtitle: Text(
                      isMissing
                          ? l10n.setlistMissingHint
                          : _overrideLine(l10n, entry),
                      style: isMissing
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                    isThreeLine: isMissing,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMissing)
                          IconButton(
                            key: ValueKey('setlistTune_$i'),
                            icon: const Icon(Icons.tune),
                            tooltip: l10n.setlistOverrideHint,
                            onPressed: () => _editEntry(i),
                          ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: l10n.setlistRemoveSong,
                          onPressed: () => _persist(setlist.removeAt(i)),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ],
                    ),
                    onTap: isMissing ? null : () => _play(i),
                  ),
                );
              },
            ),
    );
  }

  String _overrideLine(AppLocalizations l10n, SetlistEntry entry) {
    if (entry.isPlain) return l10n.setlistEntryUseChart;
    final parts = <String>[
      if (entry.transposeSemitones != 0)
        '${l10n.setlistEntryKey} '
            '${entry.transposeSemitones > 0 ? '+' : ''}'
            '${entry.transposeSemitones}',
      if (entry.tempoBpm != null) '${entry.tempoBpm} bpm',
      if (entry.note != null && entry.note!.isNotEmpty) entry.note!,
    ];
    return parts.join(' · ');
  }

  Future<void> _editEntry(int index) async {
    final setlist = _setlist;
    if (setlist == null) return;
    final edited = await showModalBottomSheet<SetlistEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntrySheet(entry: setlist.entries[index]),
    );
    if (edited == null) return;
    await _persist(setlist.replaceAt(index, edited));
  }
}

/// The per-gig overrides for one entry.
class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.entry});
  final SetlistEntry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late int _transpose = widget.entry.transposeSemitones;
  late final TextEditingController _tempo =
      TextEditingController(text: widget.entry.tempoBpm?.toString() ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.entry.note ?? '');

  @override
  void dispose() {
    _tempo.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.entry.chartName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          // Says out loud that this does not touch the chart. The card warns
          // the override is easy to mistake for an edit; so does the user.
          Text(l10n.setlistOverrideHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text(l10n.setlistEntryKey, style: theme.textTheme.labelLarge),
          Row(
            children: [
              IconButton(
                key: const ValueKey('setlistKeyDown'),
                icon: const Icon(Icons.remove),
                onPressed: _transpose > -12
                    ? () => setState(() => _transpose--)
                    : null,
              ),
              Expanded(
                child: Text(
                  _transpose == 0
                      ? l10n.setlistEntryUseChart
                      : '${_transpose > 0 ? '+' : ''}$_transpose',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const ValueKey('setlistKeyUp'),
                icon: const Icon(Icons.add),
                onPressed:
                    _transpose < 12 ? () => setState(() => _transpose++) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('setlistTempoField'),
            controller: _tempo,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.setlistEntryTempo,
              hintText: l10n.setlistEntryUseChart,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('setlistNoteField'),
            controller: _note,
            decoration: InputDecoration(labelText: l10n.setlistEntryNote),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('setlistEntrySave'),
            onPressed: () {
              // An empty or unparseable tempo means "as written", not zero.
              final bpm = int.tryParse(_tempo.text.trim());
              Navigator.of(context).pop(
                SetlistEntry(
                  chartName: widget.entry.chartName,
                  transposeSemitones: _transpose,
                  tempoBpm: bpm != null && bpm > 0 ? bpm : null,
                  note: _note.text.trim(),
                ),
              );
            },
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askForName(BuildContext context, String prompt) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(prompt),
      content: TextField(
        key: const ValueKey('setlistNameField'),
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('setlistNameOk'),
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    ),
  );
}

/// Picks saved charts to add. Multi-select, because building a set one
/// round-trip per song is the kind of thing that stops people building sets.
Future<List<String>?> _pickCharts(BuildContext context, ChartStore charts) {
  final all = charts.list();
  final chosen = <String>{};
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final saved in all)
                  CheckboxListTile(
                    key: ValueKey('pickChart_${saved.name}'),
                    title: Text(saved.name),
                    value: chosen.contains(saved.name),
                    onChanged: (on) => setSheetState(() {
                      if (on ?? false) {
                        chosen.add(saved.name);
                      } else {
                        chosen.remove(saved.name);
                      }
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const ValueKey('pickChartsDone'),
              onPressed: () => Navigator.of(context).pop(chosen.toList()),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ),
        ],
      ),
    ),
  );
}
