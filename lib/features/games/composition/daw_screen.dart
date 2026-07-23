// lib/features/games/composition/daw_screen.dart
//
// The Multitrack — the DAW Workshop tool (docs/DAW_SCOPING.md). Clips from any
// module sit on tracks in time; Play BAKES the whole arrangement offline
// (renderTimeline, per-source cache) and plays it. A "vector, not bitmap"
// arranger: each clip references its source MODEL and renders on demand.
//
// It seeds demo clips (a beat + a tune) and receives real clips from every
// module's "Send to DAW". A to-scale timeline under a second-by-second ruler:
// clips are drawn at their render duration and dragged along the lane to
// reposition in time (with optional grid-snapping); per-track mute; tap a clip
// for its inspector (volume + fades, freeze, remove), ✕ to remove; Merge-all,
// undo/redo, project save/load, direct audio import, and WAV/MP3 export.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/synth.dart' show Drum, wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart'
    show showMyInstrumentsSheet;
import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music/music_picker.dart' show showMusicPicker;
import 'package:comet_beat/shared/music/score_router.dart'
    show showScoreDestinations;
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show showAudioExportSheet;
import 'package:comet_beat/shared/music_io/audio_import.dart'
    show importAudioMono, kAudioImportExtensions;
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';

/// Test handle onto the running arranger.
@visibleForTesting
abstract interface class DawTester {
  int get trackCount;
  int get clipCount;
  bool get isPlaying;

  /// The playhead position (ms); rests at the seek marker when stopped.
  double get playheadMs;

  /// Move the play-start / resting playhead (as clicking the ruler does).
  void seekTo(double ms);

  /// Whether playback loops back to the start at the end of the arrangement.
  bool get loopOn;
  void toggleLoop();
  bool isTrackMuted(int track);
  void toggleTrackMute(int track);

  /// Per-track volume fader (linear gain).
  void setTrackGain(int track, double gain);
  double trackGain(int track);

  /// Solo a track (while any track is soloed, only soloed tracks are heard).
  void toggleTrackSolo(int track);
  bool isTrackSoloed(int track);

  /// Track management: add an empty lane, remove one (min one kept), rename.
  void addTrack();
  void removeTrack(int track);
  void renameTrack(int track, String name);
  String trackName(int track);
  void addDemoBeat();
  void addDemoTune();
  void addSampleClip(SampleClip clip);
  void clear();
  void play();
  void stop();

  /// Merge/convert: flatten every clip into one baked audio take; freeze a
  /// single live clip to audio; whether a clip is already baked; remove a clip.
  void mergeAll();
  void freezeClip(int track, int index);
  bool isClipFrozen(int track, int index);
  void removeClip(int track, int index);
  void duplicateClip(int track, int index);

  /// Split the clip at [atMs] (timeline ms) into two; [canSplitClip] is true
  /// only when the cut falls strictly inside the clip.
  void splitClip(int track, int index, double atMs);
  bool canSplitClip(int track, int index, double atMs);
  void crossfadeWithNext(int track, int index);
  bool canCrossfadeWithNext(int track, int index);

  /// Reverse the clip's audio (bakes it to a backwards take).
  void reverseClip(int track, int index);

  /// Whether a clip is engraved music that can be voiced with an instrument, and
  /// the per-clip / per-track instrument assignment (null = default synth). The
  /// instrument comes from the assets Instruments/Samples library.
  bool isScoreClip(int track, int index);
  TrackerInstrument? clipInstrument(int track, int index);
  void setClipInstrument(int track, int index, TrackerInstrument? inst);
  void setTrackInstrument(int track, TrackerInstrument? inst);

  /// Resample the clip by [factor] — tape-style speed/pitch (2× faster, 0.5×
  /// slower). Bakes to a fixed take.
  void resampleClip(int track, int index, double factor);

  /// Timeline: move a clip in time, and read a clip's start + to-scale duration.
  void moveClip(int track, int index, double startMs);
  double clipStartMs(int track, int index);
  double clipDurationMs(int track, int index);

  /// Whether the arrangement can be exported (has audible content).
  bool get canExport;

  /// Undo / redo the last edits.
  void undo();
  void redo();
  bool get canUndo;
  bool get canRedo;

  /// Per-clip gain + fade lengths.
  void setClipGain(int track, int index, double gain);
  double clipGain(int track, int index);
  void setClipFades(
    int track,
    int index, {
    double? fadeInMs,
    double? fadeOutMs,
    DawFadeCurve? fadeInCurve,
    DawFadeCurve? fadeOutCurve,
  });
  double clipFadeInMs(int track, int index);
  double clipFadeOutMs(int track, int index);
  DawFadeCurve clipFadeInCurve(int track, int index);
  DawFadeCurve clipFadeOutCurve(int track, int index);

  /// Non-destructive per-clip trim (ms into the source render).
  void setClipTrim(
    int track,
    int index, {
    double? trimStartMs,
    double? trimEndMs,
  });
  double clipTrimStartMs(int track, int index);
  double clipTrimEndMs(int track, int index);
  double clipSourceMs(int track, int index);

  /// Drag-snapping to the beat grid, and the project tempo that defines it.
  void toggleSnap();
  bool get snapOn;
  double get bpm;
  void setBpm(double value);

  /// Test seam: the length (samples) the arrangement bakes to.
  int debugBakeLength();
}

class DawScreen extends StatefulWidget {
  const DawScreen({super.key});

  @override
  State<DawScreen> createState() => _DawScreenState();
}

