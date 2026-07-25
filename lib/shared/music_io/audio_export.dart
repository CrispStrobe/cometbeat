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

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart'
    show resampleCubic;
import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart'
    show mp3EncodeMono, mp3EncodeJointStereo;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Clamps float PCM and wraps it in a WAV container. When [right] is given,
/// both channels are interleaved into a stereo WAV. If [sourceSampleRate]
/// differs from [sampleRate], PCM is resampled before encoding.
Uint8List pcmFloatToWav(
  Float64List pcm, {
  int sampleRate = kSampleRate,
  int? sourceSampleRate,
  Float64List? right,
  int bitDepth = 16,
}) {
  if (bitDepth != 8 && bitDepth != 16 && bitDepth != 24 && bitDepth != 32) {
    throw ArgumentError.value(
      bitDepth,
      'bitDepth',
      'must be 8, 16, 24, or 32',
    );
  }
  final left = _resampleForExport(
    pcm,
    sourceSampleRate: sourceSampleRate,
    exportSampleRate: sampleRate,
  );
  final rightAtRate = right == null
      ? null
      : _resampleForExport(
          right,
          sourceSampleRate: sourceSampleRate,
          exportSampleRate: sampleRate,
        );
  final channels = right == null ? 1 : 2;
  final frames = rightAtRate == null
      ? left.length
      : (left.length > rightAtRate.length ? left.length : rightAtRate.length);
  final bytesPerSample = bitDepth ~/ 8;
  final blockAlign = channels * bytesPerSample;
  final dataSize = frames * blockAlign;
  final bytes = Uint8List(44 + dataSize);
  final bd = ByteData.sublistView(bytes);

  void writeAscii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  bd.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * blockAlign, Endian.little);
  bd.setUint16(32, blockAlign, Endian.little);
  bd.setUint16(34, bitDepth, Endian.little);
  writeAscii(36, 'data');
  bd.setUint32(40, dataSize, Endian.little);

  var offset = 44;
  void writeSample(double sample) {
    final clamped = sample.clamp(-1.0, 1.0);
    switch (bitDepth) {
      case 8:
        bytes[offset++] = (clamped * 127 + 128).round().clamp(0, 255);
      case 16:
        bd.setInt16(offset, (clamped * 32767).round(), Endian.little);
        offset += 2;
      case 24:
        var v = (clamped * 8388607).round();
        if (v < 0) v += 1 << 24;
        bytes[offset++] = v & 0xFF;
        bytes[offset++] = (v >> 8) & 0xFF;
        bytes[offset++] = (v >> 16) & 0xFF;
      case 32:
        bd.setInt32(offset, (clamped * 2147483647).round(), Endian.little);
        offset += 4;
    }
  }

  for (var i = 0; i < frames; i++) {
    writeSample(i < left.length ? left[i] : 0.0);
    if (rightAtRate != null) {
      writeSample(i < rightAtRate.length ? rightAtRate[i] : 0.0);
    }
  }
  return bytes;
}

Float64List _resampleForExport(
  Float64List pcm, {
  required int? sourceSampleRate,
  required int exportSampleRate,
}) {
  if (exportSampleRate <= 0) {
    throw ArgumentError.value(
      exportSampleRate,
      'sampleRate',
      'must be positive',
    );
  }
  final sourceRate = sourceSampleRate ?? exportSampleRate;
  if (sourceRate <= 0) {
    throw ArgumentError.value(
      sourceSampleRate,
      'sourceSampleRate',
      'must be positive',
    );
  }
  if (sourceRate == exportSampleRate || pcm.isEmpty) return pcm;
  return resampleCubic(pcm, sourceRate / exportSampleRate);
}

