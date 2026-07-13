// lib/features/games/chords/chord_listen_spike_screen.dart
//
// Fuzzy chord recognition from the live mic. Strum a guitar or play a chord on a
// keyboard; it names the closest chord and shows runner-up guesses plus the
// 12-bin pitch-class profile it heard. Deliberately approximate — see
// chroma_analysis.dart for why "name the chord" beats "transcribe every note".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/audio/chroma_analysis.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/l10n/app_localizations.dart';

/// A chord candidate named in the learner's convention, e.g. "Am", "G7", or
/// "Hm" in German — the root spelled via the note-naming setting, suffix as-is.
String _candidateName(BuildContext context, ChordCandidate c) =>
    '${spelledMidiName(context, 60 + c.rootPc, withOctave: false)}${c.suffix}';

class ChordListenSpikeScreen extends StatefulWidget {
  const ChordListenSpikeScreen({super.key});

  @override
  State<ChordListenSpikeScreen> createState() => _ChordListenSpikeScreenState();
}

class _ChordListenSpikeScreenState extends State<ChordListenSpikeScreen> {
  late final MicrophonePitchService _service =
      MicrophonePitchService(chordDetector: ChordDetector());
  StreamSubscription<ChordReading>? _sub;

  ChordReading _reading = ChordReading.silent();
  ({PitchCaptureError reason, String? detail})? _error;
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
        _reading = ChordReading.silent();
      });
      return;
    }

    setState(() => _error = null);
    try {
      _sub = _service.chords.listen(
        (r) {
          if (mounted) setState(() => _reading = r);
        },
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

  String _errorText(AppLocalizations l) => switch (_error!.reason) {
        PitchCaptureError.permissionDenied => l.micPermissionDenied,
        PitchCaptureError.unsupported => l.micUnsupported,
        _ => l.micStartFailed(_error!.detail ?? _error!.reason.name),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final r = _reading;
    final best = r.best;

    return Scaffold(
      appBar: GameAppBar(title: l.gameChordListener),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                best == null ? '—' : _candidateName(context, best),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
              ),
              Text(
                best == null
                    ? l.chordListenerPrompt
                    : l.chordListenerMatch((best.score * 100).round()),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              // Runner-up guesses, so the fuzziness is visible.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  for (final c in r.candidates.skip(1))
                    Chip(
                      label: Text(
                        '${_candidateName(context, c)}  '
                        '${(c.score * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                l.chordListenerHeard,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: _ChromaBars(
                  chroma: r.chroma,
                  barColor: scheme.primary,
                  labelColor: scheme.onSurfaceVariant,
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

/// A 12-bar bar chart of the pitch-class profile (C … B).
class _ChromaBars extends StatelessWidget {
  const _ChromaBars({
    required this.chroma,
    required this.barColor,
    required this.labelColor,
  });

  final List<double> chroma;
  final Color barColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var pc = 0; pc < 12; pc++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    heightFactor:
                        chroma.length == 12 ? chroma[pc].clamp(0.0, 1.0) : 0.0,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  spelledMidiName(context, 60 + pc, withOctave: false),
                  style: TextStyle(fontSize: 10, color: labelColor),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
