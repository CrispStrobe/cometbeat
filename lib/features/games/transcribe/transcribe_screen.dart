// N2 — "Transcribe a recording". Pick an audio file (or record from the mic),
// run the auto-router pipeline (monophonic pure-Dart, or neural Basic Pitch when
// its model is present on native), and open the result as a real score in the
// Song Book — playable, editable, saveable.
//
// The heavy DSP runs on the UI isolate for now (recordings are short); a future
// pass can move it to a compute() isolate. Test seams (`debugPickAudio`,
// `debugNeural`) let a widget test drive the flow with no file-picker/mic/ONNX.

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/transcription_service.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/transcribe/crepe_provider.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/features/games/transcribe/rmvpe_provider.dart';
import 'package:comet_beat/features/games/transcribe/transcribe_engines.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Score;
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
  });

  /// Test seam: replaces the file-picker. Returns WAV bytes, or null to cancel.
  final Future<Uint8List?> Function()? debugPickAudio;

  /// Test seam: replaces neural-engine loading.
  final Future<NeuralTranscriber?> Function({bool download})? debugNeural;

  /// Test seam: replaces CREPE F0-estimator loading.
  final Future<F0Estimator?> Function({bool download})? debugCrepe;

  /// Test seam: replaces RMVPE F0-estimator loading.
  final Future<F0Estimator?> Function({bool download})? debugRmvpe;

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  bool _busy = false;
  String? _error;
  EngineChoice _choice = EngineChoice.auto;
  bool _neuralPitch = false;
  bool _configApplied = false;
  TranscriptionResult? _result;

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

  /// The neural F0 estimator to inject when melody-pitch is on — RMVPE preferred
  /// over CREPE (the router's choice), forcing a download. Null ⇒ pYIN. Not used
  /// for the polyphonic engine (it has no F0 stage). Threads the test seams.
  Future<F0Estimator?> _f0() async {
    if (!_neuralPitch || _choice == EngineChoice.neural) return null;
    final cfg = _config().copyWith(
      backends: {..._config().backends, TranscriptionStep.f0: Backend.onnx},
    );
    final engines = await resolveEngines(
      cfg,
      loadRmvpe: widget.debugRmvpe ?? loadRmvpeF0Estimator,
      loadCrepeOnnx: widget.debugCrepe ?? loadCrepeF0Estimator,
    );
    return engines.f0;
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

  Future<void> _transcribe() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final bytes = await _pickAudio();
      if (bytes == null) {
        setState(() => _busy = false); // cancelled
        return;
      }
      // Neural only when the user allows it and (native) the model is present.
      final neural = _choice == EngineChoice.monophonic
          ? null
          : await _neural(download: _choice == EngineChoice.neural);
      // Neural pitch (RMVPE/CREPE, per the Settings config) upgrades the
      // monophonic F0 when opted in — not for the polyphonic engine.
      final f0 = await _f0();
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
      final useIsolate =
          neural == null && f0 == null && widget.debugPickAudio == null;
      final result = useIsolate
          ? await compute(_monoInIsolate, (bytes: bytes, a4: 440.0))
          : await transcribeRecording(
              bytes,
              neural: neural,
              f0: f0,
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
            if (_choice != EngineChoice.neural && !kIsWeb)
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
            else if (_result != null)
              Expanded(child: _resultCard(_result!, l10n)),
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
              FilledButton.tonalIcon(
                onPressed: () => _openInSongBook(r.score, l10n),
                icon: const Icon(Icons.menu_book),
                label: Text(l10n.transcribeOpenSongBook),
              ),
          ],
        ),
      ),
    );
  }
}
