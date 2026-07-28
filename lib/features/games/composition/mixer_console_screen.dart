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
// PLAY RENDERS THE PROJECT (WS-W5c). `renderProject` sums every track through
// the sources that already render each kind and applies level, pan, mute and
// solo, so the faders here are audible rather than decorative.
//
// ⚠️ It surfaces `ProjectMixdown.skipped` rather than swallowing it. The
// renderer deliberately REPORTS tracks it cannot sound (a tab needs an
// instrument chosen; audio tracks are not carried in the project yet), and a
// Play button that hid that would undo the honesty the renderer was built with —
// the user would hear a mix quietly missing a part and have no way to know.

import 'dart:async';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytesStereo;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_render.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/core/services/undo_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/transport_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MixerConsoleScreen extends StatefulWidget {
  const MixerConsoleScreen({super.key});

  @override
  State<MixerConsoleScreen> createState() => _MixerConsoleScreenState();
}

@visibleForTesting
abstract interface class MixerConsoleTester {
  /// Renders the project and plays it. Returns the mixdown so a test can
  /// assert on the SAMPLES rather than on the button having been tapped.
  Future<ProjectMixdown> playMix();
  bool get isPlaying;
}

/// Records a mix change as one undoable step (WS-W5d).
///
/// [coalesceKey] is what makes a DRAG one undo rather than one per frame: a
/// fader dragged across sixty frames is a single edit to the person doing it,
/// and a history with sixty entries in it is a history nobody will use.
void _pushMixUndo(
  BuildContext context,
  ProjectService projects,
  ProjectTrack track,
  ProjectTrackMix next,
  String label, {
  Object? coalesceKey,
}) {
  final before = track.mix;
  final id = track.id;
  void apply(ProjectTrackMix mix) {
    final current = projects.track(id);
    if (current != null) projects.updateTrack(id, current.copyWith(mix: mix));
  }

  apply(next);
  UndoService? undo;
  try {
    undo = Provider.of<UndoService>(context, listen: false);
  } on ProviderNotFoundException {
    undo = null;
  }
  undo?.push(
    UndoEntry(
      label: label,
      scope: 'mixer:$id',
      coalesceKey: coalesceKey,
      undo: () => apply(before),
      redo: () => apply(next),
    ),
  );
}

