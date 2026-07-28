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

import 'package:comet_beat/core/audio/beat_to_tracker.dart'
    show drumSongFromBeat;
import 'package:comet_beat/core/audio/crisp_dsp/loudness.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart'
    show StretchQuality;
import 'package:comet_beat/core/audio/daw_edits.dart'
    show ClipStats, GeneratorShape, clipStatsOf;
import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_tempo_map.dart'
    show TempoMap, kMaxBpm, kMinBpm;
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart'
    show formatFxChain, fxChainStringIsLossless, parseFxChain;
import 'package:comet_beat/core/audio/fx/fx_params.dart'
    show fxParamCaption, fxParamSpecs, fxSliderStep, fxTypeLabel;
import 'package:comet_beat/core/audio/loop_engine.dart'
    show
        DrumRowsPattern,
        GrooveSpec,
        LoopEngine,
        LoopTiming,
        PatternCell,
        kPatternSteps;
import 'package:comet_beat/core/audio/loudness_advice.dart';
import 'package:comet_beat/core/audio/synth.dart'
    show Drum, kSampleRate, wavBytes;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/audio/transcription/transcription_service.dart'
    show transcribePcmToScore;
import 'package:comet_beat/core/audio/voice_clip_recorder.dart';
import 'package:comet_beat/core/interop/project_bridge.dart'
    show AppMode, ProjectBridge;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/beat_bridge.dart' show SharedBeat;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/features/games/composition/automation_curve_editor.dart';
import 'package:comet_beat/features/games/composition/daw_help_sheet.dart';
import 'package:comet_beat/features/games/composition/groove_notation.dart'
    show grooveParts;
import 'package:comet_beat/features/games/composition/spectrogram_view.dart'
    show showSpectrogramDialog;
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart'
    show showMyInstrumentsSheet;
import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/features/sound_lab/sample_extractor_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/keymap/intents.dart';
import 'package:comet_beat/shared/keymap/keymap.dart';
import 'package:comet_beat/shared/keymap/keymap_service.dart';
import 'package:comet_beat/shared/keymap/keymap_sheet.dart';
import 'package:comet_beat/shared/music/music_picker.dart'
    show showMusicPickerWithLicense;
import 'package:comet_beat/shared/music/score_router.dart'
    show
        openDrumPattern,
        openGroove,
        openScoreInTab,
        openScoreInWorkshop,
        openTrackerSong,
        showScoreDestinations;
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show AudioStem, showAudioExportSheet, showAudioStemsExportSheet;
import 'package:comet_beat/shared/music_io/audio_import.dart'
    show importAudioAsync, kAudioImportExtensions;
import 'package:comet_beat/shared/widgets/open_in_menu.dart' show OpenInMenu;
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        MultiPartScore,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard, KeyDownEvent;
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

  /// Normalize the clip to a peak target (bakes it).
  void normalizeClip(int track, int index);

  /// Invert the clip's phase (bakes it).
  void invertClip(int track, int index);

  /// Remove the clip's DC offset (bakes it).
  void removeClipDcOffset(int track, int index);

  /// Strip silence from the clip's edges (bakes it; the clip slides later by
  /// the leading silence so the audio keeps its place).
  void trimSilenceFromClip(int track, int index);

  /// Amplify the clip by [db] (bakes it).
  void amplifyClip(int track, int index, double db);

  /// Cut the marked range out of the given tracks / keep only what's inside it.
  int silenceRange(Iterable<int> tracks, double startMs, double endMs);
  int cropToRange(Iterable<int> tracks, double startMs, double endMs);

  /// Measured peak/RMS/duration/clipping for a clip's played window.
  ClipStats clipStats(int track, int index);

  /// Move a clip to another lane (drag-and-drop, or the inspector's picker).
  /// Returns its index in the new lane, or -1 if the move wasn't possible.
  int moveClipToTrack(int fromTrack, int index, int toTrack, {double? startMs});

  /// Render ONE lane on its own, for a stem export.
  Float64List bakeTrack(int track);

  /// Generate a steady tone / noise / silence onto its own new lane.
  void generateClip({
    required GeneratorShape shape,
    double freq,
    double seconds,
    double amp,
  });

  /// Timeline zoom: pixels per second, and the in/out/fit controls.
  double get pxPerSecond;
  void zoomIn();
  void zoomOut();
  void zoomToFit();

  /// Whether playback loops the marked range rather than the whole
  /// arrangement — true when looping is on AND a range is marked.
  bool get loopsMarkedRange;

  /// Peak and RMS (linear, 0..1) of what is sounding right now — 0 when
  /// stopped. Reads the baked buffer at the playhead, so it measures the mix
  /// actually being played, post-FX.
  ({double peak, double rms}) get playbackLevel;

  /// Record from the mic onto a new lane (O14). No-op without a microphone.
  Future<void> recordClip();
  bool get isRecording;

  /// Test seam: the mic can't run under the headless binding, so tests inject
  /// the captured audio instead of capturing it.
  void debugAddRecordedClip(Float64List pcm);

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
  void setClipPan(int track, int index, double pan);
  double clipPan(int track, int index);
  void setClipWidth(int track, int index, double width);
  double clipWidth(int track, int index);
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

/// Every effect the Audio Editor offers, in MENU order — grouped basics,
/// modulation, filters, dynamics, pitch/time, then the voice shapers. One list
/// feeds all four scopes (clip, track, bus, master) and the marked-range action.
///
/// Deliberately hand-ordered rather than `DawClipEffectType.values`, because the
/// grouping is what makes a 29-item menu usable. The cost of that is drift: an
/// effect appended to the enum and forgotten here still exists, still renders,
/// and is simply unreachable in the app — nothing fails. `daw_screen_test.dart`
/// asserts this list covers the enum, so the omission surfaces as a test
/// failure naming the missing effect.
const kDawClipEffectTypes = <DawClipEffectType>[
  DawClipEffectType.gain,
  DawClipEffectType.pan,
  // A4 — the stereo field, next to the other level controls.
  DawClipEffectType.stereoWidth,
  DawClipEffectType.autoPan,
  DawClipEffectType.swapChannels,
  DawClipEffectType.centreCancel,
  DawClipEffectType.crossfeed,
  DawClipEffectType.remix,
  DawClipEffectType.reverb,
  DawClipEffectType.delay,
  DawClipEffectType.chorus,
  DawClipEffectType.flanger,
  DawClipEffectType.ringMod,
  DawClipEffectType.distortion,
  DawClipEffectType.bitCrush,
  DawClipEffectType.lowpass,
  DawClipEffectType.highpass,
  DawClipEffectType.bandpass,
  DawClipEffectType.notch,
  DawClipEffectType.peakingEq,
  DawClipEffectType.lowShelf,
  DawClipEffectType.highShelf,
  // A2 — the broad curves, with the other tone shaping.
  DawClipEffectType.tilt,
  DawClipEffectType.loudness,
  DawClipEffectType.deEmphasis,
  DawClipEffectType.contrast,
  DawClipEffectType.phaser,
  DawClipEffectType.autoWah,
  // A1 — the rest of the filter set, kept with the other filters. The gentle
  // one-poles sit next to their resonant two-pole namesakes, and the two
  // specialists (a filter typed as coefficients, a 90° phase rotator) come last
  // in the group because they are tools rather than colours.
  DawClipEffectType.allpass,
  DawClipEffectType.onePoleLowpass,
  DawClipEffectType.onePoleHighpass,
  DawClipEffectType.sincFilter,
  DawClipEffectType.biquadRaw,
  DawClipEffectType.hilbert,
  DawClipEffectType.convolutionReverb,
  // A5 — the repair tools, before the creative ones: a recording gets fixed
  // first and shaped second.
  DawClipEffectType.noiseReduce,
  DawClipEffectType.humRemove,
  DawClipEffectType.declick,
  DawClipEffectType.declip,
  DawClipEffectType.dcShift,
  DawClipEffectType.compressor,
  DawClipEffectType.gate,
  // A3 — with the other dynamics.
  DawClipEffectType.limiter,
  DawClipEffectType.deEsser,
  DawClipEffectType.multibandCompressor,
  DawClipEffectType.pitchShift,
  DawClipEffectType.pitchBend,
  DawClipEffectType.timeStretch,
  DawClipEffectType.tremolo,
  DawClipEffectType.vocoder,
  DawClipEffectType.voiceShape,
  DawClipEffectType.voiceChipmunk,
  DawClipEffectType.voiceDeep,
  DawClipEffectType.voiceRobot,
  DawClipEffectType.voiceRadio,
];

