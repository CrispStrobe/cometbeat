// Browse a connected open-music library and import a work into the Song Book.
// Everything imported passes the LicensePolicy gate and carries provenance, so
// the "Sources & credits" screen can attribute it.

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/attribution_screen.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/library_import.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/source_registry.dart';
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _source.browse(query: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

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
              MaterialPageRoute(builder: (_) => AttributionScreen()),
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
          const Divider(height: 1),
          Expanded(child: _list(l10n)),
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
      itemCount: _items.length,
      itemBuilder: (context, i) {
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
