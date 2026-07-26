// lib/shared/music_io/audio_export.dart
//
// A reusable "export this rendered audio" sheet. Any screen that holds mono
// PCM as a Float64List (Sound Lab, Voice Lab, and — later — the trackers and
// Loop Mixer) can offer WAV (uncompressed), MP3, Opus or AAC from one place
// instead of copy-pasting a bespoke WAV saver.
//
// WAV and MP3 are pure Dart (`wavBytes`, `mp3EncodeMono`) so this file stays
// web-safe and must remain importable there. MP3 needs a 44100/48000/32000 Hz
// rate — the app renders at kSampleRate (44100), so the default path always
// encodes.
//
// Opus and AAC come from the native glint encoder over FFI (native/glint), and
// are offered ONLY where that symbol resolved — see availableAudioExportFormats.
// On web, in `flutter test`, or on any platform without the plugin, the sheet
// shows exactly the list it showed before this existed. Opus at ~96 kbps is
// transparent for music at a fraction of MP3's size and is the right default
// for sharing a mix from a phone.
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
import 'package:comet_beat/core/audio/sf2/encode_capability.dart'
    show
        EncodeAudio,
        EncodedAudioFormat,
        EncodedAudioFormatX,
        ensureGlintCodecReady,
        loadGlintEncoder;
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
    throw ArgumentError.value(bitDepth, 'bitDepth', 'must be 8, 16, 24, or 32');
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

