// lib/features/harmony/streamed_band.dart
//
// BB-T1 / BB-U3 / BB-T2 for a screen: one object that plays a chart's band
// through the window stream, so the chart screen and gig mode do not each
// re-wire the cache, transport and player.
//
// HOW IT PLAYS. The piece is prepared in ONE-BAR windows. A [ChartTransport]
// decides, one bar at a time and only a little ahead of the playhead, which
// realised bar plays next — the next one, the top of a loop, a jump target, or
// the next bar of a re-planned piece. Each bar is rendered off the UI thread
// (or found in the cache) and appended to the stream. Where the queue is not
// continuous, the bar is SPLICED: the previous source's carry-in (whatever was
// still ringing) plus the new bar's own starts, so nothing is cut off and
// nothing that never started rings in.
//
// THE CLOCK is the transport's `TransportService`, advanced by the audio's own
// elapsed time: a stopwatch that starts when the first bar lands and pauses
// whenever the stream waits for data. "Which bar is sounding" is the transport
// position looked up in the queue.
//
// LIVE CHANGES. [replan] (style, swing, intensity, voices, tempo) re-prepares
// the piece and takes over from the next bar queued; [roles] are voice
// volumes — instant, nothing re-renders.
//
// [play] returns null when streaming is unavailable here (a plain test, an
// unsupported platform); the caller then falls back to the whole render.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument, kSampleRate;
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/band_streamer.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_render_cache.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:comet_beat/core/services/band_stream_player.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/features/harmony/chart_transport.dart';
import 'package:comet_beat/features/harmony/practice_modes.dart';

/// The band's three voices, in stream order.
enum BandRole { comp, bass, drums }

/// Live level / mute / solo / pan per role. Pure: [volumeOf] is the whole rule.
class BandRoleMix {
  final Map<BandRole, double> _level = {for (final r in BandRole.values) r: 1};
  final Map<BandRole, double> _pan = {for (final r in BandRole.values) r: 0};
  final Set<BandRole> muted = {};
  final Set<BandRole> soloed = {};

  double levelOf(BandRole role) => _level[role]!;
  void setLevel(BandRole role, double level) =>
      _level[role] = level.clamp(0.0, 2.0);
  double panOf(BandRole role) => _pan[role]!;
  void setPan(BandRole role, double pan) => _pan[role] = pan.clamp(-1.0, 1.0);

  /// The voice volume: 0 when muted, or when another role is soloed and this
  /// one is not; otherwise the level.
  double volumeOf(BandRole role) {
    if (muted.contains(role)) return 0;
    if (soloed.isNotEmpty && !soloed.contains(role)) return 0;
    return levelOf(role);
  }
}

/// Everything that decides what the band plays, short of the chart.
class BandSettings {
  const BandSettings({
    required this.style,
    this.form = const FormOptions(),
    this.compInstrument = Instrument.piano,
    this.bassInstrument = Instrument.piano,
    this.click = BandClick.off,
    this.clickCountIn = false,
    this.kit = true,
  });

  final StyleSpec style;
  final FormOptions form;
  final Instrument compInstrument;
  final Instrument bassInstrument;
  final BandClick click;
  final bool clickCountIn;

  /// Whether the drum kit plays (a practice pass may leave only the click).
  final bool kit;

  /// These settings for one practice [pass] of [practice].
  BandSettings forPass(PassPlan pass) => BandSettings(
        style: style,
        form: FormOptions(
          choruses: form.choruses,
          countIn: form.countIn,
          ending: form.ending,
          baseIntensity: pass.intensity,
          liftLastChorus: form.liftLastChorus,
          phraseLength: form.phraseLength,
          seed: form.seed,
          countInBars: form.countInBars,
        ),
        compInstrument: compInstrument,
        bassInstrument: bassInstrument,
        click: pass.clickOnly && click == BandClick.off
            ? BandClick.everyBeat
            : click,
        clickCountIn: clickCountIn,
        kit: pass.kit,
      );
}

class StreamedBand {
  StreamedBand({
    ChartRenderCache? cache,
    BandStreamPlayer? player,
    TransportService? transport,
    this.leadMs = 2000,
  })  : cache = cache ?? ChartRenderCache(maxWindows: 256),
        _player = player ?? BandStreamPlayer(),
        transport = ChartTransport(transport ?? TransportService());

  final ChartRenderCache cache;
  final BandStreamPlayer _player;

  /// The bar queue and its clock.
  final ChartTransport transport;

  /// How far ahead of the playhead bars are queued. Small, so a jump or a
  /// change lands within a bar or two; large enough to ride out a slow render.
  final int leadMs;

  final roles = BandRoleMix();

