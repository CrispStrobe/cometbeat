// N2 — "Transcribe a recording". Pick an audio file (or record from the mic),
// run the auto-router pipeline (monophonic pure-Dart, or neural Basic Pitch when
// its model is present on native), and open the result as a real score in the
// Song Book — playable, editable, saveable.
//
// The heavy DSP runs on the UI isolate for now (recordings are short); a future
// pass can move it to a compute() isolate. Test seams (`debugPickAudio`,
// `debugNeural`) let a widget test drive the flow with no file-picker/mic/ONNX.

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, StemTranscription, transcribeSong;
import 'package:comet_beat/core/audio/transcription/transcription_service.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart'
    show TabWorkshopScreen;
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/transcribe/crepe_provider.dart';
import 'package:comet_beat/features/games/transcribe/harmony_provider.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/features/games/transcribe/rmvpe_provider.dart';
import 'package:comet_beat/features/games/transcribe/transcribe_engines.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, Score, multiPartToMusicXml;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// How the user wants the engine chosen.
enum EngineChoice { auto, monophonic, neural }

/// Top-level worker for `compute()` — runs the pure-Dart monophonic pipeline in a
/// background isolate so the UI thread stays responsive on long recordings. Only
/// used when no neural engine is in play (the ONNX model handle can't cross an
/// isolate boundary), so it's always the monophonic path here.
Future<TranscriptionResult> _monoInIsolate(({Uint8List bytes, double a4}) m) =>
    transcribeRecording(m.bytes, a4: m.a4);

