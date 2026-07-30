// Browse a connected open-music library and import a work into the Song Book.
// Everything imported passes the LicensePolicy gate and carries provenance, so
// the "Sources & credits" screen can attribute it.

import 'dart:async';

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/attribution_screen.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/library_import.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:comet_beat/features/library/sources/cometbeat_catalog_source.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LibraryBrowserScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the real registry (live network).
  final List<ContentSource>? sources;
  final LicensePolicy policy;

  const LibraryBrowserScreen({
    super.key,
    this.sources,
    this.policy = const LicensePolicy(),
  });

  @override
  State<LibraryBrowserScreen> createState() => _LibraryBrowserScreenState();
}

class _LibraryBrowserScreenState extends State<LibraryBrowserScreen> {
  late final List<ContentSource> _sources = widget.sources ?? buildSources();
  late ContentSource _source = _sources.first;

  final _search = TextEditingController();
  List<LibraryItem> _items = [];
  bool _loading = false;
  String? _error;

  /// Facet selections. A 38k-row catalog is unusable with only a text box.
  LibraryFilter _filter = const LibraryFilter();

  /// Facet values offered as chips, derived from what is actually present so a
  /// chip can never produce an empty result set.
  Map<String, List<String>> _facets = const {};

  static const _pageSize = 60;
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;

  /// Exact match count when the source can count, else null — the browser says
  /// "60 of 448" or just "60", never a made-up total.
  int? _total;

