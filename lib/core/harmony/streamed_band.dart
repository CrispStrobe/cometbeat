// lib/core/harmony/streamed_band.dart
//
// BB-T1/BB-U3 for a screen: one object that plays a chart's band through the
// window stream, so the chart screen and gig mode do not each re-wire the
// cache, feeder and player.
//
// [play] returns the band's timeline and a clock that runs with the SOUND
// (started when the first window lands, paused while the stream waits), or
// null when streaming is unavailable here — the caller then falls back to the
// whole render it always had.
//
// While it plays:
//  * rendering stays [leadMs] ahead of the playhead, no further — so a change
//    of style can still land soon;
//  * [restyle] re-plans the piece and takes over from the next window not yet
//    queued, which is always a bar line;
//  * [roles] (level / mute / solo per comp, bass, drums) are voice volumes:
//    instant, nothing re-renders.
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

/// The band's three voices, in stream order.
enum BandRole { comp, bass, drums }

/// Live level / mute / solo per role. Pure: [volumeOf] is the whole rule.
class BandRoleMix {
  final Map<BandRole, double> _level = {for (final r in BandRole.values) r: 1};
  final Map<BandRole, double> _pan = {for (final r in BandRole.values) r: 0};
  final Set<BandRole> muted = {};
  final Set<BandRole> soloed = {};

  double levelOf(BandRole role) => _level[role]!;
  double panOf(BandRole role) => _pan[role]!;
  void setPan(BandRole role, double pan) => _pan[role] = pan.clamp(-1.0, 1.0);
  void setLevel(BandRole role, double level) =>
      _level[role] = level.clamp(0.0, 2.0);

  /// The voice volume: 0 when muted, or when another role is soloed and this
  /// one is not; otherwise the level.
  double volumeOf(BandRole role) {
    if (muted.contains(role)) return 0;
    if (soloed.isNotEmpty && !soloed.contains(role)) return 0;
    return levelOf(role);
  }
}

class StreamedBand {
  StreamedBand({
    ChartRenderCache? cache,
    BandStreamPlayer? player,
    this.leadMs = 6000,
  })  : cache = cache ?? ChartRenderCache(maxWindows: 96),
        _player = player ?? BandStreamPlayer();

  final ChartRenderCache cache;
  final BandStreamPlayer _player;

  /// How far ahead of the playhead windows are rendered and queued.
  final int leadMs;

  final roles = BandRoleMix();

  late final _streamer = BandStreamer(cache: cache);
  Stopwatch? _clock;
  PreparedBand? _band;
  Chart? _chart;
  FormOptions _form = const FormOptions();
  int _sent = 0;

  bool get playing => _band != null;

  /// Starts [chart]'s band. Null when streaming is unavailable or there is no
  /// band — the caller falls back.
  Future<StreamedBandRun?> play(
    Chart chart, {
    required StyleSpec style,
    FormOptions form = const FormOptions(),
  }) async {
    await stop();
    if (!await _player.start(kSampleRate, voices: BandRole.values.length)) {
      return null;
    }
    final band = await prepareBandInIsolate(chart, style: style, form: form);
    if (band == null) {
      await _player.stop();
      return null;
    }
    final clock = Stopwatch();
    _clock = clock;
    _band = band;
    _chart = chart;
    _form = form;
    _sent = 0;
    _player.onBuffering = (buffering) {
      if (_clock != clock) return;
      buffering ? clock.stop() : clock.start();
    };
    _applyRoles();
    _feed(band, from: 0);
    return (bars: band.plan.bars, totalMs: band.plan.totalMs, clock: clock);
  }

  /// Switches to [style] from the next window not yet queued. False when not
  /// playing, or too late (everything is queued).
  Future<bool> restyle(StyleSpec style) async {
    final old = _band;
    final chart = _chart;
    if (old == null || chart == null) return false;
    final next = await prepareBandInIsolate(chart, style: style, form: _form);
    if (next == null || _band != old) return false;
    // A style changes what plays, not where the bars are; if the windows ever
    // disagreed, splicing would misplace the music, so refuse instead.
    if (!_sameWindows(old, next)) return false;
    final from = _sent;
    if (from >= next.windows.length) return false;
    _band = next;
    _feed(next, from: from, previous: old);
    return true;
  }

  /// Re-applies [roles] to the voices — call after changing them.
  void applyRoles() => _applyRoles();

  void _applyRoles() {
    for (final role in BandRole.values) {
      _player.setVolume(role.index, roles.volumeOf(role));
      _player.setPan(role.index, roles.panOf(role));
    }
  }

  void _feed(PreparedBand band, {required int from, PreparedBand? previous}) {
    final clock = _clock!;
    unawaited(
      _streamer.feed(
        band,
        (stems, index) {
          _player.add(scaleStems(band, stems));
          _sent = index + 1;
          if (index == 0) clock.start();
        },
        from: from,
        previous: previous,
        gate: (index) => _waitForLead(band, index, clock),
      ).then((complete) {
        if (complete && _band == band) _player.end();
      }),
    );
  }

  /// Holds window [index] back until it is within [leadMs] of the playhead.
  Future<void> _waitForLead(
    PreparedBand band,
    int index,
    Stopwatch clock,
  ) async {
    final startMs = band.windows[index].startSample * 1000 ~/ band.sampleRate;
    while (_clock == clock && startMs - clock.elapsedMilliseconds > leadMs) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> stop() async {
    _streamer.cancel();
    _clock?.stop();
    _clock = null;
    _band = null;
    _chart = null;
    await _player.stop();
  }
}

bool _sameWindows(PreparedBand a, PreparedBand b) {
  if (a.windows.length != b.windows.length) return false;
  for (var i = 0; i < a.windows.length; i++) {
    if (a.windows[i] != b.windows[i]) return false;
  }
  return true;
}

/// The bar sounding at [ms] in [bars], or null.
BandBarSpan? bandBarAt(List<BandBarSpan> bars, int ms) {
  for (final span in bars) {
    if (ms >= span.startMs && ms < span.endMs) return span;
  }
  return null;
}
