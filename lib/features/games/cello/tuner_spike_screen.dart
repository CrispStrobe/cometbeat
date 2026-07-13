// lib/features/games/cello/tuner_spike_screen.dart
//
// Live cello/chromatic tuner: open the mic, detect the pitch you play/sing, and
// show how many cents sharp or flat you are — the whole chain (mic → PCM →
// detector → intonation meter). Grew out of the play-along capture spike; now a
// real, localized tuner tile in the cello corner.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/l10n/app_localizations.dart';

/// Instruments with a fixed set of open strings the tuner can guide you
/// through, plus a free chromatic mode.
enum TunerInstrument { chromatic, cello, guitar, violin }

/// Open strings per instrument, low → high (MIDI note numbers).
const _instrumentStrings = <TunerInstrument, List<int>>{
  TunerInstrument.chromatic: [],
  TunerInstrument.cello: [36, 43, 50, 57], // C2 G2 D3 A3
  TunerInstrument.guitar: [40, 45, 50, 55, 59, 64], // E2 A2 D3 G3 B3 E4
  TunerInstrument.violin: [55, 62, 69, 76], // G3 D4 A4 E5
};

/// Selectable reference pitches (A4 in Hz): baroque, standard, orchestral.
const _referencePitches = <double>[415, 440, 442];

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
  ({PitchCaptureError reason, String? detail})? _error;
  bool _listening = false;

  // The reference the *detector* runs at is fixed; A4 and the target string
  // only reshape the note/cents readout, which is pure math on the raw Hz —
  // so switching them needs no plugin restart.
  double _a4 = kDefaultA4;
  TunerInstrument _instrument = TunerInstrument.chromatic;
  int? _targetMidi; // the open string being guided-tuned; null = free/nearest

  List<int> get _strings => _instrumentStrings[_instrument]!;

  /// Note the readout snaps to, re-scored against the chosen A4.
  int _adjMidi(PitchReading r) => PitchReading(
        frequency: r.frequency,
        clarity: r.clarity,
        a4: _a4,
      ).nearestMidi;

  /// Cents to display: signed deviation from the target string when guiding,
  /// otherwise from the nearest note — both against the chosen A4. Can exceed
  /// ±50 for a target string (the meter clamps).
  double _rawCents(PitchReading r) {
    if (!r.hasPitch) return double.nan;
    if (_targetMidi != null) {
      final targetHz = _a4 * pow(2, (_targetMidi! - 69) / 12.0);
      return 1200.0 * (log(r.frequency / targetHz) / ln2);
    }
    return PitchReading(frequency: r.frequency, clarity: r.clarity, a4: _a4)
        .cents;
  }

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

    setState(() => _error = null);
    try {
      _sub = _service.readings.listen(
        _onReading,
        onError: (Object e) {
          if (mounted) {
            setState(
              () => _error = (
                reason: PitchCaptureError.unknown,
                detail: '$e',
              ),
            );
          }
        },
      );
      await _service.start();
      if (mounted) setState(() => _listening = true);
    } on PitchCaptureException catch (e) {
      await _sub?.cancel();
      if (mounted) {
        setState(() {
          _listening = false;
          _error = (reason: e.reason, detail: e.detail);
        });
      }
    }
  }

  String _instrumentName(AppLocalizations l, TunerInstrument i) => switch (i) {
        TunerInstrument.chromatic => l.tunerInstrumentChromatic,
        TunerInstrument.cello => l.tunerInstrumentCello,
        TunerInstrument.guitar => l.tunerInstrumentGuitar,
        TunerInstrument.violin => l.tunerInstrumentViolin,
      };

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  void _onReading(PitchReading r) {
    if (!mounted) return;
    setState(() {
      _reading = r;
      if (r.hasPitch) {
        final c = _rawCents(r);
        _smoothedCents =
            _smoothedCents == null ? c : _smoothedCents! * 0.6 + c * 0.4;
      } else {
        _smoothedCents = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final r = _reading;
    // Everything the readout shows is A4- and target-adjusted, not the raw
    // 440-scored reading.
    final displayCents = _smoothedCents;
    final inTune =
        r.hasPitch && displayCents != null && displayCents.abs() <= 5;
    // The big note: the target string when guiding, else the nearest note.
    final labelMidi = _targetMidi ?? (r.hasPitch ? _adjMidi(r) : -1);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.gameTuner),
        actions: [
          PopupMenuButton<double>(
            icon: const Icon(Icons.tune),
            tooltip: l.tunerReference,
            initialValue: _a4,
            onSelected: (a) => setState(() {
              _a4 = a;
              _smoothedCents = null;
            }),
            itemBuilder: (context) => [
              for (final a in _referencePitches)
                PopupMenuItem(value: a, child: Text('A4 = ${a.round()} Hz')),
            ],
          ),
          PopupMenuButton<TunerInstrument>(
            icon: const Icon(Icons.music_note),
            tooltip: l.tunerInstrument,
            initialValue: _instrument,
            onSelected: (i) => setState(() {
              _instrument = i;
              _targetMidi = null;
              _smoothedCents = null;
            }),
            itemBuilder: (context) => [
              for (final i in TunerInstrument.values)
                PopupMenuItem(value: i, child: Text(_instrumentName(l, i))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                labelMidi >= 0 ? spelledMidiName(context, labelMidi) : '—',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: inTune ? Colors.green : scheme.onSurface,
                    ),
              ),
              Text(
                r.hasPitch
                    ? '${r.frequency.toStringAsFixed(1)} Hz  ·  clarity ${r.clarity.toStringAsFixed(2)}'
                    : (_targetMidi != null
                        ? l.tunerTuneString(
                            spelledMidiName(context, _targetMidi!),
                          )
                        : l.tunerPrompt),
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
                    cents: displayCents,
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
                inTune
                    ? l.tunerStringInTune
                    : (displayCents != null
                        ? l.tunerCents(
                            '${displayCents >= 0 ? '+' : ''}${displayCents.toStringAsFixed(0)}',
                          )
                        : ' '),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: inTune ? Colors.green : scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 24),
              if (_strings.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    for (final midi in _strings)
                      ChoiceChip(
                        label: Text(spelledMidiName(context, midi)),
                        selected: _targetMidi == midi,
                        // A played string that isn't the target still lights up
                        // faintly so you can see what the tuner hears.
                        backgroundColor: _targetMidi == null &&
                                r.hasPitch &&
                                _adjMidi(r) == midi
                            ? scheme.primaryContainer
                            : null,
                        onSelected: (sel) => setState(() {
                          _targetMidi = sel ? midi : null;
                          _smoothedCents = null;
                        }),
                      ),
                  ],
                ),
              if (_strings.isNotEmpty && _targetMidi == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.tunerPickString,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              const Spacer(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorText(l),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(_listening ? l.micStop : l.micStart),
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
