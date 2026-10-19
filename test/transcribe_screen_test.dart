// N2 UI — the Transcribe screen, driven headlessly through its test seams (no
// file-picker, no mic, no ONNX): a fake audio source hands it a synthesized
// scale WAV, and the screen must run the pipeline and show a result with an
// "Open in Song Book" action.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart' show Stems;
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/transcribe/transcribe_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Pump until [done] shows, letting real time pass between frames.
///
/// ⚠️ Not `pumpAndSettle` alone: the pipeline awaits real asynchronous work
/// (engine and model probing), which the test's fake clock never advances —
/// the spinner then animates until pumpAndSettle times out, on some machines
/// and CI runner images and not others. `runAsync` lets that work finish.
Future<void> _untilShown(WidgetTester t, Finder done) async {
  for (var i = 0; i < 200 && done.evaluate().isEmpty; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

void main() {
  testWidgets('transcribes an injected WAV and offers to open it', (t) async {
    final wav = _scaleWav();
    await t.pumpWidget(
      _app(
        TranscribeScreen(
          debugPickAudio: () async => wav,
          debugNeural: ({bool download = false}) async => null, // no neural
          // Stub the model loaders so a machine-cached RMVPE/CREPE/BTC doesn't
          // load a real (huge) ONNX model and stall pumpAndSettle.
          debugRmvpe: ({bool download = false}) async => null,
          debugCrepe: ({bool download = false}) async => null,
          debugHarmony: ({bool download = false}) async => null,
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Kick off the transcription (the pick button doubles as "go").
    await t.tap(find.text(l10n.transcribePickFile));
    await _untilShown(t, find.text(l10n.transcribeOpenSongBook));

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
          debugHarmony: ({bool download = false}) async => null,
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Opt into neural pitch, then transcribe.
    await t.tap(find.text(l10n.transcribeNeuralPitch));
    await t.pumpAndSettle();
    await t.tap(find.text(l10n.transcribePickFile));
    await _untilShown(t, find.text(l10n.transcribeOpenSongBook));

    expect(crepeUsed, isTrue, reason: 'CREPE estimator should have been used');
    expect(find.text(l10n.transcribeOpenSongBook), findsOneWidget);
  });

  testWidgets('whole-song mode → multi-part result saved to the Song Book',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final songs = UserSongsService();
    await songs.load();
    final wav = _scaleWav();
    // A fake separator that returns the mix as a single vocal stem → one part.
    Future<Stems> fakeSep(Float64List mono, int sr) async =>
        (vocals: mono, bass: null, drums: null, other: null);

    await t.pumpWidget(
      _app(
        ChangeNotifierProvider<UserSongsService>.value(
          value: songs,
          child: TranscribeScreen(
            debugPickAudio: () async => wav,
            debugNeural: ({bool download = false}) async => null,
            debugRmvpe: ({bool download = false}) async => null,
            debugCrepe: ({bool download = false}) async => null,
            debugHarmony: ({bool download = false}) async => null,
            debugSeparator: () async => fakeSep,
          ),
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Turn on whole-song mode, then transcribe.
    await t.tap(find.text(l10n.transcribeWholeSong));
    await t.pumpAndSettle();
    await t.tap(find.text(l10n.transcribePickFile));
    await _untilShown(t, find.text(l10n.transcribeSaveSongBook));

    // A multi-part result with a "Save to Song Book" action.
    expect(find.text(l10n.transcribeSaveSongBook), findsOneWidget);

    // Saving adds a multi-part song to the library.
    final before = songs.songs.length;
    await t.tap(find.text(l10n.transcribeSaveSongBook));
    await t.pumpAndSettle();
    expect(songs.songs.length, before + 1);
    expect(songs.songs.last.musicXml, contains('score-partwise'));
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
