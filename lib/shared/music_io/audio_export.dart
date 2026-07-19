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
//
// Passing a second channel via [right] exports true stereo (joint M/S for MP3,
// interleaved for WAV). MP3 export uses short/transient blocks by default —
// this is offline, so we spend a little encode time to cut pre-echo on
// percussive material (drums, beatbox, tracker/DAW mixes); it is byte-identical
// to the long-only path when there are no transients.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart'
    show mp3EncodeMono, mp3EncodeJointStereo;
import 'package:comet_beat/core/audio/synth.dart'
    show kSampleRate, wavBytes, wavBytesStereo;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Clamps float PCM to 16-bit and wraps it in a WAV container. When [right] is
/// given, both channels are interleaved into a stereo WAV.
Uint8List pcmFloatToWav(
  Float64List pcm, {
  int sampleRate = kSampleRate,
  Float64List? right,
}) {
  if (right == null) {
    final i16 = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      i16[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return wavBytes(i16, sampleRate: sampleRate);
  }
  final n = pcm.length > right.length ? pcm.length : right.length;
  final il = Int16List(n * 2);
  for (var i = 0; i < n; i++) {
    final l = i < pcm.length ? pcm[i] : 0.0;
    final r = i < right.length ? right[i] : 0.0;
    il[i * 2] = (l.clamp(-1.0, 1.0) * 32767).round();
    il[i * 2 + 1] = (r.clamp(-1.0, 1.0) * 32767).round();
  }
  return wavBytesStereo(il, sampleRate: sampleRate);
}

/// Encodes float PCM to an MP3 bitstream (constant bitrate, kbps). When [right]
/// is given, encodes joint (M/S) stereo. [shortBlocks] (default on for offline
/// export) switches to short blocks over transients to cut pre-echo.
Uint8List pcmFloatToMp3(
  Float64List pcm, {
  int sampleRate = kSampleRate,
  int bitrate = 128,
  Float64List? right,
  bool shortBlocks = true,
}) =>
    right == null
        ? mp3EncodeMono(
            pcm,
            sampleRate: sampleRate,
            bitrate: bitrate,
            shortBlocks: shortBlocks,
          )
        : mp3EncodeJointStereo(
            pcm,
            right,
            sampleRate: sampleRate,
            bitrate: bitrate,
            shortBlocks: shortBlocks,
          );

/// One exportable audio format.
enum AudioExportFormat { wav, mp3 }

extension _Fmt on AudioExportFormat {
  String get ext => switch (this) {
        AudioExportFormat.wav => 'wav',
        AudioExportFormat.mp3 => 'mp3',
      };

  Uint8List build(
    Float64List pcm,
    int sampleRate, {
    Float64List? right,
    bool shortBlocks = true,
  }) =>
      switch (this) {
        AudioExportFormat.wav =>
          pcmFloatToWav(pcm, sampleRate: sampleRate, right: right),
        AudioExportFormat.mp3 => pcmFloatToMp3(
            pcm,
            sampleRate: sampleRate,
            right: right,
            shortBlocks: shortBlocks,
          ),
      };
}

/// Shows the audio-format picker; on pick, builds the bytes and prompts for a
/// save location. [baseName] seeds the suggested filename (no extension).
Future<void> showAudioExportSheet(
  BuildContext context, {
  required Float64List pcm,
  required String baseName,
  int sampleRate = kSampleRate,
  Float64List? rightPcm,
  bool shortBlocks = true,
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
                        rightPcm,
                        shortBlocks,
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
  Float64List? right,
  bool shortBlocks,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes =
        fmt.build(pcm, sampleRate, right: right, shortBlocks: shortBlocks);
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
