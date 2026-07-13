// lib/features/games/composition/free_sing_screen.dart
//
// Free Sing: a creative toy — sing (or play) any tune, watch your pitch trace
// scroll by, then hear it back on the synth. Uses the mono pitch detector +
// MelodyRecorder (transcribe) + AudioService (replay). Not scored; no stars.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/audio/melody_recorder.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class FreeSingScreen extends StatefulWidget {
  const FreeSingScreen({super.key});

  @override
  State<FreeSingScreen> createState() => _FreeSingScreenState();
}

class _FreeSingScreenState extends State<FreeSingScreen> {
  final MicrophonePitchService _service = MicrophonePitchService();
  final MelodyRecorder _recorder = MelodyRecorder();
  final Stopwatch _clock = Stopwatch();
  StreamSubscription<PitchReading>? _sub;

  PitchReading _latest = PitchReading.silent();
  // Rolling (timeMs, fractional midi | null) for the scrolling trace.
  final List<(double, double?)> _trace = [];
  static const _windowMs = 5000.0;

  bool _recording = false;
  ({PitchCaptureError reason, String? detail})? _error;

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      _recorder.finish();
      _clock.stop();
      await _service.stop();
      await _sub?.cancel();
      setState(() {
        _recording = false;
        _latest = PitchReading.silent();
      });
      return;
    }

    setState(() {
      _error = null;
      _recorder.reset();
      _trace.clear();
      _clock
        ..reset()
        ..start();
    });
    try {
      _sub = _service.readings.listen(
        _onReading,
        onError: (Object e) {
          if (mounted) {
            setState(
              () => _error = (reason: PitchCaptureError.unknown, detail: '$e'),
            );
          }
        },
      );
      await _service.start();
      if (mounted) setState(() => _recording = true);
    } on PitchCaptureException catch (e) {
      await _sub?.cancel();
      if (mounted) {
        setState(() {
          _recording = false;
          _error = (reason: e.reason, detail: e.detail);
        });
      }
    }
  }

  void _onReading(PitchReading r) {
    if (!mounted) return;
    final t = _clock.elapsedMilliseconds.toDouble();
    _recorder.update(elapsedMs: t, reading: r);
    _trace.add((t, r.hasPitch ? r.midi : null));
    while (_trace.isNotEmpty && _trace.first.$1 < t - _windowMs) {
      _trace.removeAt(0);
    }
    setState(() => _latest = r);
  }

  void _playback() {
    if (_recorder.notes.isEmpty) return;
    context.read<AudioService>().playSequence(
      [for (final (midi, ms) in _recorder.notes) (midi, ms)],
    );
  }

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final captured = _recorder.notes.length;

    return Scaffold(
      appBar: AppBar(title: Text(l.gameFreeSing)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                _latest.hasPitch
                    ? spelledMidiName(context, _latest.nearestMidi)
                    : (_recording ? l.freeSingPrompt : '—'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color:
                          _latest.hasPitch ? scheme.primary : scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: CustomPaint(
                  painter: _TracePainter(
                    trace: _trace,
                    windowMs: _windowMs,
                    scheme: scheme,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 8),
              if (!_recording && captured > 0)
                Text(
                  l.freeSingCaptured(captured),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _errorText(l),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_recording && captured > 0)
                    OutlinedButton.icon(
                      onPressed: _playback,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l.myMelodyPlay),
                    ),
                  if (!_recording && captured > 0) const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _toggle,
                    icon: Icon(_recording ? Icons.stop : Icons.mic),
                    label: Text(_recording ? l.micStop : l.freeSingRecord),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scrolling pitch trace: time on X (recent [windowMs]), pitch on Y.
class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.trace,
    required this.windowMs,
    required this.scheme,
  });

  final List<(double, double?)> trace;
  final double windowMs;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, border);
    if (trace.isEmpty) return;

    // Pitch range from the voiced samples (padded), fallback to a middle range.
    var lo = 84.0, hi = 48.0;
    for (final (_, m) in trace) {
      if (m != null) {
        lo = m < lo ? m : lo;
        hi = m > hi ? m : hi;
      }
    }
    if (hi < lo) {
      lo = 55;
      hi = 79;
    }
    lo -= 3;
    hi += 3;
    final span = (hi - lo).clamp(1.0, 200.0);

    final now = trace.last.$1;
    double x(double t) => size.width * (1 - (now - t) / windowMs);
    double y(double m) => size.height - (m - lo) / span * size.height;

    final dot = Paint()..color = scheme.primary;
    for (final (t, m) in trace) {
      if (m == null) continue;
      canvas.drawCircle(Offset(x(t), y(m)), 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) => true;
}