/// WS-T3 — what the Audio Editor actually does, so its keymap sheet lists only
/// shortcuts that work HERE. Listing ones that do nothing on this screen would
/// be worse than listing none.
const Set<AppIntent> kDawIntents = {
  AppIntent.transportToggle,
  AppIntent.editDelete,
  AppIntent.editUndo,
  AppIntent.editRedo,
};

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
  //
  // WS-W2: the tick computes `_seekMs + elapsed`, i.e. an ABSOLUTE position
  // read from an authority — not an accumulated delta. That is why the shared
  // transport is fed with `syncTo` rather than `advance`; accumulating would
  // drift away from the baked audio one dropped frame at a time.
  late final Ticker _ticker;
  final ValueNotifier<double> _positionMs = ValueNotifier<double>(0);
  double _totalMs = 0;
  bool _loop = false;

  /// Timeline zoom multiplier over [_basePxPerSecond] (O8).
  double _zoom = 1;

  /// The last baked mix, kept so the meters (O12) can measure what's playing.
  Float64List? _bakedPcm;

  /// The app-wide transport, when one is provided. Null when the screen is
  /// mounted without a provider tree, so every use is null-safe rather than
  /// forcing existing tests to grow one.
  TransportService? _transport;

  /// O14 — the app's one mic-facing capture path, shared with the Tracker.
  final VoiceClipRecorder _recorder = VoiceClipRecorder();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    _ticker.dispose();
    _positionMs.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _transport = Provider.of<TransportService>(context, listen: false);
    } on ProviderNotFoundException {
      _transport = null;
    }
  }

  void _onTick(Duration elapsed) {
    final ms = _seekMs + elapsed.inMilliseconds.toDouble();
    // O9 — with a range marked, looping cycles THAT selection rather than the
    // whole arrangement, so you can work on one bar over and over.
    if (loopsMarkedRange && ms >= _rangeEndMs) {
      seekTo(_rangeStartMs);
      play();
      return;
    }
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
    // WS-W2 — publish into the SHARED transport so another surface can follow
    // this playhead. `syncTo`, because `ms` is an absolute read of the Ticker.
    _transport?.syncTo(ms);
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
            _chainClipboardActions(ctx, _daw.trackEffects(track), (chain) {
              _daw.setTrackEffects(track, chain);
              setDialog(() {});
            }),
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
            onAutomate: (key, startValue, endValue) async {
              setDialog(() {
                _daw.setTrackEffectAutomation(
                  track,
                  fxIndex,
                  key,
                  _projectRangeAutomationPoints(startValue, endValue),
                );
              });
              if (_playing) play();
            },
            onSetAutomation: (key, points) async {
              setDialog(() {
                _daw.setTrackEffectAutomation(track, fxIndex, key, points);
              });
              if (_playing) play();
            },
          ),
      ],
    );
  }

  /// F3 — the chain string as a copy/paste preset.
  ///
  /// The same text `bin/fxproc.dart --chain` takes, so a chain tuned by ear in
  /// the app pastes straight into a terminal or a test, and one found in a test
  /// pastes back. That round trip is the whole reason the codec exists; without
  /// these two buttons it only ever ran in one direction.
  Widget _chainClipboardActions(
    BuildContext ctx,
    List<DawClipEffect> effects,
    void Function(List<DawClipEffect> chain) onReplace,
  ) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy chain',
            icon: const Icon(Icons.content_copy),
            onPressed: effects.isEmpty
                ? null
                : () async {
                    final text = formatFxChain(effects);
                    await Clipboard.setData(ClipboardData(text: text));
                    // The State's `mounted`, because the snackbar goes through
                    // the State's context — guarding the dialog's context would
                    // be checking the wrong thing.
                    if (!mounted) return;
                    // Automation has no syntax in the string form, so say so
                    // rather than let it vanish silently on the way back.
                    final lossy = !fxChainStringIsLossless(effects);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          lossy ? '$text\n(automation is not copied)' : text,
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Paste chain',
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text?.trim() ?? '';
              if (!mounted || text.isEmpty) return;
              final parsed = parseFxChain(text);
              if (!parsed.ok || parsed.isEmpty) {
                // Report rather than silently doing nothing: the user just
                // pasted something they believed was a chain.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      parsed.errors.isEmpty
                          ? 'That is not an effect chain.'
                          : parsed.errors.first,
                    ),
                  ),
                );
                return;
              }
              onReplace(parsed.chain);
              if (_playing) play();
            },
          ),
        ],
      );

  /// WS-A9 — choose how low the warp has to hold.
  ///
  /// Presented as "the lowest note it keeps" rather than a quality level,
  /// because that is the axis the measurements support: a longer WSOLA frame
  /// holds lower pitches and costs time, and the transient trade this was
  /// scoped around did not reproduce. See `StretchQuality`.
  Future<void> _pickWarpQuality(int track, int index) async {
    final chosen = await showModalBottomSheet<StretchQuality>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Stretch quality',
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'A longer window keeps low notes in tune when the clip is '
                'stretched, and takes longer to work out. Below its lowest '
                'note, a stretch drops the pitch rather than just sounding '
                'rougher.',
              ),
            ),
            for (final q in StretchQuality.values)
              ListTile(
                leading: Icon(
                  _daw.clipWarpQuality(track, index) == q
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  switch (q) {
                    StretchQuality.light => 'Light',
                    StretchQuality.balanced => 'Balanced',
                    StretchQuality.deep => 'Deep — for bass',
                  },
                ),
                subtitle: Text(
                  'Keeps notes down to '
                  '${q.lowestReliableHz(kDawSampleRate.toDouble()).round()} Hz',
                ),
                onTap: () => Navigator.of(sheetCtx).pop(q),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _daw.setClipWarpQuality(track, index, chosen);
  }

  /// WS-A7 — turn "follow the project tempo" on or off for one clip.
  ///
  /// A symbolic clip already knows the tempo it is in (a drum pattern carries
  /// its grid), so it just toggles. A RECORDING cannot know, and that is the
  /// case warping most exists for — so it asks, rather than hiding the feature
  /// exactly where it is most wanted or guessing a number that would shift the
  /// arrangement's timing invisibly.
  Future<void> _toggleClipWarp(int track, int index) async {
    if (_daw.clipWarps(track, index)) {
      _daw.setClipWarp(track, index, false);
      return;
    }
    var bpm = _daw.clipNativeBpm(track, index);
    if (bpm == null) {
      bpm = await _askNativeBpm();
      if (bpm == null) return; // cancelled — do nothing at all
    }
    _daw.setClipWarp(track, index, true, nativeBpm: bpm);
  }

  /// Ask what tempo a recording was played at.
  Future<double?> _askNativeBpm() async {
    final controller = TextEditingController(text: _daw.bpm.round().toString());
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What tempo is this clip in?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The tempo it was played at. Following the project tempo '
              'stretches it from there, without changing its pitch.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'BPM'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              // An unparseable or out-of-range tempo returns nothing rather
              // than a clamped guess: the number IS the feature here.
              Navigator.of(ctx).pop(
                value != null && value >= kMinBpm && value <= kMaxBpm
                    ? value
                    : null,
              );
            },
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  /// WS-A5 — measure the mix and say what the numbers MEAN.
  ///
  /// Measures the marked range when there is one, because "is the chorus
  /// louder than the verse" is the question people actually have; otherwise the
  /// whole mix. The judgement lives in `loudness_advice.dart` rather than here,
  /// so it can be tested — a meter that renders beautifully and reasons wrongly
  /// is worse than none, because it is trusted.
  Future<void> _showLoudness() async {
    var target = LoudnessTarget.streaming;
    final mix = _daw.bakeStereo();
    if (mix.left.isEmpty) return;

    Float64List slice(Float64List channel) {
      if (!_hasFxRange) return channel;
      final from = (_rangeStartMs * kDawSampleRate / 1000)
          .round()
          .clamp(0, channel.length);
      final to = (_rangeEndMs * kDawSampleRate / 1000)
          .round()
          .clamp(from, channel.length);
      return Float64List.sublistView(channel, from, to);
    }

    final reading = measureLoudness(
      slice(mix.left),
      slice(mix.right),
      sampleRate: kDawSampleRate,
    );
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final notes = loudnessAdvice(reading, target: target);
          final scheme = Theme.of(sheetCtx).colorScheme;
          Color colourFor(LoudnessStatus s) => switch (s) {
                LoudnessStatus.good => scheme.primary,
                LoudnessStatus.note => scheme.onSurfaceVariant,
                LoudnessStatus.warn => scheme.error,
              };
          IconData iconFor(LoudnessStatus s) => switch (s) {
                LoudnessStatus.good => Icons.check_circle_outline,
                LoudnessStatus.note => Icons.info_outline,
                LoudnessStatus.warn => Icons.warning_amber_outlined,
              };
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  _hasFxRange ? 'Loudness — marked range' : 'Loudness — mix',
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                // The target first: every level judgement below depends on it,
                // so choosing it afterwards would read as the meter changing
                // its mind.
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in LoudnessTarget.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: target == t,
                        onSelected: (_) => setSheet(() => target = t),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    target.blurb,
                    style: Theme.of(sheetCtx).textTheme.bodySmall,
                  ),
                ),
                const Divider(),
                for (final note in notes)
                  ListTile(
                    leading: Icon(
                      iconFor(note.status),
                      color: colourFor(note.status),
                    ),
                    title: Text(note.headline),
                    subtitle: Text(note.detail),
                    isThreeLine: true,
                  ),
                const Divider(),
                // The raw numbers stay available underneath the reading of
                // them — the advice is the point, but someone checking a
                // delivery spec needs the figures themselves.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Integrated ${reading.integratedLufs.toStringAsFixed(1)} · '
                    'short ${reading.shortTermLufs.toStringAsFixed(1)} · '
                    'momentary ${reading.momentaryLufs.toStringAsFixed(1)} LUFS'
                    '   ·   ${reading.truePeakDb.toStringAsFixed(2)} dBTP'
                    '   ·   phase ${reading.correlation.toStringAsFixed(2)}',
                    style: Theme.of(sheetCtx).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
            _chainClipboardActions(ctx, effects, (chain) {
              _daw.setMasterEffects(chain);
              setDialog(() {});
            }),
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
            onAutomate: (key, startValue, endValue) async {
              setDialog(() {
                _daw.setMasterEffectAutomation(
                  fxIndex,
                  key,
                  _projectRangeAutomationPoints(startValue, endValue),
                );
              });
              if (_playing) play();
            },
            onSetAutomation: (key, points) async {
              setDialog(() {
                _daw.setMasterEffectAutomation(fxIndex, key, points);
              });
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
                  onAutomate: (key, startValue, endValue) async {
                    setDialog(() {
                      _daw.setBusEffectAutomation(
                        bus,
                        fxIndex,
                        key,
                        _projectRangeAutomationPoints(startValue, endValue),
                      );
                    });
                    if (_playing) play();
                  },
                  onSetAutomation: (key, points) async {
                    setDialog(() {
                      _daw.setBusEffectAutomation(bus, fxIndex, key, points);
                    });
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

  /// O15 — the clip's frequency content over time. Uses the clip's PLAYED
  /// window (trim folded in), so what you see is what you hear.
  void _showClipSpectrogram(int track, int index) {
    final pcm = _daw.clipWindowPcm(track, index);
    if (pcm.isEmpty) return;
    showSpectrogramDialog(context, pcm: pcm, sampleRate: kDawSampleRate);
  }

  /// O13 — name a marker as it's dropped. An empty name is fine (the flag
  /// alone is a useful "come back here"), so Add is never blocked.
  Future<void> _addMarkerAtPlayhead() async {
    final l10n = AppLocalizations.of(context)!;
    final at = playheadMs;
    // NB: TextFormField, not TextField + our own controller — a controller we
    // dispose right after the pop is still referenced by the field while the
    // dialog animates out, which corrupts the focus tree.
    var text = '';
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawAddMarker),
        content: TextFormField(
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.dawMarkerName),
          onChanged: (v) => text = v,
          onFieldSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(text),
            child: Text(l10n.dawAmplifyApply),
          ),
        ],
      ),
    );
    if (label == null) return;
    _daw.addMarker(at, label.trim());
  }

  /// Tap a marker flag → rename, move it here, or delete it.
  Future<void> _markerMenu(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final marker = _daw.markers[index];
    var text = marker.label;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawMarkers),
        content: TextFormField(
          autofocus: true,
          initialValue: marker.label,
          decoration: InputDecoration(labelText: l10n.dawMarkerName),
          onChanged: (v) => text = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('delete'),
            child: Text(l10n.dawDelete),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('rename'),
            child: Text(l10n.dawAmplifyApply),
          ),
        ],
      ),
    );
    if (action == 'delete') {
      _daw.removeMarker(index);
    } else if (action == 'rename') {
      _daw.renameMarker(index, text.trim());
    }
  }

  /// O12 — a live peak/RMS meter. The filled bar is RMS (how loud it *feels*),
  /// the bright tick is the peak (what actually clips), on a −60…0 dBFS scale.
  /// It repaints off the playhead notifier, so it costs nothing when stopped.
  Widget _levelMeter(AppLocalizations l10n) {
    double norm(double amplitude) {
      if (amplitude <= 0) return 0;
      final db = 20 * math.log(amplitude) / math.ln10;
      return ((db + 60) / 60).clamp(0.0, 1.0);
    }

    return ValueListenableBuilder<double>(
      valueListenable: _positionMs,
      builder: (ctx, _, __) {
        final level = playbackLevel;
        final scheme = Theme.of(ctx).colorScheme;
        final hot = level.peak >= 1;
        return Tooltip(
          message: '${l10n.dawLevel} — RMS / peak dBFS',
          child: SizedBox(
            width: 96,
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: norm(level.rms),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: hot ? scheme.error : scheme.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                // The peak tick rides ahead of the RMS fill.
                Align(
                  alignment: Alignment(2 * norm(level.peak) - 1, 0),
                  child: Container(
                    width: 2,
                    height: 14,
                    color: level.peak <= 0
                        ? Colors.transparent
                        : (hot ? scheme.error : scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _shapeLabel(GeneratorShape shape, AppLocalizations l10n) =>
      switch (shape) {
        GeneratorShape.sine => l10n.dawShapeSine,
        GeneratorShape.square => l10n.dawShapeSquare,
        GeneratorShape.saw => l10n.dawShapeSaw,
        GeneratorShape.triangle => l10n.dawShapeTriangle,
        GeneratorShape.whiteNoise => l10n.dawShapeWhiteNoise,
        GeneratorShape.pinkNoise => l10n.dawShapePinkNoise,
        GeneratorShape.silence => l10n.dawShapeSilence,
        // A7 — left untranslated on purpose, the same call the FX rack makes
        // for its effect names: these are established audio-engineering terms
        // that appear in English in every tool the user will meet, and the
        // alternative is seven new keys in the hot shared ARBs to invent
        // German for "violet noise".
        GeneratorShape.brownNoise => 'Brown noise',
        GeneratorShape.blueNoise => 'Blue noise',
        GeneratorShape.violetNoise => 'Violet noise',
        GeneratorShape.sweep => 'Sweep (linear)',
        GeneratorShape.logSweep => 'Sweep (log)',
        GeneratorShape.pluck => 'Plucked string',
        GeneratorShape.impulse => 'Impulse',
      };

  /// Whether a frequency control means anything for [shape].
  ///
  /// Listed as what IS pitched rather than what is not: a new noise colour
  /// added to the enum should default to hiding the control, not to showing a
  /// frequency slider that does nothing.
  static bool _shapeIsPitched(GeneratorShape shape) => const {
        GeneratorShape.sine,
        GeneratorShape.square,
        GeneratorShape.saw,
        GeneratorShape.triangle,
        GeneratorShape.sweep,
        GeneratorShape.logSweep,
        GeneratorShape.pluck,
      }.contains(shape);

  /// O7 — build a tone / noise / silence clip from scratch onto a new lane.
  Future<void> _generateClipDialog() async {
    final l10n = AppLocalizations.of(context)!;
    var shape = GeneratorShape.sine;
    var freq = 440.0;
    var endFreq = 8000.0;
    var seconds = 2.0;
    var amp = 0.5;
    final made = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final pitched = _shapeIsPitched(shape);
          final sweeping =
              shape == GeneratorShape.sweep || shape == GeneratorShape.logSweep;
          return AlertDialog(
            title: Text(l10n.dawGenerate),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<GeneratorShape>(
                    value: shape,
                    isExpanded: true,
                    onChanged: (v) {
                      if (v != null) setDialog(() => shape = v);
                    },
                    items: [
                      for (final s in GeneratorShape.values)
                        DropdownMenuItem(
                          value: s,
                          child: Text(_shapeLabel(s, l10n)),
                        ),
                    ],
                  ),
                  // Frequency only means something for the tone shapes.
                  if (pitched) ...[
                    Text(
                      '${l10n.dawFrequency} ${freq.round()} Hz'
                      '${sweeping ? ' → ${endFreq.round()} Hz' : ''}',
                    ),
                    Slider(
                      value: freq,
                      min: 20,
                      max: 4000,
                      label: '${freq.round()} Hz',
                      onChanged: (v) => setDialog(() => freq = v),
                    ),
                  ],
                  // A sweep needs somewhere to sweep TO.
                  if (sweeping)
                    Slider(
                      value: endFreq,
                      min: 40,
                      max: 20000,
                      label: '${endFreq.round()} Hz',
                      onChanged: (v) => setDialog(() => endFreq = v),
                    ),
                  Text('${l10n.dawLength} ${seconds.toStringAsFixed(1)} s'),
                  Slider(
                    value: seconds,
                    min: 0.1,
                    max: 30,
                    onChanged: (v) => setDialog(() => seconds = v),
                  ),
                  if (shape != GeneratorShape.silence) ...[
                    Text('${l10n.dawLevel} ${(amp * 100).round()}%'),
                    Slider(
                      value: amp,
                      onChanged: (v) => setDialog(() => amp = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.dawCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.dawAmplifyApply),
              ),
            ],
          );
        },
      ),
    );
    if (made != true) return;
    generateClip(
      shape: shape,
      freq: freq,
      endFreq: endFreq,
      seconds: seconds,
      amp: amp,
    );
  }

  /// Ocenaudio's "Amplify": pick a gain in dB and bake it into the clip.
  Future<void> _amplifyClipDialog(int track, int index) async {
    final l10n = AppLocalizations.of(context)!;
    var db = 3.0;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(l10n.dawAmplify),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB'),
                Slider(
                  value: db,
                  min: -24,
                  max: 24,
                  divisions: 96,
                  label: '${db.toStringAsFixed(1)} dB',
                  onChanged: (value) => setDialog(() => db = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.dawAmplifyApply),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    amplifyClip(track, index, db);
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

  void _silenceMarkedRange() {
    if (!_hasFxRange) return;
    silenceRange(_rangeTargetTracks(), _rangeStartMs, _rangeEndMs);
    if (_playing) play();
  }

  void _cropToMarkedRange() {
    if (!_hasFxRange) return;
    cropToRange(_rangeTargetTracks(), _rangeStartMs, _rangeEndMs);
    if (_playing) play();
  }

  /// D1 — remove the marked span AND the time it occupied.
  ///
  /// Deliberately not scoped to the selected lanes, unlike its neighbours in
  /// this menu: rippling some lanes and not others slides the arrangement out
  /// of sync with itself. "Just here" is what Silence is for.
  void _rippleDeleteMarkedRange() {
    if (!_hasFxRange) return;
    _daw.rippleDelete(_rangeStartMs, _rangeEndMs);
    setState(() {});
    if (_playing) play();
  }

  /// D1 — open the marked span as empty time, sliding everything after it.
  void _rippleInsertMarkedRange() {
    if (!_hasFxRange) return;
    _daw.rippleInsert(_rangeStartMs, _rangeEndMs - _rangeStartMs);
    setState(() {});
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

  List<DawAutomationPoint> _projectRangeAutomationPoints(
    double startValue,
    double endValue,
  ) =>
      [
        DawAutomationPoint(ms: _rangeStartMs, value: startValue),
        DawAutomationPoint(ms: _rangeEndMs, value: endValue),
      ];

  List<DawAutomationPoint> _clipRangeAutomationPoints(
    int track,
    int index,
    double startValue,
    double endValue,
  ) {
    final clipStart = _daw.clipStartMs(track, index);
    final clipEnd = clipStart + _daw.clipDurationMs(track, index);
    final from = math.max(_rangeStartMs, clipStart);
    final to = math.min(_rangeEndMs, clipEnd);
    if (to <= from) return const [];
    return [
      DawAutomationPoint(ms: from - clipStart, value: startValue),
      DawAutomationPoint(ms: to - clipStart, value: endValue),
    ];
  }

  Widget _fxTile(
    BuildContext ctx, {
    required List<DawClipEffect> effects,
    required int fxIndex,
    required VoidCallback onToggle,
    required void Function(int delta) onMove,
    required VoidCallback onRemove,
    required void Function(String key, double value) onParam,
    Future<void> Function(String key, double startValue, double endValue)?
        onAutomate,
    Future<void> Function(String key, List<DawAutomationPoint> points)?
        onSetAutomation,
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
            automation: fx.automation[spec.key] ?? const [],
            (v) => onParam(spec.key, v),
            onAutomate: onAutomate == null || !_hasFxRange
                ? null
                : () async {
                    final current = fx.params[spec.key] ??
                        defaultDawClipEffect(fx.type).params[spec.key] ??
                        spec.min;
                    final values = await _fxAutomationDialog(
                      ctx,
                      label: spec.label,
                      min: spec.min,
                      max: spec.max,
                      step: spec.step,
                      startValue: current,
                      endValue: current,
                    );
                    if (values == null) return;
                    await onAutomate(
                      spec.key,
                      values.startValue,
                      values.endValue,
                    );
                  },
            onEditAutomation: onSetAutomation == null ||
                    (fx.automation[spec.key] ?? const []).isEmpty
                ? null
                : () async {
                    final points = fx.automation[spec.key] ?? const [];
                    final edited = await _fxAutomationPointsDialog(
                      ctx,
                      label: spec.label,
                      min: spec.min,
                      max: spec.max,
                      step: spec.step,
                      points: points,
                    );
                    if (edited == null) return;
                    await onSetAutomation(spec.key, edited);
                  },
            onClearAutomation: onSetAutomation == null ||
                    (fx.automation[spec.key] ?? const []).isEmpty
                ? null
                : () async => onSetAutomation(spec.key, const []),
          ),
      ],
    );
  }

  /// D5 — audition the alternative takes of a clip, and fold parallel clips in
  /// as more of them.
  ///
  /// Switching plays immediately rather than on a confirm: the whole reason to
  /// keep alternatives is comparing them by ear, and a dialog that only commits
  /// on OK makes that a chore. The sheet stays open for the same reason.
  Future<void> _pickTake(int track, int index) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final count = _daw.takeCount(track, index);
          final active = _daw.activeTake(track, index);
          // Clips that overlap this one in time are the ones plausibly being
          // ANOTHER PASS at the same passage — the only ones worth offering to
          // stack, and the workflow lanes of takes come from.
          final candidates = _overlappingClips(track, index);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text('Takes', style: Theme.of(sheetCtx).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (count <= 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'One take. Record the part again on another lane, then '
                      'stack it here to compare them.',
                    ),
                  )
                else
                  RadioGroup<int>(
                    groupValue: active,
                    onChanged: (chosen) {
                      if (chosen == null) return;
                      _daw.selectTake(track, index, chosen);
                      setSheet(() {});
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < count; i++)
                          RadioListTile<int>(
                            value: i,
                            title: Text('Take ${i + 1}'),
                          ),
                      ],
                    ),
                  ),
                if (candidates.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Stack in as another take',
                    style: Theme.of(sheetCtx).textTheme.labelLarge,
                  ),
                  for (final candidate in candidates)
                    ListTile(
                      leading: const Icon(Icons.layers),
                      title: Text(
                        'Lane ${candidate.track + 1} · '
                        '${_clipKind(_daw.timeline.tracks[candidate.track].clips[candidate.index])} '
                        'at ${_daw.timeline.tracks[candidate.track].clips[candidate.index].startMs.round()} ms',
                      ),
                      subtitle: const Text('Moves it in — undoable'),
                      onTap: () {
                        _daw.stackAsTake(
                          track,
                          index,
                          candidate.track,
                          candidate.index,
                        );
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Clips elsewhere on the timeline whose played window overlaps this one's.
  List<({int track, int index})> _overlappingClips(int track, int index) {
    if (index >= _daw.timeline.tracks[track].clips.length) return const [];
    final start = _daw.timeline.tracks[track].clips[index].startMs;
    final end = start + _daw.clipDurationMs(track, index);
    final out = <({int track, int index})>[];
    for (var t = 0; t < _daw.timeline.tracks.length; t++) {
      final clips = _daw.timeline.tracks[t].clips;
      for (var i = 0; i < clips.length; i++) {
        if (t == track && i == index) continue;
        final otherStart = clips[i].startMs;
        final otherEnd = otherStart + _daw.clipDurationMs(t, i);
        if (otherStart < end && otherEnd > start) {
          out.add((track: t, index: i));
        }
      }
    }
    return out;
  }

  /// D3 — draw a gain envelope over one clip.
  ///
  /// Seeded with a flat line across the clip when it has none, because the
  /// shared points dialog edits an EXISTING curve and returns null for an empty
  /// one — there would otherwise be no way to make a first envelope.
  Future<void> _editClipEnvelope(int track, int index) async {
    final existing = _daw.clipGainAutomation(track, index);
    final duration = _daw.clipDurationMs(track, index);
    final seeded = existing.isNotEmpty
        ? existing
        : [
            const DawAutomationPoint(ms: 0, value: 1),
            DawAutomationPoint(ms: math.max(duration, 1), value: 1),
          ];
    final edited = await _fxAutomationPointsDialog(
      context,
      label: 'clip gain',
      min: 0,
      max: 2,
      // A gain multiplier reads in hundredths; the same step the mix and gain
      // sliders use.
      step: 0.01,
      points: seeded,
    );
    if (edited == null) return;
    _daw.setClipGainAutomation(track, index, edited);
    if (_playing) play();
  }

  Future<List<DawAutomationPoint>?> _fxAutomationPointsDialog(
    BuildContext ctx, {
    required String label,
    required double min,
    required double max,
    required double step,
    required List<DawAutomationPoint> points,
  }) async {
    if (points.isEmpty) return null;
    final edited = [...points]..sort((a, b) => a.ms.compareTo(b.ms));
    for (var i = 0; i < edited.length; i++) {
      edited[i] = edited[i].copyWith(
        value: edited[i].value.clamp(min, max).toDouble(),
      );
    }
    final timeMax = math
        .max(
          edited.last.ms,
          math.max(_rangeEndMs, 1000),
        )
        .toDouble();
    return showDialog<List<DawAutomationPoint>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) => AlertDialog(
          title: Text('Edit $label automation'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Draw the shape; the numeric list below stays for precise
                  // values and for anyone who can't drag.
                  AutomationCurveEditor(
                    points: edited,
                    min: min,
                    max: max,
                    timeMax: timeMax,
                    onChanged: (next) => setDialog(() {
                      edited
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(dialogCtx)!.dawCurveHint,
                    style: Theme.of(dialogCtx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text('${edited.length} points'),
                  const SizedBox(height: 8),
                  for (var index = 0; index < edited.length; index++)
                    _automationPointEditor(
                      point: edited[index],
                      index: index,
                      count: edited.length,
                      min: min,
                      max: max,
                      step: step,
                      timeMax: timeMax,
                      onChanged: (point) => setDialog(() {
                        edited[index] = point;
                        edited.sort((a, b) => a.ms.compareTo(b.ms));
                      }),
                      onRemove: edited.length <= 2
                          ? null
                          : () => setDialog(() => edited.removeAt(index)),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setDialog(() {
                      var gapIndex = 0;
                      var gap = -1.0;
                      for (var i = 0; i < edited.length - 1; i++) {
                        final candidate = edited[i + 1].ms - edited[i].ms;
                        if (candidate > gap) {
                          gap = candidate;
                          gapIndex = i;
                        }
                      }
                      final left = edited[gapIndex];
                      final right = edited[gapIndex + 1];
                      edited.insert(
                        gapIndex + 1,
                        DawAutomationPoint(
                          ms: (left.ms + right.ms) / 2,
                          value: (left.value + right.value) / 2,
                          curve: left.curve,
                        ),
                      );
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Add point'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(AppLocalizations.of(dialogCtx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () {
                edited.sort((a, b) => a.ms.compareTo(b.ms));
                Navigator.of(dialogCtx).pop(edited);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _automationPointEditor({
    required DawAutomationPoint point,
    required int index,
    required int count,
    required double min,
    required double max,
    required double step,
    required double timeMax,
    required ValueChanged<DawAutomationPoint> onChanged,
    required VoidCallback? onRemove,
  }) {
    final timeLabel = index == 0
        ? 'Start ms'
        : index == count - 1
            ? 'End ms'
            : 'Point ${index + 1} ms';
    final valueLabel = index == 0
        ? 'Start value'
        : index == count - 1
            ? 'End value'
            : 'Point ${index + 1} value';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Point ${index + 1}')),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove point',
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
              ),
          ],
        ),
        _effectParamSlider(
          timeLabel,
          point.ms.clamp(0, timeMax).toDouble(),
          0,
          timeMax,
          1,
          (value) => onChanged(point.copyWith(ms: value)),
        ),
        _effectParamSlider(
          valueLabel,
          point.value,
          min,
          max,
          step,
          (value) => onChanged(point.copyWith(value: value)),
        ),
        if (index < count - 1)
          DropdownButtonFormField<DawFadeCurve>(
            initialValue: point.curve,
            decoration: const InputDecoration(labelText: 'Curve'),
            items: [
              for (final curve in DawFadeCurve.values)
                DropdownMenuItem(
                  value: curve,
                  child: Text(_fadeCurveLabel(curve)),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(point.copyWith(curve: value));
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<({double startValue, double endValue})?> _fxAutomationDialog(
    BuildContext ctx, {
    required String label,
    required double min,
    required double max,
    required double step,
    required double startValue,
    required double endValue,
  }) async {
    var start = startValue.clamp(min, max).toDouble();
    var end = endValue.clamp(min, max).toDouble();
    return showDialog<({double startValue, double endValue})>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) => AlertDialog(
          title: Text('Automate $label'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel()),
                const SizedBox(height: 8),
                _effectParamSlider(
                  'Start',
                  start,
                  min,
                  max,
                  step,
                  (value) => setDialog(() => start = value),
                ),
                _effectParamSlider(
                  'End',
                  end,
                  min,
                  max,
                  step,
                  (value) => setDialog(() => end = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(AppLocalizations.of(dialogCtx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(
                (startValue: start, endValue: end),
              ),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _effectParamSlider(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged, {
    List<DawAutomationPoint> automation = const [],
    VoidCallback? onAutomate,
    Future<void> Function()? onEditAutomation,
    Future<void> Function()? onClearAutomation,
  }) {
    String fmt(double v) =>
        step >= 1 ? v.round().toString() : v.toStringAsFixed(2);
    String fmtMs(double v) => '${v.round()} ms';
    final automatedPoints = automation.length;
    final automationCurve =
        automation.isEmpty ? DawFadeCurve.linear : automation.first.curve;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                automatedPoints > 0
                    ? '$label — ${fmt(value)} · $automatedPoints auto'
                    : '$label — ${fmt(value)}',
              ),
            ),
            if (onAutomate != null)
              TextButton(
                onPressed: onAutomate,
                child: const Text('Auto'),
              ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions:
              step > 0 ? ((max - min) / step).round().clamp(1, 1000) : null,
          label: fmt(value),
          onChanged: onChanged,
        ),
        if (automation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$label automation: '
                        '${fmtMs(automation.first.ms)} ${fmt(automation.first.value)}'
                        ' → ${fmtMs(automation.last.ms)} ${fmt(automation.last.value)}'
                        ' · ${_fadeCurveLabel(automationCurve)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: onEditAutomation == null
                          ? null
                          : () async => onEditAutomation(),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: onClearAutomation == null
                          ? null
                          : () async => onClearAutomation(),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ),
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
    final right = clip.right == null
        ? null
        : clip.sampleRate == kDawSampleRate
            ? clip.right
            : resampleCubic(clip.right!, clip.sampleRate / kDawSampleRate);
    // A fresh lane so a dropped-in sample never lands on top of another clip.
    _daw.addClip(
      right == null
          ? SampleSource(pcm, key: 'sample:${clip.name}')
          : StereoSampleSource(pcm, right, key: 'sample:${clip.name}'),
      track: _daw.timeline.tracks.length,
      // Carry the licence in with the audio. This is the point where an
      // imported work's obligation either attaches or is lost forever — the
      // export gate can only enforce what arrived here. A clip with no declared
      // licence (the user's own recording, or a file off their disk) carries
      // nothing, which is correct: it owes nothing.
      provenance: _provenanceOf(clip),
    );
  }

  /// A [SampleClip]'s licence, as a [LicensedWork] — or null when it doesn't
  /// declare one.
  LicensedWork? _provenanceOf(SampleClip clip) {
    final license = clip.license?.trim() ?? '';
    if (license.isEmpty) return null;
    return LicensedWork(
      title: clip.name,
      license: license,
      source: clip.source,
      url: clip.sourceUrl,
    );
  }

  /// Picks a sample from the shared "My Samples" library and arranges it.
  Future<void> addSample() async {
    final clip = await showMySamplesSheet(
      context,
      onCatalogSampleInsert: (clip) async => addSampleClip(clip),
      preferCatalogSampleInsert: true,
      onSampleInsert: (clip) async => addSampleClip(clip),
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
      final imported = await importAudioAsync(await file.readAsBytes());
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
          right: imported.right,
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
    final picked = await showMusicPickerWithLicense(context);
    if (picked == null || !mounted) return;
    _daw.addClip(
      ScoreSource(picked.score),
      track: _daw.timeline.tracks.length,
      // Music from the library carries its licence in with the notes, the same
      // way an imported sample does.
      provenance: picked.provenance,
    );
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
  void normalizeClip(int track, int index) => _daw.normalizeClip(track, index);

  @override
  void invertClip(int track, int index) => _daw.invertClip(track, index);

  @override
  void removeClipDcOffset(int track, int index) =>
      _daw.removeClipDcOffset(track, index);

  @override
  void trimSilenceFromClip(int track, int index) =>
      _daw.trimSilenceFromClip(track, index);

  @override
  void amplifyClip(int track, int index, double db) =>
      _daw.amplifyClip(track, index, db);

  @override
  int silenceRange(Iterable<int> tracks, double startMs, double endMs) =>
      _daw.silenceRange(tracks, startMs, endMs);

  @override
  int cropToRange(Iterable<int> tracks, double startMs, double endMs) =>
      _daw.cropToRange(tracks, startMs, endMs);

  @override
  ClipStats clipStats(int track, int index) => _daw.clipStats(track, index);

  @override
  int moveClipToTrack(
    int fromTrack,
    int index,
    int toTrack, {
    double? startMs,
  }) {
    final at = _daw.moveClipToTrack(
      fromTrack,
      index,
      toTrack,
      startMs: startMs,
    );
    if (at >= 0) {
      // The selection points at (track, index) pairs that just moved.
      setState(_selectedClips.clear);
      if (_playing) play();
    }
    return at;
  }

  @override
  Float64List bakeTrack(int track) => _daw.bakeTrack(track);

  @override
  void generateClip({
    required GeneratorShape shape,
    double freq = 440,
    double endFreq = 20000,
    double seconds = 2,
    double amp = 0.5,
  }) {
    _daw.addGeneratedClip(
      shape: shape,
      freq: freq,
      endFreq: endFreq,
      seconds: seconds,
      amp: amp,
    );
    if (_playing) play();
  }

  @override
  double get pxPerSecond => _pxPerSecond;

  @override
  void zoomIn() => setState(
        () => _zoom = math.min(_maxZoom, _zoom * _zoomStep),
      );

  @override
  void zoomOut() => setState(
        () => _zoom = math.max(_minZoom, _zoom / _zoomStep),
      );

  @override
  void zoomToFit() {
    final seconds = _arrangementMs / 1000;
    if (seconds <= 0) {
      setState(() => _zoom = 1);
      return;
    }
    // Fit the arrangement into the lane viewport: the screen minus the track
    // gutter and the timeline's own padding.
    final available = MediaQuery.of(context).size.width - _gutterWidth - 48;
    if (available <= 0) return;
    setState(
      () => _zoom = (available / seconds / _basePxPerSecond)
          .clamp(_minZoom, _maxZoom)
          .toDouble(),
    );
  }

  @override
  bool get loopsMarkedRange => _loop && _hasFxRange;

  @override
  bool get isRecording => _recording;

  /// O14 — capture a mic take straight onto its own lane. The recorder is the
  /// Tracker's `VoiceClipRecorder` (the app's single mic-facing capture path);
  /// it can't run under the headless test binding, so this is guarded and
  /// tests go through [debugAddRecordedClip] instead.
  @override
  Future<void> recordClip() async {
    if (_recording) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _recording = true);
    try {
      final pcm = await _recorder.record(
        maxDuration: const Duration(seconds: 10),
      );
      if (!mounted) return;
      if (pcm.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.dawRecordFailed)),
        );
        return;
      }
      debugAddRecordedClip(pcm);
    } catch (_) {
      // No mic, denied permission, unsupported encoder — all one message.
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.dawRecordFailed)));
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  void debugAddRecordedClip(Float64List pcm) {
    if (pcm.isEmpty) return;
    // The recorder captures at the synth rate and the timeline runs at its own.
    // They're the same today, but converting explicitly means a future change
    // to either constant can't silently detune every recorded take.
    // (resampleLinear's ratio is a playback-SPEED multiplier: capture/playback.)
    const ratio = kSampleRate / kDawSampleRate;
    _daw.addRecordedClip(ratio == 1.0 ? pcm : resampleLinear(pcm, ratio));
    if (_playing) play();
  }

  @override
  ({double peak, double rms}) get playbackLevel {
    final pcm = _bakedPcm;
    if (!_playing || pcm == null || pcm.isEmpty) return (peak: 0, rms: 0);
    // Measure the ~23 ms just played: short enough to track a transient, long
    // enough that the RMS number doesn't flicker.
    const window = 1024;
    final at = (_positionMs.value * kDawSampleRate / 1000).round();
    final to = at.clamp(1, pcm.length);
    final from = math.max(0, to - window);
    if (to <= from) return (peak: 0, rms: 0);
    final s = clipStatsOf(
      Float64List.sublistView(pcm, from, to),
      null,
      sampleRate: kDawSampleRate,
    );
    return (peak: s.peak, rms: s.rms);
  }

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

  static const _clipEffectTypes = kDawClipEffectTypes;

  /// The effect's name, from the shared FX registry.
  ///
  /// This used to be a hand-written switch over every [FxType], duplicating
  /// `fxTypeLabel`. Two tables of the same facts means a new effect compiles
  /// everywhere except here — which is exactly how it went: each effect added to
  /// the rack turned CI red on this file until someone remembered. The registry
  /// is the single source, so a new effect now appears in the panel by itself.
  String _clipEffectLabel(DawClipEffectType type) => fxTypeLabel(type);

  String _clipEffectPresetLabel(DawClipEffectPreset preset) => switch (preset) {
        DawClipEffectPreset.vocalPolish => 'Vocal Polish',
        DawClipEffectPreset.lofiCrunch => 'Lo-fi Crunch',
        DawClipEffectPreset.wideSpace => 'Wide Space',
        DawClipEffectPreset.robotVoice => 'Robot Voice',
      };

  /// The editable params of [type], as the panel's sliders want them — derived
  /// from the shared registry (range, unit, integer-ness) rather than tabulated
  /// here, for the same reason as [_clipEffectLabel].
  ///
  /// Where the two tables disagreed, the wider range won and was merged BACK
  /// into the registry (a level fader reaching -60 dB, a notch's Q reaching 20),
  /// so this is not a narrowing — and the CLI now offers exactly what the
  /// sliders do.
  List<({String key, String label, double min, double max, double step})>
      _clipEffectParams(DawClipEffectType type) => [
            for (final spec in fxParamSpecs(type))
              (
                key: spec.key,
                label: fxParamCaption(spec),
                min: spec.min,
                max: spec.max,
                step: fxSliderStep(spec),
              ),
          ];

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
  void setClipPan(int track, int index, double pan) =>
      _daw.setClipPan(track, index, pan);

  @override
  double clipPan(int track, int index) => _daw.clipPan(track, index);

  @override
  void setClipWidth(int track, int index, double width) =>
      _daw.setClipWidth(track, index, width);

  @override
  double clipWidth(int track, int index) => _daw.clipWidth(track, index);

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
    _bakedPcm = pcm; // O12 — the meters read the mix that's actually sounding
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
    _transport
      ?..syncTo(_seekMs)
      ..play();
    setState(() => _playing = true);
  }

  @override
  void stop() {
    _ticker.stop();
    _positionMs.value = _seekMs; // rest at the seek marker
    _audio.stop();
    // pause, not stop: the shared transport's stop() would rewind to 0 or the
    // loop start, and this transport rests at the seek marker by design.
    _transport
      ?..pause()
      ..syncTo(_seekMs);
    setState(() => _playing = false);
  }

  /// Move the play start (and the resting playhead) to [ms] on the timeline.
  @override
  void seekTo(double ms) {
    _seekMs = ms < 0 ? 0 : ms;
    _positionMs.value = _seekMs;
    _transport?.syncTo(_seekMs);
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
  /// Batch stems: one file per lane, into a folder. Which lanes depends on
  /// [onlySelected] — the gutter selection, or everything with audio on it.
  Future<void> _exportStems({required bool onlySelected}) async {
    final lanes = [
      for (var t = 0; t < _daw.timeline.tracks.length; t++)
        if (!onlySelected || _selectedTracks.contains(t)) t,
    ];
    final stems = <AudioStem>[];
    for (final t in lanes) {
      final stereo = _daw.bakeTrackStereo(t);
      if (stereo.left.isEmpty) continue; // silent/empty lane — nothing to write
      stems.add(
        AudioStem(
          name: _daw.timeline.tracks[t].name.isEmpty
              ? '${t + 1}'
              : _daw.timeline.tracks[t].name,
          pcm: stereo.left,
          right: stereo.right,
        ),
      );
    }
    await showAudioStemsExportSheet(
      context,
      stems: stems,
      baseName: _exportBaseName(),
    );
  }

  Future<void> _export() async {
    final fullMix = _daw.bakeStereo();
    if (fullMix.left.isEmpty) {
      await showAudioExportSheet(
        context,
        pcm: fullMix.left,
        baseName: _exportBaseName(),
      );
      return;
    }
    var useRange = false;
    var normalize = false;
    // null = the full mix; otherwise the lane to export on its own (a stem).
    int? stemTrack;
    final rangeAvailable = _hasFxRange;

    // A stem skips the master limiter, so stems sum back to the mix instead of
    // each arriving separately mastered.
    DawStereoMix source() =>
        stemTrack == null ? fullMix : _daw.bakeTrackStereo(stemTrack!);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final pcm = source().left;
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
                  // What to export: everything, or one lane on its own.
                  DropdownButton<int?>(
                    value: stemTrack,
                    isExpanded: true,
                    onChanged: (v) => setDialog(() => stemTrack = v),
                    items: [
                      DropdownMenuItem(
                        child: Text(AppLocalizations.of(ctx)!.dawExportFullMix),
                      ),
                      for (var t = 0; t < _daw.timeline.tracks.length; t++)
                        DropdownMenuItem(
                          value: t,
                          child: Text(
                            AppLocalizations.of(ctx)!.dawExportTrackOnly(
                              _daw.timeline.tracks[t].name.isEmpty
                                  ? '${t + 1}'
                                  : _daw.timeline.tracks[t].name,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      // This picks the time WINDOW; the dropdown above picks
                      // the SOURCE. Calling both "Full mix" was ambiguous.
                      const ButtonSegment(
                        value: false,
                        label: Text('Whole length'),
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
                  Text(
                    stemTrack == null
                        ? 'Whole length: ${_exportSummary(pcm)}'
                        : 'This track: ${_exportSummary(pcm)}',
                  ),
                  Text(
                    rangeAvailable
                        ? 'Marked range: ${_exportSummary(_exportRangePcm(pcm))}'
                        : 'Marked range: Set Mark In and Mark Out first',
                  ),
                  const SizedBox(height: 8),
                  // Licence obligations from the clips actually in the mix.
                  // Shown BEFORE the format chooser: a share-alike notice that
                  // only appears after the file is written is too late.
                  Builder(
                    builder: (licCtx) {
                      final ob = _daw.licenseObligations();
                      if (ob.isClear) return const SizedBox.shrink();
                      final scheme = Theme.of(licCtx).colorScheme;
                      final small = Theme.of(licCtx).textTheme.bodySmall;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ob.hasProblem
                                ? scheme.errorContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final c in ob.conflicts)
                                Text(
                                  c,
                                  style: small?.copyWith(
                                    color: scheme.onErrorContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              for (final b in ob.blocking)
                                Text(
                                  '${AppLocalizations.of(licCtx)!.dawExportBlocked}'
                                  ': ${b.creditLine}',
                                  style: small?.copyWith(
                                    color: scheme.onErrorContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (ob.noticeText().isNotEmpty)
                                Text(ob.noticeText(), style: small),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
              // Batch stems: one file per lane, in one go.
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(
                  _selectedTracks.isEmpty ? 'stemsAll' : 'stemsSelected',
                ),
                child: Text(
                  _selectedTracks.isEmpty
                      ? AppLocalizations.of(ctx)!.dawExportStemsAll
                      : AppLocalizations.of(ctx)!.dawExportStemsSelected,
                ),
              ),
              FilledButton(
                // Refuse when the mix can't lawfully be exported (incompatible
                // copyleft, or NC/unstated material in it) — the point of
                // computing obligations is that they can say no.
                onPressed:
                    selected.isEmpty || _daw.licenseObligations().hasProblem
                        ? null
                        : () => Navigator.of(ctx).pop('export'),
                child: const Text('Choose format'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'stemsAll' || action == 'stemsSelected') {
      await _exportStems(onlySelected: action == 'stemsSelected');
      return;
    }
    if (action != 'export') return;
    final chosen = source();
    final selected = useRange ? _exportRangePcm(chosen.left) : chosen.left;
    final selectedRight =
        useRange ? _exportRangePcm(chosen.right) : chosen.right;
    final exportPcm = normalize ? _normalizeExportPcm(selected) : selected;
    final exportRight =
        normalize ? _normalizeExportPcm(selectedRight) : selectedRight;
    await showAudioExportSheet(
      context,
      pcm: exportPcm,
      rightPcm: exportRight,
      baseName: _exportBaseName(
        range: useRange,
        stem: stemTrack == null ? null : _daw.timeline.tracks[stemTrack!].name,
      ),
      // Bounded-memory save for the plain full mix (no stem/range/normalize):
      // the sheet streams the WAV straight to disk for the native-rate/16-bit
      // case instead of holding the whole file in RAM. Falls back to the baked
      // [exportPcm] above for every other choice (and on web).
      wavStreamProducer: (stemTrack == null && !useRange && !normalize)
          ? (sink) => streamTimelineWav(_daw.timeline, onBytes: sink)
          : null,
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

  String _exportBaseName({bool range = false, String? stem}) {
    final active = [
      for (final track in _daw.timeline.tracks)
        if (track.clips.isNotEmpty) track.name,
    ];
    final title = active.isEmpty ? 'audio-editor' : active.take(3).join('-');
    String slugify(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final slug = slugify(title);
    final stemSlug = stem == null ? '' : slugify(stem);
    return [
      if (slug.isEmpty) 'audio-editor' else slug,
      // A stem's filename has to say which lane it is, or four exports land in
      // the folder as indistinguishable siblings.
      if (stem != null) 'stem',
      if (stem != null) (stemSlug.isEmpty ? 'track' : stemSlug),
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
                    // Make the editor round-trip explicit: this clip is linked to
                    // the notation editors, so edits sent back update it in place.
                    if (_daw.isScoreClip(track, index))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.link,
                              size: 15,
                              color: Theme.of(sheetCtx).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.dawClipLinked,
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(sheetCtx)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                  Text(
                                    l10n.dawClipLinkedHint,
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(sheetCtx)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
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
                      'Clip Pan',
                      (_daw.clipPan(track, index) + 1) / 2,
                      1,
                      (v) => (v * 2 - 1).abs() < 0.01
                          ? 'Centre'
                          : v < 0.5
                              ? 'L ${((0.5 - v) * 200).round()}%'
                              : 'R ${((v - 0.5) * 200).round()}%',
                      (v) => _daw.setClipPan(track, index, v * 2 - 1),
                    ),
                    slider(
                      'Stereo Width',
                      _daw.clipWidth(track, index),
                      2,
                      (v) => v < 0.01
                          ? 'Mono'
                          : v < 0.01 + 0.99
                              ? '${(v * 100).round()}%'
                              : '${(v * 100).round()}% wide',
                      (v) => _daw.setClipWidth(track, index, v),
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
                    // O10 — what the audio actually measures. Peak/RMS are
                    // technical units (like dBFS/Hz), so they aren't translated.
                    const SizedBox(height: 12),
                    Builder(
                      builder: (statsCtx) {
                        final s = clipStats(track, index);
                        final small = Theme.of(statsCtx).textTheme.bodySmall;
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${(s.durationMs / 1000).toStringAsFixed(2)} s'
                                ' · ${s.channels == 2 ? 'stereo' : 'mono'}'
                                ' · peak ${s.peakDb.toStringAsFixed(1)} dBFS'
                                ' · RMS ${s.rmsDb.toStringAsFixed(1)} dBFS',
                                style: small,
                              ),
                            ),
                            if (s.clippedSamples > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  l10n.dawStatsClipping,
                                  style: small?.copyWith(
                                    color: Theme.of(statsCtx).colorScheme.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
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
                        onAutomate: (key, startValue, endValue) async {
                          final points = _clipRangeAutomationPoints(
                            track,
                            index,
                            startValue,
                            endValue,
                          );
                          if (points.isEmpty) return;
                          setSheet(() {
                            _daw.setClipEffectAutomation(
                              track,
                              index,
                              fxIndex,
                              key,
                              points,
                            );
                          });
                          if (_playing) play();
                        },
                        onSetAutomation: (key, points) async {
                          setSheet(() {
                            _daw.setClipEffectAutomation(
                              track,
                              index,
                              fxIndex,
                              key,
                              points,
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
                        // The same door for a clip that came from the Tracker.
                        // It still holds the song, so this hands back the very
                        // document — no conversion, nothing approximated.
                        if (_daw.isTrackerClip(track, index))
                          TextButton.icon(
                            onPressed: () {
                              final song = _daw.clipTrackerSong(track, index);
                              final source = _daw.clipSourceAt(track, index);
                              Navigator.of(sheetCtx).pop();
                              if (song != null) {
                                openTrackerSong(
                                  context,
                                  song,
                                  onReturn: (edited) => _daw
                                      .replaceTrackerClipSource(source, edited),
                                );
                              }
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: Text(l10n.dawOpenInEditor),
                          ),
                        // C2 — the same door for the two kinds that never had
                        // one. A beat sent from the Drum Kit and a groove sent
                        // from the Loop Mixer still hold their grid and their
                        // spec, so this is exact retrieval like the tracker
                        // case: nothing is transcribed, nothing approximated.
                        if (_daw.isDrumClip(track, index))
                          TextButton.icon(
                            onPressed: () {
                              final pattern =
                                  _daw.clipDrumPattern(track, index);
                              final timing = _daw.clipDrumTiming(track, index);
                              final source = _daw.clipSourceAt(track, index);
                              Navigator.of(sheetCtx).pop();
                              if (pattern != null) {
                                openDrumPattern(
                                  context,
                                  pattern,
                                  timing: timing,
                                  onReturn: (edited, editedTiming) =>
                                      _daw.replaceDrumClipSource(
                                    source,
                                    edited,
                                    editedTiming,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: Text(l10n.dawOpenInEditor),
                          ),
                        if (_daw.isGrooveClip(track, index))
                          TextButton.icon(
                            onPressed: () {
                              final spec = _daw.clipGroove(track, index);
                              final source = _daw.clipSourceAt(track, index);
                              Navigator.of(sheetCtx).pop();
                              if (spec != null) {
                                openGroove(
                                  context,
                                  spec,
                                  onReturn: (edited) => _daw
                                      .replaceGrooveClipSource(source, edited),
                                );
                              }
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: Text(l10n.dawOpenInEditor),
                          ),
                        // The cross-mode door: a COPY, converted, with its
                        // cost named before it runs. Null for a clip whose
                        // model no other editor can hold (a recording).
                        if (_openACopyIn(sheetCtx, track, index)
                            case final openIn?)
                          openIn,
                        // The in-place twin: convert, edit in the other editor,
                        // and the edit REPLACES this clip (it becomes the edited
                        // mode) so mixing continues on it. Same loss warning; the
                        // replacement is undoable.
                        if (_openAndReplaceIn(sheetCtx, track, index)
                            case final replaceIn?)
                          replaceIn,
                        // C5 — the way back for a raw recording: no symbolic
                        // model to convert, so transcribe its audio onto a new
                        // notation clip (the audio stays).
                        if (_transcribeAction(sheetCtx, track, index)
                            case final transcribe?)
                          transcribe,
                        // D3 — ride the level across THIS take without
                        // splitting it. Distinct from the lane automation in
                        // the track menu: that one is anchored to the timeline,
                        // this shape moves with the clip.
                        TextButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            await _editClipEnvelope(track, index);
                          },
                          icon: const Icon(Icons.show_chart),
                          label: const Text('Clip envelope'),
                        ),
                        // WS-A7 — follow the project tempo. Offered only when
                        // the clip can actually say what tempo it is IN:
                        // without that there is nothing to warp FROM, and a
                        // switch that silently does nothing is worse than an
                        // absent one.
                        TextButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            await _toggleClipWarp(track, index);
                          },
                          icon: Icon(
                            _daw.clipWarps(track, index)
                                ? Icons.link
                                : Icons.link_off,
                          ),
                          label: Text(
                            _daw.clipWarps(track, index)
                                ? 'Following tempo '
                                    '(${_daw.clipNativeBpm(track, index)?.round()} BPM)'
                                : 'Follow project tempo',
                          ),
                        ),
                        // WS-A9 — which stretch a warp uses. Only shown when
                        // the clip actually warps: it is meaningless otherwise,
                        // and an inert control teaches people to ignore the
                        // panel.
                        if (_daw.clipWarps(track, index))
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.of(sheetCtx).pop();
                              await _pickWarpQuality(track, index);
                            },
                            icon: const Icon(Icons.graphic_eq),
                            label: Text(
                              'Stretch: '
                              '${_daw.clipWarpQuality(track, index).name}',
                            ),
                          ),
                        // D5 — the alternative takes. The count is on the
                        // label because which take is playing is otherwise
                        // invisible on the timeline.
                        TextButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            await _pickTake(track, index);
                          },
                          icon: const Icon(Icons.layers),
                          label: Text(
                            _daw.takeCount(track, index) > 1
                                ? 'Takes '
                                    '(${_daw.activeTake(track, index) + 1}'
                                    '/${_daw.takeCount(track, index)})'
                                : 'Takes',
                          ),
                        ),
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
                        // Destructive amplitude tools (bake the clip): normalize
                        // to a peak target, flip phase, strip a DC offset.
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            normalizeClip(track, index);
                          },
                          icon: const Icon(Icons.vertical_align_center),
                          label: Text(l10n.dawNormalize),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            invertClip(track, index);
                          },
                          icon: const Icon(Icons.swap_vert),
                          label: Text(l10n.dawInvertPhase),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            removeClipDcOffset(track, index);
                          },
                          icon: const Icon(Icons.horizontal_rule),
                          label: Text(l10n.dawRemoveDc),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            trimSilenceFromClip(track, index);
                          },
                          icon: const Icon(Icons.content_cut),
                          label: Text(l10n.dawTrimSilence),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            _amplifyClipDialog(track, index);
                          },
                          icon: const Icon(Icons.graphic_eq),
                          label: Text(l10n.dawAmplify),
                        ),
                        // Move to another lane — the reliable path when a
                        // long-press drag is fiddly (phones, precise moves).
                        if (_daw.timeline.tracks.length > 1)
                          MenuAnchor(
                            menuChildren: [
                              for (var t = 0;
                                  t < _daw.timeline.tracks.length;
                                  t++)
                                if (t != track)
                                  MenuItemButton(
                                    onPressed: () {
                                      Navigator.of(sheetCtx).pop();
                                      moveClipToTrack(track, index, t);
                                    },
                                    leadingIcon: const Icon(Icons.swap_horiz),
                                    child: Text(
                                      _daw.timeline.tracks[t].name.isEmpty
                                          ? '${t + 1}'
                                          : _daw.timeline.tracks[t].name,
                                    ),
                                  ),
                            ],
                            builder: (context, controller, _) =>
                                TextButton.icon(
                              onPressed: () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                              icon: const Icon(Icons.swap_horiz),
                              label: Text(l10n.dawMoveToLane),
                            ),
                          ),
                        // O15 — see what's IN the clip, not just how loud.
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            _showClipSpectrogram(track, index);
                          },
                          icon: const Icon(Icons.gradient),
                          label: Text(l10n.dawSpectrogram),
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

  /// The `(from-mode, document)` a clip exposes to the cross-mode doors, or null
  /// when it has none. Score and Tracker clips hand their model directly; a DRUM
  /// beat is read as a percussion tracker song (beat→tracker, lossless) and a
  /// GROOVE as its engraved score (`grooveParts`) — so both get a cross-mode door
  /// too. Null for a raw recording (no symbolic model — Transcribe is the only
  /// route) or a purely-percussive groove (nothing to engrave).
  /// C5 — the one-way door back. A raw-audio clip (a recording, an import, a
  /// bounce) has no symbolic model to convert, so the only way to get notes out
  /// of it is to *listen*: run the pure-Dart monophonic transcriber over its PCM
  /// and drop the detected melody onto a NEW notation clip. Non-destructive —
  /// the audio clip stays put; the score is a sibling you can then re-voice,
  /// open in any editor, or bounce back. Null for any clip that already has a
  /// symbolic model ([_clipSymbolicDoc] handles those; you'd never transcribe a
  /// score back from its own audio).
  Widget? _transcribeAction(BuildContext sheetCtx, int track, int index) {
    final source = _daw.clipSourceAt(track, index);
    if (source is! SampleSource && source is! StereoSampleSource) return null;
    return TextButton.icon(
      key: const ValueKey('transcribe-clip'),
      onPressed: () => _transcribeClipToScore(sheetCtx, track, index),
      icon: const Icon(Icons.lyrics_outlined),
      label: const Text('Transcribe → notation'),
    );
  }

  /// Renders the clip's PCM (whatever the source is) and transcribes it to a
  /// score with the always-available monophonic engine (no model download), then
  /// adds the result as a fresh, independently editable [ScoreSource] clip.
  Future<void> _transcribeClipToScore(
    BuildContext sheetCtx,
    int track,
    int index,
  ) async {
    final source = _daw.clipSourceAt(track, index);
    Navigator.of(sheetCtx).pop();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Transcribing the audio…')),
      );
    try {
      final pcm = source.render(kDawSampleRate);
      // kDawSampleRate is the transcriber's default rate; passing it would trip
      // avoid_redundant_argument_values.
      final score = await transcribePcmToScore(pcm);
      if (!mounted) return;
      _daw.addClip(ScoreSource.single(score));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Added a notation clip transcribed from the audio.'),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not transcribe: $e')));
    }
  }

  (AppMode, Object)? _clipSymbolicDoc(ClipSource source) {
    if (source is ScoreSource) return (AppMode.score, source.score);
    if (source is TrackerSource) return (AppMode.tracker, source.song);
    if (source is DrumSource) {
      final beat = SharedBeat(
        rows: source.pattern.rows,
        tempoBpm: source.timing.tempoBpm,
        swing: source.timing.swing,
      );
      return (AppMode.tracker, drumSongFromBeat(beat));
    }
    if (source is GrooveSource) {
      final parts = grooveParts(
        LoopEngine()..applySpec(source.spec),
        nameOf: (id) => id,
      );
      return parts == null ? null : (AppMode.score, parts.score);
    }
    return null;
  }

  /// Wraps a converted loop document (a cells list) as a [GrooveSpec] whose
  /// USER ('voice') track holds those cells, so the Loop Mixer can be seeded from
  /// it — the bridge produces cells, the Loop Mixer speaks grooves.
  GrooveSpec _loopSpecFromCells(List<PatternCell> cells) => GrooveSpec(
        userCells: cells,
        enabled: {LoopEngine.userTrackId},
      );

  /// C3 — "Open a copy in…" for a clip whose model is a document the
  /// [ProjectBridge] can convert (now including drum + groove via
  /// [_clipSymbolicDoc]).
  ///
  /// Distinct from the exact "Open in editor" door above it, and deliberately
  /// so. That one hands the clip's OWN model to its OWN editor and takes the
  /// edit back into the same clip: nothing is converted, so nothing can be
  /// lost. This one crosses modes — a tracker pattern read as notation, a score
  /// fretted for tab — which always costs something, so it goes through
  /// [OpenInMenu]: the menu names the cost of each edge up front and makes a
  /// lossy conversion confirm before it runs.
  ///
  /// A converted document opens as a COPY with no send-back callback. Routing a
  /// lossy conversion back into the source clip would quietly overwrite the
  /// user's original with a degraded version of itself; "Send to Audio Editor"
  /// from the target editor adds it as a new clip instead, which keeps both.
  ///
  /// All four other modes are offered now: score / tab / tracker directly, and
  /// LOOP by seeding the Loop Mixer's user track from the converted cells (see
  /// [_loopSpecFromCells]) — the restriction that once dropped Loop is gone.
  Widget? _openACopyIn(BuildContext sheetCtx, int track, int index) {
    final source = _daw.clipSourceAt(track, index);
    final sym = _clipSymbolicDoc(source);
    if (sym == null) return null;
    final l10n = AppLocalizations.of(context)!;
    final from = sym.$1;
    final document = sym.$2;
    return OpenInMenu(
      from: from,
      documentBuilder: () => document,
      targets: const [
        AppMode.score,
        AppMode.tab,
        AppMode.tracker,
        AppMode.loop,
      ],
      tooltip: l10n.openInCopyTooltip,
      icon: const Icon(Icons.call_split),
      onConverted: (target, result) {
        final converted = result.document;
        if (converted == null) return;
        Navigator.of(sheetCtx).pop();
        switch (target) {
          case AppMode.score:
            if (converted is MultiPartScore) {
              openScoreInWorkshop(context, converted);
            }
          case AppMode.tab:
            // The bridge's tab document is a `TabDocument`, but the Tab
            // Workshop is seeded from a SCORE and does its own fretting — that
            // fretting IS the score→tab conversion, so handing it the notes is
            // both simpler and exactly what the menu promised ("picks a
            // playable fingering for you"). What it needs is therefore the
            // music as a score, which for a score clip it already is and for a
            // tracker clip is one more bridge hop.
            final asScore = _clipAsScore(from, document);
            if (asScore != null) openScoreInTab(context, asScore);
          case AppMode.tracker:
            if (converted is TrackerSong) openTrackerSong(context, converted);
          case AppMode.loop:
            // The loop document is a cells list; seed the Loop Mixer's user
            // ('voice') track from it. "Send to Audio Editor" there adds a new
            // groove clip (copy), leaving this one untouched.
            if (converted is List<PatternCell>) {
              openGroove(context, _loopSpecFromCells(converted));
            }
          case AppMode.audio:
            break; // a bounce, not a conversion — see the doc comment.
        }
      },
    );
  }

  /// The IN-PLACE twin of [_openACopyIn]: convert to the chosen mode, edit
  /// there, and the returned document REPLACES this clip's source (the clip
  /// becomes the edited mode) so mixing continues on the very same clip. Same
  /// lossy-conversion warning as the copy door; the source-replace is undoable.
  /// Offered for the same clip kinds the copy door supports (score/tracker).
  Widget? _openAndReplaceIn(BuildContext sheetCtx, int track, int index) {
    final source = _daw.clipSourceAt(track, index);
    final sym = _clipSymbolicDoc(source);
    if (sym == null) return null;
    final l10n = AppLocalizations.of(context)!;
    final from = sym.$1;
    final document = sym.$2;
    return OpenInMenu(
      from: from,
      documentBuilder: () => document,
      targets: const [
        AppMode.score,
        AppMode.tab,
        AppMode.tracker,
        AppMode.loop,
      ],
      tooltip: l10n.openInReplaceTooltip,
      keyPrefix: 'replace-',
      icon: const Icon(Icons.sync_alt),
      onConverted: (target, result) {
        final converted = result.document;
        if (converted == null) return;
        Navigator.of(sheetCtx).pop();
        switch (target) {
          case AppMode.score:
            if (converted is MultiPartScore) {
              openScoreInWorkshop(
                context,
                converted,
                onReturn: (edited) =>
                    _daw.replaceScoreClipSource(source, edited),
              );
            }
          case AppMode.tab:
            final asScore = _clipAsScore(from, document);
            if (asScore != null) {
              openScoreInTab(
                context,
                asScore,
                // Tab sends a SCORE back, so the clip returns as a score clip.
                onReturn: (edited) =>
                    _daw.replaceScoreClipSource(source, edited),
              );
            }
          case AppMode.tracker:
            if (converted is TrackerSong) {
              openTrackerSong(
                context,
                converted,
                onReturn: (edited) =>
                    _daw.replaceTrackerClipSource(source, edited),
              );
            }
          case AppMode.loop:
            // Seed the Loop Mixer's user track from the loop cells; its edited
            // groove replaces this clip (it becomes a groove clip).
            if (converted is List<PatternCell>) {
              openGroove(
                context,
                _loopSpecFromCells(converted),
                onReturn: (edited) =>
                    _daw.replaceGrooveClipSource(source, edited),
              );
            }
          case AppMode.audio:
            break;
        }
      },
    );
  }

  /// [document] as engraved music: itself when it already is, else via the
  /// bridge. Null when that conversion cannot be made — the caller then opens
  /// nothing rather than opening something empty.
  MultiPartScore? _clipAsScore(AppMode from, Object document) {
    if (document is MultiPartScore) return document;
    final result = ProjectBridge.convert(
      from: from,
      to: AppMode.score,
      document: document,
    );
    final converted = result.document;
    return converted is MultiPartScore ? converted : null;
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

  /// WS-T3 — the shared bindings, loaded once so a rebinding persists.
  final KeymapService _keymap = KeymapService()..load();
  final FocusNode _keyFocus = FocusNode(debugLabel: 'dawKeys');

  /// Desktop/web keyboard shortcuts for the transport: Space toggles play/stop,
  /// Delete/Backspace removes the selected clips. The DAW has no persistent text
  /// field on this surface, so intercepting these globally is safe.
  KeyEventResult _handleDawKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // WS-T3 — the same shared table the Tracker resolves through, so a
    // rebinding made once applies on both surfaces. This screen handles the
    // subset in `kDawIntents`; everything else falls through untouched, which
    // is what lets one table serve three unlike surfaces.
    final intent = _keymap.keymap.intentFor(
      chordOf(event.logicalKey, HardwareKeyboard.instance),
    );
    switch (intent) {
      case AppIntent.transportToggle:
        _playing ? stop() : play();
        return KeyEventResult.handled;
      case AppIntent.editDelete:
        // Unlike the Tracker's, this one is conditional: with nothing
        // selected the key should stay available to whatever else wants it.
        if (_hasSelectedClips) {
          _deleteSelectedClips();
          return KeyEventResult.handled;
        }
      case AppIntent.editUndo:
        if (_daw.canUndo) {
          undo();
          return KeyEventResult.handled;
        }
      case AppIntent.editRedo:
        if (_daw.canRedo) {
          redo();
          return KeyEventResult.handled;
        }
      default:
        break;
    }
    return KeyEventResult.ignored;
  }

  /// The app-bar transport/edit actions, made width-aware so the row never
  /// overflows on a narrow (phone/web) window. Essential actions (help,
  /// undo/redo, play/stop) stay as icons; the rest collapse into a single
  /// "more" menu below a threshold width.
  List<Widget> _toolbarActions(
    BuildContext context,
    DawService daw,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final narrow = MediaQuery.of(context).size.width < 640;

    final primary = <Widget>[
      IconButton(
        icon: const Icon(Icons.help_outline),
        tooltip: l10n.dawHelpTooltip,
        onPressed: () => showDawHelpSheet(context),
      ),
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
        icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
        tooltip: _playing ? l10n.songStop : l10n.myMelodyPlay,
        onPressed: _playing ? stop : play,
      ),
    ];

    // Secondary actions: shown as icons when wide, folded into a menu when
    // narrow. `active` marks a lit toggle (loop / snap).
    final secondary =
        <({IconData icon, String label, VoidCallback? onPressed, bool active})>[
      (
        icon: Icons.content_copy,
        label: l10n.dawCopyClips,
        onPressed: _hasSelectedClips ? _copySelectedClips : null,
        active: false,
      ),
      (
        icon: Icons.content_cut,
        label: l10n.dawCutClips,
        onPressed: _hasSelectedClips
            ? () => _deleteSelectedClips(copyFirst: true)
            : null,
        active: false,
      ),
      (
        icon: Icons.content_paste,
        label: l10n.dawPasteClips,
        onPressed: _clipClipboard.isEmpty ? null : _pasteClipClipboard,
        active: false,
      ),
      (
        icon: Icons.delete_sweep_outlined,
        label: l10n.dawDeleteClips,
        onPressed: _hasSelectedClips ? _deleteSelectedClips : null,
        active: false,
      ),
      (
        icon: Icons.repeat,
        label: l10n.dawLoop,
        onPressed: toggleLoop,
        active: _loop,
      ),
      (
        icon: daw.snapOn ? Icons.grid_on : Icons.grid_off,
        label: l10n.dawSnap,
        onPressed: toggleSnap,
        active: daw.snapOn,
      ),
      (
        icon: Icons.download,
        label: l10n.audioExportTitle,
        onPressed: daw.clipCount == 0 ? null : _export,
        active: false,
      ),
      (
        icon: Icons.delete_outline,
        label: l10n.trackerClear,
        onPressed: daw.clipCount == 0 ? null : clear,
        active: false,
      ),
    ];

    if (!narrow) {
      return [
        ...primary,
        for (final s in secondary)
          IconButton(
            icon: Icon(s.icon, color: s.active ? scheme.primary : null),
            tooltip: s.label,
            onPressed: s.onPressed,
          ),
      ];
    }

    return [
      ...primary,
      PopupMenuButton<VoidCallback?>(
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.dawMoreActions,
        onSelected: (cb) => cb?.call(),
        itemBuilder: (ctx) => [
          for (final s in secondary)
            PopupMenuItem<VoidCallback?>(
              enabled: s.onPressed != null,
              value: s.onPressed,
              child: Row(
                children: [
                  Icon(
                    s.icon,
                    size: 20,
                    color: s.active ? scheme.primary : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.label)),
                  if (s.active)
                    Icon(Icons.check, size: 18, color: scheme.primary),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final daw = context.watch<DawService>(); // rebuild as clips are sent

    return Focus(
      // An explicit node so it can be disposed with the screen — and so a test
      // can claim it, since autofocus does not win against the route's focus
      // scope in the test binding.
      focusNode: _keyFocus,
      autofocus: true,
      onKeyEvent: _handleDawKey,
      child: Scaffold(
        appBar: GameAppBar(
          title: l10n.dawTitle,
          actions: _toolbarActions(context, daw, scheme, l10n),
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
              // The control strip wraps into many rows at narrow widths; bound it
              // to half the viewport and let it scroll so it never pushes the
              // timeline off-screen (keeps every control reachable on phone/web).
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Add clip is timeline material only. Instrument
                        // generation lives in the Sound Library; voice shaping
                        // lives in track FX.
                        MenuAnchor(
                          menuChildren: [
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.graphic_eq),
                              onPressed: addSample,
                              child: Text(l10n.dawAddFromLibrary),
                            ),
                            MenuItemButton(
                              leadingIcon:
                                  const Icon(Icons.file_upload_outlined),
                              onPressed: _importAudioFile,
                              child: Text(l10n.dawImportAudioFile),
                            ),
                            MenuItemButton(
                              leadingIcon:
                                  const Icon(Icons.library_music_outlined),
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
                          builder: (context, controller, _) =>
                              FilledButton.icon(
                            onPressed: () => controller.isOpen
                                ? controller.close()
                                : controller.open(),
                            icon: const Icon(Icons.add),
                            label: Text(l10n.dawAddClip),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed:
                              daw.clipCount < 2 ? null : _mergeAllWithToast,
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
                        // WS-T3 — the keyboard reference. An unlisted shortcut
                        // does not exist, and this screen's shortcuts have
                        // never been written down anywhere.
                        OutlinedButton.icon(
                          onPressed: () => showKeymapSheet(
                            context,
                            keymap: _keymap.keymap,
                            supported: kDawIntents,
                            service: _keymap,
                          ),
                          icon: const Icon(Icons.keyboard),
                          label: const Text('Keyboard'),
                        ),
                        // WS-A5 — the meter. Disabled with nothing to measure,
                        // rather than opening onto "Silence".
                        OutlinedButton.icon(
                          onPressed: daw.clipCount == 0 ? null : _showLoudness,
                          icon: const Icon(Icons.speed),
                          label: const Text('Loudness'),
                        ),
                        // O13 — drop a labelled marker at the playhead, and
                        // hop between them.
                        MenuAnchor(
                          menuChildren: [
                            MenuItemButton(
                              onPressed: _addMarkerAtPlayhead,
                              leadingIcon: const Icon(Icons.flag),
                              child: Text(l10n.dawAddMarker),
                            ),
                            MenuItemButton(
                              onPressed: daw.markerBefore(playheadMs) == null
                                  ? null
                                  : () => seekTo(
                                        daw.markerBefore(playheadMs)!.ms,
                                      ),
                              leadingIcon: const Icon(Icons.skip_previous),
                              child: Text(l10n.dawPreviousMarker),
                            ),
                            MenuItemButton(
                              onPressed: daw.markerAfter(playheadMs) == null
                                  ? null
                                  : () =>
                                      seekTo(daw.markerAfter(playheadMs)!.ms),
                              leadingIcon: const Icon(Icons.skip_next),
                              child: Text(l10n.dawNextMarker),
                            ),
                            MenuItemButton(
                              onPressed:
                                  daw.markers.isEmpty ? null : daw.clearMarkers,
                              leadingIcon: const Icon(Icons.flag_outlined),
                              child: Text(l10n.dawClearMarkers),
                            ),
                          ],
                          builder: (context, controller, _) =>
                              OutlinedButton.icon(
                            onPressed: () => controller.isOpen
                                ? controller.close()
                                : controller.open(),
                            icon: const Icon(Icons.flag),
                            label: Text(l10n.dawMarkers),
                          ),
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
                          builder: (context, controller, _) =>
                              OutlinedButton.icon(
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
                          onPressed:
                              _hasFxRange ? _trackAutomationDialog : null,
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
                                child:
                                    Text('Fade In ${_fadeCurveLabel(curve)}'),
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
                                child:
                                    Text('Fade Out ${_fadeCurveLabel(curve)}'),
                              ),
                          ],
                          builder: (context, controller, _) =>
                              OutlinedButton.icon(
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
                              onPressed: _hasFxRange
                                  ? () => _setRangeMuted(true)
                                  : null,
                              leadingIcon: const Icon(Icons.volume_off),
                              child: const Text('Mute'),
                            ),
                            MenuItemButton(
                              onPressed: _hasFxRange
                                  ? () => _setRangeMuted(false)
                                  : null,
                              leadingIcon: const Icon(Icons.volume_up),
                              child: const Text('Unmute'),
                            ),
                          ],
                          builder: (context, controller, _) =>
                              OutlinedButton.icon(
                            onPressed: _hasFxRange
                                ? () => controller.isOpen
                                    ? controller.close()
                                    : controller.open()
                                : null,
                            icon: const Icon(Icons.volume_off),
                            label: const Text('Range Mute'),
                          ),
                        ),
                        // Destructive range edits: cut the marked segment out,
                        // or throw away everything around it.
                        MenuAnchor(
                          menuChildren: [
                            MenuItemButton(
                              onPressed:
                                  _hasFxRange ? _silenceMarkedRange : null,
                              leadingIcon: const Icon(Icons.content_cut),
                              child: Text(l10n.dawRangeSilence),
                            ),
                            MenuItemButton(
                              onPressed:
                                  _hasFxRange ? _cropToMarkedRange : null,
                              leadingIcon: const Icon(Icons.crop),
                              child: Text(l10n.dawRangeCrop),
                            ),
                            // D1. English labels, like the FX rack's: "ripple"
                            // is the term every DAW uses and the one a user
                            // searching for this behaviour will look for.
                            MenuItemButton(
                              onPressed:
                                  _hasFxRange ? _rippleDeleteMarkedRange : null,
                              leadingIcon: const Icon(Icons.compress),
                              child: const Text('Ripple delete'),
                            ),
                            MenuItemButton(
                              onPressed:
                                  _hasFxRange ? _rippleInsertMarkedRange : null,
                              leadingIcon: const Icon(Icons.expand),
                              child: const Text('Ripple insert'),
                            ),
                          ],
                          builder: (context, controller, _) =>
                              OutlinedButton.icon(
                            onPressed: _hasFxRange
                                ? () => controller.isOpen
                                    ? controller.close()
                                    : controller.open()
                                : null,
                            icon: const Icon(Icons.crop),
                            label: Text(l10n.dawRangeEdit),
                          ),
                        ),
                        // O14 — capture a mic take onto a new lane.
                        OutlinedButton.icon(
                          onPressed: _recording ? null : recordClip,
                          icon: Icon(
                            Icons.fiber_manual_record,
                            color: _recording ? scheme.error : null,
                          ),
                          label: Text(
                            _recording ? l10n.dawRecording : l10n.dawRecord,
                          ),
                        ),
                        // O12 — peak/RMS of what's sounding, live.
                        _levelMeter(l10n),
                        // O7 — build a tone/noise/silence clip from scratch.
                        OutlinedButton.icon(
                          onPressed: _generateClipDialog,
                          icon: const Icon(Icons.graphic_eq),
                          label: Text(l10n.dawGenerate),
                        ),
                        // O8 — timeline zoom.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.zoom_out),
                              tooltip: l10n.dawZoomOut,
                              onPressed: _zoom <= _minZoom ? null : zoomOut,
                            ),
                            TextButton(
                              onPressed: zoomToFit,
                              child: Text(l10n.dawZoomFit),
                            ),
                            IconButton(
                              icon: const Icon(Icons.zoom_in),
                              tooltip: l10n.dawZoomIn,
                              onPressed: _zoom >= _maxZoom ? null : zoomIn,
                            ),
                          ],
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Timeline (to-scale clips, draggable in time) --------------------------

  /// Timeline scale at 1x zoom. Everything that maps time↔pixels goes through
  /// [_pxPerSecond], so changing [_zoom] rescales the ruler, the clips, the
  /// beat grid, the range overlay and the drag maths together.
  static const double _basePxPerSecond = 80;
  static const double _minZoom =
      0.1; // ~8 px/s — a long arrangement at a glance
  static const double _maxZoom = 20; // ~1600 px/s — sample-level detail
  static const double _zoomStep = 1.5;

  double get _pxPerSecond => _basePxPerSecond * _zoom;
  static const double _laneHeight = 108;
  static const double _gutterWidth = 112;
  static const double _rulerHeight = 20;

  // The clip's start when a long-press drag begins (offsets are relative to it).
  double _dragOriginMs = 0;

  /// How many lanes up (−) or down (+) the in-flight drag currently sits. Shown
  /// on the dragged clip and committed on release.
  int _dragLaneDelta = 0;

  /// Where the last clip ends — the arrangement's length, which sets the lane
  /// width and what "zoom to fit" has to fit.
  double get _arrangementMs {
    var maxEndMs = 0.0;
    for (var i = 0; i < _daw.timeline.tracks.length; i++) {
      for (var j = 0; j < _daw.timeline.tracks[i].clips.length; j++) {
        final end = _daw.clipStartMs(i, j) + _daw.clipDurationMs(i, j);
        if (end > maxEndMs) maxEndMs = end;
      }
    }
    return maxEndMs;
  }

  Widget _timeline(DawService daw, ColorScheme scheme) {
    final laneWidth =
        math.max(320.0, _arrangementMs / 1000 * _pxPerSecond + 48);

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
                            tempoMap: daw.tempoMap,
                            pxPerMs: _pxPerSecond / 1000,
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
  /// Seconds between ruler ticks. Zooming out must not produce a wall of
  /// unreadable labels, so the step grows until ticks are ≥60 px apart.
  int get _rulerStepSeconds {
    const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
    for (final s in steps) {
      if (s * _pxPerSecond >= 60) return s;
    }
    return steps.last;
  }

  Widget _ruler(double laneWidth, ColorScheme scheme) {
    final seconds = (laneWidth / _pxPerSecond).ceil();
    final step = _rulerStepSeconds;
    final markers = _daw.markers;
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
        // NB: no `clipBehavior:` here — the DAW's own `Clip` class shadows
        // Flutter's `Clip` enum in this file.
        child: Stack(
          children: [
            for (var s = 0; s <= seconds; s += step)
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
            // O13 — marker flags sit ON the ruler and take the tap themselves,
            // so hitting one opens its menu instead of moving the playhead.
            for (var i = 0; i < markers.length; i++)
              Positioned(
                left: markers[i].ms / 1000 * _pxPerSecond,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _markerMenu(i),
                  child: Tooltip(
                    message: markers[i].label.isEmpty
                        ? '${(markers[i].ms / 1000).toStringAsFixed(2)}s'
                        : markers[i].label,
                    child: Row(
                      children: [
                        Container(width: 2, color: scheme.tertiary),
                        if (markers[i].label.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            color: scheme.tertiaryContainer,
                            child: Text(
                              markers[i].label,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
          Row(
            children: [
              const SizedBox(width: 8),
              const Text('Pan', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: track.pan.clamp(-1.0, 1.0),
                  min: -1,
                  divisions: 40,
                  label: track.pan.toStringAsFixed(2),
                  onChanged: (v) {
                    _daw.setTrackPan(i, v);
                    if (_playing) play();
                  },
                ),
              ),
            ],
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
    final stereoPeaks = daw.clipStereoPeaks(
      i,
      j,
      buckets: math.max(8, widthPx ~/ 2),
    );
    final isStereo = clip.source is StereoSampleSource;

    return Positioned(
      left: startPx,
      top: 6,
      height: _laneHeight - 12,
      width: widthPx,
      child: GestureDetector(
        // Long-press then drag to reposition (a plain drag over the lane still
        // scrolls it); tap to open the inspector. Horizontal movement retimes
        // the clip live; VERTICAL movement moves it to another lane, but only
        // on release — re-parenting mid-drag would tear down the very gesture
        // that's driving it.
        onLongPressStart: (_) {
          _dragOriginMs = daw.clipStartMs(i, j);
          _dragLaneDelta = 0;
        },
        onLongPressMoveUpdate: (d) {
          moveClip(
            i,
            j,
            _dragOriginMs + d.localOffsetFromOrigin.dx / _pxPerSecond * 1000,
          );
          final delta = (d.localOffsetFromOrigin.dy / _laneHeight).round();
          if (delta != _dragLaneDelta) setState(() => _dragLaneDelta = delta);
        },
        onLongPressEnd: (_) {
          final delta = _dragLaneDelta;
          setState(() => _dragLaneDelta = 0);
          if (delta == 0) return;
          final target = (i + delta).clamp(0, daw.timeline.tracks.length - 1);
          if (target != i) moveClipToTrack(i, j, target);
        },
        onLongPressCancel: () {
          if (_dragLaneDelta != 0) setState(() => _dragLaneDelta = 0);
        },
        onTap: () => _openClipInspector(i, j),
        child: Stack(
          // The body must FILL, not size itself: as a bare non-positioned child
          // it collapsed to zero height and the waveform painter's clamp went
          // min > max. The Stack's own size comes from the lane's Positioned.
          fit: StackFit.expand,
          children: [
            _clipBody(
              daw,
              i,
              j,
              scheme,
              clip,
              frozen,
              bg,
              fg,
              selected,
              stereoPeaks,
              isStereo,
              widthPx,
              target,
            ),
            // WS-A1 — the edge handles, drawn OVER the body so they take the
            // gesture first. Only offered on a clip wide enough to hold them:
            // below that they would cover the clip itself, and the inspector
            // is still the way in.
            if (widthPx >= _kHandleMinClipPx) ...[
              _trimHandle(daw, i, j, scheme, leading: true),
              _trimHandle(daw, i, j, scheme, leading: false),
              _fadeHandle(daw, i, j, scheme, leading: true),
              _fadeHandle(daw, i, j, scheme, leading: false),
            ],
          ],
        ),
      ),
    );
  }

  /// WS-A1 — how wide a clip must be before edge handles are worth offering.
  /// Narrower than this they would cover the clip they are meant to edit.
  static const double _kHandleMinClipPx = 64;

  /// Handle hit width. Generous enough for a finger without eating the clip.
  static const double _kHandleWidth = 18;

  /// Drag an edge to trim. Sits on the LOWER part of the clip so the fade
  /// handles have the corners — two gestures on one edge need two places.
  Widget _trimHandle(
    DawService daw,
    int i,
    int j,
    ColorScheme scheme, {
    required bool leading,
  }) {
    return Positioned(
      // Keyed so a gesture test can aim at the affordance itself rather than
      // guess its coordinates from the clip's label.
      key: ValueKey('trim-$i-$j-${leading ? 'in' : 'out'}'),
      left: leading ? 0 : null,
      right: leading ? null : 0,
      top: _kHandleWidth,
      bottom: 0,
      width: _kHandleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          // A PLAIN horizontal drag, deliberately: the clip's move gesture is
          // long-press precisely so a plain drag scrolls the lane, and that
          // still holds everywhere except these narrow strips. Handing the
          // whole clip a plain-drag handler is what would break scrolling.
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => daw.trimClipEdge(
            i,
            j,
            leading: leading,
            deltaMs: d.delta.dx / _pxPerSecond * 1000,
          ),
          // End the coalesced run so the NEXT drag is its own undo entry.
          onHorizontalDragEnd: (_) => daw.endCoalescedEdit(),
          onHorizontalDragCancel: daw.endCoalescedEdit,
          child: Align(
            alignment: leading ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Drag a top corner to set that side's fade. Shown filled once there IS a
  /// fade, so the clip says what it is doing without opening the inspector.
  Widget _fadeHandle(
    DawService daw,
    int i,
    int j,
    ColorScheme scheme, {
    required bool leading,
  }) {
    final clip = daw.timeline.tracks[i].clips[j];
    final fadeMs = leading ? clip.fadeInMs : clip.fadeOutMs;
    return Positioned(
      key: ValueKey('fade-$i-$j-${leading ? 'in' : 'out'}'),
      left: leading ? 0 : null,
      right: leading ? null : 0,
      top: 0,
      height: _kHandleWidth,
      width: _kHandleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            // Dragging INWARD lengthens the fade on both sides, so the gesture
            // means the same thing at each end rather than being mirrored.
            final deltaMs =
                (leading ? d.delta.dx : -d.delta.dx) / _pxPerSecond * 1000;
            final next = math.max(0.0, fadeMs + deltaMs);
            daw.setClipFades(
              i,
              j,
              fadeInMs: leading ? next : null,
              fadeOutMs: leading ? null : next,
            );
          },
          onHorizontalDragEnd: (_) => daw.endCoalescedEdit(),
          onHorizontalDragCancel: daw.endCoalescedEdit,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: BoxDecoration(
                color: fadeMs > 0
                    ? scheme.tertiary.withValues(alpha: 0.85)
                    : scheme.onPrimaryContainer.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The clip's own visuals, split out so the handles can sit above them.
  Widget _clipBody(
    DawService daw,
    int i,
    int j,
    ColorScheme scheme,
    Clip clip,
    bool frozen,
    Color bg,
    Color fg,
    bool selected,
    ({List<double> left, List<double> right}) stereoPeaks,
    bool isStereo,
    double widthPx,
    ({int track, int index}) target,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        // While a drag is heading for another lane, say so on the clip —
        // otherwise the move only becomes visible after the drop.
        border: Border.all(
          color: _dragLaneDelta != 0
              ? scheme.tertiary
              : (selected ? scheme.primary : scheme.outline),
          width: _dragLaneDelta != 0 || selected ? 2 : 1,
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
                  stereoPeaks.left,
                  fg.withValues(alpha: 0.35),
                  rightPeaks: isStereo ? stereoPeaks.right : null,
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
                  // A music clip stays linked to the notation editors: open
                  // it in Score/Tab and "Send to Audio Editor" updates it in
                  // place. The badge makes that round-trip discoverable.
                  if (!frozen && daw.isScoreClip(i, j) && widthPx >= 48)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.link, size: 14, color: fg),
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
                tooltip:
                    selected ? 'Deselect clip for FX' : 'Select clip for FX',
                icon: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
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
    );
  }
}

/// Faint vertical lines marking the beat grid clips snap to.
///
/// Takes the TEMPO MAP rather than a single spacing (D6): once the tempo can
/// change, "a line every N pixels" is not the grid any more, and a painter that
/// only knows one number cannot draw the right thing. The constant-tempo case
/// still walks a fixed step, because that is the overwhelming majority and the
/// map's own fast path.
class _BeatGridPainter extends CustomPainter {
  _BeatGridPainter({
    required this.beatPx,
    required this.color,
    this.tempoMap,
    this.pxPerMs,
  });

  /// Spacing at the opening tempo — used when the tempo never changes.
  final double beatPx;
  final Color color;

  /// The project tempo over time. Null (or constant) keeps the fixed step.
  final TempoMap? tempoMap;

  /// Pixels per millisecond, needed to place a beat that is not on a fixed
  /// step. Null falls back to the fixed step.
  final double? pxPerMs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final map = tempoMap;
    final scale = pxPerMs;

    if (map != null && !map.isConstant && scale != null && scale > 0) {
      // Ask the map where the beats actually are.
      for (final ms in map.beatTimes(size.width / scale)) {
        final x = ms * scale;
        if (x <= 0 || x >= size.width) continue;
        canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
      }
      return;
    }

    if (beatPx < 4) return; // too dense to be useful
    for (var x = beatPx; x < size.width; x += beatPx) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_BeatGridPainter old) =>
      old.beatPx != beatPx ||
      old.color != color ||
      old.pxPerMs != pxPerMs ||
      !identical(old.tempoMap, tempoMap);
}

/// Draws a clip's downsampled [peaks] (0..1) as a centre-line waveform that
/// fills the clip box. Repaints only when the peak list identity changes.
class _ClipWaveformPainter extends CustomPainter {
  _ClipWaveformPainter(this.peaks, this.color, {this.rightPeaks});
  final List<double> peaks;
  final Color color;
  final List<double>? rightPeaks;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final paint = Paint()..color = color;
    void drawLane(List<double> lane, double center, double laneHeight) {
      final dx = size.width / lane.length;
      for (var i = 0; i < lane.length; i++) {
        final h = (lane[i] * laneHeight).clamp(1.0, laneHeight);
        canvas.drawRect(
          Rect.fromLTWH(
            i * dx,
            center - h / 2,
            dx <= 1 ? 1 : dx - 0.5,
            h,
          ),
          paint,
        );
      }
    }

    final right = rightPeaks;
    if (right == null) {
      drawLane(peaks, size.height / 2, size.height);
    } else {
      drawLane(peaks, size.height / 4, size.height / 2);
      drawLane(right, size.height * 3 / 4, size.height / 2);
    }
  }

  @override
  bool shouldRepaint(_ClipWaveformPainter old) =>
      !identical(old.peaks, peaks) ||
      !identical(old.rightPeaks, rightPeaks) ||
      old.color != color;
}
