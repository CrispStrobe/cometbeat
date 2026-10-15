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
import 'package:comet_beat/core/harmony/chart_search.dart';
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
  late Set<String> _favourites = widget.store.favourites();
  late final TextEditingController _query = TextEditingController();
  var _favouritesOnly = false;
  var _recentOnly = false;
  late Map<String, int> _played = widget.store.playedAt();
  late final TextEditingController _name = TextEditingController(
    // The chart's own title is the name the user already chose; making them
    // type it again is the fastest way to end up with "Untitled".
    text: widget.currentName ?? widget.current.title,
  );

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  /// The rows to show. Decoded ONCE per rebuild and handed to the filter,
  /// rather than decoding inside the match — a keystroke must not reparse the
  /// whole library.
  List<SavedChart> get _visible => filterCharts(
        _saved,
        nameOf: (row) => row.name,
        chartOf: (row) => row.chart,
        isFavourite: (row) => _favourites.contains(row.name),
        query: _query.text,
        favouritesOnly: _favouritesOnly,
        tagsOf: (row) => widget.store.tagsOf(row.name),
        playedAt: _played,
        recentOnly: _recentOnly,
      );

  /// Edits [chart]'s tags: one comma-separated field, existing tags offered
  /// as chips to tap in.
  Future<void> _editTags(SavedChart chart) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _TagsDialog(
        name: chart.name,
        initial: widget.store.tagsOf(chart.name),
        known: widget.store.allTags(),
      ),
    );
    if (result == null) return;
    await widget.store.setTags(chart.name, result.split(','));
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavourite(SavedChart chart) async {
    final next = await widget.store.toggleFavourite(chart.name);
    if (!mounted) return;
    setState(() => _favourites = next);
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
    // The store drops the star with the chart; re-read so the UI agrees.
    setState(() {
      _saved = saved;
      _favourites = widget.store.favourites();
      _played = widget.store.playedAt();
    });
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
            // Search + starred-only. Hidden until there is enough to search:
            // a filter bar above three rows is clutter, not a feature.
            if (_saved.length > 3) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chartSearchField'),
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.chartSearch,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('chartFavouritesOnly'),
                    isSelected: _favouritesOnly,
                    tooltip: l10n.chartFavourites,
                    icon: const Icon(Icons.star_border),
                    selectedIcon: const Icon(Icons.star),
                    onPressed: () =>
                        setState(() => _favouritesOnly = !_favouritesOnly),
                  ),
                  IconButton.filledTonal(
                    key: const Key('chartRecentOnly'),
                    isSelected: _recentOnly,
                    tooltip: l10n.chartRecent,
                    icon: const Icon(Icons.history),
                    onPressed: () => setState(() => _recentOnly = !_recentOnly),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
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
            else if (_visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l10n.chartSearchNone,
                  key: const Key('chartSearchNone'),
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
                  itemCount: _visible.length,
                  itemBuilder: (context, i) {
                    final saved = _visible[i];
                    final chart = saved.chart;
                    final starred = _favourites.contains(saved.name);
                    final tags = widget.store.tagsOf(saved.name);
                    return ListTile(
                      key: Key('chartRow_${saved.name}'),
                      title: Text(saved.name),
                      subtitle: Text(
                        [
                          if (chart == null)
                            l10n.chartUnreadableSaved
                          else
                            _rowSummary(l10n, chart),
                          // Tags on the row: they are searched, so they show.
                          if (tags.isNotEmpty) tags.map((t) => '#$t').join(' '),
                        ].join('\n'),
                      ),
                      isThreeLine: tags.isNotEmpty,
                      onTap: () => _open(saved),
                      onLongPress: () => _editTags(saved),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('chartStar_${saved.name}'),
                            tooltip: starred
                                ? l10n.chartUnfavourite
                                : l10n.chartFavourite,
                            icon: Icon(
                              starred ? Icons.star : Icons.star_border,
                            ),
                            onPressed: () => _toggleFavourite(saved),
                          ),
                          IconButton(
                            key: Key('chartTags_${saved.name}'),
                            tooltip: l10n.chartTags,
                            icon: const Icon(Icons.sell_outlined),
                            onPressed: () => _editTags(saved),
                          ),
                          IconButton(
                            tooltip: l10n.chartDelete,
                            icon: const Icon(Icons.delete_outline),
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

/// Key · tempo · bars. The row shows what the search matches on, so a player
/// can see why a result came back.
String _rowSummary(AppLocalizations l10n, Chart chart) {
  final key = keyNameOf(chart.keyFifths, minor: chart.minor);
  return [
    if (key != null) key,
    '${chart.tempoBpm} bpm',
    l10n.chartBarCount(chart.totalBars),
  ].join(' · ');
}

/// The tag editor. Its own State owns the text controller, so it lives exactly
/// as long as the dialog — including the closing animation, which still reads
/// the field after the dialog has returned.
class _TagsDialog extends StatefulWidget {
  const _TagsDialog({
    required this.name,
    required this.initial,
    required this.known,
  });

  final String name;
  final List<String> initial;
  final List<String> known;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  late final _controller = TextEditingController(
    text: widget.initial.join(', '),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String tag) {
    final parts = _controller.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (!parts.contains(tag)) parts.add(tag);
    setState(() => _controller.text = parts.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.chartTagsFor(widget.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('chartTagsField'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(helperText: l10n.chartTagsHelp),
            ),
            if (widget.known.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in widget.known)
                    ActionChip(label: Text(tag), onPressed: () => _add(tag)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.chartCancel),
        ),
        FilledButton(
          key: const Key('chartTagsSave'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.chartOk),
        ),
      ],
    );
  }
}
