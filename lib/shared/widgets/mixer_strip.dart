// lib/shared/widgets/mixer_strip.dart
//
// One mixer strip — name, mute, solo, level, pan — as a plain view.
//
// The project mixer console and the backing band's live controls (BB-U3) both
// draw THIS strip; neither owns a second one. What a change means (an undoable
// project edit, or a voice volume on a playing band) is the caller's business,
// passed in as callbacks.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class MixerStripView extends StatelessWidget {
  const MixerStripView({
    required this.id,
    required this.title,
    required this.muted,
    required this.soloed,
    required this.level,
    required this.onMute,
    required this.onLevel,
    this.onSolo,
    this.subtitle,
    this.pan,
    this.onPan,
    this.onDragEnd,
    this.trailing,
    super.key,
  });

  /// Keys the controls (`mixer-mute-<id>`, `mixer-level-<id>`, …).
  final String id;
  final String title;
  final String? subtitle;
  final bool muted;
  final bool soloed;

  /// 0–1.
  final double level;

  /// −1–1; null hides the pan row.
  final double? pan;

  final VoidCallback onMute;

  /// Null hides the solo button (an effects bus has nothing to solo).
  final VoidCallback? onSolo;
  final ValueChanged<double> onLevel;
  final ValueChanged<double>? onPan;

  /// A level or pan drag ended.
  final VoidCallback? onDragEnd;

  /// Extra control under the title row (the band's voice picker, say).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final pan = this.pan;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('mixer-mute-$id'),
                  tooltip: l10n.mixerMute,
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  color: muted ? scheme.error : null,
                  onPressed: onMute,
                ),
                if (onSolo != null)
                  IconButton(
                    key: ValueKey('mixer-solo-$id'),
                    tooltip: l10n.mixerSolo,
                    icon: const Icon(Icons.headphones),
                    color: soloed ? scheme.primary : null,
                    onPressed: onSolo,
                  ),
              ],
            ),
            if (trailing != null) trailing!,
            Row(
              children: [
                SizedBox(width: 44, child: Text(l10n.mixerLevel)),
                Expanded(
                  child: Slider(
                    key: ValueKey('mixer-level-$id'),
                    value: level.clamp(0, 1),
                    onChanged: onLevel,
                    onChangeEnd: (_) => onDragEnd?.call(),
                  ),
                ),
              ],
            ),
            if (pan != null)
              Row(
                children: [
                  SizedBox(width: 44, child: Text(l10n.mixerPan)),
                  Expanded(
                    child: Slider(
                      key: ValueKey('mixer-pan-$id'),
                      value: pan.clamp(-1, 1),
                      min: -1,
                      onChanged: onPan,
                      onChangeEnd: (_) => onDragEnd?.call(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