class _DawScreenState extends State<DawScreen>
    with SingleTickerProviderStateMixin
    implements DawTester {
  bool _playing = false;
  final Set<int> _selectedTracks = <int>{};
  final Set<DawClipTarget> _selectedClips = <DawClipTarget>{};
  final List<DawClipCopy> _clipClipboard = <DawClipCopy>[];
  double? _rangeInMs;
  double? _rangeOutMs;

  // Playhead: driven by the Ticker's own elapsed (NOT wall-clock), so it stays
  // in step with the baked audio AND is deterministic under `tester.pump`.
  late final Ticker _ticker;
  final ValueNotifier<double> _positionMs = ValueNotifier<double>(0);
  double _totalMs = 0;
  bool _loop = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionMs.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final ms = _seekMs + elapsed.inMilliseconds.toDouble();
    if (_totalMs > 0 && ms >= _totalMs) {
      // Reached the end: loop restarts (from the seek point), else stop. The
      // re-bake in play() is cheap (every clip is served from the cache).
      if (_loop) {
        play();
      } else {
        stop();
      }
      return;
    }
    _positionMs.value = ms;
  }

  AudioService get _audio => context.read<AudioService>();
  DawService get _daw => context.read<DawService>();

  // --- DawTester -------------------------------------------------------------

  @override
  int get trackCount => _daw.timeline.tracks.length;

  @override
  int get clipCount => _daw.clipCount;

  @override
  bool get isPlaying => _playing;

  @override
  bool isTrackMuted(int track) => _daw.timeline.tracks[track].muted;

  @override
  void toggleTrackMute(int track) {
    _daw.toggleTrackMute(track);
    if (_playing) play(); // re-bake with the change
  }

  @override
  void setTrackGain(int track, double gain) {
    _daw.setTrackGain(track, gain);
    if (_playing) play(); // re-bake with the level change
  }

  @override
  double trackGain(int track) => _daw.trackGain(track);

  @override
  void toggleTrackSolo(int track) {
    _daw.toggleTrackSolo(track);
    if (_playing) play(); // re-bake — solo changes what's audible
  }

  @override
  bool isTrackSoloed(int track) => _daw.isTrackSoloed(track);

  @override
  void addTrack() => _daw.addTrack();

  @override
  void removeTrack(int track) {
    final shiftedSelection = <int>{
      for (final i in _selectedTracks)
        if (i < track) i else if (i > track) i - 1,
    };
    _daw.removeTrack(track);
    _selectedTracks
      ..clear()
      ..addAll(shiftedSelection)
      ..removeWhere((i) => i >= _daw.timeline.tracks.length);
    if (_playing) play();
  }

  @override
  void renameTrack(int track, String name) => _daw.renameTrack(track, name);

  @override
  String trackName(int track) => _daw.trackName(track);

  /// Track name → a small menu to rename the lane or remove it.
  Future<void> _trackMenu(int i) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _daw.trackName(i));
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawTrackTitle),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(labelText: l10n.dawTrackName),
                    onSubmitted: (_) => Navigator.of(ctx).pop('rename'),
                  ),
                  const SizedBox(height: 16),
                  _trackFxEditor(ctx, i, setDialog),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('instrument'),
            child: Text(l10n.dawTrackInstrument),
          ),
          TextButton(
            onPressed: _daw.timeline.tracks.length <= 1
                ? null
                : () => Navigator.of(ctx).pop('remove'),
            child: Text(l10n.dawRemoveTrack),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('rename'),
            child: Text(l10n.dawRename),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = controller.text.trim();
      if (name.isNotEmpty) renameTrack(i, name);
    } else if (action == 'remove') {
      removeTrack(i);
    } else if (action == 'instrument') {
      await _assignTrackInstrument(i);
    }
  }

  Widget _trackFxEditor(
    BuildContext ctx,
    int track,
    StateSetter setDialog,
  ) {
    final effects = _daw.trackEffects(track);
    final selectedTargets = _selectedTrackTargets(track);
    final hasSelectedTargets = _selectedTracks.any(
      (i) => i >= 0 && i < _daw.timeline.tracks.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Track FX', style: Theme.of(ctx).textTheme.labelLarge),
            const Spacer(),
            Text(
              hasSelectedTargets
                  ? '${selectedTargets.length} selected'
                  : 'This track',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 2,
          children: [
            IconButton(
              tooltip: 'Copy chain to selected tracks',
              icon: const Icon(Icons.checklist),
              onPressed: effects.isEmpty || !hasSelectedTargets
                  ? null
                  : () {
                      _daw.copyTrackEffectsToTracks(track, selectedTargets);
                      setDialog(() {});
                      if (_playing) play();
                    },
            ),
            IconButton(
              tooltip: 'Copy chain to all tracks',
              icon: const Icon(Icons.copy_all),
              onPressed: effects.isEmpty || _daw.timeline.tracks.length < 2
                  ? null
                  : () {
                      _daw.copyTrackEffectsToTracks(
                        track,
                        Iterable<int>.generate(_daw.timeline.tracks.length),
                      );
                      setDialog(() {});
                      if (_playing) play();
                    },
            ),
            PopupMenuButton<DawClipEffectPreset>(
              tooltip: 'Apply preset to selected tracks',
              icon: const Icon(Icons.playlist_add_check),
              enabled: hasSelectedTargets,
              onSelected: (preset) {
                _daw.applyTrackEffectPresetToTracks(selectedTargets, preset);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final preset in DawClipEffectPreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(_clipEffectPresetLabel(preset)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectType>(
              tooltip: 'Add effect to selected tracks',
              icon: const Icon(Icons.add_task),
              enabled: hasSelectedTargets,
              onSelected: (type) {
                _daw.addTrackEffectToTracks(selectedTargets, type);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final type in _clipEffectTypes)
                  PopupMenuItem(
                    value: type,
                    child: Text(_clipEffectLabel(type)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectPreset>(
              tooltip: 'Apply preset',
              icon: const Icon(Icons.auto_fix_high),
              onSelected: (preset) {
                _daw.applyTrackEffectPreset(track, preset);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final preset in DawClipEffectPreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(_clipEffectPresetLabel(preset)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectType>(
              tooltip: 'Add effect',
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (type) {
                _daw.addTrackEffect(track, type);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final type in _clipEffectTypes)
                  PopupMenuItem(
                    value: type,
                    child: Text(_clipEffectLabel(type)),
                  ),
              ],
            ),
          ],
        ),
        if (effects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No track effects',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
        for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
          _fxTile(
            ctx,
            effects: effects,
            fxIndex: fxIndex,
            onToggle: () {
              _daw.toggleTrackEffect(track, fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onMove: (delta) {
              _daw.moveTrackEffect(track, fxIndex, delta);
              setDialog(() {});
              if (_playing) play();
            },
            onRemove: () {
              _daw.removeTrackEffect(track, fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onParam: (key, value) {
              setDialog(() {
                _daw.setTrackEffectParam(track, fxIndex, key, value);
              });
              if (_playing) play();
            },
          ),
      ],
    );
  }

  Future<void> _masterFxMenu() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Master FX'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: _masterFxEditor(ctx, setDialog),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx)!.dawCancel),
          ),
        ],
      ),
    );
  }

  Widget _masterFxEditor(BuildContext ctx, StateSetter setDialog) {
    final effects = _daw.masterEffects();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Output bus', style: Theme.of(ctx).textTheme.labelLarge),
            const Spacer(),
            PopupMenuButton<DawClipEffectPreset>(
              tooltip: 'Apply preset',
              icon: const Icon(Icons.auto_fix_high),
              onSelected: (preset) {
                _daw.applyMasterEffectPreset(preset);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final preset in DawClipEffectPreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(_clipEffectPresetLabel(preset)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectType>(
              tooltip: 'Add effect',
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (type) {
                _daw.addMasterEffect(type);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final type in _clipEffectTypes)
                  PopupMenuItem(
                    value: type,
                    child: Text(_clipEffectLabel(type)),
                  ),
              ],
            ),
          ],
        ),
        if (effects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No master effects',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
        for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
          _fxTile(
            ctx,
            effects: effects,
            fxIndex: fxIndex,
            onToggle: () {
              _daw.toggleMasterEffect(fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onMove: (delta) {
              _daw.moveMasterEffect(fxIndex, delta);
              setDialog(() {});
              if (_playing) play();
            },
            onRemove: () {
              _daw.removeMasterEffect(fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onParam: (key, value) {
              setDialog(() => _daw.setMasterEffectParam(fxIndex, key, value));
              if (_playing) play();
            },
          ),
      ],
    );
  }

  Future<void> _busMenu() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buses'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          _daw.addBus();
                          setDialog(() {});
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add bus'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _explicitSelectedTracks().isEmpty
                            ? null
                            : () {
                                _daw.setTrackBusForTracks(
                                  _explicitSelectedTracks(),
                                  null,
                                );
                                setDialog(() {});
                                setState(() {});
                                if (_playing) play();
                              },
                        icon: const Icon(Icons.output),
                        label: const Text('Route selected to Master'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_daw.buses().isEmpty)
                    Text(
                      'No buses',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  if (_daw.buses().isNotEmpty) ...[
                    _busMixerMatrix(ctx, setDialog),
                    const SizedBox(height: 12),
                  ],
                  for (var bus = 0; bus < _daw.buses().length; bus++)
                    _busEditor(ctx, bus, setDialog),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx)!.dawCancel),
          ),
        ],
      ),
    );
  }

  Widget _busMixerMatrix(BuildContext ctx, StateSetter setDialog) {
    final buses = _daw.buses();
    final tracks = _daw.timeline.tracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mixer', style: Theme.of(ctx).textTheme.labelLarge),
        const SizedBox(height: 6),
        for (var track = 0; track < tracks.length; track++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tracks[track].name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.labelMedium,
                          ),
                        ),
                        DropdownButton<int?>(
                          key: ValueKey('bus-route-$track'),
                          value: _validRouteValue(tracks[track].busIndex),
                          onChanged: (route) {
                            _daw.setTrackBus(track, route);
                            setDialog(() {});
                            setState(() {});
                            if (_playing) play();
                          },
                          items: [
                            const DropdownMenuItem<int?>(
                              child: Text('Master'),
                            ),
                            for (var bus = 0; bus < buses.length; bus++)
                              DropdownMenuItem<int?>(
                                value: bus,
                                child: Text(_busDisplayName(bus)),
                              ),
                          ],
                        ),
                      ],
                    ),
                    for (var bus = 0; bus < buses.length; bus++)
                      Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              _busDisplayName(bus),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              key: ValueKey('bus-send-$track-$bus'),
                              value: _daw.trackSend(track, bus),
                              max: 1.5,
                              divisions: 30,
                              label:
                                  _daw.trackSend(track, bus).toStringAsFixed(2),
                              onChanged: (value) {
                                setDialog(() {
                                  _daw.setTrackSend(track, bus, value);
                                });
                                setState(() {});
                                if (_playing) play();
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  int? _validRouteValue(int? route) =>
      route != null && route >= 0 && route < _daw.buses().length ? route : null;

  String _busDisplayName(int bus) {
    final buses = _daw.buses();
    if (bus < 0 || bus >= buses.length) return 'Bus ${bus + 1}';
    return buses[bus].name.isEmpty ? 'Bus ${bus + 1}' : buses[bus].name;
  }

  Future<void> _renameBusDialog(
    BuildContext ctx,
    int bus,
    StateSetter setDialog,
  ) async {
    if (bus < 0 || bus >= _daw.buses().length) return;
    var draft = _busDisplayName(bus);
    final name = await showDialog<String>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename bus'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Bus name'),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) => Navigator.of(dialogCtx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(AppLocalizations.of(dialogCtx)!.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(draft),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    _daw.renameBus(bus, trimmed);
    setDialog(() {});
    setState(() {});
  }

  Widget _busEditor(BuildContext ctx, int bus, StateSetter setDialog) {
    final buses = _daw.buses();
    final routeTargets = _explicitSelectedTracks();
    if (bus < 0 || bus >= buses.length) return const SizedBox.shrink();
    final routeCount =
        _daw.timeline.tracks.where((track) => track.busIndex == bus).length;
    final name = _busDisplayName(bus);
    final effects = _daw.busEffects(bus);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    '$routeCount tracks',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  IconButton(
                    tooltip: 'Rename bus',
                    icon: const Icon(Icons.drive_file_rename_outline),
                    onPressed: () => _renameBusDialog(ctx, bus, setDialog),
                  ),
                  IconButton(
                    tooltip: 'Route selected tracks to this bus',
                    icon: const Icon(Icons.call_merge),
                    onPressed: routeTargets.isEmpty
                        ? null
                        : () {
                            _daw.setTrackBusForTracks(routeTargets, bus);
                            setDialog(() {});
                            setState(() {});
                            if (_playing) play();
                          },
                  ),
                  PopupMenuButton<DawClipEffectPreset>(
                    tooltip: 'Apply preset',
                    icon: const Icon(Icons.auto_fix_high),
                    onSelected: (preset) {
                      _daw.applyBusEffectPreset(bus, preset);
                      setDialog(() {});
                      if (_playing) play();
                    },
                    itemBuilder: (_) => [
                      for (final preset in DawClipEffectPreset.values)
                        PopupMenuItem(
                          value: preset,
                          child: Text(_clipEffectPresetLabel(preset)),
                        ),
                    ],
                  ),
                  PopupMenuButton<DawClipEffectType>(
                    tooltip: 'Add effect',
                    icon: const Icon(Icons.add_circle_outline),
                    onSelected: (type) {
                      _daw.addBusEffect(bus, type);
                      setDialog(() {});
                      if (_playing) play();
                    },
                    itemBuilder: (_) => [
                      for (final type in _clipEffectTypes)
                        PopupMenuItem(
                          value: type,
                          child: Text(_clipEffectLabel(type)),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Remove bus',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      _daw.removeBus(bus);
                      setDialog(() {});
                      setState(() {});
                      if (_playing) play();
                    },
                  ),
                ],
              ),
              if (effects.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'No bus effects',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              if (routeTargets.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${routeTargets.length} selected send',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    Expanded(
                      child: Slider(
                        value: _averageTrackSend(routeTargets, bus),
                        max: 1.5,
                        divisions: 30,
                        label: _averageTrackSend(
                          routeTargets,
                          bus,
                        ).toStringAsFixed(2),
                        onChanged: (value) {
                          setDialog(() {
                            _daw.setTrackSendForTracks(
                              routeTargets,
                              bus,
                              value,
                            );
                          });
                          setState(() {});
                          if (_playing) play();
                        },
                      ),
                    ),
                  ],
                ),
              ],
              for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
                _fxTile(
                  ctx,
                  effects: effects,
                  fxIndex: fxIndex,
                  onToggle: () {
                    _daw.toggleBusEffect(bus, fxIndex);
                    setDialog(() {});
                    if (_playing) play();
                  },
                  onMove: (delta) {
                    _daw.moveBusEffect(bus, fxIndex, delta);
                    setDialog(() {});
                    if (_playing) play();
                  },
                  onRemove: () {
                    _daw.removeBusEffect(bus, fxIndex);
                    setDialog(() {});
                    if (_playing) play();
                  },
                  onParam: (key, value) {
                    setDialog(
                      () => _daw.setBusEffectParam(bus, fxIndex, key, value),
                    );
                    if (_playing) play();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _averageTrackSend(List<int> tracks, int bus) {
    if (tracks.isEmpty) return 0;
    var sum = 0.0;
    for (final track in tracks) {
      sum += _daw.trackSend(track, bus);
    }
    return sum / tracks.length;
  }

  List<int> _explicitSelectedTracks() {
    final targets = [
      for (final i in _selectedTracks)
        if (i >= 0 && i < _daw.timeline.tracks.length) i,
    ]..sort();
    return targets;
  }

  List<int> _selectedTrackTargets(int fallbackTrack) {
    final targets = _explicitSelectedTracks();
    return targets.isEmpty ? [fallbackTrack] : targets;
  }

  bool _validClipSelection(DawClipTarget target) =>
      target.track >= 0 &&
      target.track < _daw.timeline.tracks.length &&
      target.index >= 0 &&
      target.index < _daw.timeline.tracks[target.track].clips.length;

  List<DawClipTarget> _selectedClipTargets(
    int fallbackTrack,
    int fallbackIndex,
  ) {
    final targets = [
      for (final target in _selectedClips)
        if (_validClipSelection(target)) target,
    ]..sort((a, b) {
        final byTrack = a.track.compareTo(b.track);
        return byTrack != 0 ? byTrack : a.index.compareTo(b.index);
      });
    return targets.isEmpty
        ? [(track: fallbackTrack, index: fallbackIndex)]
        : targets;
  }

  bool get _hasSelectedClips => _selectedClips.any(_validClipSelection);

  void _copySelectedClips() {
    final copies = [
      for (final target in _selectedClips)
        if (_validClipSelection(target))
          (
            track: target.track,
            clip: _daw.timeline.tracks[target.track].clips[target.index],
          ),
    ];
    if (copies.isEmpty) return;
    setState(() {
      _clipClipboard
        ..clear()
        ..addAll(copies);
    });
  }

  void _deleteSelectedClips({bool copyFirst = false}) {
    final targets = [
      for (final target in _selectedClips)
        if (_validClipSelection(target)) target,
    ];
    if (targets.isEmpty) return;
    if (copyFirst) _copySelectedClips();
    final removed = _daw.removeClipTargets(targets);
    if (removed == 0) return;
    setState(() {
      _selectedClips
        ..clear()
        ..removeWhere((target) => !_validClipSelection(target));
    });
    if (_playing) play();
  }

  void _pasteClipClipboard() {
    if (_clipClipboard.isEmpty) return;
    final pasted = _daw.pasteClipCopies(_clipClipboard, playheadMs);
    if (pasted.isEmpty) return;
    setState(() {
      _selectedClips
        ..clear()
        ..addAll(pasted);
    });
    if (_playing) play();
  }

  bool get _hasFxRange =>
      _rangeInMs != null &&
      _rangeOutMs != null &&
      (_rangeInMs! - _rangeOutMs!).abs() > 5;

  double get _rangeStartMs => math.min(_rangeInMs ?? 0, _rangeOutMs ?? 0);
  double get _rangeEndMs => math.max(_rangeInMs ?? 0, _rangeOutMs ?? 0);

  String _rangeLabel() {
    String seconds(double ms) => (ms / 1000).toStringAsFixed(2);
    if (!_hasFxRange) {
      final inText = _rangeInMs == null ? '--' : seconds(_rangeInMs!);
      final outText = _rangeOutMs == null ? '--' : seconds(_rangeOutMs!);
      return 'Range $inText-$outText s';
    }
    return 'Range ${seconds(_rangeStartMs)}-${seconds(_rangeEndMs)} s';
  }

  List<int> _rangeTargetTracks() {
    final selected = [
      for (final i in _selectedTracks)
        if (i >= 0 && i < _daw.timeline.tracks.length) i,
    ]..sort();
    return selected.isNotEmpty
        ? selected
        : Iterable<int>.generate(_daw.timeline.tracks.length).toList();
  }

  void _markRangeIn() => setState(() => _rangeInMs = playheadMs);

  void _markRangeOut() => setState(() => _rangeOutMs = playheadMs);

  void _addRangeEffect(DawClipEffectType type) {
    if (!_hasFxRange) return;
    _daw.addClipEffectToRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      type,
    );
    if (_playing) play();
  }

  void _applyRangePreset(DawClipEffectPreset preset) {
    if (!_hasFxRange) return;
    _daw.applyClipEffectPresetToRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      preset,
    );
    if (_playing) play();
  }

  Future<void> _rangeGainDialog() async {
    if (!_hasFxRange) return;
    var multiplier = 0.5;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Range Gain'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel()),
                const SizedBox(height: 8),
                Slider(
                  value: multiplier,
                  max: 2,
                  divisions: 40,
                  label: '${(multiplier * 100).round()}%',
                  onChanged: (value) => setDialog(() => multiplier = value),
                ),
                Text('${(multiplier * 100).round()}%'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    _daw.multiplyClipGainInRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      multiplier,
    );
    if (_playing) play();
  }

  Future<void> _trackAutomationDialog() async {
    if (!_hasFxRange) return;
    var startGain = 1.0;
    var endGain = 0.5;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Track Automation'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel()),
                const SizedBox(height: 8),
                Text('Start ${(startGain * 100).round()}%'),
                Slider(
                  value: startGain,
                  max: 2,
                  divisions: 40,
                  label: '${(startGain * 100).round()}%',
                  onChanged: (value) => setDialog(() => startGain = value),
                ),
                Text('End ${(endGain * 100).round()}%'),
                Slider(
                  value: endGain,
                  max: 2,
                  divisions: 40,
                  label: '${(endGain * 100).round()}%',
                  onChanged: (value) => setDialog(() => endGain = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    _daw.setTrackGainAutomationInRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      startGain,
      endGain,
    );
    if (_playing) play();
  }

  String _fadeCurveLabel(DawFadeCurve curve) => switch (curve) {
        DawFadeCurve.linear => 'Linear',
        DawFadeCurve.exponential => 'Exponential',
        DawFadeCurve.sCurve => 'S-Curve',
      };

  void _applyRangeFade({
    required bool fadeIn,
    DawFadeCurve curve = DawFadeCurve.linear,
  }) {
    if (!_hasFxRange) return;
    if (fadeIn) {
      _daw.applyFadeInToRange(
        _rangeTargetTracks(),
        _rangeStartMs,
        _rangeEndMs,
        curve,
      );
    } else {
      _daw.applyFadeOutToRange(
        _rangeTargetTracks(),
        _rangeStartMs,
        _rangeEndMs,
        curve,
      );
    }
    if (_playing) play();
  }

  void _setRangeMuted(bool muted) {
    if (!_hasFxRange) return;
    _daw.setClipMutedInRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      muted,
    );
    if (_playing) play();
  }

  Widget _fxTile(
    BuildContext ctx, {
    required List<DawClipEffect> effects,
    required int fxIndex,
    required VoidCallback onToggle,
    required void Function(int delta) onMove,
    required VoidCallback onRemove,
    required void Function(String key, double value) onParam,
  }) {
    final fx = effects[fxIndex];
    final specs = _clipEffectParams(fx.type);
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      leading: IconButton(
        icon: Icon(fx.enabled ? Icons.power_settings_new : Icons.power_off),
        tooltip: fx.enabled ? 'Bypass' : 'Enable',
        onPressed: onToggle,
      ),
      title: Text(_clipEffectLabel(fx.type)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Move up',
            onPressed: fxIndex == 0 ? null : () => onMove(-1),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward),
            tooltip: 'Move down',
            onPressed: fxIndex == effects.length - 1 ? null : () => onMove(1),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove effect',
            onPressed: onRemove,
          ),
        ],
      ),
      children: [
        for (final spec in specs)
          _effectParamSlider(
            spec.label,
            fx.params[spec.key] ??
                defaultDawClipEffect(fx.type).params[spec.key] ??
                spec.min,
            spec.min,
            spec.max,
            spec.step,
            (v) => onParam(spec.key, v),
          ),
      ],
    );
  }

  Widget _effectParamSlider(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged,
  ) {
    String fmt(double v) =>
        step >= 1 ? v.round().toString() : v.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — ${fmt(value)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions:
              step > 0 ? ((max - min) / step).round().clamp(1, 1000) : null,
          label: fmt(value),
          onChanged: onChanged,
        ),
      ],
    );
  }

  DrumRowsPattern _demoBeat() {
    final rows = {
      for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
    };
    for (var s = 0; s < kPatternSteps; s += 4) {
      rows[Drum.kick]![s] = true;
    }
    for (var s = 2; s < kPatternSteps; s += 4) {
      rows[Drum.snare]![s] = true;
    }
    for (var s = 0; s < kPatternSteps; s += 2) {
      rows[Drum.hat]![s] = true;
    }
    return DrumRowsPattern(rows);
  }

  Score _demoTune() {
    const q = NoteDuration(DurationBase.quarter);
    return Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c), q),
          NoteElement.note(const Pitch(Step.e), q),
          NoteElement.note(const Pitch(Step.g), q),
          NoteElement.note(const Pitch(Step.c, octave: 5), q),
        ]),
      ],
    );
  }

  @override
  void addDemoBeat() => _daw.addClip(
        DrumSource(_demoBeat(), const LoopTiming(tempoBpm: 100)),
      );

  @override
  void addDemoTune() => _daw.addClip(ScoreSource.single(_demoTune()), track: 1);

  @override
  void addSampleClip(SampleClip clip) {
    // Clips carry their own rate; the timeline renders at kDawSampleRate, so
    // resample first (SampleSource assumes it's already at the timeline rate).
    final pcm = clip.sampleRate == kDawSampleRate
        ? clip.pcm
        : resampleCubic(clip.pcm, clip.sampleRate / kDawSampleRate);
    // A fresh lane so a dropped-in sample never lands on top of another clip.
    _daw.addClip(
      SampleSource(pcm, key: 'sample:${clip.name}'),
      track: _daw.timeline.tracks.length,
    );
  }

  /// Picks a sample from the shared "My Samples" library and arranges it.
  Future<void> addSample() async {
    final clip = await showMySamplesSheet(
      context,
      onCatalogSampleInsert: (clip) async => addSampleClip(clip),
      preferCatalogSampleInsert: true,
    );
    if (clip == null || clip.pcm.isEmpty || !mounted) return;
    addSampleClip(clip);
  }

  Future<void> _importAudioFile() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: l10n.dawImportAudioFile,
            extensions: kAudioImportExtensions,
          ),
        ],
      );
      if (file == null || !mounted) return;
      final imported = importAudioMono(await file.readAsBytes());
      if (imported == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.mySamplesImportFailed)),
        );
        return;
      }
      addSampleClip(
        SampleClip(
          name: _clipNameFromFile(file),
          sampleRate: imported.sampleRate,
          pcm: imported.pcm,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mySamplesImportFailed)),
      );
    }
  }

  String _clipNameFromFile(XFile file) {
    final raw = file.name.isNotEmpty
        ? file.name
        : file.path.split(RegExp(r'[/\\]')).last;
    final dot = raw.lastIndexOf('.');
    return dot > 0 ? raw.substring(0, dot) : raw;
  }

  /// The Sample Extractor lifts many samples into the shared library at once, so
  /// it stays a library flow: extract, then pick which one to arrange.
  Future<void> _addFromExtractor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SampleExtractorScreen()),
    );
    if (!mounted) return;
    await addSample();
  }

  /// Pick actual MUSIC from the library (Song Book or a file import) and drop it
  /// onto a fresh lane as a re-voiceable ScoreSource clip.
  Future<void> _addMusic() async {
    final score = await showMusicPicker(context);
    if (score == null || !mounted) return;
    _daw.addClip(ScoreSource(score), track: _daw.timeline.tracks.length);
  }

  @override
  void clear() {
    _selectedTracks.clear();
    _selectedClips.clear();
    _clipClipboard.clear();
    _daw.clear();
  }

  @override
  void mergeAll() {
    _daw.mergeAll();
    if (_playing) play(); // the merged take is bit-identical, but re-sync state
  }

  @override
  void freezeClip(int track, int index) => _daw.freezeClip(track, index);

  @override
  bool isClipFrozen(int track, int index) => _daw.isClipFrozen(track, index);

  @override
  void removeClip(int track, int index) {
    final shiftedSelection = <DawClipTarget>{
      for (final target in _selectedClips)
        if (target.track != track)
          target
        else if (target.index < index)
          target
        else if (target.index > index)
          (track: target.track, index: target.index - 1),
    };
    _daw.removeClip(track, index);
    _selectedClips
      ..clear()
      ..addAll(shiftedSelection)
      ..removeWhere((target) => !_validClipSelection(target));
  }

  @override
  void duplicateClip(int track, int index) => _daw.duplicateClip(track, index);

  @override
  void splitClip(int track, int index, double atMs) =>
      _daw.splitClip(track, index, atMs);

  @override
  bool canSplitClip(int track, int index, double atMs) =>
      _daw.canSplitClip(track, index, atMs);

  @override
  void crossfadeWithNext(int track, int index) =>
      _daw.crossfadeWithNext(track, index);

  @override
  bool canCrossfadeWithNext(int track, int index) =>
      _daw.canCrossfadeWithNext(track, index);

  @override
  void reverseClip(int track, int index) => _daw.reverseClip(track, index);

  @override
  bool isScoreClip(int track, int index) => _daw.isScoreClip(track, index);

  @override
  TrackerInstrument? clipInstrument(int track, int index) =>
      _daw.clipInstrument(track, index);

  @override
  void setClipInstrument(int track, int index, TrackerInstrument? inst) {
    _daw.setClipInstrument(track, index, inst);
    if (_playing) play(); // re-bake — the voice changed
  }

  @override
  void setTrackInstrument(int track, TrackerInstrument? inst) {
    _daw.setTrackInstrument(track, inst);
    if (_playing) play();
  }

  static const _clipEffectTypes = [
    DawClipEffectType.reverb,
    DawClipEffectType.delay,
    DawClipEffectType.chorus,
    DawClipEffectType.flanger,
    DawClipEffectType.ringMod,
    DawClipEffectType.distortion,
    DawClipEffectType.bitCrush,
    DawClipEffectType.lowpass,
    DawClipEffectType.highpass,
    DawClipEffectType.compressor,
    DawClipEffectType.gate,
    DawClipEffectType.pitchShift,
    DawClipEffectType.timeStretch,
    DawClipEffectType.voiceShape,
    DawClipEffectType.voiceChipmunk,
    DawClipEffectType.voiceDeep,
    DawClipEffectType.voiceRobot,
    DawClipEffectType.voiceRadio,
  ];

  String _clipEffectLabel(DawClipEffectType type) => switch (type) {
        DawClipEffectType.reverb => 'Reverb',
        DawClipEffectType.delay => 'Delay',
        DawClipEffectType.chorus => 'Chorus',
        DawClipEffectType.flanger => 'Flanger',
        DawClipEffectType.ringMod => 'Ring Mod',
        DawClipEffectType.distortion => 'Distortion',
        DawClipEffectType.bitCrush => 'Bit Crush',
        DawClipEffectType.lowpass => 'Low Pass',
        DawClipEffectType.highpass => 'High Pass',
        DawClipEffectType.compressor => 'Compressor',
        DawClipEffectType.gate => 'Noise Gate',
        DawClipEffectType.pitchShift => 'Pitch Shift',
        DawClipEffectType.timeStretch => 'Time Stretch',
        DawClipEffectType.voiceShape => 'Voice Shape',
        DawClipEffectType.voiceChipmunk => 'Voice: Chipmunk',
        DawClipEffectType.voiceDeep => 'Voice: Deep',
        DawClipEffectType.voiceRobot => 'Voice: Robot',
        DawClipEffectType.voiceRadio => 'Voice: Radio',
      };

  String _clipEffectPresetLabel(DawClipEffectPreset preset) => switch (preset) {
        DawClipEffectPreset.vocalPolish => 'Vocal Polish',
        DawClipEffectPreset.lofiCrunch => 'Lo-fi Crunch',
        DawClipEffectPreset.wideSpace => 'Wide Space',
        DawClipEffectPreset.robotVoice => 'Robot Voice',
      };

  List<({String key, String label, double min, double max, double step})>
      _clipEffectParams(DawClipEffectType type) => switch (type) {
            DawClipEffectType.reverb => const [
                (key: 'roomSize', label: 'Size', min: 0, max: 1, step: 0.01),
                (key: 'damping', label: 'Damping', min: 0, max: 1, step: 0.01),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.delay => const [
                (key: 'delayMs', label: 'Time ms', min: 0, max: 2000, step: 10),
                (
                  key: 'feedback',
                  label: 'Feedback',
                  min: 0,
                  max: 0.95,
                  step: 0.01
                ),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.chorus => const [
                (key: 'rateHz', label: 'Rate Hz', min: 0.1, max: 8, step: 0.1),
                (key: 'depthMs', label: 'Depth ms', min: 0, max: 20, step: 0.5),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.flanger => const [
                (
                  key: 'rateHz',
                  label: 'Rate Hz',
                  min: 0.05,
                  max: 5,
                  step: 0.05
                ),
                (
                  key: 'depthMs',
                  label: 'Depth ms',
                  min: 0,
                  max: 10,
                  step: 0.25
                ),
                (
                  key: 'feedback',
                  label: 'Feedback',
                  min: 0,
                  max: 0.95,
                  step: 0.01
                ),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.ringMod => const [
                (
                  key: 'carrierHz',
                  label: 'Freq Hz',
                  min: 1,
                  max: 2000,
                  step: 1
                ),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.distortion => const [
                (key: 'drive', label: 'Drive', min: 0, max: 12, step: 0.1),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.bitCrush => const [
                (key: 'bits', label: 'Bits', min: 1, max: 16, step: 1),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.lowpass || DawClipEffectType.highpass => const [
                (
                  key: 'freq',
                  label: 'Cutoff Hz',
                  min: 20,
                  max: 20000,
                  step: 10
                ),
                (key: 'q', label: 'Q', min: 0.1, max: 20, step: 0.1),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.compressor => const [
                (
                  key: 'thresholdDb',
                  label: 'Threshold dB',
                  min: -60,
                  max: 0,
                  step: 1
                ),
                (key: 'ratio', label: 'Ratio', min: 1, max: 20, step: 0.5),
                (
                  key: 'attackMs',
                  label: 'Attack ms',
                  min: 0,
                  max: 200,
                  step: 1
                ),
                (
                  key: 'releaseMs',
                  label: 'Release ms',
                  min: 10,
                  max: 1000,
                  step: 10
                ),
                (key: 'makeupDb', label: 'Makeup dB', min: 0, max: 24, step: 1),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.gate => const [
                (
                  key: 'thresholdDb',
                  label: 'Threshold dB',
                  min: -80,
                  max: 0,
                  step: 1
                ),
                (key: 'ratio', label: 'Ratio', min: 1, max: 20, step: 0.5),
                (key: 'rangeDb', label: 'Range dB', min: -80, max: 0, step: 1),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.pitchShift => const [
                (
                  key: 'semitones',
                  label: 'Semitones',
                  min: -24,
                  max: 24,
                  step: 1
                ),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.timeStretch => const [
                (key: 'speed', label: 'Speed', min: 0.5, max: 2, step: 0.05),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.voiceShape => const [
                (
                  key: 'formant',
                  label: 'Formant',
                  min: -0.8,
                  max: 0.8,
                  step: 0.01
                ),
                (
                  key: 'carrierHz',
                  label: 'Robot Hz',
                  min: 1,
                  max: 600,
                  step: 1
                ),
                (
                  key: 'carrierMix',
                  label: 'Robot Mix',
                  min: 0,
                  max: 1,
                  step: 0.01
                ),
                (key: 'grit', label: 'Grit', min: 0, max: 1, step: 0.01),
                (
                  key: 'radioLowHz',
                  label: 'Low Hz',
                  min: 20,
                  max: 3000,
                  step: 10
                ),
                (
                  key: 'radioHighHz',
                  label: 'High Hz',
                  min: 1000,
                  max: 12000,
                  step: 10
                ),
                (
                  key: 'radioMix',
                  label: 'Radio Mix',
                  min: 0,
                  max: 1,
                  step: 0.01
                ),
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
            DawClipEffectType.voiceChipmunk ||
            DawClipEffectType.voiceDeep ||
            DawClipEffectType.voiceRobot ||
            DawClipEffectType.voiceRadio =>
              const [
                (key: 'mix', label: 'Mix', min: 0, max: 1, step: 0.01),
              ],
          };

  /// Opens the assets Instruments/Samples library and returns the picked
  /// instrument SOUND (a `TrackerInstrument`), or null if cancelled / the pick
  /// still needs its SoundFont resolved (a bare reference has no playable voice).
  Future<TrackerInstrument?> _pickInstrument() async {
    final picked = await showMyInstrumentsSheet(context, includeBuiltIns: true);
    if (picked == null || !mounted) return null;
    final inst = picked.instrument;
    if (inst == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.drumkitSoundUnavailable),
        ),
      );
    }
    return inst;
  }

  Future<void> _assignClipInstrument(int track, int index) async {
    final inst = await _pickInstrument();
    if (inst == null || !mounted) return;
    setClipInstrument(track, index, inst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.dawInstrumentSet(inst.id)),
      ),
    );
  }

  Future<void> _assignTrackInstrument(int track) async {
    final inst = await _pickInstrument();
    if (inst == null || !mounted) return;
    setTrackInstrument(track, inst);
  }

  @override
  void resampleClip(int track, int index, double factor) =>
      _daw.resampleClip(track, index, factor);

  @override
  void moveClip(int track, int index, double startMs) =>
      _daw.moveClip(track, index, startMs);

  @override
  double clipStartMs(int track, int index) => _daw.clipStartMs(track, index);

  @override
  double clipDurationMs(int track, int index) =>
      _daw.clipDurationMs(track, index);

  @override
  bool get canExport => _daw.clipCount > 0;

  @override
  void undo() => _daw.undo();

  @override
  void redo() => _daw.redo();

  @override
  bool get canUndo => _daw.canUndo;

  @override
  bool get canRedo => _daw.canRedo;

  @override
  void setClipGain(int track, int index, double gain) =>
      _daw.setClipGain(track, index, gain);

  @override
  double clipGain(int track, int index) => _daw.clipGain(track, index);

  @override
  void setClipFades(
    int track,
    int index, {
    double? fadeInMs,
    double? fadeOutMs,
    DawFadeCurve? fadeInCurve,
    DawFadeCurve? fadeOutCurve,
  }) =>
      _daw.setClipFades(
        track,
        index,
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
        fadeInCurve: fadeInCurve,
        fadeOutCurve: fadeOutCurve,
      );

  @override
  double clipFadeInMs(int track, int index) => _daw.clipFadeInMs(track, index);

  @override
  double clipFadeOutMs(int track, int index) =>
      _daw.clipFadeOutMs(track, index);

  @override
  DawFadeCurve clipFadeInCurve(int track, int index) =>
      _daw.clipFadeInCurve(track, index);

  @override
  DawFadeCurve clipFadeOutCurve(int track, int index) =>
      _daw.clipFadeOutCurve(track, index);

  @override
  void setClipTrim(
    int track,
    int index, {
    double? trimStartMs,
    double? trimEndMs,
  }) =>
      _daw.setClipTrim(
        track,
        index,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
      );

  @override
  double clipTrimStartMs(int track, int index) =>
      _daw.clipTrimStartMs(track, index);

  @override
  double clipTrimEndMs(int track, int index) =>
      _daw.clipTrimEndMs(track, index);

  @override
  double clipSourceMs(int track, int index) => _daw.clipSourceMs(track, index);

  @override
  void toggleSnap() => _daw.toggleSnap();

  @override
  bool get snapOn => _daw.snapOn;

  @override
  double get bpm => _daw.bpm;

  @override
  void setBpm(double value) => _daw.setBpm(value);

  Float64List _bake() => _daw.bake();

  Int16List _toPcm16(Float64List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  @override
  int debugBakeLength() => _bake().length;

  // Where playback starts (set by clicking the ruler); the playhead rests here
  // when stopped and playback resumes from it.
  double _seekMs = 0;

  @override
  void play() {
    final pcm = _bake();
    if (pcm.isEmpty) return;
    _totalMs = pcm.length / kDawSampleRate * 1000;
    final from = (_seekMs.clamp(0, _totalMs) * kDawSampleRate / 1000).round();
    // Play from the seek point onward. The transport (playhead) runs whenever
    // Play is engaged; only the audible output is gated on the sound toggle.
    if (_audio.soundOn && from < pcm.length) {
      _audio
          .playWavBytes(wavBytes(_toPcm16(Float64List.sublistView(pcm, from))));
    }
    _positionMs.value = _seekMs;
    _ticker
      ..stop()
      ..start(); // elapsed restarts at 0; _onTick adds _seekMs
    setState(() => _playing = true);
  }

  @override
  void stop() {
    _ticker.stop();
    _positionMs.value = _seekMs; // rest at the seek marker
    _audio.stop();
    setState(() => _playing = false);
  }

  /// Move the play start (and the resting playhead) to [ms] on the timeline.
  @override
  void seekTo(double ms) {
    _seekMs = ms < 0 ? 0 : ms;
    _positionMs.value = _seekMs;
    if (_playing) play(); // restart from the new point
  }

  @override
  double get playheadMs => _positionMs.value;

  @override
  bool get loopOn => _loop;

  @override
  void toggleLoop() => setState(() => _loop = !_loop);

  // --- UI --------------------------------------------------------------------

  // Bake the arrangement, choose the export window, then hand off to the shared
  // WAV/MP3 sheet.
  Future<void> _export() async {
    final pcm = _bake();
    if (pcm.isEmpty) {
      await showAudioExportSheet(
        context,
        pcm: pcm,
        baseName: _exportBaseName(),
      );
      return;
    }
    var useRange = false;
    var normalize = false;
    final rangeAvailable = _hasFxRange;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final selected = useRange ? _exportRangePcm(pcm) : pcm;
          final exportPcm =
              normalize ? _normalizeExportPcm(selected) : selected;
          return AlertDialog(
            title: const Text('Export mix'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment(
                        value: false,
                        label: Text('Full mix'),
                        icon: Icon(Icons.multitrack_audio),
                      ),
                      ButtonSegment(
                        value: true,
                        enabled: rangeAvailable,
                        label: const Text('Marked range'),
                        icon: const Icon(Icons.segment),
                      ),
                    ],
                    selected: {useRange},
                    onSelectionChanged: (values) =>
                        setDialog(() => useRange = values.single),
                  ),
                  const SizedBox(height: 12),
                  Text('Full mix: ${_exportSummary(pcm)}'),
                  Text(
                    rangeAvailable
                        ? 'Marked range: ${_exportSummary(_exportRangePcm(pcm))}'
                        : 'Marked range: Set Mark In and Mark Out first',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Duration ${_secondsLabel(selected.length / kDawSampleRate)}',
                  ),
                  Text('Peak ${_peakLabel(selected)}'),
                  CheckboxListTile(
                    value: normalize,
                    onChanged: (value) =>
                        setDialog(() => normalize = value ?? false),
                    title: const Text('Normalize peak'),
                    subtitle: Text(
                      'Export peak ${_peakLabel(exportPcm)}',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(ctx)!.dawCancel),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop('export'),
                child: const Text('Choose format'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || action != 'export') return;
    final selected = useRange ? _exportRangePcm(pcm) : pcm;
    final exportPcm = normalize ? _normalizeExportPcm(selected) : selected;
    await showAudioExportSheet(
      context,
      pcm: exportPcm,
      baseName: _exportBaseName(range: useRange),
    );
  }

  Float64List _exportRangePcm(Float64List pcm) {
    if (!_hasFxRange) return pcm;
    final start =
        (_rangeStartMs * kDawSampleRate / 1000).round().clamp(0, pcm.length);
    final end =
        (_rangeEndMs * kDawSampleRate / 1000).round().clamp(start, pcm.length);
    return Float64List.sublistView(pcm, start, end);
  }

  String _exportSummary(Float64List pcm) =>
      '${_secondsLabel(pcm.length / kDawSampleRate)} · peak ${_peakLabel(pcm)}';

  String _secondsLabel(double seconds) => '${seconds.toStringAsFixed(2)} s';

  Float64List _normalizeExportPcm(Float64List pcm, {double target = 0.98}) {
    final peak = _peak(pcm);
    if (peak <= 0 || peak >= target) return pcm;
    final out = Float64List(pcm.length);
    final gain = target / peak;
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i] * gain).clamp(-1.0, 1.0);
    }
    return out;
  }

  double _peak(Float64List pcm) {
    var peak = 0.0;
    for (final sample in pcm) {
      final abs = sample.abs();
      if (abs > peak) peak = abs;
    }
    return peak;
  }

  String _peakLabel(Float64List pcm) {
    return _peak(pcm).toStringAsFixed(2);
  }

  String _exportBaseName({bool range = false}) {
    final active = [
      for (final track in _daw.timeline.tracks)
        if (track.clips.isNotEmpty) track.name,
    ];
    final title = active.isEmpty ? 'audio-editor' : active.take(3).join('-');
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return [
      if (slug.isEmpty) 'audio-editor' else slug,
      if (range) 'range',
    ].join('-');
  }

  static const _kProjectGroup = XTypeGroup(
    label: 'Multitrack project',
    extensions: ['cbdaw', 'json'],
  );

  Future<void> _saveProject() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = _daw.saveProject();
      final loc = await getSaveLocation(
        suggestedName: 'project.cbdaw',
        acceptedTypeGroups: const [_kProjectGroup],
      );
      if (loc == null) return;
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(json)),
        name: 'project.cbdaw',
      ).saveTo(loc.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dawProjectSaved)),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dawProjectSaveFailed)),
      );
    }
  }

  Future<void> _openProject() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(acceptedTypeGroups: const [_kProjectGroup]);
      if (file == null) return;
      _daw.loadProject(utf8.decode(await file.readAsBytes()));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dawProjectOpenFailed)),
      );
    }
  }

  void _mergeAllWithToast() {
    final l10n = AppLocalizations.of(context)!;
    mergeAll();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dawMerged)),
    );
  }

  void _freezeWithToast(int track, int index) {
    if (isClipFrozen(track, index)) return;
    final l10n = AppLocalizations.of(context)!;
    freezeClip(track, index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dawFrozen)),
    );
  }

  // Tap a clip → gain + fade sliders, freeze, remove.
  void _openClipInspector(int track, int index) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          // The clip may have been removed while the sheet is open.
          if (index >= _daw.timeline.tracks[track].clips.length) {
            return const SizedBox.shrink();
          }
          final frozen = _daw.isClipFrozen(track, index);
          final selectedTargets = _selectedClipTargets(track, index);
          final hasSelectedTargets = _selectedClips.any(_validClipSelection);
          final effects = _daw.clipEffects(track, index);
          Widget slider(
            String label,
            double value,
            double max,
            String Function(double) fmt,
            void Function(double) onChanged,
          ) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label — ${fmt(value)}'),
                  Slider(
                    value: value.clamp(0, max),
                    max: max,
                    onChanged: (v) => setSheet(() => onChanged(v)),
                  ),
                ],
              );
          Widget fadeCurvePicker(
            String label,
            DawFadeCurve value,
            void Function(DawFadeCurve) onChanged,
          ) =>
              Row(
                children: [
                  Text(label),
                  const Spacer(),
                  DropdownButton<DawFadeCurve>(
                    value: value,
                    onChanged: (curve) {
                      if (curve == null) return;
                      setSheet(() => onChanged(curve));
                    },
                    items: [
                      for (final curve in DawFadeCurve.values)
                        DropdownMenuItem(
                          value: curve,
                          child: Text(_fadeCurveLabel(curve)),
                        ),
                    ],
                  ),
                ],
              );

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The clip's current voice, for engraved clips.
                    if (_daw.isScoreClip(track, index))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _daw.clipInstrument(track, index)?.id ??
                                  l10n.dawInstrumentDefault,
                              style: Theme.of(sheetCtx).textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                    slider(
                      l10n.dawGain,
                      _daw.clipGain(track, index),
                      1.5,
                      (v) => '${(v * 100).round()}%',
                      (v) => setClipGain(track, index, v),
                    ),
                    slider(
                      l10n.dawFadeIn,
                      _daw.clipFadeInMs(track, index),
                      2000,
                      (v) => '${v.round()} ms',
                      (v) => setClipFades(track, index, fadeInMs: v),
                    ),
                    fadeCurvePicker(
                      'Fade In Curve',
                      _daw.clipFadeInCurve(track, index),
                      (curve) => setClipFades(track, index, fadeInCurve: curve),
                    ),
                    slider(
                      l10n.dawFadeOut,
                      _daw.clipFadeOutMs(track, index),
                      2000,
                      (v) => '${v.round()} ms',
                      (v) => setClipFades(track, index, fadeOutMs: v),
                    ),
                    fadeCurvePicker(
                      'Fade Out Curve',
                      _daw.clipFadeOutCurve(track, index),
                      (curve) =>
                          setClipFades(track, index, fadeOutCurve: curve),
                    ),
                    // Trim: bound both edges to the untrimmed source length. The
                    // end slider shows the full length when unset (0 = to end).
                    ...() {
                      final srcMs = _daw.clipSourceMs(track, index);
                      final endMs = _daw.clipTrimEndMs(track, index);
                      return [
                        slider(
                          l10n.dawTrimStart,
                          _daw.clipTrimStartMs(track, index),
                          srcMs,
                          (v) => '${v.round()} ms',
                          (v) => setClipTrim(track, index, trimStartMs: v),
                        ),
                        slider(
                          l10n.dawTrimEnd,
                          endMs <= 0 ? srcMs : endMs,
                          srcMs,
                          (v) => '${v.round()} ms',
                          // At or past the full length ⇒ clear the trim (0 = to end).
                          (v) => setClipTrim(
                            track,
                            index,
                            trimEndMs: v >= srcMs ? 0 : v,
                          ),
                        ),
                      ];
                    }(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Clip FX',
                          style: Theme.of(sheetCtx).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        Text(
                          hasSelectedTargets
                              ? '${selectedTargets.length} selected'
                              : 'This clip',
                          style: Theme.of(sheetCtx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 2,
                      children: [
                        IconButton(
                          tooltip: 'Copy FX to selected clips',
                          icon: const Icon(Icons.checklist),
                          onPressed: effects.isEmpty || !hasSelectedTargets
                              ? null
                              : () {
                                  _daw.copyClipEffectsToClips(
                                    track,
                                    index,
                                    selectedTargets,
                                  );
                                  setSheet(() {});
                                  if (_playing) play();
                                },
                        ),
                        PopupMenuButton<DawClipEffectPreset>(
                          tooltip: 'Apply preset to selected clips',
                          icon: const Icon(Icons.playlist_add_check),
                          enabled: hasSelectedTargets,
                          onSelected: (preset) {
                            _daw.applyClipEffectPresetToClips(
                              selectedTargets,
                              preset,
                            );
                            setSheet(() {});
                            if (_playing) play();
                          },
                          itemBuilder: (_) => [
                            for (final preset in DawClipEffectPreset.values)
                              PopupMenuItem(
                                value: preset,
                                child: Text(_clipEffectPresetLabel(preset)),
                              ),
                          ],
                        ),
                        PopupMenuButton<DawClipEffectType>(
                          tooltip: 'Add effect to selected clips',
                          icon: const Icon(Icons.add_task),
                          enabled: hasSelectedTargets,
                          onSelected: (type) {
                            _daw.addClipEffectToClips(selectedTargets, type);
                            setSheet(() {});
                            if (_playing) play();
                          },
                          itemBuilder: (_) => [
                            for (final type in _clipEffectTypes)
                              PopupMenuItem(
                                value: type,
                                child: Text(_clipEffectLabel(type)),
                              ),
                          ],
                        ),
                        PopupMenuButton<DawClipEffectPreset>(
                          tooltip: 'Apply preset',
                          icon: const Icon(Icons.auto_fix_high),
                          onSelected: (preset) {
                            _daw.applyClipEffectPreset(track, index, preset);
                            setSheet(() {});
                            if (_playing) play();
                          },
                          itemBuilder: (_) => [
                            for (final preset in DawClipEffectPreset.values)
                              PopupMenuItem(
                                value: preset,
                                child: Text(_clipEffectPresetLabel(preset)),
                              ),
                          ],
                        ),
                        PopupMenuButton<DawClipEffectType>(
                          tooltip: 'Add effect',
                          icon: const Icon(Icons.add_circle_outline),
                          onSelected: (type) {
                            _daw.addClipEffect(track, index, type);
                            setSheet(() {});
                            if (_playing) play();
                          },
                          itemBuilder: (_) => [
                            for (final type in _clipEffectTypes)
                              PopupMenuItem(
                                value: type,
                                child: Text(_clipEffectLabel(type)),
                              ),
                          ],
                        ),
                      ],
                    ),
                    for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
                      _fxTile(
                        sheetCtx,
                        effects: effects,
                        fxIndex: fxIndex,
                        onToggle: () {
                          _daw.toggleClipEffect(track, index, fxIndex);
                          setSheet(() {});
                          if (_playing) play();
                        },
                        onMove: (delta) {
                          _daw.moveClipEffect(track, index, fxIndex, delta);
                          setSheet(() {});
                          if (_playing) play();
                        },
                        onRemove: () {
                          _daw.removeClipEffect(track, index, fxIndex);
                          setSheet(() {});
                          if (_playing) play();
                        },
                        onParam: (key, value) {
                          setSheet(() {
                            _daw.setClipEffectParam(
                              track,
                              index,
                              fxIndex,
                              key,
                              value,
                            );
                          });
                          if (_playing) play();
                        },
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: frozen
                              ? null
                              : () {
                                  Navigator.of(sheetCtx).pop();
                                  _freezeWithToast(track, index);
                                },
                          icon: Icon(frozen ? Icons.lock : Icons.ac_unit),
                          label: Text(l10n.dawFreeze),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            duplicateClip(track, index);
                          },
                          icon: const Icon(Icons.control_point_duplicate),
                          label: Text(l10n.dawDuplicate),
                        ),
                        // Voice an engraved clip through an instrument from the
                        // assets library (W7). A default reset appears once voiced.
                        if (_daw.isScoreClip(track, index)) ...[
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              _assignClipInstrument(track, index);
                            },
                            icon: const Icon(Icons.music_note),
                            label: Text(l10n.dawInstrument),
                          ),
                          if (_daw.clipInstrument(track, index) != null)
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(sheetCtx).pop();
                                setClipInstrument(track, index, null);
                              },
                              icon: const Icon(Icons.music_off),
                              label: Text(l10n.dawInstrumentDefault),
                            ),
                          // Take this music to a symbolic editor; "Send to Audio
                          // Editor" there updates THIS clip in place (round-trip).
                          TextButton.icon(
                            onPressed: () {
                              final score = _daw.clipScore(track, index);
                              final source = _daw.clipSourceAt(track, index);
                              Navigator.of(sheetCtx).pop();
                              if (score != null) {
                                showScoreDestinations(
                                  context,
                                  score,
                                  onReturn: (edited) => _daw
                                      .replaceScoreClipSource(source, edited),
                                );
                              }
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: Text(l10n.dawOpenInEditor),
                          ),
                        ],
                        // Split at the playhead — only when it falls inside the clip.
                        TextButton.icon(
                          onPressed: canSplitClip(track, index, playheadMs)
                              ? () {
                                  Navigator.of(sheetCtx).pop();
                                  splitClip(track, index, playheadMs);
                                }
                              : null,
                          icon: const Icon(Icons.content_cut),
                          label: Text(l10n.dawSplit),
                        ),
                        TextButton.icon(
                          onPressed: canCrossfadeWithNext(track, index)
                              ? () {
                                  Navigator.of(sheetCtx).pop();
                                  crossfadeWithNext(track, index);
                                }
                              : null,
                          icon: const Icon(Icons.compare_arrows),
                          label: const Text('Crossfade next'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            reverseClip(track, index);
                          },
                          icon: const Icon(Icons.fast_rewind),
                          label: Text(l10n.dawReverse),
                        ),
                        // Tape-style speed: slower (½×) / faster (2×).
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            resampleClip(track, index, 0.5);
                          },
                          icon: const Icon(Icons.slow_motion_video),
                          label: Text(l10n.dawSlower),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            resampleClip(track, index, 2.0);
                          },
                          icon: const Icon(Icons.speed),
                          label: Text(l10n.dawFaster),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            removeClip(track, index);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.dawRemoveClip),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _clipKind(Clip clip) {
    final s = clip.source;
    return s is DrumSource
        ? '🥁'
        : s is ScoreSource
            ? '🎼'
            : s is GrooveSource
                ? '🎛️'
                : s is TrackerSource
                    ? '🎹'
                    : '🎵';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final daw = context.watch<DawService>(); // rebuild as clips are sent

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.dawTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.dawUndo,
            onPressed: daw.canUndo ? undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.dawRedo,
            onPressed: daw.canRedo ? redo : null,
          ),
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: 'Copy selected clips',
            onPressed: _hasSelectedClips ? _copySelectedClips : null,
          ),
          IconButton(
            icon: const Icon(Icons.content_cut),
            tooltip: 'Cut selected clips',
            onPressed: _hasSelectedClips
                ? () => _deleteSelectedClips(copyFirst: true)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'Paste clips at playhead',
            onPressed: _clipClipboard.isEmpty ? null : _pasteClipClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Delete selected clips',
            onPressed: _hasSelectedClips ? _deleteSelectedClips : null,
          ),
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: _playing ? l10n.songStop : l10n.myMelodyPlay,
            onPressed: _playing ? stop : play,
          ),
          IconButton(
            icon: const Icon(Icons.repeat),
            color: _loop ? scheme.primary : null,
            tooltip: l10n.dawLoop,
            onPressed: toggleLoop,
          ),
          IconButton(
            icon: Icon(daw.snapOn ? Icons.grid_on : Icons.grid_off),
            color: daw.snapOn ? scheme.primary : null,
            tooltip: l10n.dawSnap,
            onPressed: toggleSnap,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: l10n.audioExportTitle,
            onPressed: daw.clipCount == 0 ? null : _export,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.trackerClear,
            onPressed: daw.clipCount == 0 ? null : clear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // A DAW look from the first frame: the lanes/ruler are always shown
            // (even empty), with a gentle hint banner until the first clip lands.
            if (daw.clipCount == 0)
              Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.dawEmpty,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _timeline(daw, scheme)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Add clip is timeline material only. Instrument generation
                  // lives in the Sound Library; voice shaping lives in track FX.
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.graphic_eq),
                        onPressed: addSample,
                        child: Text(l10n.dawAddFromLibrary),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.file_upload_outlined),
                        onPressed: _importAudioFile,
                        child: Text(l10n.dawImportAudioFile),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.library_music_outlined),
                        onPressed: _addMusic,
                        child: Text(l10n.dawAddMusic),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.colorize),
                        onPressed: _addFromExtractor,
                        child: Text(l10n.dawExtractSample),
                      ),
                      const Divider(height: 1),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.music_note),
                        onPressed: addDemoBeat,
                        child: Text(l10n.dawAddBeat),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.piano),
                        onPressed: addDemoTune,
                        child: Text(l10n.dawAddTune),
                      ),
                    ],
                    builder: (context, controller, _) => FilledButton.icon(
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.dawAddClip),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: daw.clipCount < 2 ? null : _mergeAllWithToast,
                    icon: const Icon(Icons.layers),
                    label: Text(l10n.dawMergeAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: daw.clipCount == 0 ? null : _saveProject,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.dawSaveProject),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openProject,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.dawOpenProject),
                  ),
                  OutlinedButton.icon(
                    onPressed: addTrack,
                    icon: const Icon(Icons.add_road),
                    label: Text(l10n.dawAddTrack),
                  ),
                  OutlinedButton.icon(
                    onPressed: _masterFxMenu,
                    icon: const Icon(Icons.graphic_eq),
                    label: const Text('Master FX'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busMenu,
                    icon: const Icon(Icons.call_merge),
                    label: const Text('Buses'),
                  ),
                  OutlinedButton.icon(
                    onPressed: daw.clipCount == 0 ? null : _markRangeIn,
                    icon: const Icon(Icons.keyboard_tab),
                    label: const Text('Mark In'),
                  ),
                  OutlinedButton.icon(
                    onPressed: daw.clipCount == 0 ? null : _markRangeOut,
                    icon: const Icon(Icons.keyboard_return),
                    label: const Text('Mark Out'),
                  ),
                  MenuAnchor(
                    menuChildren: [
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.auto_fix_high),
                        menuChildren: [
                          for (final preset in DawClipEffectPreset.values)
                            MenuItemButton(
                              onPressed: _hasFxRange
                                  ? () => _applyRangePreset(preset)
                                  : null,
                              child: Text(_clipEffectPresetLabel(preset)),
                            ),
                        ],
                        child: const Text('Preset'),
                      ),
                      SubmenuButton(
                        leadingIcon: const Icon(Icons.add_circle_outline),
                        menuChildren: [
                          for (final type in _clipEffectTypes)
                            MenuItemButton(
                              onPressed: _hasFxRange
                                  ? () => _addRangeEffect(type)
                                  : null,
                              child: Text(_clipEffectLabel(type)),
                            ),
                        ],
                        child: const Text('Effect'),
                      ),
                    ],
                    builder: (context, controller, _) => OutlinedButton.icon(
                      onPressed: _hasFxRange
                          ? () => controller.isOpen
                              ? controller.close()
                              : controller.open()
                          : null,
                      icon: const Icon(Icons.segment),
                      label: Text(_rangeLabel()),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _hasFxRange ? _rangeGainDialog : null,
                    icon: const Icon(Icons.tune),
                    label: const Text('Range Gain'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _hasFxRange ? _trackAutomationDialog : null,
                    icon: const Icon(Icons.timeline),
                    label: const Text('Track Auto'),
                  ),
                  MenuAnchor(
                    menuChildren: [
                      for (final curve in DawFadeCurve.values)
                        MenuItemButton(
                          onPressed: _hasFxRange
                              ? () => _applyRangeFade(
                                    fadeIn: true,
                                    curve: curve,
                                  )
                              : null,
                          leadingIcon: const Icon(Icons.trending_up),
                          child: Text('Fade In ${_fadeCurveLabel(curve)}'),
                        ),
                      for (final curve in DawFadeCurve.values)
                        MenuItemButton(
                          onPressed: _hasFxRange
                              ? () => _applyRangeFade(
                                    fadeIn: false,
                                    curve: curve,
                                  )
                              : null,
                          leadingIcon: const Icon(Icons.trending_down),
                          child: Text('Fade Out ${_fadeCurveLabel(curve)}'),
                        ),
                    ],
                    builder: (context, controller, _) => OutlinedButton.icon(
                      onPressed: _hasFxRange
                          ? () => controller.isOpen
                              ? controller.close()
                              : controller.open()
                          : null,
                      icon: const Icon(Icons.show_chart),
                      label: const Text('Range Fade'),
                    ),
                  ),
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        onPressed:
                            _hasFxRange ? () => _setRangeMuted(true) : null,
                        leadingIcon: const Icon(Icons.volume_off),
                        child: const Text('Mute'),
                      ),
                      MenuItemButton(
                        onPressed:
                            _hasFxRange ? () => _setRangeMuted(false) : null,
                        leadingIcon: const Icon(Icons.volume_up),
                        child: const Text('Unmute'),
                      ),
                    ],
                    builder: (context, controller, _) => OutlinedButton.icon(
                      onPressed: _hasFxRange
                          ? () => controller.isOpen
                              ? controller.close()
                              : controller.open()
                          : null,
                      icon: const Icon(Icons.volume_off),
                      label: const Text('Range Mute'),
                    ),
                  ),
                  // Project tempo — defines the beat snap grid.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        tooltip: l10n.dawTempoDown,
                        onPressed: () => setBpm(daw.bpm - 5),
                      ),
                      Text(l10n.dawBpm(daw.bpm.round())),
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: l10n.dawTempoUp,
                        onPressed: () => setBpm(daw.bpm + 5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Timeline (to-scale clips, draggable in time) --------------------------

  static const double _pxPerSecond = 80;
  static const double _laneHeight = 60;
  static const double _gutterWidth = 112;
  static const double _rulerHeight = 20;

  // The clip's start when a long-press drag begins (offsets are relative to it).
  double _dragOriginMs = 0;

  Widget _timeline(DawService daw, ColorScheme scheme) {
    // Total arrangement length → the shared lane width.
    var maxEndMs = 0.0;
    for (var i = 0; i < daw.timeline.tracks.length; i++) {
      for (var j = 0; j < daw.timeline.tracks[i].clips.length; j++) {
        final end = daw.clipStartMs(i, j) + daw.clipDurationMs(i, j);
        if (end > maxEndMs) maxEndMs = end;
      }
    }
    final laneWidth = math.max(320.0, maxEndMs / 1000 * _pxPerSecond + 48);

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed left gutter: a ruler-height spacer, then per-track name + mute.
          Column(
            children: [
              const SizedBox(height: _rulerHeight, width: _gutterWidth),
              for (var i = 0; i < daw.timeline.tracks.length; i++)
                _gutterHeader(daw, i, scheme),
            ],
          ),
          // Shared, horizontally-scrolling ruler + lanes (they scroll together).
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: laneWidth,
                child: Stack(
                  children: [
                    // Faint beat gridlines behind the lanes, when snapping.
                    if (daw.snapOn)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BeatGridPainter(
                            beatPx: daw.beatMs / 1000 * _pxPerSecond,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    Column(
                      children: [
                        _ruler(laneWidth, scheme),
                        for (var i = 0; i < daw.timeline.tracks.length; i++)
                          _lane(daw, i, scheme, laneWidth),
                      ],
                    ),
                    if (_hasFxRange)
                      Positioned(
                        left: _rangeStartMs / 1000 * _pxPerSecond,
                        top: _rulerHeight,
                        width:
                            (_rangeEndMs - _rangeStartMs) / 1000 * _pxPerSecond,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.08),
                              border: Border.symmetric(
                                vertical: BorderSide(color: scheme.primary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // The playhead: a thin line that sweeps across during play.
                    Positioned.fill(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _positionMs,
                        builder: (context, ms, _) {
                          // Show while playing, or resting at a seek marker.
                          if (!_playing && ms <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: ms / 1000 * _pxPerSecond,
                              ),
                              child: Container(width: 2, color: scheme.primary),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A second-by-second time ruler aligned with the lanes below it.
  Widget _ruler(double laneWidth, ColorScheme scheme) {
    final seconds = (laneWidth / _pxPerSecond).ceil();
    return GestureDetector(
      // Click the ruler to move the playhead / play-start marker.
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => seekTo(d.localPosition.dx / _pxPerSecond * 1000),
      child: Container(
        width: laneWidth,
        height: _rulerHeight,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Stack(
          children: [
            for (var s = 0; s <= seconds; s++)
              Positioned(
                left: s * _pxPerSecond,
                top: 0,
                bottom: 0,
                child: Row(
                  children: [
                    Container(width: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text(
                        '${s}s',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gutterHeader(DawService daw, int i, ColorScheme scheme) {
    final track = daw.timeline.tracks[i];
    final selected = _selectedTracks.contains(i);
    final busIndex = track.busIndex;
    final busName = busIndex != null &&
            busIndex >= 0 &&
            busIndex < daw.timeline.buses.length
        ? daw.timeline.buses[busIndex].name
        : null;
    final sends = [
      for (final send in track.busSends.entries)
        if (send.value > 0 &&
            send.key >= 0 &&
            send.key < daw.timeline.buses.length)
          send,
    ];
    return SizedBox(
      width: _gutterWidth,
      height: _laneHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(
                tooltip:
                    selected ? 'Deselect track for FX' : 'Select track for FX',
                icon: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    if (selected) {
                      _selectedTracks.remove(i);
                    } else {
                      _selectedTracks.add(i);
                    }
                  });
                },
              ),
              // A small badge when the lane has a voice — new clips adopt it.
              if (track.instrument != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child:
                      Icon(Icons.music_note, size: 12, color: scheme.primary),
                ),
              if (busName != null)
                Tooltip(
                  message: busName.isEmpty
                      ? 'Routed to Bus ${busIndex! + 1}'
                      : 'Routed to $busName',
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.call_merge,
                      size: 12,
                      color: scheme.tertiary,
                    ),
                  ),
                ),
              if (sends.isNotEmpty)
                Tooltip(
                  message: '${sends.length} bus sends',
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.alt_route,
                      size: 12,
                      color: scheme.secondary,
                    ),
                  ),
                ),
              Expanded(
                child: InkWell(
                  onTap: () => _trackMenu(i),
                  child: Text(
                    track.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              InkWell(
                onTap: () => toggleTrackSolo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'S',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: track.soloed ? scheme.primary : scheme.outline,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => toggleTrackMute(i),
                child: Icon(
                  track.muted ? Icons.volume_off : Icons.volume_up,
                  size: 18,
                  color: track.muted ? scheme.error : null,
                ),
              ),
            ],
          ),
          // Per-track volume fader (0 – 150%).
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: track.gain.clamp(0.0, 1.5),
              max: 1.5,
              onChanged: (v) => setTrackGain(i, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lane(DawService daw, int i, ColorScheme scheme, double laneWidth) {
    final clips = daw.timeline.tracks[i].clips;
    return Container(
      width: laneWidth,
      height: _laneHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        children: [
          for (var j = 0; j < clips.length; j++) _clipBox(daw, i, j, scheme),
        ],
      ),
    );
  }

  Widget _clipBox(DawService daw, int i, int j, ColorScheme scheme) {
    final clip = daw.timeline.tracks[i].clips[j];
    final frozen = daw.isClipFrozen(i, j);
    final startPx = daw.clipStartMs(i, j) / 1000 * _pxPerSecond;
    final widthPx =
        math.max(30.0, daw.clipDurationMs(i, j) / 1000 * _pxPerSecond);
    final bg = frozen ? scheme.secondaryContainer : scheme.primaryContainer;
    final fg = frozen ? scheme.onSecondaryContainer : scheme.onPrimaryContainer;
    final target = (track: i, index: j);
    final selected = _selectedClips.contains(target);

    return Positioned(
      left: startPx,
      top: 6,
      height: _laneHeight - 12,
      width: widthPx,
      child: GestureDetector(
        // Long-press then drag to reposition in time (a plain drag over the lane
        // still scrolls it); tap to freeze to audio.
        onLongPressStart: (_) => _dragOriginMs = daw.clipStartMs(i, j),
        onLongPressMoveUpdate: (d) => moveClip(
          i,
          j,
          _dragOriginMs + d.localOffsetFromOrigin.dx / _pxPerSecond * 1000,
        ),
        onTap: () => _openClipInspector(i, j),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                // The clip's audio shape, filling the box behind the label.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClipWaveformPainter(
                      daw.clipPeaks(i, j, buckets: math.max(8, widthPx ~/ 2)),
                      fg.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 28, right: 2),
                  child: Row(
                    children: [
                      if (frozen && widthPx >= 48)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(Icons.lock, size: 14, color: fg),
                        ),
                      if (widthPx >= 36)
                        Expanded(
                          child: Text(
                            _clipKind(clip),
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: TextStyle(color: fg),
                          ),
                        ),
                      if (widthPx >= 48)
                        InkWell(
                          onTap: () => removeClip(i, j),
                          child: Icon(Icons.close, size: 16, color: fg),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: IconButton(
                    tooltip: selected
                        ? 'Deselect clip for FX'
                        : 'Select clip for FX',
                    icon: Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: fg,
                    ),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 26,
                      height: 26,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {
                        if (selected) {
                          _selectedClips.remove(target);
                        } else {
                          _selectedClips.add(target);
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint vertical lines every [beatPx], marking the beat grid clips snap to.
class _BeatGridPainter extends CustomPainter {
  _BeatGridPainter({required this.beatPx, required this.color});
  final double beatPx;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (beatPx < 4) return; // too dense to be useful
    final paint = Paint()..color = color;
    for (var x = beatPx; x < size.width; x += beatPx) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_BeatGridPainter old) =>
      old.beatPx != beatPx || old.color != color;
}

/// Draws a clip's downsampled [peaks] (0..1) as a centre-line waveform that
/// fills the clip box. Repaints only when the peak list identity changes.
class _ClipWaveformPainter extends CustomPainter {
  _ClipWaveformPainter(this.peaks, this.color);
  final List<double> peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final paint = Paint()..color = color;
    final mid = size.height / 2;
    final dx = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final h = (peaks[i] * size.height).clamp(1.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(i * dx, mid - h / 2, dx <= 1 ? 1 : dx - 0.5, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ClipWaveformPainter old) =>
      !identical(old.peaks, peaks) || old.color != color;
}
