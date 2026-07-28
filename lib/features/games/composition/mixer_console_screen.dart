// lib/features/games/composition/mixer_console_screen.dart
//
// WS-W5 — one mixer strip per project track, whatever kind it is.
//
// WHY IT MATTERS MORE THAN IT LOOKS. `ProjectTrackMix` (level · pan · mute ·
// solo) has existed since WS-W1 and **nothing in the app ever read or wrote
// it** — it was constructed only inside `project.dart` and its codec. That is
// the same shape as the shared count-in and `Project` itself: complete, tested,
// inert. This screen is what makes the mix real, which is why it comes before
// more per-surface plumbing.
//
// ONE STRIP PER TRACK, ANY KIND. A tracker pattern, a loop, a tab and a score
// sit side by side here, which is the point of a workstation: the mix is a
// property of the PROJECT, not of whichever editor happened to make the track.
// The kind is shown on the strip rather than being segregated into sections,
// because a user mixing does not care which editor a part came from.
//
// SOLO IS EXCLUSIVE-BY-CONVENTION, NOT BY DATA. `soloed` is per-track, so more
// than one track can be soloed at once — that is deliberate and matches every
// mixer worth using ("solo these three"). What a soloed track means for the
// AUDIBLE mix is a renderer question, and the renderer does not read these
// values yet.
//
// ⚠️ WHAT THIS SCREEN DOES NOT DO, stated so nobody reads more into it: the
// values are editable and persist with the project, but **no render path
// honours them yet**. Teaching the renderers to apply project mix is its own
// card, with its own byte-identical guard, and pretending otherwise here would
// be the kind of half-truth that costs someone an afternoon.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MixerConsoleScreen extends StatelessWidget {
  const MixerConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final projects = context.watch<ProjectService>();
    final tracks = projects.tracks;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mixerConsoleTitle)),
      body: tracks.isEmpty
          // An empty mixer is the normal state until a surface adds a track,
          // and a blank screen reads as broken. Say which action fills it.
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.mixerConsoleEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: tracks.length,
              itemBuilder: (context, i) => _Strip(
                key: ValueKey('mixer-strip-${tracks[i].id}'),
                track: tracks[i],
                projects: projects,
              ),
            ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({super.key, required this.track, required this.projects});

  final ProjectTrack track;
  final ProjectService projects;

  void _setMix(ProjectTrackMix mix) {
    projects.updateTrack(track.id, track.copyWith(mix: mix));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final mix = track.mix;

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
                        track.name.isEmpty ? track.id : track.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      // The kind, because a mixer holding four different sorts
                      // of track has to say which is which.
                      Text(
                        appModeLabel(track.kind),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('mixer-mute-${track.id}'),
                  tooltip: l10n.mixerMute,
                  icon: Icon(mix.muted ? Icons.volume_off : Icons.volume_up),
                  color: mix.muted ? scheme.error : null,
                  onPressed: () => _setMix(mix.copyWith(muted: !mix.muted)),
                ),
                IconButton(
                  key: ValueKey('mixer-solo-${track.id}'),
                  tooltip: l10n.mixerSolo,
                  icon: const Icon(Icons.headphones),
                  color: mix.soloed ? scheme.primary : null,
                  onPressed: () => _setMix(mix.copyWith(soloed: !mix.soloed)),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(width: 44, child: Text(l10n.mixerLevel)),
                Expanded(
                  child: Slider(
                    key: ValueKey('mixer-level-${track.id}'),
                    value: mix.level.clamp(0, 1),
                    onChanged: (v) => _setMix(mix.copyWith(level: v)),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(width: 44, child: Text(l10n.mixerPan)),
                Expanded(
                  child: Slider(
                    key: ValueKey('mixer-pan-${track.id}'),
                    value: mix.pan.clamp(-1, 1),
                    min: -1,
                    onChanged: (v) => _setMix(mix.copyWith(pan: v)),
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
