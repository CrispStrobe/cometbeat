import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Charts survive leaving the screen.
///
/// This is also the first thing that ever exercised `chart_codec` end to end —
/// it has been able to serialise a `Chart` since BB-D2 with no caller, so the
/// round-trip assertions here are load-bearing, not incidental.
Chart _chart(String text) => parseChartText(text).chart;

Future<ChartStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return ChartStore(await SharedPreferences.getInstance());
}

void main() {
  const source = 'title: Blues\nkey: C\ntempo: 100\n[A] x2\n| C7 | F7 |';

  group('named charts', () {
    test('a saved chart comes back with its music intact', () async {
      final store = await _store();
      final before = _chart(source);
      await store.save('My Blues', before);

      final after = store.find('My Blues')!.chart!;
      expect(after.title, 'Blues');
      expect(after.tempoBpm, 100);
      expect(after.keyFifths, 0);
      expect(after.sections.single.passes, 2);
      expect(
        after.barsInPlayOrder
            .map((b) => b.chordsInOrder.map((c) => c.chord.text).join()),
        ['C7', 'F7', 'C7', 'F7'],
      );
    });

    test('saving under the same name replaces rather than duplicates',
        () async {
      final store = await _store();
      await store.save('Tune', _chart('| C |'), nowMs: 1);
      await store.save('Tune', _chart('| G | Am |'), nowMs: 2);

      final list = store.list();
      expect(list, hasLength(1));
      expect(list.single.chart!.totalBars, 2);
    });

    test('the list is newest first', () async {
      final store = await _store();
      await store.save('old', _chart('| C |'), nowMs: 100);
      await store.save('new', _chart('| G |'), nowMs: 200);
      expect(store.list().map((c) => c.name), ['new', 'old']);
    });

    test('remove forgets one and keeps the rest', () async {
      final store = await _store();
      await store.save('a', _chart('| C |'), nowMs: 1);
      await store.save('b', _chart('| G |'), nowMs: 2);
      await store.remove('a');
      expect(store.list().map((c) => c.name), ['b']);
    });

    test('an empty chart is refused', () async {
      final store = await _store();
      await store.save('nothing', const Chart());
      expect(store.list(), isEmpty);
    });

    test('a blank name is refused', () async {
      final store = await _store();
      await store.save('   ', _chart('| C |'));
      expect(store.list(), isEmpty);
    });

    test('the name is trimmed, so " x " and "x" are one chart', () async {
      final store = await _store();
      await store.save('x', _chart('| C |'), nowMs: 1);
      await store.save('  x  ', _chart('| G |'), nowMs: 2);
      expect(store.list(), hasLength(1));
    });

    test('the oldest is dropped past the cap', () async {
      final store = await _store();
      for (var i = 0; i <= ChartStore.maxCharts; i++) {
        await store.save('chart$i', _chart('| C |'), nowMs: i);
      }
      final list = store.list();
      expect(list, hasLength(ChartStore.maxCharts));
      expect(list.map((c) => c.name), isNot(contains('chart0')));
      expect(list.first.name, 'chart${ChartStore.maxCharts}');
    });
  });

  group('the working chart', () {
    test('is restored after leaving the screen', () async {
      final store = await _store();
      await store.saveWorking(_chart('| Dm7 | G7 | Cmaj7 |'));

      // A fresh store over the same prefs — what a new screen sees.
      final reopened = ChartStore(await SharedPreferences.getInstance());
      expect(reopened.readWorking()!.totalBars, 3);
    });

    test('is NOT in the named list', () async {
      // An autosave that fills the library with "Untitled 7" is worse than no
      // autosave at all.
      final store = await _store();
      await store.saveWorking(_chart('| C |'));
      expect(store.list(), isEmpty);
    });

    test('an empty chart clears the slot rather than storing a blank',
        () async {
      final store = await _store();
      await store.saveWorking(_chart('| C |'));
      await store.saveWorking(const Chart());
      expect(store.readWorking(), isNull);
    });

    test('nothing saved reads as null, not as an empty chart', () async {
      final store = await _store();
      expect(store.readWorking(), isNull);
    });
  });

  group('corrupt storage', () {
    test('a corrupt store reads as empty rather than throwing', () async {
      // A throw at start-up is unrecoverable; an empty list is not.
      final store = await _store({'charts_v1': 'not json at all'});
      expect(store.list(), isEmpty);
    });

    test('one bad row does not cost the whole list', () async {
      final good = await _store();
      await good.save('keep', _chart('| C |'), nowMs: 1);
      final raw = (await SharedPreferences.getInstance())
          .getString('charts_v1')!
          .replaceFirst('[', '[{"nonsense":true},');

      final store = await _store({'charts_v1': raw});
      expect(store.list().map((c) => c.name), ['keep']);
    });

    test('a row whose chart no longer decodes surfaces as null, not a throw',
        () async {
      final store = await _store({
        'charts_v1': '[{"name":"broken","json":"{oops}","savedAtMs":1}]',
      });
      expect(store.list(), hasLength(1));
      expect(store.list().single.chart, isNull);
    });

    test('a corrupt working slot reads as null', () async {
      final store = await _store({'chart_working_v1': 'nope'});
      expect(store.readWorking(), isNull);
    });
  });

  group('codec fidelity through the store', () {
    test('sections, repeats, meter and split bars all survive', () async {
      final store = await _store();
      final before = _chart(
        'title: Everything\ncomposer: Nobody\nkey: Bb\nmeter: 3/4\ntempo: 132\n'
        '[Intro] x3\n| Cmaj7 | F#m7b5 |\n[A]\n| Bb13 Eb7 | % | Am7 |',
      );
      await store.save('everything', before);
      final after = store.find('everything')!.chart!;

      expect(after.title, before.title);
      expect(after.composer, before.composer);
      expect(after.keyFifths, before.keyFifths);
      expect(after.meter, before.meter);
      expect(after.tempoBpm, before.tempoBpm);
      expect(
        after.sections.map((s) => s.label),
        before.sections.map((s) => s.label),
      );
      expect(
        after.sections.map((s) => s.passes),
        before.sections.map((s) => s.passes),
      );
      expect(after.totalBars, before.totalBars);

      // The split bar keeps both chords AND their beat positions.
      final split = after.sections[1].bars.first.chordsInOrder;
      expect(split.map((c) => c.chord.text), ['Bb13', 'Eb7']);
      expect(split.map((c) => c.beat), [0, 1.5]);

      // The held bar stays held rather than becoming a copy of its neighbour.
      expect(after.sections[1].bars[1].chords, isEmpty);
    });
  });
}