/// Encodes float PCM to an MP3 bitstream (constant bitrate, kbps). When [right]
/// is given, encodes joint (M/S) stereo. [shortBlocks] (default on for offline
/// export) switches to short blocks over transients to cut pre-echo.
Uint8List pcmFloatToMp3(
  Float64List pcm, {
  int sampleRate = kSampleRate,
  int? sourceSampleRate,
  int bitrate = 128,
  Float64List? right,
  bool shortBlocks = true,
}) {
  final left = _resampleForExport(
    pcm,
    sourceSampleRate: sourceSampleRate,
    exportSampleRate: sampleRate,
  );
  final rightAtRate = right == null
      ? null
      : _resampleForExport(
          right,
          sourceSampleRate: sourceSampleRate,
          exportSampleRate: sampleRate,
        );
  return rightAtRate == null
      ? mp3EncodeMono(
          left,
          sampleRate: sampleRate,
          bitrate: bitrate,
          shortBlocks: shortBlocks,
        )
      : mp3EncodeJointStereo(
          left,
          rightAtRate,
          sampleRate: sampleRate,
          bitrate: bitrate,
          shortBlocks: shortBlocks,
        );
}

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
    int? exportSampleRate,
    int wavBitDepth = 16,
    int mp3Bitrate = 128,
    bool shortBlocks = true,
  }) {
    final outRate = exportSampleRate ?? sampleRate;
    return switch (this) {
      AudioExportFormat.wav => pcmFloatToWav(
          pcm,
          sampleRate: outRate,
          sourceSampleRate: sampleRate,
          right: right,
          bitDepth: wavBitDepth,
        ),
      AudioExportFormat.mp3 => pcmFloatToMp3(
          pcm,
          sampleRate: outRate,
          sourceSampleRate: sampleRate,
          bitrate: mp3Bitrate,
          right: right,
          shortBlocks: shortBlocks,
        ),
    };
  }
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
  var selectedFormat = AudioExportFormat.wav;
  var selectedRate = sampleRate;
  var selectedWavBitDepth = 16;
  var selectedMp3Bitrate = 128;
  final rateChoices = _uniqueRates([sampleRate, kSampleRate, 48000, 32000]);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SafeArea(
        child: SingleChildScrollView(
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
              _ExportChoiceRow<AudioExportFormat>(
                label: 'Format',
                values: AudioExportFormat.values,
                selected: selectedFormat,
                labelFor: (format) => switch (format) {
                  AudioExportFormat.wav => l10n.audioExportWav,
                  AudioExportFormat.mp3 => l10n.audioExportMp3,
                },
                onSelected: (format) =>
                    setSheetState(() => selectedFormat = format),
              ),
              const SizedBox(height: 10),
              _ExportChoiceRow<int>(
                label: 'Sample rate',
                values: rateChoices,
                selected: selectedRate,
                labelFor: _sampleRateLabel,
                onSelected: (rate) => setSheetState(() => selectedRate = rate),
              ),
              const SizedBox(height: 10),
              if (selectedFormat == AudioExportFormat.wav)
                _ExportChoiceRow<int>(
                  label: 'Bit depth',
                  values: const [8, 16, 24, 32],
                  selected: selectedWavBitDepth,
                  labelFor: (depth) => '$depth-bit',
                  onSelected: (depth) =>
                      setSheetState(() => selectedWavBitDepth = depth),
                )
              else
                _ExportChoiceRow<int>(
                  label: 'Bitrate',
                  values: const [128, 192, 320],
                  selected: selectedMp3Bitrate,
                  labelFor: (bitrate) => '$bitrate kbps',
                  onSelected: (bitrate) =>
                      setSheetState(() => selectedMp3Bitrate = bitrate),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: Text(
                    selectedFormat == AudioExportFormat.wav
                        ? 'Export WAV'
                        : 'Export MP3',
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _exportAs(
                      context,
                      selectedFormat,
                      pcm,
                      baseName,
                      sampleRate,
                      rightPcm,
                      selectedRate,
                      selectedWavBitDepth,
                      selectedMp3Bitrate,
                      shortBlocks,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

List<int> _uniqueRates(List<int> rates) {
  final out = <int>[];
  for (final rate in rates) {
    if (rate > 0 && !out.contains(rate)) out.add(rate);
  }
  return out;
}

String _sampleRateLabel(int sampleRate) => sampleRate % 1000 == 0
    ? '${sampleRate ~/ 1000} kHz'
    : '${sampleRate / 1000} kHz';

class _ExportChoiceRow<T> extends StatelessWidget {
  const _ExportChoiceRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(labelFor(value)),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }
}

/// One lane's audio, for a batch stems export.
class AudioStem {
  const AudioStem({required this.name, required this.pcm, this.right});

  /// Used in the filename — the lane's name.
  final String name;
  final Float64List pcm;
  final Float64List? right;
}

/// Export SEVERAL stems in one go: pick a format, pick a folder, write one file
/// per lane. Silent lanes are skipped rather than written as empty files.
///
/// Picking a folder needs a directory picker, which desktop has and mobile
/// doesn't. Where it's unavailable this degrades to a save prompt per stem —
/// more taps, but it still works, which beats hiding the feature.
Future<void> showAudioStemsExportSheet(
  BuildContext context, {
  required List<AudioStem> stems,
  required String baseName,
  int sampleRate = kSampleRate,
  bool shortBlocks = true,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final sounding = [
    for (final s in stems)
      if (s.pcm.isNotEmpty) s,
  ];
  if (sounding.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.audioExportEmpty)));
    return;
  }

  var format = AudioExportFormat.wav;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text(l10n.audioExportStemsTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.audioExportStemsCount(sounding.length)),
              const SizedBox(height: 12),
              _ExportChoiceRow<AudioExportFormat>(
                label: 'Format',
                values: AudioExportFormat.values,
                selected: format,
                labelFor: (f) => switch (f) {
                  AudioExportFormat.wav => 'WAV (uncompressed)',
                  AudioExportFormat.mp3 => 'MP3 (smaller)',
                },
                onSelected: (f) => setDialog(() => format = f),
              ),
              const SizedBox(height: 8),
              for (final s in sounding)
                Text(
                  '• $baseName-${_slug(s.name)}.${format.ext}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.audioExportStemsSave),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;

  String? directory;
  var perFilePrompt = false;
  try {
    directory = await getDirectoryPath();
    // A null path here means the user cancelled — respect that.
    if (directory == null) return;
  } catch (_) {
    // No directory picker on this platform (mobile): ask per file instead.
    perFilePrompt = true;
  }

  var written = 0;
  for (final stem in sounding) {
    final name = '$baseName-${_slug(stem.name)}.${format.ext}';
    try {
      final bytes = format.build(
        stem.pcm,
        sampleRate,
        right: stem.right,
        shortBlocks: shortBlocks,
      );
      if (perFilePrompt) {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: [
            XTypeGroup(
              label: format.ext.toUpperCase(),
              extensions: [format.ext],
            ),
          ],
        );
        if (location == null) continue; // skipped this one
        await XFile.fromData(bytes, name: name).saveTo(location.path);
      } else {
        await XFile.fromData(bytes, name: name).saveTo(_join(directory!, name));
      }
      written++;
    } catch (_) {
      // Keep going: one bad lane shouldn't abandon the other stems.
    }
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        written == 0
            ? l10n.audioExportFailed
            : l10n.audioExportStemsSaved(written),
      ),
    ),
  );
}

/// Join a directory and a filename. Deliberately NOT `dart:io`'s separator —
/// this file is web-safe and must stay importable there; a directory picker
/// only exists on desktop anyway, and Windows accepts '/' in file paths.
String _join(String directory, String name) {
  final windows = directory.contains(r'\') && !directory.contains('/');
  final sep = windows ? r'\' : '/';
  return directory.endsWith(sep) ? '$directory$name' : '$directory$sep$name';
}

/// A filename-safe version of a lane name.
String _slug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'track' : slug;
}

Future<void> _exportAs(
  BuildContext context,
  AudioExportFormat fmt,
  Float64List pcm,
  String baseName,
  int sampleRate,
  Float64List? right,
  int exportSampleRate,
  int? wavBitDepth,
  int? mp3Bitrate,
  bool shortBlocks,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = fmt.build(
      pcm,
      sampleRate,
      right: right,
      exportSampleRate: exportSampleRate,
      wavBitDepth: wavBitDepth ?? 16,
      mp3Bitrate: mp3Bitrate ?? 128,
      shortBlocks: shortBlocks,
    );
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