  int _run = 0;
  Stopwatch? _clock;
  int _clockSyncedMs = 0;
  Chart? _chart;
  BandSettings? _settings;
  PreparedBand? _band;
  final Map<int, PreparedBand> _bandByGeneration = {};

  // BB-T3 practice: the base chart every pass is derived from, the pass now
  // playing and what it silences, and the NEXT pass already being prepared.
  PracticeConfig? _practice;
  Chart? _practiceChart;
  int _pass = 0;
  PassPlan? _passPlan;
  Future<({PreparedBand band, PassPlan plan})?>? _nextPass;

  /// The practice pass playing (0 = first time through); 0 when not practising.
  int get pass => _pass;

  bool get playing => _band != null;

  /// The bar sounding now, or null.
  QueuedBar? get current => transport.current;

  /// The realised bars of the plan now in play (the latest re-plan).
  List<BandBarSpan> get barsInPlay => _band?.plan.bars ?? const [];

  /// The run has played out (nothing more queued, playhead past the end).
  bool get finished => _band != null && transport.finished;

  /// Starts [chart]'s band. False when streaming is unavailable or there is no
  /// band — the caller falls back.
  /// With [practice], the form's body loops for ever and every time round is
  /// a practice pass (BB-T3).
  Future<bool> play(
    Chart chart,
    BandSettings settings, {
    PracticeConfig? practice,
  }) async {
    await stop();
    final run = _run;
    if (!await _player.start(kSampleRate, voices: BandRole.values.length)) {
      return false;
    }
    _practice = practice;
    _practiceChart = chart;
    _pass = 0;
    final first = practice == null
        ? null
        : passPlan(
            practice,
            chart,
            0,
            baseIntensity: settings.form.baseIntensity,
          );
    _passPlan = first;
    final band = first == null
        ? await _prepare(chart, settings)
        : await _prepare(first.chart, settings.forPass(first));
    if (band == null || run != _run) {
      await _player.stop();
      return false;
    }
    final clock = Stopwatch();
    _clock = clock;
    _clockSyncedMs = 0;
    _chart = chart;
    _settings = settings;
    _band = band;
    _player.onBuffering = (buffering) {
      if (_clock != clock) return;
      buffering ? clock.stop() : clock.start();
    };
    _applyRoles();
    transport.start(band.plan.bars);
    _bandByGeneration
      ..clear()
      ..[transport.generation] = band;
    if (practice != null) {
      // Loop the tune itself — not the count-in, not the ending.
      final bars = band.plan.bars;
      final first = bars.indexWhere((b) => b.bar.role == BarRole.tune);
      final last = bars.lastIndexWhere((b) => b.bar.role == BarRole.tune);
      if (first >= 0) transport.setLoop(first, last);
      _nextPass = _preparePass(1);
    }
    unawaited(_pump(run, clock));
    return true;
  }

  /// Re-plans with whatever is given — a chart (a new tempo), settings (style,
  /// swing, intensity, voices, click) — from the next bar queued. False when
  /// not playing.
  Future<bool> replan({Chart? chart, BandSettings? settings}) async {
    final old = _band;
    final run = _run;
    if (old == null) return false;
    final nextChart = chart ?? _chart!;
    final nextSettings = settings ?? _settings!;
    final next = await _prepare(nextChart, nextSettings);
    if (next == null || run != _run || _band != old) return false;
    _chart = nextChart;
    _settings = nextSettings;
    _band = next;
    transport.setBars(next.plan.bars);
    _bandByGeneration[transport.generation] = next;
    // The next pass was prepared with the old settings; prepare it again.
    if (_practice != null) _nextPass = _preparePass(_pass + 1);
    return true;
  }

  /// Re-applies [roles] to the voices — call after changing them.
  void applyRoles() => _applyRoles();

  /// Moves the transport to the audio's elapsed time. The pump does this
  /// itself; a screen calls it from its tick so the highlight is current.
  void sync() {
    final clock = _clock;
    if (clock == null) return;
    final now = clock.elapsedMilliseconds;
    final delta = now - _clockSyncedMs;
    _clockSyncedMs = now;
    if (delta > 0) transport.transport.advance(delta.toDouble());
  }

  Future<void> stop() async {
    _run++;
    _clock?.stop();
    _clock = null;
    _band = null;
    _chart = null;
    _settings = null;
    _bandByGeneration.clear();
    _practice = null;
    _practiceChart = null;
    _passPlan = null;
    _nextPass = null;
    _pass = 0;
    transport.stop();
    await _player.stop();
  }

  // -------------------------------------------------------------------------

  Future<PreparedBand?> _prepare(Chart chart, BandSettings s) =>
      prepareBandInIsolate(
        chart,
        style: s.style,
        form: s.form,
        compInstrument: s.compInstrument,
        bassInstrument: s.bassInstrument,
        barsPerWindow: 1,
        click: s.click,
        clickCountIn: s.clickCountIn,
        kit: s.kit,
      );

