import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_render_cache.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-T1 — the band a window at a time.
///
/// The load-bearing assertion is the first: windows laid end to end are
/// `renderBand`'s samples exactly. Everything else (seams, levels, caching)
/// rests on it.
const _rate = 8000;

Chart _chart(String text) => parseChartText(text).chart;

const _blues = 'tempo: 132\n[A]\n| C7 | F7 | C7 | C7 |\n'
    '| F7 | F7 | C7 | C7 |\n| G7 | F7 | C7 | G7 |';

BandPlan _plan(
  Chart chart, {
  String style = 'straight',
  int choruses = 1,
  bool humanize = true,
}) =>
    planBand(
      chart,
      style: styleFor(style),
      form: FormOptions(choruses: choruses),
      humanize: humanize,
    )!;

/// The whole-piece PCM `renderBand` produces (the WAV minus its header).
Int16List _whole(Chart chart, {String style = 'straight', int choruses = 1}) {
  final wav = renderBand(
    chart,
    style: styleFor(style),
    form: FormOptions(choruses: choruses),
    sampleRate: _rate,
  )!
      .wav;
  return Int16List.fromList(
    ByteData.sublistView(wav, 44).buffer.asInt16List(wav.offsetInBytes + 44),
  );
}

Int16List _windowed(
  Chart chart, {
  String style = 'straight',
  int choruses = 1,
  int barsPerWindow = 4,
  ChartRenderCache? cache,
}) {
  final band = prepareBand(
    _plan(chart, style: style, choruses: choruses),
    barsPerWindow: barsPerWindow,
    sampleRate: _rate,
  );
  final out = <int>[];
  for (var i = 0; i < band.windows.length; i++) {
    final stems =
        cache == null ? renderWindowStems(band, i) : cache.stems(band, i);
    out.addAll(mixWindow(band, stems));
  }
  return Int16List.fromList(out);
}

void main() {
  group('windows are an exact crop of the whole render', () {
    for (final style in ['straight', 'swing', 'bossa']) {
      test('$style, two choruses', () {
        final chart = _chart(_blues);
        final whole = _whole(chart, style: style, choruses: 2);
        final windowed = _windowed(chart, style: style, choruses: 2);
        expect(windowed.length, whole.length);
        expect(windowed, whole, reason: 'every sample, seams included');
      });
    }

    test('any window size, including one bar', () {
      final chart = _chart(_blues);
      final whole = _whole(chart);
      for (final bars in [1, 3, 5, 100]) {
        expect(_windowed(chart, barsPerWindow: bars), whole, reason: '$bars');
      }
    });
  });

  test('other comp and bass voices stay exact, and key their own windows', () {
    final chart = _chart(_blues);
    final wav = renderBand(
      chart,
      style: styleFor('straight'),
      sampleRate: _rate,
      compInstrument: Instrument.flute,
      bassInstrument: Instrument.cello,
    )!
        .wav;
    final whole = Int16List.sublistView(Uint8List.fromList(wav.sublist(44)));
    final band = prepareBand(
      _plan(chart),
      sampleRate: _rate,
      compInstrument: Instrument.flute,
      bassInstrument: Instrument.cello,
    );
    final out = <int>[
      for (var i = 0; i < band.windows.length; i++)
        ...mixWindow(band, renderWindowStems(band, i)),
    ];
    expect(out, whole);
    final piano = prepareBand(_plan(chart), sampleRate: _rate);
    expect(windowKey(band, 0), isNot(windowKey(piano, 0)));
  });

  test('windows tile the piece on bar lines', () {
    final band = prepareBand(_plan(_chart(_blues)), sampleRate: _rate);
    expect(band.windows.first.startSample, 0);
    expect(band.windows.last.endSample, band.totalSamples);
    for (var i = 1; i < band.windows.length; i++) {
      expect(band.windows[i].startSample, band.windows[i - 1].endSample);
      expect(band.windows[i].firstBar, band.windows[i - 1].endBar);
    }
    expect(band.windowAt(0), 0);
    expect(band.windowAt(band.totalSamples + 99), band.windows.length - 1);
  });

  test('muting a role is a re-mix: the cached stems are reused', () {
    final cache = ChartRenderCache(sampleRate: _rate);
    final band = prepareBand(_plan(_chart(_blues)), sampleRate: _rate);
    final full = mixWindow(band, cache.stems(band, 1));
    final noDrums = mixWindow(
      band,
      cache.stems(band, 1),
      mix: const BandMix(drums: 0),
    );
    expect(cache.renders, 1);
    expect(cache.hits, 1);
    expect(noDrums, isNot(full));
  });

  group('the cache re-renders only what changed', () {
    test('playing an unchanged chart again renders nothing', () {
      // Re-planning is cheap and deterministic, so the second Play finds every
      // window. (Repeated choruses do NOT share windows: bar lines fall on
      // fractional milliseconds, so each bar's events sit a sample or two
      // differently against its window — and exactness keeps them there.)
      final cache = ChartRenderCache(sampleRate: _rate);
      for (var pass = 0; pass < 2; pass++) {
        final band = cache.prepare(_plan(_chart(_blues), choruses: 2));
        for (var i = 0; i < band.windows.length; i++) {
          cache.stems(band, i);
        }
        if (pass == 0) expect(cache.hits, 0);
      }
      expect(cache.hits, cache.renders);
    });

    test('a one-chord edit late in a long chart re-renders near the edit', () {
      // 96 bars: eight choruses of the blues as one long section.
      const chorus = [
        'C7',
        'F7',
        'C7',
        'C7',
        'F7',
        'F7',
        'C7',
        'C7',
        'G7',
        'F7',
        'C7',
        'G7',
      ];
      String text(List<String> chords) {
        final rows = [
          for (var i = 0; i < chords.length; i += 4)
            '| ${chords.sublist(i, i + 4).join(' | ')} |',
        ];
        return 'tempo: 132\n[A]\n${rows.join('\n')}';
      }

      final chords = [for (var c = 0; c < 8; c++) ...chorus];
      final long = _chart(text(chords));
      expect(long.sections.single.bars, hasLength(96));
      final cache = ChartRenderCache(sampleRate: _rate);
      final before = cache.prepare(_plan(long));
      for (var i = 0; i < before.windows.length; i++) {
        cache.stems(before, i);
      }

      // Bar 40 (index 39) becomes an A♭7.
      final edited = _chart(text([...chords]..[39] = 'Ab7'));
      final after = cache.prepare(_plan(edited));
      final rendered = cache.renders;
      for (var i = 0; i < after.windows.length; i++) {
        cache.stems(after, i);
      }
      final windowOfEdit = after.windows.indexWhere(
        (w) =>
            w.firstBar <= 39 + _leadIn(after) && 39 + _leadIn(after) < w.endBar,
      );
      expect(windowOfEdit, isNonNegative);
      expect(
        cache.renders - rendered,
        lessThanOrEqualTo(2),
        reason: 'the edited window, and at most its neighbour',
      );
      // And what was rendered is still exact.
      expect(_windowed(edited, cache: cache), _whole(edited));
    });
  });
}

/// Bars the form puts before the chart's first bar (a count-in).
int _leadIn(PreparedBand band) =>
    band.plan.bars.indexWhere((b) => b.bar.sourceBar != null);