  /// Debounces as-you-type search. Previously the box only searched on submit,
  /// which on a 38k catalog meant typing blind.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onQueryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _reload();
    });
  }

  /// Re-runs the query from the top, or appends the next page when [append].
  Future<void> _reload({bool append = false}) async {
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _offset = 0;
      }
      _error = null;
    });
    try {
      final page = await _source.browsePage(
        query: _search.text.trim(),
        filter: _filter,
        limit: _pageSize,
        offset: append ? _offset + _pageSize : 0,
      );
      if (!mounted) return;
      // Facets come from the source when it can enumerate them, else from the
      // rows in hand — a partial list still beats no filters at all.
      final facets = await _facetsFor(_source, page.items);
      if (!mounted) return;
      setState(() {
        if (append) {
          _items = [..._items, ...page.items];
          _offset += _pageSize;
        } else {
          _items = page.items;
          _offset = 0;
          _facets = facets;
        }
        _total = page.total;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<Map<String, List<String>>> _facetsFor(
    ContentSource source,
    List<LibraryItem> shown,
  ) async {
    if (source is CometbeatCatalogSource) {
      try {
        return await source.facets();
      } catch (_) {/* fall through to what is on screen */}
    }
    List<String> distinct(String Function(LibraryItem) f, int top) {
      final c = <String, int>{};
      for (final i in shown) {
        final k = f(i);
        if (k.isNotEmpty) c[k] = (c[k] ?? 0) + 1;
      }
      return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(top)
          .map((e) => e.key)
          .toList();
    }

    return {
      'kind': distinct((i) => i.collection, 8),
      'format': distinct((i) => i.format, 12),
      'source': distinct((i) => i.corpusSource ?? '', 20),
    };
  }

  void _toggleFacet(String facet, String value) {
    setState(() => _filter = _filter.toggle(facet, value));
    _reload();
  }

  Set<String> _selected(String facet) => switch (facet) {
        'kind' => _filter.kinds,
        'format' => _filter.formats,
        'source' => _filter.sources,
        _ => _filter.licences,
      };

  Future<void> _import(LibraryItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final service = context.read<UserSongsService>();
    if (service.songs.any((s) => s.id == 'lib_${item.sourceId}_${item.id}')) {
      _snack(l10n.libraryAlreadyImported);
      return;
    }
    try {
      final song =
          await importLibraryItem(item, _source, policy: widget.policy);
      if (!mounted) return;
      service.addSong(song);
      _snack(l10n.libraryImported(item.title));
    } on LicenseBlocked {
      _snack(l10n.libraryLicenseBlocked);
    } catch (e) {
      if (!mounted) return;
      _snack(l10n.libraryImportFailed);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.copyright),
            tooltip: l10n.librarySourcesCredits,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AttributionScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.public, size: 20),
                const SizedBox(width: 8),
                if (_sources.length > 1)
                  Expanded(
                    child: DropdownButton<ContentSource>(
                      value: _source,
                      isExpanded: true,
                      onChanged: (s) {
                        if (s == null || s == _source) return;
                        setState(() => _source = s);
                        _reload();
                      },
                      items: [
                        for (final s in _sources)
                          DropdownMenuItem(
                            value: s,
                            child: Text(
                              '${s.name} · ${s.licenseSummary}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      '${_source.name} · ${_source.licenseSummary}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: l10n.librarySearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          _facetBar(),
          if (!_loading && _error == null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  // "showing 60 of 448" when the source can count, else just the
                  // number in hand. Never a guessed total.
                  _total == null
                      ? '${_items.length}'
                      : '${_items.length} / $_total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _list(l10n)),
        ],
      ),
    );
  }

  /// Horizontally scrolling facet chips. Only facets with a real choice are
  /// shown — a lone value filters nothing and would just take up space.
  Widget _facetBar() {
    final groups = [
      for (final facet in const ['kind', 'format', 'source'])
        if ((_facets[facet] ?? const []).length > 1) facet,
    ];
    // The lyric toggle is always offered when the source can do it: it is the
    // difference between finding a song by its title and finding it by the words
    // a child remembers.
    final lyricChip = _source is CometbeatCatalogSource
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: FilterChip(
              avatar: const Icon(Icons.lyrics_outlined, size: 16),
              label: Text(AppLocalizations.of(context)!.librarySearchLyrics),
              selected: _filter.searchLyrics,
              onSelected: (v) {
                setState(() => _filter = _filter.withLyricSearch(v));
                _reload();
              },
              visualDensity: VisualDensity.compact,
            ),
          )
        : null;
    if (groups.isEmpty && lyricChip == null) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (lyricChip != null) lyricChip,
          for (final facet in groups) ...[
            for (final v in _facets[facet]!)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                child: FilterChip(
                  label: Text(v),
                  selected: _selected(facet).contains(v),
                  onSelected: (_) => _toggleFacet(facet, v),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (facet != groups.last)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: VerticalDivider(width: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _list(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.libraryLoadFailed, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reload,
                child: Text(l10n.libraryRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(l10n.libraryNoResults));
    }
    return ListView.builder(
      // One extra row for "load more" when the source says there is more. The
      // list used to stop dead at 60 with no way forward, so a query matching
      // thousands looked like a query matching sixty.
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton.icon(
                      onPressed: () => _reload(append: true),
                      icon: const Icon(Icons.expand_more),
                      label: Text(l10n.libraryLoadMore),
                    ),
            ),
          );
        }
        final item = _items[i];
        final subtitle = [
          if (item.composer.isNotEmpty) item.composer,
          item.declaredLicense,
        ].join(' · ');
        // Key/metre/range answer "could we actually play this?" before the
        // download, which is the whole point of indexing them in the catalog.
        final music = item.music;
        final musical = music == null
            ? null
            : [
                if (music.key != null) music.key!,
                if (music.meter != null) music.meter!,
                if (music.ambitusLabel != null) music.ambitusLabel!,
                if (music.bars != null) '${music.bars} bars',
              ].join(' · ');
        return ListTile(
          isThreeLine: musical != null && musical.isNotEmpty,
          title: Text(item.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subtitle),
              if (musical != null && musical.isNotEmpty)
                Row(
                  children: [
                    if (music!.fitsOneOctave) ...[
                      Icon(
                        Icons.straighten,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        musical,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download),
            tooltip: l10n.libraryImport,
            onPressed: () => _import(item),
          ),
          onTap: () => _import(item),
        );
      },
    );
  }
}
