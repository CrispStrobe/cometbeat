// O15 — the spectrogram view: a clip's frequency content over time.
//
// The waveform in the timeline shows how LOUD a clip is; this shows what's in
// it. Time runs left to right, frequency bottom (DC) to top (Nyquist), and
// brightness is level in dBFS. Useful for spotting rumble, hiss, a stuck mains
// hum, or exactly where one sound ends and the next begins.
//
// The maths lives in core/audio/spectrogram.dart (pure, tested headlessly);
// this file is only the painting.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/spectrogram.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Show [pcm] as a spectrogram in a dialog.
Future<void> showSpectrogramDialog(
  BuildContext context, {
  required Float64List pcm,
  required int sampleRate,
  String? title,
}) {
  final l10n = AppLocalizations.of(context)!;
  final spectrogram = computeSpectrogram(pcm, sampleRate: sampleRate);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? l10n.dawSpectrogram),
      content: SizedBox(
        width: 560,
        height: 300,
        child: spectrogram.frames.isEmpty
            ? Center(child: Text(l10n.dawSpectrogramEmpty))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRect(
                      child: CustomPaint(
                        painter: SpectrogramPainter(spectrogram),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Without a scale the picture is just pretty colours.
                  Text(
                    '0 Hz – ${(spectrogram.sampleRate / 2 / 1000).toStringAsFixed(1)} kHz  ·  '
                    '${(spectrogram.frames.length * spectrogram.frameMs / 1000).toStringAsFixed(2)} s  ·  '
                    '${spectrogram.floorDb.round()} … 0 dBFS',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.dawClose),
        ),
      ],
    ),
  );
}

/// Paints a [Spectrogram]: one column per frame, one row per frequency bin.
class SpectrogramPainter extends CustomPainter {
  const SpectrogramPainter(this.spectrogram);

  final Spectrogram spectrogram;

  /// dBFS → colour. A dark-to-hot ramp (near-black → blue → magenta → yellow)
  /// keeps quiet detail visible while loud partials still stand out.
  static Color colorFor(double db, double floorDb) {
    final t = ((db - floorDb) / (0 - floorDb)).clamp(0.0, 1.0);
    if (t < 0.5) {
      // black → blue → magenta
      final u = t / 0.5;
      return Color.fromARGB(
        255,
        (u * 180).round(),
        (u * 20).round(),
        (40 + u * 175).round(),
      );
    }
    // magenta → orange → yellow
    final u = (t - 0.5) / 0.5;
    return Color.fromARGB(
      255,
      (180 + u * 75).round(),
      (20 + u * 235).round(),
      (215 - u * 195).round(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frames = spectrogram.frames;
    if (frames.isEmpty || size.width <= 0 || size.height <= 0) return;
    final bins = spectrogram.bins;
    final colWidth = size.width / frames.length;
    final rowHeight = size.height / bins;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var t = 0; t < frames.length; t++) {
      final frame = frames[t];
      final x = t * colWidth;
      for (var b = 0; b < bins; b++) {
        // Bin 0 (DC) at the BOTTOM: low frequencies below, like every other
        // spectrogram and like a staff.
        final y = size.height - (b + 1) * rowHeight;
        paint.color = colorFor(frame[b], spectrogram.floorDb);
        canvas.drawRect(
          Rect.fromLTWH(x, y, colWidth + 0.5, rowHeight + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SpectrogramPainter old) => old.spectrogram != spectrogram;
}
