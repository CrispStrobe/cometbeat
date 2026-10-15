// lib/core/harmony/band_streamer.dart
//
// BB-T1 — feeds a prepared band to a player one window at a time.
//
// Windows go out strictly in order, each from the cache when its content was
// rendered before and otherwise synthesised off the UI thread. The loop runs
// ahead of the playhead as fast as rendering allows — that IS the prefetch —
// and a [cancel] (Stop, or a new Play) ends it between windows.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_render_cache.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';

/// Synthesises one window; [renderWindowInIsolate] in the app, synchronous in
/// tests.
typedef WindowRenderer = Future<BandStems> Function(
  PreparedBand band,
  int index,
);

/// Renders window [index] on a background isolate.
Future<BandStems> renderWindowInIsolate(PreparedBand band, int index) =>
    Isolate.run(() => renderWindowStems(band, index));

/// Plans and prepares [chart]'s band on a background isolate — the part of
/// Play that has to finish before the first window can render. Null when
/// there is nothing to play.
Future<PreparedBand?> prepareBandInIsolate(
  Chart chart, {
  required StyleSpec style,
  FormOptions form = const FormOptions(),
  int sampleRate = kSampleRate,
}) =>
    Isolate.run(() {
      final plan = planBand(chart, style: style, form: form);
      return plan == null ? null : prepareBand(plan, sampleRate: sampleRate);
    });

class BandStreamer {
  BandStreamer({required this.cache, WindowRenderer? render})
      : _render = render ?? renderWindowInIsolate;

  final ChartRenderCache cache;
  final WindowRenderer _render;
  int _generation = 0;

  /// Sends every window of [band] to [sink], in order, mixed with [mix].
  /// Completes true when all were sent, false when [cancel]led first.
  Future<bool> feed(
    PreparedBand band,
    void Function(Int16List pcm, int index) sink, {
    BandMix mix = const BandMix(),
  }) async {
    final generation = ++_generation;
    for (var i = 0; i < band.windows.length; i++) {
      final stems =
          cache.lookup(band, i) ?? cache.store(band, i, await _render(band, i));
      if (generation != _generation) return false;
      sink(mixWindow(band, stems, mix: mix), i);
    }
    return true;
  }

  /// Stops a running [feed] before its next window.
  void cancel() => _generation++;
}
