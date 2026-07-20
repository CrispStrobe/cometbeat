// lib/features/games/songs/songbook_screen.dart
//
// Browse and arrange one songbook — a named, ordered collection of the user's
// imported/composed songs (the SongCollection model in UserSongsService). Songs
// can be reordered by drag, removed from the book (the song itself stays in the
// library), added from a picker, and the book renamed or deleted. Tapping a
// song opens it in the shared player.

import 'package:comet_beat/features/games/songs/song_book.dart'
    show Song, kSongs;
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show scoreToMusicXml;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongbookScreen extends StatelessWidget {
  const SongbookScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final service = context.watch<UserSongsService>();
    final books = service.collections.where((c) => c.id == collectionId);
    // The book was deleted out from under us (e.g. on another screen) — leave.
    if (books.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final book = books.first;
    final songs = service.songsInCollection(collectionId);

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: l.songbookAddSongs,
            onPressed: () => _addSongs(context, service),
          ),
          PopupMenuButton<String>(
            onSelected: (choice) {
              if (choice == 'rename') {
                _rename(context, service, book.title);
              } else if (choice == 'delete') {
                service.removeCollection(collectionId);
                Navigator.of(context).maybePop();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l.songbookRename)),
              PopupMenuItem(value: 'delete', child: Text(l.songbookDelete)),
            ],
          ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  service.songs.isEmpty ? l.songbookNoImports : l.songbookEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: songs.length,
              onReorderItem: (oldIndex, newIndex) =>
                  service.reorderCollection(collectionId, oldIndex, newIndex),
              itemBuilder: (context, i) {
                final song = songs[i];
                return Card(
                  key: ValueKey(song.id),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(song.title),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: l.songbookRemoveFromBook,
                          onPressed: () => service.removeSongFromCollection(
                            collectionId,
                            song.id,
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ],
                    ),
                    onTap: () => openImportedSong(context, song),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    UserSongsService service,
    String current,
  ) async {
    final name = await _promptName(context, current);
    if (name != null && name.isNotEmpty) {
      service.renameCollection(collectionId, name);
    }
  }

  /// A checklist of songs to add to this book — the built-in children's songs
  /// AND the user's own imported/composed/transcribed songs. Ticking a built-in
  /// song first materialises it into the library (its DSL → MusicXML, under a
  /// stable `builtin_<id>`) so a book can actually contain the nursery songs.
  /// Changes apply immediately (the service is the source of truth).
  Future<void> _addSongs(
    BuildContext context,
    UserSongsService service,
  ) async {
    final l = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Consumer<UserSongsService>(
            builder: (ctx, svc, _) {
              final books = svc.collections.where((c) => c.id == collectionId);
              final inBook =
                  books.isEmpty ? <String>{} : books.first.songIds.toSet();
              // The user's OWN songs (exclude materialised built-ins so they
              // aren't listed twice).
              final imported =
                  svc.songs.where((s) => !s.id.startsWith('builtin_')).toList();
              return ListView(
                shrinkWrap: true,
                children: [
                  _sheetHeader(ctx, l.songbookAddSongs),
                  _sectionLabel(ctx, l.songbookBuiltinSongs),
                  for (final song in kSongs)
                    CheckboxListTile(
                      value: inBook.contains('builtin_${song.id}'),
                      title: Text(song.title),
                      onChanged: (checked) =>
                          _toggleBuiltin(svc, song, checked ?? false),
                    ),
                  if (imported.isNotEmpty) ...[
                    _sectionLabel(ctx, l.importedSongs),
                    for (final song in imported)
                      CheckboxListTile(
                        value: inBook.contains(song.id),
                        title: Text(song.title),
                        onChanged: (checked) {
                          if (checked ?? false) {
                            svc.addSongToCollection(collectionId, song.id);
                          } else {
                            svc.removeSongFromCollection(collectionId, song.id);
                          }
                        },
                      ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Add/remove a built-in song to this book, materialising it into the library
  /// on first add (idempotent — the `builtin_<id>` copy is reused thereafter).
  void _toggleBuiltin(UserSongsService svc, Song song, bool checked) {
    final id = 'builtin_${song.id}';
    if (checked) {
      if (!svc.songs.any((s) => s.id == id)) {
        svc.addSong(
          ImportedSong(
            id: id,
            title: song.title,
            musicXml: scoreToMusicXml(song.score, partName: song.title),
          ),
        );
      }
      svc.addSongToCollection(collectionId, id);
    } else {
      svc.removeSongFromCollection(collectionId, id);
    }
  }

  Widget _sheetHeader(BuildContext ctx, String text) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: Theme.of(ctx).textTheme.titleMedium),
      );

  Widget _sectionLabel(BuildContext ctx, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                color: Theme.of(ctx).colorScheme.primary,
              ),
        ),
      );
}

/// Shared name dialog for creating/renaming a songbook. Returns the trimmed
/// name, or null if cancelled.
Future<String?> _promptName(BuildContext context, String initial) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.songbookNameTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
  return result?.trim();
}

/// Prompt for a new songbook's name and create it. Exposed so the song list can
/// trigger creation from its "+" action.
Future<void> createSongbook(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final service = context.read<UserSongsService>();
  final name = await _promptName(context, l.songbookDefaultName);
  if (name == null) return;
  service.createCollection(name.isEmpty ? l.songbookDefaultName : name);
}