/// Encodes float PCM to Opus or AAC through the native glint encoder.
///
/// Unlike WAV/MP3 above this is NOT pure Dart — it needs the glint FFI plugin,
/// so callers must have an [EncodeAudio] in hand (see [nativeAudioEncoder]).
/// glint takes interleaved PCM and resamples internally to a rate the codec
/// allows, so we hand it whatever we have and let it pick: **Opus always comes
/// back at 48 kHz** no matter what was requested, which is why the sheet's
/// sample-rate choice is advisory for these formats.
///
/// Throws [StateError] if the encoder refuses the input, so the caller's
/// existing try/catch reports a failed export rather than writing a truncated
/// file.
Uint8List pcmFloatToNative(
  Float64List pcm, {
  required EncodeAudio encode,
  required EncodedAudioFormat format,
  int sampleRate = kSampleRate,
  int? sourceSampleRate,
  int bitrate = 128,
  Float64List? right,
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

  final channels = rightAtRate == null ? 1 : 2;
  final Float64List interleaved;
  if (rightAtRate == null) {
    interleaved = left;
  } else {
    final frames =
        left.length > rightAtRate.length ? left.length : rightAtRate.length;
    interleaved = Float64List(frames * 2);
    for (var i = 0; i < frames; i++) {
      interleaved[i * 2] = i < left.length ? left[i] : 0.0;
      interleaved[i * 2 + 1] = i < rightAtRate.length ? rightAtRate[i] : 0.0;
    }
  }

  final bytes = encode(
    interleaved,
    channels: channels,
    sampleRate: sampleRate,
    format: format,
    bitrateKbps: bitrate,
  );
  if (bytes == null || bytes.isEmpty) {
    throw StateError('glint could not encode ${format.label}');
  }
  return bytes;
}

/// Which MP3 encoder to use. Two exist and they are genuinely different code:
///
/// * [dart] — our own pure-Dart port (`lib/core/audio/mp3/`). Works EVERYWHERE
///   including web, and is the historical default, so its output is what the
///   golden tests pin.
/// * [native] — glint's C encoder through FFI or wasm. Faster, and the more
///   mature of the two (it is the encoder the Dart one was ported from), but it
///   only exists where the glint plugin/wasm loaded.
///
/// The default stays [dart] deliberately: it is the better-exercised path here
/// and keeps exports byte-comparable across platforms. Flipping the default is
/// a one-line change in [showAudioExportSheet] if the native one proves out.
enum Mp3Encoder { dart, native }

extension Mp3EncoderX on Mp3Encoder {
  String get label => switch (this) {
        Mp3Encoder.dart => 'Built-in',
        Mp3Encoder.native => 'Native (faster)',
      };
}

/// One exportable audio format.
///
/// APPEND new values — the export UI and any future persisted project field
/// are both happier that way.
enum AudioExportFormat { wav, mp3, opus, aac }

extension AudioExportFormatX on AudioExportFormat {
  String get ext => switch (this) {
        AudioExportFormat.wav => 'wav',
        AudioExportFormat.mp3 => 'mp3',
        AudioExportFormat.opus => 'opus',
        AudioExportFormat.aac => 'm4a',
      };

  /// Short name for buttons ("Export Opus").
  String get shortLabel => switch (this) {
        AudioExportFormat.wav => 'WAV',
        AudioExportFormat.mp3 => 'MP3',
        AudioExportFormat.opus => 'Opus',
        AudioExportFormat.aac => 'AAC',
      };

  /// True when this format needs the native glint encoder, i.e. it is only
  /// offered where [nativeAudioEncoder] resolved.
  bool get needsNativeEncoder => switch (this) {
        AudioExportFormat.wav || AudioExportFormat.mp3 => false,
        AudioExportFormat.opus || AudioExportFormat.aac => true,
      };

  /// The glint format this maps to, or null for the pure-Dart formats.
  EncodedAudioFormat? get nativeFormat => switch (this) {
        AudioExportFormat.wav || AudioExportFormat.mp3 => null,
        AudioExportFormat.opus => EncodedAudioFormat.opus,
        AudioExportFormat.aac => EncodedAudioFormat.aac,
      };

  /// Compressed formats take a bitrate; WAV takes a bit depth.
  bool get isCompressed => this != AudioExportFormat.wav;

  Uint8List build(
    Float64List pcm,
    int sampleRate, {
    Float64List? right,
    int? exportSampleRate,
    int wavBitDepth = 16,
    int bitrate = 128,
    bool shortBlocks = true,
    EncodeAudio? nativeEncoder,
    Mp3Encoder mp3Encoder = Mp3Encoder.dart,
  }) {
    final outRate = exportSampleRate ?? sampleRate;
    // MP3 can go through EITHER encoder. Asking for the native one where it
    // isn't available falls back to the Dart writer rather than failing the
    // export — unlike Opus/AAC, MP3 always has a working path, so refusing
    // would be gratuitous.
    var native = nativeFormat;
    if (this == AudioExportFormat.mp3 && mp3Encoder == Mp3Encoder.native) {
      final probe = nativeEncoder ?? nativeAudioEncoder();
      if (probe != null) native = EncodedAudioFormat.mp3;
    }
    if (native != null) {
      final encode = nativeEncoder ?? nativeAudioEncoder();
      if (encode == null) {
        throw StateError('no native encoder for ${native.label} on this build');
      }
      return pcmFloatToNative(
        pcm,
        encode: encode,
        format: native,
        sampleRate: outRate,
        sourceSampleRate: sampleRate,
        bitrate: bitrate,
        right: right,
      );
    }
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
          bitrate: bitrate,
          right: right,
          shortBlocks: shortBlocks,
        ),
      // Unreachable: nativeFormat != null was handled above.
      _ => throw StateError('unhandled format $this'),
    };
  }
}

/// The formats this build can actually write.
///
/// Web and any platform without the glint plugin get exactly today's list
/// (WAV + the pure-Dart MP3 writer) — the native formats are added only when
/// the encoder resolved, so nothing can be picked that would fail at save time.
List<AudioExportFormat> availableAudioExportFormats({EncodeAudio? encoder}) {
  final native = encoder ?? nativeAudioEncoder();
  return [
    for (final f in AudioExportFormat.values)
      if (!f.needsNativeEncoder || native != null) f,
  ];
}

// The native encoder is resolved once per process: loadGlintEncoder() does a
// dynamic-symbol lookup, and it cannot change at runtime.
EncodeAudio? _nativeEncoder;
bool _nativeEncoderProbed = false;

/// The glint encoder, or null where it isn't linked in (web, `flutter test`,
/// any platform without the plugin).
EncodeAudio? nativeAudioEncoder() {
  if (!_nativeEncoderProbed) {
    _nativeEncoderProbed = true;
    _nativeEncoder = loadGlintEncoder();
  }
  return _nativeEncoder;
}

