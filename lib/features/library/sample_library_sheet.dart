// "Browse free sounds" — a modal sheet that browses CC0/PD audio samples from a
// [ContentSource] (Wikimedia Commons WAV via buildSampleSources), downloads the
// picked one and decodes it to mono-float PCM. Returns a [Float64List] the
// Tracker can drop straight into its sample-instrument path (same type its
// "Load WAV" button already produces), so wiring it in is a one-liner.
//
// All the browse/fetch/decode logic lives here (libraries-and-tab's lane); the
// Tracker just calls [showSampleLibrarySheet].

import 'dart:typed_data';

import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Decodes WAV [bytes] to mono-float PCM (the Tracker's sample format). Pure +
/// injectable so the sheet is testable without the real `wav_io` on odd files.
typedef WavDecode = Float64List Function(Uint8List bytes);

Float64List _defaultDecode(Uint8List bytes) =>
    wavToMonoFloat(readWavPcm16(bytes));

/// Shows the free-sound browser. Returns the decoded mono-float PCM of the
/// picked sample, or null if cancelled / on error. [sources] defaults to
/// [buildSampleSources]; [decode] is injectable for tests.
Future<Float64List?> showSampleLibrarySheet(
  BuildContext context, {
  List<ContentSource>? sources,
  WavDecode decode = _defaultDecode,
}) {
  return showModalBottomSheet<Float64List>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SampleLibrarySheet(
      sources: sources ?? buildSampleSources(),
      decode: decode,
    ),
  );
}

class _SampleLibrarySheet extends StatefulWidget {
  final List<ContentSource> sources;
  final WavDecode decode;
  const _SampleLibrarySheet({required this.sources, required this.decode});

  @override
  State<_SampleLibrarySheet> createState() => _SampleLibrarySheetState();
}

class _SampleLibrarySheetState extends State<_SampleLibrarySheet> {
  late final ContentSource _source = widget.sources.first;
  final _search = TextEditingController();
  List<LibraryItem> _items = const [];
  bool _loading = false;
  bool _fetching = false;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.libraryLoadFailed;
        _loading = false;
      });
    }
  }

  Future<void> _pick(LibraryItem item) async {
    setState(() => _fetching = true);
    try {
      final bytes = await _source.fetch(item);
      final pcm = widget.decode(bytes);
      if (!mounted) return;
      Navigator.of(context).pop(pcm);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = AppLocalizations.of(context)!.libraryImportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_source.name} · ${_source.licenseSummary}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
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
            const SizedBox(height: 8),
            if (_fetching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SizedBox(height: 260, child: _list(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: Text(l10n.libraryRetry)),
          ],
        ),
      );
    }
    if (_items.isEmpty) return Center(child: Text(l10n.libraryNoResults));
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.music_note),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.declaredLicense),
          onTap: () => _pick(item),
        );
      },
    );
  }
}
