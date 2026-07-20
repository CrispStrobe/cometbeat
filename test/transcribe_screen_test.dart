// N2 UI — the Transcribe screen, driven headlessly through its test seams (no
// file-picker, no mic, no ONNX): a fake audio source hands it a synthesized
// scale WAV, and the screen must run the pipeline and show a result with an
// "Open in Song Book" action.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:comet_beat/features/games/transcribe/transcribe_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

Uint8List _scaleWav() {
  const midis = [60, 62, 64, 65, 67];
  const beat = 0.5;
  final noteN = (beat * 0.85 * _sr).round();
  final restN = (beat * 0.15 * _sr).round();
  final pcm = Int16List(midis.length * (noteN + restN));
  var off = 0;
  for (final m in midis) {
    final f = _hz(m);
    for (var i = 0; i < noteN; i++) {
      final env = min(1.0, min(i, noteN - i) / (0.01 * _sr));
      pcm[off + i] = (0.5 * env * sin(2 * pi * f * i / _sr) * 32767).round();
    }
    off += noteN + restN;
  }
  return wavBytes(pcm);
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('transcribes an injected WAV and offers to open it', (t) async {
    final wav = _scaleWav();
    await t.pumpWidget(
      _app(
        TranscribeScreen(
          debugPickAudio: () async => wav,
          debugNeural: ({bool download = false}) async => null, // no neural
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Kick off the transcription (the pick button doubles as "go").
    await t.tap(find.text(l10n.transcribePickFile));
    await t.pumpAndSettle();

    // A result card with the note count + an "Open in Song Book" action.
    expect(find.text(l10n.transcribeOpenSongBook), findsOneWidget);
    expect(find.textContaining('BPM'), findsOneWidget);
  });

  testWidgets('the neural-pitch toggle routes F0 through the CREPE seam',
      (t) async {
    final wav = _scaleWav();
    var crepeUsed = false;
    await t.pumpWidget(
      _app(
        TranscribeScreen(
          debugPickAudio: () async => wav,
          debugNeural: ({bool download = false}) async => null,
          // No RMVPE, so the resolver falls to CREPE (RMVPE is preferred when
          // present — this keeps the test deterministic regardless of caches).
          debugRmvpe: ({bool download = false}) async => null,
          // A stand-in CREPE estimator: flags that it ran, then delegates to the
          // real pYIN so the pipeline still produces notes.
          debugCrepe: ({bool download = false}) async =>
              (Float64List mono, int sr) {
            crepeUsed = true;
            return pyinF0(mono, sampleRate: sr);
          },
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Opt into neural pitch, then transcribe.
    await t.tap(find.text(l10n.transcribeNeuralPitch));
    await t.pumpAndSettle();
    await t.tap(find.text(l10n.transcribePickFile));
    await t.pumpAndSettle();

    expect(crepeUsed, isTrue, reason: 'CREPE estimator should have been used');
    expect(find.text(l10n.transcribeOpenSongBook), findsOneWidget);
  });

  testWidgets('a cancelled pick leaves no result and no spinner', (t) async {
    await t.pumpWidget(
      _app(
        TranscribeScreen(
          debugPickAudio: () async => null, // user cancelled
          debugNeural: ({bool download = false}) async => null,
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l10n.transcribePickFile));
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(l10n.transcribeOpenSongBook), findsNothing);
  });
}