/// Make the encoder usable, then report whether it is.
///
/// Natively this is immediate — the symbols are linked in or they aren't. On
/// WEB the glint wasm is fetched lazily, so this must be awaited once before
/// [nativeAudioEncoder] returns anything useful; without it the web export
/// sheet would offer Opus/AAC on the first open and then fail to encode.
/// Cheap and idempotent, so both export sheets just await it up front.
Future<bool> prepareNativeAudioEncoder() async {
  if (_nativeEncoderProbed && _nativeEncoder != null) return true;
  final ok = await ensureGlintCodecReady();
  // Re-probe: on web the loader only yields a working encoder post-init.
  _nativeEncoderProbed = false;
  return nativeAudioEncoder() != null && ok;
}

/// Test seam: pin the encoder (or null to force the no-native path) so the
/// gating logic is exercisable headless. Pass nothing to reset to a fresh
/// probe.
@visibleForTesting
void debugSetNativeAudioEncoder(EncodeAudio? encoder, {bool probed = true}) {
  _nativeEncoder = encoder;
  _nativeEncoderProbed = probed;
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
  var selectedBitrate = 128;
  var selectedMp3Encoder = Mp3Encoder.dart;
  final rateChoices = _uniqueRates([sampleRate, kSampleRate, 48000, 32000]);
  // On web this loads the glint wasm; native returns immediately.
  await prepareNativeAudioEncoder();
  if (!context.mounted) return;
  final formats = availableAudioExportFormats();
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
                values: formats,
                selected: selectedFormat,
                labelFor: (format) => _formatLabel(l10n, format),
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
              // Opus is always 48 kHz on the wire; say so rather than let the
              // chip above quietly lie about what lands on disk.
              if (selectedFormat == AudioExportFormat.opus &&
                  selectedRate != 48000)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.audioExportOpusRateNote,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 10),
              if (!selectedFormat.isCompressed)
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
                  selected: selectedBitrate,
                  labelFor: (bitrate) => '$bitrate kbps',
                  onSelected: (bitrate) =>
                      setSheetState(() => selectedBitrate = bitrate),
                ),
              // Only for MP3, and only where both encoders actually exist —
              // offering a choice of one is noise.
              if (selectedFormat == AudioExportFormat.mp3 &&
                  nativeAudioEncoder() != null) ...[
                const SizedBox(height: 10),
                _ExportChoiceRow<Mp3Encoder>(
                  label: 'MP3 encoder',
                  values: Mp3Encoder.values,
                  selected: selectedMp3Encoder,
                  labelFor: (e) => e.label,
                  onSelected: (e) =>
                      setSheetState(() => selectedMp3Encoder = e),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: Text('Export ${selectedFormat.shortLabel}'),
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
                      selectedBitrate,
                      shortBlocks,
                      selectedMp3Encoder,
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

String _formatLabel(AppLocalizations l10n, AudioExportFormat format) =>
    switch (format) {
      AudioExportFormat.wav => l10n.audioExportWav,
      AudioExportFormat.mp3 => l10n.audioExportMp3,
      AudioExportFormat.opus => l10n.audioExportOpus,
      AudioExportFormat.aac => l10n.audioExportAac,
    };

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
  var mp3Encoder = Mp3Encoder.dart;
  await prepareNativeAudioEncoder();
  if (!context.mounted) return;
  final formats = availableAudioExportFormats();
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
                values: formats,
                selected: format,
                labelFor: (f) => _formatLabel(l10n, f),
                onSelected: (f) => setDialog(() => format = f),
              ),
              if (format == AudioExportFormat.mp3 &&
                  nativeAudioEncoder() != null) ...[
                const SizedBox(height: 8),
                _ExportChoiceRow<Mp3Encoder>(
                  label: 'MP3 encoder',
                  values: Mp3Encoder.values,
                  selected: mp3Encoder,
                  labelFor: (e) => e.label,
                  onSelected: (e) => setDialog(() => mp3Encoder = e),
                ),
              ],
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
        mp3Encoder: mp3Encoder,
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
  int? bitrate,
  bool shortBlocks,
  Mp3Encoder mp3Encoder,
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
      bitrate: bitrate ?? 128,
      shortBlocks: shortBlocks,
      mp3Encoder: mp3Encoder,
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
