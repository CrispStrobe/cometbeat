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

import 'package:comet_beat/core/audio/synth.dart' show Instrument, kSampleRate;
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
  Instrument compInstrument = Instrument.piano,
  Instrument bassInstrument = Instrument.piano,
}) =>
    Isolate.run(() {
      final plan = planBand(chart, style: style, form: form);
      return plan == null
          ? null
          : prepareBand(
              plan,
              sampleRate: sampleRate,
              compInstrument: compInstrument,
              bassInstrument: bassInstrument,
            );
    });

class BandStreamer {
  BandStreamer({required this.cache, WindowRenderer? render})
      : _render = render ?? renderWindowInIsolate;

  final ChartRenderCache cache;
  final WindowRenderer _render;
  int _generation = 0;

  /// Sends windows of [band] to [sink], in order, from window [from].
  ///
  /// [gate] is awaited before each window — the pacing (how far ahead of the
  /// playhead to render); without one the loop runs as fast as rendering.
  /// [previous] is the plan that was playing before [band] replaced it
  /// mid-performance: window [from] is then its carry-in plus [band]'s own
  /// starts (see [WindowPart]), so the switch cuts nothing off and rings in
  /// nothing that never started.
  ///
  /// Completes true when every window was sent, false when [cancel]led.
  Future<bool> feed(
    PreparedBand band,
    void Function(BandStems stems, int index) sink, {
    int from = 0,
    Future<void> Function(int index)? gate,
    PreparedBand? previous,
  }) async {
    final generation = ++_generation;
    for (var i = from; i < band.windows.length; i++) {
      if (gate != null) await gate(i);
      if (generation != _generation) return false;
      final BandStems stems;
      if (previous != null && i == from) {
        // A one-off; not worth a cache slot.
        stems = addStems(
          renderWindowStems(previous, i, part: WindowPart.carryIn),
          renderWindowStems(band, i, part: WindowPart.ownStarts),
        );
      } else {
        stems = cache.lookup(band, i) ??
            cache.store(band, i, await _render(band, i));
      }
      if (generation != _generation) return false;
      sink(stems, i);
    }
    return true;
  }

  /// Stops a running [feed] before its next window.
  void cancel() => _generation++;
}
