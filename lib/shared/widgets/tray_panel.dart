// lib/shared/widgets/tray_panel.dart
//
// WS-X6 slice 1 — the clipboard, drawn.
//
// ⚠️ THIS IS AN INLINE BAND, NOT AN OVERLAY, AND THAT IS THE WHOLE REASON THE
// FEATURE WORKS. The obvious build is a menu or a bottom sheet hung off the
// top-bar button — and it would break the main use, because a route or a menu
// puts a barrier between you and the surface underneath. You could look at your
// samples and never drag one onto anything. That is precisely the wall WS-X2
// spent four drop targets failing to get over: nothing could be dragged, because
// nothing was ever on screen at the same time as a target.
//
// So the host inserts this into its OWN layout, under the app bar and above the
// surface. Source and target then live in one widget tree, one frame, no
// barrier — on a phone as much as on a desktop. That is what makes the four
// existing drop targets reachable without touching any of them.
//
// TWO WAYS TO USE AN ITEM, because one of them fails on a small screen: DRAG it
// onto the surface (direct, and what a mouse wants), or TAP it (which a thumb
// can do, and which needs no aim). Both hand over the same `MusicDragPayload`,
// so a target cannot tell them apart and neither can behave differently.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/tray/tray.dart';
import 'package:flutter/material.dart';

/// The icon for a kind. Small and recognisable rather than a real thumbnail:
/// a waveform for audio, a grid for a tracker pattern, notes for a score. Real
/// per-item thumbnails (an actual waveform, an actual pattern) are worth having
/// and are not slice 1 — an icon that is right beats a picture that is late.
IconData trayIconFor(AppMode kind) => switch (kind) {
      AppMode.audio => Icons.graphic_eq,
      AppMode.tracker => Icons.grid_on,
      AppMode.loop => Icons.loop,
      AppMode.score => Icons.music_note,
      AppMode.tab => Icons.linear_scale,
    };

/// The clipboard band.
///
/// Rendered by a host when its clipboard button is on. Collapsed height is zero
/// — the host decides whether to animate it.
class TrayPanel extends StatefulWidget {
  const TrayPanel({
    required this.tray,
    super.key,
    this.onPlace,
    this.emptyHint = 'Nothing here yet. Put something on it from any editor.',
    this.title = 'Clipboard',
  });

  final TrayService tray;

  /// Tap-to-place. Null means this host can only be dragged onto — which is a
  /// legitimate state for a surface with nowhere obvious to put a thing.
  final void Function(TrayItem item)? onPlace;

  final String emptyHint;
  final String title;

  @override
  State<TrayPanel> createState() => _TrayPanelState();
}

class _TrayPanelState extends State<TrayPanel> {
  @override
  void initState() {
    super.initState();
    widget.tray.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(TrayPanel old) {
    super.didUpdateWidget(old);
    if (old.tray != widget.tray) {
      old.tray.removeListener(_onChanged);
      widget.tray.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.tray.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.tray.items;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.content_paste, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                if (items.isNotEmpty)
                  Text(
                    '${items.length}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  widget.emptyHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              // One row that scrolls: a clipboard holding "every sample of a
              // drum kit" must not grow downward until it eats the surface it
              // exists to serve.
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _TrayChip(
                    item: items[i],
                    onPlace: widget.onPlace,
                    onRemove: () => widget.tray.remove(items[i].id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrayChip extends StatelessWidget {
  const _TrayChip({
    required this.item,
    required this.onRemove,
    this.onPlace,
  });

  final TrayItem item;
  final VoidCallback onRemove;
  final void Function(TrayItem item)? onPlace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final place = onPlace;

    final body = Container(
      key: Key('tray-chip-${item.id}'),
      width: 108,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(trayIconFor(item.kind), size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Draggable rather than LongPressDraggable: this band does not scroll
        // vertically and the row's own horizontal scroll wins the arena for a
        // horizontal drag, so a plain drag is free to mean "take this out".
        // ⚠️ Drags `MusicDragPayload` ITSELF, not a wrapper around it. A
        // `Draggable<T>` and a `DragTarget<T>` are matched by T alone, so this
        // is exactly what makes the four drop targets WS-X2 already shipped
        // accept a clipboard item without a line of change to any of them —
        // which was the point of building this rather than a fifth target.
        Draggable<MusicDragPayload>(
          data: item.payload,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: body),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: body),
          child: place == null
              ? body
              : InkWell(
                  onTap: () => place(item),
                  borderRadius: BorderRadius.circular(8),
                  child: body,
                ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            key: Key('tray-remove-${item.id}'),
            tooltip: 'Remove',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.cancel),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
