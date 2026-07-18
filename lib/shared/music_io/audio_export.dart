// lib/shared/music_io/audio_export.dart
//
// A reusable "export this rendered audio" sheet. Any screen that holds mono
// PCM as a Float64List (Sound Lab, Voice Lab, and — later — the trackers and
// Loop Mixer) can offer WAV (uncompressed) or MP3 (compressed, much smaller)
// from one place instead of copy-pasting a bespoke WAV saver.
//
// Both encoders are pure Dart (`wavBytes`, `mp3EncodeMono`) so this is
// web-safe. MP3 needs a 44100/48000/32000 Hz rate — the app renders at
// kSampleRate (44100), so the default path always encodes.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart' show mp3EncodeMono;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate, wavBytes;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Clamps mono float PCM to 16-bit and wraps it in a WAV container.
Uint8List pcmFloatToWav(Float64List pcm, {int sampleRate = kSampleRate}) {
  final i16 = Int16List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    i16[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return wavBytes(i16, sampleRate: sampleRate);
}

/// Encodes mono float PCM to an MP3 bitstream (constant bitrate, kbps).
Uint8List pcmFloatToMp3(
  Float64List pcm, {
  int sampleRate = kSampleRate,
  int bitrate = 128,
}) =>
    mp3EncodeMono(pcm, sampleRate: sampleRate, bitrate: bitrate);

/// One exportable audio format.
enum AudioExportFormat { wav, mp3 }

extension _Fmt on AudioExportFormat {
  String get ext => switch (this) {
        AudioExportFormat.wav => 'wav',
        AudioExportFormat.mp3 => 'mp3',
      };

  Uint8List build(Float64List pcm, int sampleRate) => switch (this) {
        AudioExportFormat.wav => pcmFloatToWav(pcm, sampleRate: sampleRate),
        AudioExportFormat.mp3 => pcmFloatToMp3(pcm, sampleRate: sampleRate),
      };
}

/// Shows the audio-format picker; on pick, builds the bytes and prompts for a
/// save location. [baseName] seeds the suggested filename (no extension).
Future<void> showAudioExportSheet(
  BuildContext context, {
  required Float64List pcm,
  required String baseName,
  int sampleRate = kSampleRate,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  if (pcm.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.audioExportEmpty)));
    return;
  }
  final choices = <(AudioExportFormat, String)>[
    (AudioExportFormat.wav, l10n.audioExportWav),
    (AudioExportFormat.mp3, l10n.audioExportMp3),
  ];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.audioExportTitle,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (fmt, label) in choices)
                  ActionChip(
                    label: Text(label),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _exportAs(
                        context,
                        fmt,
                        pcm,
                        baseName,
                        sampleRate,
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _exportAs(
  BuildContext context,
  AudioExportFormat fmt,
  Float64List pcm,
  String baseName,
  int sampleRate,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = fmt.build(pcm, sampleRate);
    final suggested = '$baseName.${fmt.ext}';
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: [
        XTypeGroup(label: fmt.ext.toUpperCase(), extensions: [fmt.ext]),
      ],
    );
    if (location == null) return;
    await XFile.fromData(bytes, name: suggested).saveTo(location.path);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.audioExportSavedTo(location.path))),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.audioExportFailed)));
  }
}