class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({
    super.key,
    this.debugPickAudio,
    this.debugNeural,
    this.debugCrepe,
    this.debugRmvpe,
    this.debugHarmony,
    this.debugSeparator,
  });

  /// Test seam: replaces the file-picker. Returns WAV bytes, or null to cancel.
  final Future<Uint8List?> Function()? debugPickAudio;

  /// Test seam: replaces neural-engine loading.
  final Future<NeuralTranscriber?> Function({bool download})? debugNeural;

  /// Test seam: replaces CREPE F0-estimator loading.
  final Future<F0Estimator?> Function({bool download})? debugCrepe;

  /// Test seam: replaces RMVPE F0-estimator loading.
  final Future<F0Estimator?> Function({bool download})? debugRmvpe;

  /// Test seam: replaces neural chord-estimator (BTC) loading.
  final Future<ChordEstimator?> Function({bool download})? debugHarmony;

  /// Test seam: replaces the whole-song source separator resolution.
  final Future<Separator?> Function()? debugSeparator;

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  bool _busy = false;
  String? _error;
  EngineChoice _choice = EngineChoice.auto;
  bool _neuralPitch = false;
  bool _wholeSong = false;
  bool _configApplied = false;
  TranscriptionResult? _result;
  StemTranscription? _songResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configApplied) return;
    _configApplied = true;
    // Default the melody-pitch (neural F0) toggle from the Settings "Transcription
    // engine" F0 choice — on for a neural backend, off for on-device/auto.
    final f0 = _config().backendFor(TranscriptionStep.f0);
    if (f0 == Backend.onnx || f0 == Backend.crispasr) _neuralPitch = true;
  }

  /// The persisted engine config, or defaults when the service isn't in scope
  /// (widget tests).
  TranscriptionEngineConfig _config() {
    try {
      return context.read<TranscriptionConfigService>().config;
    } on ProviderNotFoundException {
      return const TranscriptionEngineConfig();
    }
  }

  /// Resolve the neural engines from the Settings config, threading the test
  /// seams. Melody-pitch on ⇒ force the ONNX F0 (RMVPE preferred, then CREPE).
  Future<TranscriptionEngines> _resolve() {
    final base = _config();
    final cfg = _neuralPitch
        ? base.copyWith(
            backends: {...base.backends, TranscriptionStep.f0: Backend.onnx},
          )
        : base;
    return resolveEngines(
      cfg,
      loadRmvpe: widget.debugRmvpe ?? loadRmvpeF0Estimator,
      loadCrepeOnnx: widget.debugCrepe ?? loadCrepeF0Estimator,
      loadHarmony: widget.debugHarmony ?? loadHarmonyEstimator,
    );
  }

  Future<Uint8List?> _pickAudio() async {
    if (widget.debugPickAudio != null) return widget.debugPickAudio!();
    const group = XTypeGroup(label: 'Audio', extensions: ['wav']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<NeuralTranscriber?> _neural({bool download = false}) {
    final loader = widget.debugNeural ?? loadNeuralTranscriber;
    return loader(download: download);
  }

  Future<Separator?> _resolveSeparator() {
    if (widget.debugSeparator != null) return widget.debugSeparator!();
    return resolveSeparator(_config());
  }

  Future<void> _transcribe() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _songResult = null;
    });
    try {
      final bytes = await _pickAudio();
      if (bytes == null) {
        setState(() => _busy = false); // cancelled
        return;
      }
      // Whole-song: separate into stems (if a separator is available) and
      // transcribe each into a multi-part score. Always inline — the separator
      // and per-stem engines hold ONNX handles that can't cross an isolate.
      if (_wholeSong) {
        final wav = readWavPcm16(bytes);
        final mono = wavToMonoFloat(wav);
        final sep = await _resolveSeparator();
        final engines = await _resolve();
        final song = await transcribeSong(
          mono,
          separator: sep,
          neural: engines.neural,
          f0: engines.f0,
          sampleRate: wav.sampleRate,
        );
        if (!mounted) return;
        setState(() {
          _songResult = song;
          _busy = false;
        });
        return;
      }
      // Neural only when the user allows it and (native) the model is present.
      final neural = _choice == EngineChoice.monophonic
          ? null
          : await _neural(download: _choice == EngineChoice.neural);
      // Neural pitch (RMVPE/CREPE) upgrades the monophonic F0 when opted in;
      // neural chords (BTC) run only when explicitly chosen in Settings.
      final engines = await _resolve();
      final f0 =
          (_neuralPitch && _choice != EngineChoice.neural) ? engines.f0 : null;
      final chords =
          _config().backendFor(TranscriptionStep.chords) == Backend.onnx
              ? engines.chords
              : null;
      final force = switch (_choice) {
        EngineChoice.monophonic => TranscriptionEngine.monophonic,
        EngineChoice.neural => TranscriptionEngine.neural,
        EngineChoice.auto => null,
      };
      // With no ONNX model in play the pipeline is pure Dart → run it in a
      // background isolate so the UI (and spinner) stay live on long clips. A
      // neural transcriber OR a CREPE F0 estimator holds an ONNX handle that
      // can't cross an isolate, so run inline then. Under a widget test (a debug
      // pick source) run inline too — a compute() isolate doesn't advance the
      // test's fake clock.
      final useIsolate = neural == null &&
          f0 == null &&
          chords == null &&
          widget.debugPickAudio == null;
      final result = useIsolate
          ? await compute(_monoInIsolate, (bytes: bytes, a4: 440.0))
          : await transcribeRecording(
              bytes,
              neural: neural,
              f0: f0,
              chordEstimator: chords,
              forceEngine: force,
            );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _openInSongBook(Score score, AppLocalizations l10n) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongScreen.fromScore(
          title: l10n.transcribeTitle,
          score: score,
        ),
      ),
    );
  }

  /// Open a transcription in the full Score Workshop (editable notation). Takes a
  /// [MultiPartScore] so both a single recording (wrapped) and a whole-song
  /// (multi-part) transcription can be edited there.
  void _openInScoreEditor(MultiPartScore score, [List<String>? names]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompositionWorkshopScreen(
          initialScore: score,
          initialNames: names,
        ),
      ),
    );
  }

  /// Open a transcription in the Tab Workshop (it engraves the [score] to a
  /// guitar tab via its own arranger).
  void _openInTabEditor(Score score) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TabWorkshopScreen(initialScore: score)),
    );
  }

  /// Persist a whole-song transcription to the Song Book as a multi-part song
  /// (every voice kept via MusicXML — the same store the Tracker/Workshop use).
  void _saveSongToBook(
    MultiPartScore score,
    List<String> partNames,
    AppLocalizations l10n,
  ) {
    context.read<UserSongsService>().addSong(
          ImportedSong(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: l10n.transcribeTitle,
            musicXml: multiPartToMusicXml(score, partNames: partNames),
          ),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.transcribeSongSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.transcribeTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.transcribeIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SegmentedButton<EngineChoice>(
              segments: [
                ButtonSegment(
                  value: EngineChoice.auto,
                  label: Text(l10n.transcribeEngineAuto),
                ),
                ButtonSegment(
                  value: EngineChoice.monophonic,
                  label: Text(l10n.transcribeEngineMono),
                ),
                ButtonSegment(
                  value: EngineChoice.neural,
                  label: Text(l10n.transcribeEngineNeural),
                ),
              ],
              selected: {_choice},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _choice = s.first),
            ),
            if (_choice == EngineChoice.neural && kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.transcribeNeuralWebNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            // CREPE neural pitch upgrades the melody F0; native-only, and not for
            // the polyphonic neural engine (which has no F0 stage).
            if (_choice != EngineChoice.neural && !kIsWeb && !_wholeSong)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _neuralPitch,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _neuralPitch = v ?? false),
                title: Text(l10n.transcribeNeuralPitch),
              ),
            // Whole-song: separate the mix into stems and transcribe each into a
            // multi-part score (needs a separation model; degrades to a single
            // part when none is present).
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _wholeSong,
              onChanged:
                  _busy ? null : (v) => setState(() => _wholeSong = v ?? false),
              title: Text(l10n.transcribeWholeSong),
              subtitle: Text(l10n.transcribeWholeSongHint),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _transcribe,
              icon: const Icon(Icons.audio_file),
              label: Text(l10n.transcribePickFile),
            ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                l10n.transcribeError(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_songResult != null)
              Expanded(
                child: SingleChildScrollView(
                  child: _songCard(_songResult!, l10n),
                ),
              )
            else if (_result != null)
              Expanded(
                child: SingleChildScrollView(
                  child: _resultCard(_result!, l10n),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _songCard(StemTranscription song, AppLocalizations l10n) {
    final score = song.score;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.transcribeSongResult(song.partNames.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (song.partNames.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(song.partNames.join(' · ')),
            ],
            const SizedBox(height: 16),
            if (score == null)
              Text(l10n.transcribeNoNotes)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _openInScoreEditor(score, song.partNames),
                    icon: const Icon(Icons.edit_note),
                    label: Text(l10n.transcribeOpenScore),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _saveSongToBook(score, song.partNames, l10n),
                    icon: const Icon(Icons.library_add),
                    label: Text(l10n.transcribeSaveSongBook),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(TranscriptionResult r, AppLocalizations l10n) {
    final engineName = r.engine == TranscriptionEngine.neural
        ? l10n.transcribeEngineNeural
        : l10n.transcribeEngineMono;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.transcribeResult(r.notes.length, r.bpm.round()),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.transcribeEngineUsed(engineName)),
            const SizedBox(height: 16),
            if (r.notes.isEmpty)
              Text(l10n.transcribeNoNotes)
            else
              // Open the transcription in any editor — the notes interchange.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _openInScoreEditor(MultiPartScore([r.score])),
                    icon: const Icon(Icons.edit_note),
                    label: Text(l10n.transcribeOpenScore),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openInTabEditor(r.score),
                    icon: const Icon(Icons.straighten),
                    label: Text(l10n.transcribeOpenTab),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openInSongBook(r.score, l10n),
                    icon: const Icon(Icons.menu_book),
                    label: Text(l10n.transcribeOpenSongBook),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
