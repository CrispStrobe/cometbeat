import 'dart:typed_data';

import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/band_streamer.dart';
import 'package:comet_beat/core/harmony/chart_render_cache.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-T1 — the feeder that hands a player one window at a time.
const _rate = 8000;

final _chart = parseChartText(
  'tempo: 120\n[A]\n| C | Am | F | G |\n| C | Am | F | G |',
).chart;

PreparedBand _band() => prepareBand(
      planBand(_chart, style: styleFor('straight'))!,
      sampleRate: _rate,
    );

Future<BandStems> _sync(PreparedBand band, int index) async =>
    renderWindowStems(band, index);

Int16List _wholePcm() {
  final wav = renderBand(
    _chart,
    style: styleFor('straight'),
    sampleRate: _rate,
  )!
      .wav;
  return Int16List.sublistView(Uint8List.fromList(wav.sublist(44)));
}

void main() {
  test('sends every window, in order, and they make the whole piece', () async {
    final band = _band();
    final streamer = BandStreamer(
      cache: ChartRenderCache(sampleRate: _rate),
      render: _sync,
    );
    final order = <int>[];
    final pcm = <int>[];
    final complete = await streamer.feed(band, (stems, index) {
      order.add(index);
      pcm.addAll(mixWindow(band, stems));
    });
    expect(complete, isTrue);
    expect(order, List.generate(band.windows.length, (i) => i));
    expect(pcm, _wholePcm());
  });

  test('cancel stops before the next window', () async {
    final band = _band();
    expect(band.windows.length, greaterThan(1));
    late BandStreamer streamer;
    streamer = BandStreamer(
      cache: ChartRenderCache(sampleRate: _rate),
      render: _sync,
    );
    final sent = <int>[];
    final complete = await streamer.feed(band, (_, index) {
      sent.add(index);
      streamer.cancel(); // Stop pressed while the first window plays
    });
    expect(complete, isFalse);
    expect(sent, [0]);
  });

  test('a second Play is served from the cache', () async {
    final cache = ChartRenderCache(sampleRate: _rate);
    var rendered = 0;
    final streamer = BandStreamer(
      cache: cache,
      render: (band, i) {
        rendered++;
        return _sync(band, i);
      },
    );
    await streamer.feed(_band(), (_, __) {});
    final first = rendered;
    await streamer.feed(_band(), (_, __) {});
    expect(rendered, first, reason: 'nothing re-rendered');
    expect(cache.hits, first);
  });

  test('the isolate path prepares and renders the same audio', () async {
    final band = await prepareBandInIsolate(
      _chart,
      style: styleFor('straight'),
      sampleRate: _rate,
    );
    expect(band, isNotNull);
    final stems = await renderWindowInIsolate(band!, 0);
    final local = renderWindowStems(_band(), 0);
    expect(stems.comp, local.comp);
    expect(stems.drums, local.drums);
  });

  test('pieces from a window index, after its gate', () async {
    final band = _band();
    final streamer = BandStreamer(
      cache: ChartRenderCache(sampleRate: _rate),
      render: _sync,
    );
    final gated = <int>[];
    final sent = <int>[];
    await streamer.feed(
      band,
      (_, i) => sent.add(i),
      from: 1,
      gate: (i) async => gated.add(i),
    );
    expect(sent, List.generate(band.windows.length - 1, (i) => i + 1));
    expect(gated, sent);
  });

  test('a switch window is the old carry-in plus the new own starts', () {
    // Switching a plan to ITSELF must sound exactly like not switching.
    final band = _band();
    final plain = renderWindowStems(band, 1);
    final spliced = addStems(
      renderWindowStems(band, 1, part: WindowPart.carryIn),
      renderWindowStems(band, 1, part: WindowPart.ownStarts),
    );
    for (final (a, b) in [
      (plain.comp, spliced.comp),
      (plain.bass, spliced.bass),
      (plain.drums, spliced.drums),
    ]) {
      for (var i = 0; i < a.length; i++) {
        expect(b[i], closeTo(a[i], 1e-9));
      }
    }
    // And the carry-in is real: somewhere, something rings over a bar line.
    final rings = [
      for (var w = 1; w < band.windows.length; w++)
        renderWindowStems(band, w, part: WindowPart.carryIn),
    ].any(
      (c) => [...c.comp, ...c.bass, ...c.drums].any((v) => v != 0),
    );
    expect(rings, isTrue);
  });

  test('scaled stems sum to the mix (the voices ARE the mix)', () {
    final band = _band();
    final stems = renderWindowStems(band, 0);
    final voices = scaleStems(band, stems);
    final mixed = mixWindow(band, stems);
    for (var i = 0; i < mixed.length; i++) {
      final sum = voices[0][i] + voices[1][i] + voices[2][i];
      expect(
        (sum.clamp(-1.0, 1.0) * 32767).round(),
        closeTo(mixed[i], 1),
        reason: 'float32 voices, one LSB of rounding',
      );
    }
  });
}
