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
