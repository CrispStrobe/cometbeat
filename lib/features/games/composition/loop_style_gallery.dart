// lib/features/games/composition/loop_style_gallery.dart
//
// The Loop Studio style gallery: the generated style catalog
// (core/audio/loop_style_recipes.dart) as cards grouped by genre, each showing
// its tempo and feel. Tapping a card asks the host to roll that style; the 🎲
// in the header rolls a random one. The host owns the engine and the undo
// history — this sheet only reports what was chosen, so every pick lands
// through the mixer's ordinary edit path and is undoable like any other edit.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_style_recipes.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/groove_slots.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The fixed seed a gallery audition uses: every child hears the same take
/// of a style when browsing, and its render can be cached.
const kStylePreviewSeed = 1;

/// The audition band: drums, bass, chords, melody of [recipeId] at
/// [kStylePreviewSeed], over the recipe's own progression. Synchronous and
/// pure on purpose — it is what runs inside the isolate.
Uint8List renderStylePreviewSync(String recipeId) {
  final engine = LoopEngine()
    ..setRecipe(recipeId, kStylePreviewSeed)
    ..enabled.addAll(const ['drums', 'bass', 'chords', 'melody']);
  return engine.renderLoop();
}

// Small LRU of rendered auditions (a 4-bar preview is ~1 MB of WAV, so keep
// a handful, not the whole catalog).
final Map<String, Uint8List> _previewCache = {};
const _previewCacheSize = 4;

/// Renders (or recalls) a style audition OFF the UI isolate. Top-level so the
/// isolate closure captures only the id string, never widget state.
Future<Uint8List> renderStylePreview(String recipeId) async {
  final hit = _previewCache.remove(recipeId);
  if (hit != null) return _previewCache[recipeId] = hit;
  final wav = await Isolate.run(() => renderStylePreviewSync(recipeId));
  _previewCache[recipeId] = wav;
  while (_previewCache.length > _previewCacheSize) {
    _previewCache.remove(_previewCache.keys.first);
  }
  return wav;
}

/// A style's display name.
String styleRecipeName(AppLocalizations l10n, String id) => switch (id) {
      'pop' => l10n.loopStyleNamePop,
      'rock' => l10n.loopStyleNameRock,
      'ballad' => l10n.loopStyleNameBallad,
      'funk' => l10n.loopStyleNameFunk,
      'hiphop' => l10n.loopStyleNameHiphop,
      'house' => l10n.loopStyleNameHouse,
      'lofi' => l10n.loopStyleNameLofi,
      'reggae' => l10n.loopStyleNameReggae,
      'bossa' => l10n.loopStyleNameBossa,
      'swing' => l10n.loopStyleNameSwing,
      'march' => l10n.loopStyleNameMarch,
      'kinderlied' => l10n.loopStyleNameKinderlied,
      _ => id,
    };

String styleGenreName(AppLocalizations l10n, StyleGenre g) => switch (g) {
      StyleGenre.popRock => l10n.loopStyleGenrePopRock,
      StyleGenre.groove => l10n.loopStyleGenreGroove,
      StyleGenre.world => l10n.loopStyleGenreWorld,
      StyleGenre.classic => l10n.loopStyleGenreClassic,
    };

String styleFeelName(AppLocalizations l10n, StyleFeel f) => switch (f) {
      StyleFeel.straight => l10n.loopStyleFeelStraight,
      StyleFeel.driving => l10n.loopStyleFeelDriving,
      StyleFeel.swung => l10n.loopStyleFeelSwung,
      StyleFeel.shuffle => l10n.loopStyleFeelShuffle,
      StyleFeel.laidBack => l10n.loopStyleFeelLaidBack,
      StyleFeel.gentle => l10n.loopStyleFeelGentle,
    };

IconData _genreIcon(StyleGenre g) => switch (g) {
      StyleGenre.popRock => Icons.electric_bolt,
      StyleGenre.groove => Icons.graphic_eq,
      StyleGenre.world => Icons.public,
      StyleGenre.classic => Icons.music_note,
    };

/// Opens the gallery as a bottom sheet. [onPick] gets a recipe id, [onRoll]
/// is the header 🎲. Both close the sheet first.
Future<void> showLoopStyleGallery(
  BuildContext context, {
  required String? currentRecipeId,
  required ValueChanged<String> onPick,
  required VoidCallback onRoll,
  VoidCallback? onPreviewStart,
  Future<Uint8List> Function(String recipeId)? previewRender,
  List<GrooveSlot> presets = const [],
  ValueChanged<String>? onLoadPreset,
  VoidCallback? onSavePreset,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: 0.85,
        child: LoopStyleGallery(
          currentRecipeId: currentRecipeId,
          onPreviewStart: onPreviewStart,
          previewRender: previewRender ?? renderStylePreview,
          presets: presets,
          onLoadPreset: onLoadPreset == null
              ? null
              : (token) {
                  Navigator.of(sheet).pop();
                  onLoadPreset(token);
                },
          onSavePreset: onSavePreset == null
              ? null
              : () {
                  Navigator.of(sheet).pop();
                  onSavePreset();
                },
          onPick: (id) {
            Navigator.of(sheet).pop();
            onPick(id);
          },
          onRoll: () {
            Navigator.of(sheet).pop();
            onRoll();
          },
        ),
      ),
    );