class _MixerConsoleScreenState extends State<MixerConsoleScreen>
    implements MixerConsoleTester {
  bool _playing = false;
  List<SkippedTrack> _skipped = const [];

  @override
  bool get isPlaying => _playing;

  @override
  Future<ProjectMixdown> playMix() async {
    final projects = context.read<ProjectService>();
    final audio = context.read<AudioService>();
    final mix = renderProject(projects.project);
    if (mounted) setState(() => _skipped = mix.skipped);
    if (mix.isSilent) {
      if (mounted) setState(() => _playing = false);
      return mix;
    }
    // Not awaited, and gated on the master sound switch — both copied from the
    // Audio Editor deliberately. Awaiting the player never completes under the
    // headless test binding (it hung a 10-minute run), and `soundOn` is the
    // app-wide mute that every other surface honours.
    if (audio.soundOn) {
      unawaited(
        audio.playWavBytes(
          wavBytesStereo(_interleave(mix), sampleRate: mix.sampleRate),
        ),
      );
    }
    if (mounted) setState(() => _playing = true);
    return mix;
  }

  Future<void> _stop() async {
    await context.read<AudioService>().stop();
    if (mounted) setState(() => _playing = false);
  }

  Widget _transportBar(BuildContext context) {
    TransportService? transport;
    UndoService? undo;
    try {
      transport = Provider.of<TransportService>(context, listen: false);
    } on ProviderNotFoundException {
      transport = null;
    }
    try {
      undo = Provider.of<UndoService>(context, listen: false);
    } on ProviderNotFoundException {
      undo = null;
    }
    if (transport == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      // Rebuild on undo too, so the bar's undo/redo enable state is honest.
      animation: undo ?? transport,
      builder: (context, _) => TransportBar(
        transport: transport!,
        // The mixer has no record arm of its own — arming here would imply a
        // capture path this screen does not have.
        showRecord: false,
        onUndo: undo?.undo,
        onRedo: undo?.redo,
        canUndo: undo?.canUndo ?? false,
        canRedo: undo?.canRedo ?? false,
      ),
    );
  }

  Widget _skippedBanner() => _SkippedBanner(
        key: const ValueKey('mixer-skipped'),
        skipped: _skipped,
      );

  /// Float pairs → the interleaved 16-bit frames `wavBytesStereo` wants.
  /// Clamped rather than scaled: a mix the user pushed into clipping should
  /// clip, not be silently turned down (see the no-normalisation rule in
  /// `project_render.dart`).
  static Int16List _interleave(ProjectMixdown mix) {
    final out = Int16List(mix.left.length * 2);
    for (var i = 0; i < mix.left.length; i++) {
      out[i * 2] = (mix.left[i].clamp(-1.0, 1.0) * 32767).round();
      out[i * 2 + 1] = (mix.right[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final projects = context.watch<ProjectService>();
    final tracks = projects.tracks;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mixerConsoleTitle),
        actions: [
          IconButton(
            key: const ValueKey('mixer-play'),
            tooltip: _playing ? l10n.mixerStop : l10n.mixerPlay,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            onPressed:
                tracks.isEmpty ? null : () => _playing ? _stop() : playMix(),
          ),
        ],
      ),
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
          : Column(
              children: [
                // WS-W3's shared bar, finally hosted. The project mixer is a
                // natural home for the shared transport: it is the one screen
                // that is about the project rather than about one editor.
                _transportBar(context),
                if (_skipped.isNotEmpty) _skippedBanner(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: tracks.length,
                    itemBuilder: (context, i) => _Strip(
                      key: ValueKey('mixer-strip-${tracks[i].id}'),
                      track: tracks[i],
                      projects: projects,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({super.key, required this.track, required this.projects});

  final ProjectTrack track;
  final ProjectService projects;

  void _setMix(
    BuildContext context,
    ProjectTrackMix mix,
    String label, {
    Object? coalesceKey,
  }) {
    _pushMixUndo(
      context,
      projects,
      track,
      mix,
      label,
      coalesceKey: coalesceKey,
    );
  }

  /// Ends the coalescing run so the NEXT drag is its own undo entry.
  void _endDrag(BuildContext context) {
    try {
      Provider.of<UndoService>(context, listen: false).breakCoalescing();
    } on ProviderNotFoundException {
      // No undo provided; nothing to end.
    }
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
                  onPressed: () => _setMix(
                    context,
                    mix.copyWith(muted: !mix.muted),
                    l10n.mixerMute,
                  ),
                ),
                IconButton(
                  key: ValueKey('mixer-solo-${track.id}'),
                  tooltip: l10n.mixerSolo,
                  icon: const Icon(Icons.headphones),
                  color: mix.soloed ? scheme.primary : null,
                  onPressed: () => _setMix(
                    context,
                    mix.copyWith(soloed: !mix.soloed),
                    l10n.mixerSolo,
                  ),
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
                    onChanged: (v) => _setMix(
                      context,
                      mix.copyWith(level: v),
                      l10n.mixerLevel,
                      // One undo for the whole drag, not one per frame.
                      coalesceKey: 'level:${track.id}',
                    ),
                    onChangeEnd: (_) => _endDrag(context),
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
                    onChanged: (v) => _setMix(
                      context,
                      mix.copyWith(pan: v),
                      l10n.mixerPan,
                      coalesceKey: 'pan:${track.id}',
                    ),
                    onChangeEnd: (_) => _endDrag(context),
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

/// Names the tracks the mix could not sound. Shown after a play rather than
/// permanently: before you press Play there is nothing to report, and a
/// standing warning about tracks that might not sound would be noise.
class _SkippedBanner extends StatelessWidget {
  const _SkippedBanner({super.key, required this.skipped});

  final List<SkippedTrack> skipped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            skipped.length == 1
                ? l10n.mixerSkippedOne
                : l10n.mixerSkippedMany(skipped.length),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
          ),
          // The REASON, per track — "no sound yet" alone leaves the user with
          // nothing to act on.
          for (final s in skipped)
            Text(
              '${s.trackId}: ${s.reason}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
        ],
      ),
    );
  }
}
