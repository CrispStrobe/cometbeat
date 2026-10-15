// lib/core/harmony/streamed_band.dart
//
// BB-T1 for a screen: one object that plays a chart's band through the window
// stream, so the chart screen and gig mode do not each re-wire the cache,
// feeder and player.
//
// [play] returns the band's timeline and a clock that runs with the SOUND
// (started when the first window lands, paused while the stream waits), or
// null when streaming is unavailable here — the caller then falls back to the
// whole render it always had.
library;

import 'dart:async';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/band_streamer.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_render_cache.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:comet_beat/core/services/band_stream_player.dart';

/// What a screen follows while a streamed band plays.
typedef StreamedBandRun = ({
  List<BandBarSpan> bars,
  int totalMs,
  Stopwatch clock,
});

class StreamedBand {
  StreamedBand({ChartRenderCache? cache, BandStreamPlayer? player})
      : cache = cache ?? ChartRenderCache(maxWindows: 96),
        _player = player ?? BandStreamPlayer();

  final ChartRenderCache cache;
  final BandStreamPlayer _player;
  late final _streamer = BandStreamer(cache: cache);
  Stopwatch? _clock;

  /// Starts [chart]'s band. Null when streaming is unavailable or there is no
  /// band — the caller falls back.
  Future<StreamedBandRun?> play(
    Chart chart, {
    required StyleSpec style,
    FormOptions form = const FormOptions(),
    BandMix mix = const BandMix(),
  }) async {
    await stop();
    if (!await _player.start(kSampleRate)) return null;
    final band = await prepareBandInIsolate(chart, style: style, form: form);
    if (band == null) {
      await _player.stop();
      return null;
    }
    final clock = Stopwatch();
    _clock = clock;
    _player.onBuffering = (buffering) {
      if (_clock != clock) return;
      buffering ? clock.stop() : clock.start();
    };
    unawaited(
      _streamer.feed(
        band,
        (pcm, index) {
          _player.add(pcm);
          if (index == 0) clock.start();
        },
        mix: mix,
      ).then((complete) {
        if (complete) _player.end();
      }),
    );
    return (bars: band.plan.bars, totalMs: band.plan.totalMs, clock: clock);
  }

  Future<void> stop() async {
    _streamer.cancel();
    _clock?.stop();
    _clock = null;
    await _player.stop();
  }
}

/// The bar sounding at [ms] in [bars], or null.
BandBarSpan? bandBarAt(List<BandBarSpan> bars, int ms) {
  for (final span in bars) {
    if (ms >= span.startMs && ms < span.endMs) return span;
  }
  return null;
}