  void _applyRoles() {
    for (final role in BandRole.values) {
      _player.setVolume(role.index, roles.volumeOf(role));
      _player.setPan(role.index, roles.panOf(role));
    }
  }

  /// Queues, renders and appends bars until the run ends or is replaced.
  Future<void> _pump(int run, Stopwatch clock) async {
    QueuedBar? previous;
    var first = true;
    while (run == _run) {
      sync();
      if (transport.queuedAheadMs > leadMs) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      if (_atPassWrap()) {
        if (!await _advancePass(run)) return;
      }
      final queued = transport.enqueueNext();
      if (queued == null) {
        _player.end();
        return;
      }
      final band = _bandByGeneration[queued.generation]!;
      final List<Float32List> voices;
      if (ChartTransport.isDiscontinuity(previous, queued)) {
        voices = await _splice(
          _bandByGeneration[previous!.generation]!,
          previous.bar + 1,
          band,
          queued.bar,
        );
      } else {
        final stems = cache.lookup(band, queued.bar) ??
            cache.store(
              band,
              queued.bar,
              await renderWindowInIsolate(band, queued.bar),
            );
        voices = scaleStems(band, stems);
      }
      if (run != _run) return;
      _player.add(_practiced(voices, queued));
      if (first) {
        clock.start();
        first = false;
      }
      previous = queued;
    }
  }

  /// Whether the next bar queued starts a new practice pass (the loop wraps).
  bool _atPassWrap() {
    if (_practice == null) return false;
    final loop = transport.loop;
    final queue = transport.queue;
    return loop != null &&
        queue.isNotEmpty &&
        queue.last.bar == loop.last &&
        transport.peekNext() == loop.first;
  }

  /// Swaps in the prepared next pass and starts preparing the one after.
  /// False when the run ended while waiting.
  Future<bool> _advancePass(int run) async {
    final next = await _nextPass;
    if (run != _run) return false;
    if (next == null) return true; // nothing to play differently: keep going
    _pass++;
    _passPlan = next.plan;
    _band = next.band;
    _chart = next.plan.chart;
    transport.setBars(next.band.plan.bars);
    _bandByGeneration[transport.generation] = next.band;
    _nextPass = _preparePass(_pass + 1);
    return true;
  }

  Future<({PreparedBand band, PassPlan plan})?> _preparePass(int pass) async {
    final practice = _practice;
    final chart = _practiceChart;
    final settings = _settings;
    if (practice == null || chart == null || settings == null) return null;
    final plan = passPlan(
      practice,
      chart,
      pass,
      baseIntensity: settings.form.baseIntensity,
    );
    final band = await _prepare(plan.chart, settings.forPass(plan));
    return band == null ? null : (band: band, plan: plan);
  }

  /// A queued bar's voices with the pass's faded roles silenced, or all of
  /// them on a drop-out bar.
  List<Float32List> _practiced(List<Float32List> voices, QueuedBar queued) {
    final practice = _practice;
    final plan = _passPlan;
    if (practice == null || plan == null) return voices;
    final role = queued.span?.bar.role;
    if (role != BarRole.tune) return voices; // never silence the count-in
    final drop = isDropOut(practice, _pass, queued.bar);
    if (!drop && plan.silent.isEmpty) return voices;
    return [
      for (final r in BandRole.values)
        drop || plan.silent.contains(r)
            ? Float32List(voices[r.index].length)
            : voices[r.index],
    ];
  }

  /// The bar [toBar] of [to], entered from [from] where bar [fromNext] would
  /// have come next: [from]'s carry-in, fitted to the new bar's length, plus
  /// [to]'s own starts — each at its own plan's levels.
  Future<List<Float32List>> _splice(
    PreparedBand from,
    int fromNext,
    PreparedBand to,
    int toBar,
  ) async {
    final own =
        await renderWindowInIsolate(to, toBar, part: WindowPart.ownStarts);
    final ownVoices = scaleStems(to, own);
    if (fromNext >= from.windows.length) return ownVoices;
    final carry = await renderWindowInIsolate(
      from,
      fromNext,
      part: WindowPart.carryIn,
    );
    final carryVoices = scaleStems(from, carry);
    return [
      for (var v = 0; v < ownVoices.length; v++)
        _sumFitted(ownVoices[v], carryVoices[v]),
    ];
  }
}

/// [base] plus as much of [extra] as fits in it.
Float32List _sumFitted(Float32List base, Float32List extra) {
  final out = Float32List.fromList(base);
  final n = extra.length < out.length ? extra.length : out.length;
  for (var i = 0; i < n; i++) {
    out[i] += extra[i];
  }
  return out;
}
