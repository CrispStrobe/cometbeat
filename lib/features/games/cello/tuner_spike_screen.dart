// lib/features/games/cello/tuner_spike_screen.dart
//
// SPIKE — capture-layer proof for automatic play-along. A live cello tuner:
// open the mic, detect the pitch you play/sing, and show how many cents sharp
// or flat you are. This validates the whole chain (mic → PCM → detector →
// intonation meter) on a real device before any game/scoring logic is built.
//
// Deliberately NOT localized and NOT wired into the game registry as a real
// module yet — it is a developer harness. Reachable via a temporary tile so it
// can be exercised on-device. See HANDOVER once the approach is confirmed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';

/// The cello's four open strings, low → high, as intonation reference chips.
const _celloStrings = <({String name, int midi})>[
  (name: 'C2', midi: 36),
  (name: 'G2', midi: 43),
  (name: 'D3', midi: 50),
  (name: 'A3', midi: 57),
];

class TunerSpikeScreen extends StatefulWidget {
  const TunerSpikeScreen({super.key});

  @override
  State<TunerSpikeScreen> createState() => _TunerSpikeScreenState();
}

class _TunerSpikeScreenState extends State<TunerSpikeScreen> {
  final MicrophonePitchService _service = MicrophonePitchService();
  StreamSubscription<PitchReading>? _sub;

  PitchReading _reading = PitchReading.silent();
  // A little smoothing so the readout does not jitter frame-to-frame.
  double? _smoothedCents;
  String? _errorMessage;
  bool _listening = false;

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _service.stop();
      await _sub?.cancel();
      setState(() {
        _listening = false;
        _reading = PitchReading.silent();
        _smoothedCents = null;
      });
      return;
    }

    setState(() => _errorMessage = null);
    try {
      _sub = _service.readings.listen(
        _onReading,
        onError: (Object e) {
          if (mounted) setState(() => _errorMessage = '$e');
        },
      );
      await _service.start();
      if (mounted) setState(() => _listening = true);
    } on PitchCaptureException catch (e) {
      await _sub?.cancel();
      if (mounted) {
        setState(() {
          _listening = false;
          _errorMessage = switch (e.reason) {
            PitchCaptureError.permissionDenied =>
              'Microphone permission denied. Enable it in system settings.',
            PitchCaptureError.unsupported =>
              'PCM capture is not supported on this device.',
            _ => 'Could not start the microphone: ${e.detail ?? e.reason.name}',
          };
        });
      }
    }
  }

  void _onReading(PitchReading r) {
    if (!mounted) return;
    setState(() {
      _reading = r;
      if (r.hasPitch) {
        _smoothedCents = _smoothedCents == null
            ? r.cents
            : _smoothedCents! * 0.6 + r.cents * 0.4;
      } else {
        _smoothedCents = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _reading;
    final inTune = r.hasPitch && r.cents.abs() <= 5;

    return Scaffold(
      appBar: AppBar(title: const Text('Tuner (spike)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                r.hasPitch ? r.noteName : '—',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: inTune ? Colors.green : scheme.onSurface,
                    ),
              ),
              Text(
                r.hasPitch
                    ? '${r.frequency.toStringAsFixed(1)} Hz  ·  clarity ${r.clarity.toStringAsFixed(2)}'
                    : 'Play or sing a note',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: _CentsMeterPainter(
                    cents: _smoothedCents,
                    color: scheme.primary,
                    trackColor: scheme.surfaceContainerHighest,
                    inTuneColor: Colors.green,
                    labelColor: scheme.onSurfaceVariant,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                r.hasPitch
                    ? '${r.cents >= 0 ? '+' : ''}${r.cents.toStringAsFixed(0)} cents'
                    : ' ',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: inTune ? Colors.green : scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  for (final s in _celloStrings)
                    Chip(
                      label: Text(s.name),
                      backgroundColor: r.nearestMidi == s.midi
                          ? scheme.primaryContainer
                          : null,
                    ),
                ],
              ),
              const Spacer(),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(_listening ? 'Stop' : 'Start listening'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal −50..+50 cent meter with a moving needle and a green centre
/// zone. Null [cents] parks the needle at centre and dims it.
class _CentsMeterPainter extends CustomPainter {
  _CentsMeterPainter({
    required this.cents,
    required this.color,
    required this.trackColor,
    required this.inTuneColor,
    required this.labelColor,
  });

  final double? cents;
  final Color color;
  final Color trackColor;
  final Color inTuneColor;
  final Color labelColor;

  static const double _range = 50; // cents shown left/right of centre

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final track = Paint()
      ..color = trackColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), track);

    // Green in-tune zone (±5¢) around the centre.
    final centre = size.width / 2;
    final zoneHalf = size.width * (5 / (2 * _range));
    final zone = Paint()..color = inTuneColor.withValues(alpha: 0.25);
    canvas.drawRect(
      Rect.fromLTRB(centre - zoneHalf, midY - 20, centre + zoneHalf, midY + 20),
      zone,
    );

    // Tick marks at -50 -25 0 +25 +50.
    final tick = Paint()
      ..color = labelColor
      ..strokeWidth = 1.5;
    for (final c in [-50, -25, 0, 25, 50]) {
      final x = centre + size.width * (c / (2 * _range));
      final h = c == 0 ? 22.0 : 12.0;
      canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), tick);
    }

    if (cents == null) return;

    final clamped = cents!.clamp(-_range, _range);
    final needleX = centre + size.width * (clamped / (2 * _range));
    final onTune = cents!.abs() <= 5;
    final needle = Paint()
      ..color = onTune ? inTuneColor : color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(needleX, midY - 34),
      Offset(needleX, midY + 34),
      needle,
    );
    canvas.drawCircle(Offset(needleX, midY), 7, needle);
  }

  @override
  bool shouldRepaint(_CentsMeterPainter old) =>
      old.cents != cents ||
      old.color != color ||
      old.inTuneColor != inTuneColor;
}