class LoopStyleGallery extends StatefulWidget {
  const LoopStyleGallery({
    super.key,
    required this.currentRecipeId,
    required this.onPick,
    required this.onRoll,
    this.onPreviewStart,
    this.previewRender = renderStylePreview,
    this.presets = const [],
    this.onLoadPreset,
    this.onSavePreset,
  });

  /// The player's saved grooves ("my presets") — the SAME store as the
  /// mixer's save slots: a slot is a `KU1.` token, which already carries the
  /// style, seed, pins and every edit, so a preset needs no format of its own.
  final List<GrooveSlot> presets;

  /// Loads a preset's token (null hides the section's taps).
  final ValueChanged<String>? onLoadPreset;

  /// Saves the current groove as a preset (null hides the button).
  final VoidCallback? onSavePreset;

  final String? currentRecipeId;
  final ValueChanged<String> onPick;
  final VoidCallback onRoll;

  /// Called when an audition starts — the host pauses its own groove so two
  /// loops never play over each other.
  final VoidCallback? onPreviewStart;

  /// Renders a style's audition WAV (off the UI isolate by default).
  final Future<Uint8List> Function(String recipeId) previewRender;

  @override
  State<LoopStyleGallery> createState() => _LoopStyleGalleryState();
}

class _LoopStyleGalleryState extends State<LoopStyleGallery> {
  GaplessLoopPlayer? _player;

  /// The style auditioning (or loading) now, if any.
  String? _previewId;
  bool _loading = false;

  /// Bumped on every start/stop so a slow render that lands after the child
  /// moved on is dropped instead of starting to play.
  int _generation = 0;

  @override
  void dispose() {
    // Leaving the gallery always ends the audition.
    _generation++;
    final p = _player;
    if (p != null) {
      p.stop().whenComplete(p.dispose);
    }
    super.dispose();
  }

  Future<void> _togglePreview(String id) async {
    final gen = ++_generation;
    if (_previewId == id) {
      setState(() {
        _previewId = null;
        _loading = false;
      });
      await _player?.stop();
      return;
    }
    widget.onPreviewStart?.call();
    setState(() {
      _previewId = id;
      _loading = true;
    });
    final wav = await widget.previewRender(id);
    if (!mounted || gen != _generation) return;
    setState(() => _loading = false);
    await (_player ??= GaplessLoopPlayer()).playLoop(wav);
  }

  void _pick(String id) {
    _generation++;
    _player?.stop();
    widget.onPick(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.loopStyleGallery,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const Key('loop-style-gallery-dice'),
                  onPressed: () {
                    _generation++;
                    _player?.stop();
                    widget.onRoll();
                  },
                  icon: const Text('🎲', style: TextStyle(fontSize: 18)),
                  label: Text(l10n.loopStyleDice),
                ),
              ],
            ),
          ),
        ),
        if (widget.onSavePreset != null || widget.presets.isNotEmpty)
          SliverToBoxAdapter(child: _presetSection(context, l10n)),
        for (final genre in StyleGenre.values) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Icon(_genreIcon(genre), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    styleGenreName(l10n, genre),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 1.9,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final r in kStyleRecipes)
                  if (r.genre == genre) _card(context, l10n, r),
              ],
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _presetSection(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bookmarks, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.loopStyleMyPresets,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (widget.onSavePreset != null)
                TextButton.icon(
                  key: const Key('loop-style-save-preset'),
                  onPressed: widget.onSavePreset,
                  icon: const Icon(Icons.bookmark_add, size: 18),
                  label: Text(l10n.loopStyleSavePreset),
                ),
            ],
          ),
          if (widget.presets.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final slot in widget.presets)
                  ActionChip(
                    key: Key('loop-style-preset-${slot.name}'),
                    avatar: const Icon(Icons.queue_music, size: 18),
                    label: Text(_presetLabel(l10n, slot)),
                    onPressed: widget.onLoadPreset == null
                        ? null
                        : () => widget.onLoadPreset!(slot.token),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// "My band · Funk" — the style a preset was made in, when it was one of
  /// the generated ones.
  String _presetLabel(AppLocalizations l10n, GrooveSlot slot) {
    final recipe = decodeGrooveToken(slot.token)?.recipeId;
    return recipe == null
        ? slot.name
        : '${slot.name} · ${styleRecipeName(l10n, recipe)}';
  }

  Widget _card(BuildContext context, AppLocalizations l10n, StyleRecipe r) {
    final scheme = Theme.of(context).colorScheme;
    final selected = r.id == widget.currentRecipeId;
    final auditioning = r.id == _previewId;
    final tempos = r.tempos.length == 1
        ? '${r.tempos.single}'
        : '${r.tempos.reduce((a, b) => a < b ? a : b)}–'
            '${r.tempos.reduce((a, b) => a > b ? a : b)}';
    return Card(
      key: Key('loop-style-card-${r.id}'),
      margin: EdgeInsets.zero,
      color: selected ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _pick(r.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      styleRecipeName(l10n, r.id),
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: Key('loop-style-preview-${r.id}'),
                    tooltip: auditioning
                        ? l10n.loopStyleStopPreview
                        : l10n.loopStylePreview(styleRecipeName(l10n, r.id)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _togglePreview(r.id),
                    icon: auditioning && _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            auditioning
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline,
                          ),
                  ),
                ],
              ),
              Text(
                '${l10n.loopStyleBpm(tempos)} · ${styleFeelName(l10n, r.feel)}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
