import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/setlist.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Setlists.
///
/// The card's acceptance is one precise invariant: **a chart in two setlists at
/// two keys plays at each set's key and the chart file is unchanged.** That is
/// the reason the override lives in the SET and not on the chart, and it is the
/// first thing asserted here.
Chart chart(String text) => parseChartText(text).chart;

List<String> symbols(Chart c) => [
      for (final bar in c.barsInPlayOrder)
        for (final chord in bar.chordsInOrder) chord.chord.text,
    ];

void main() {
  group("the card's invariant", () {
    test('one chart in two sets at two keys plays at each set\'s key', () {
      final tune = chart('key: C\n| C | Am | Dm7 | G7 |');

      const jazzNight = SetlistEntry(chartName: 'Tune');
      const singersGig = SetlistEntry(chartName: 'Tune', transposeSemitones: 3);

      expect(symbols(resolveEntry(tune, jazzNight)), ['C', 'Am', 'Dm7', 'G7']);
      expect(
        symbols(resolveEntry(tune, singersGig)),
        ['Eb', 'Cm', 'Fm7', 'Bb7'],
      );

      // …and the chart itself never moved.
      expect(symbols(tune), ['C', 'Am', 'Dm7', 'G7']);
      expect(tune.keyFifths, 0);
    });

    test('resolving does not mutate the chart, even repeatedly', () {
      final tune = chart('key: F\n| F | Bb |');
      const entry = SetlistEntry(chartName: 'x', transposeSemitones: 2);
      for (var i = 0; i < 5; i++) {
        resolveEntry(tune, entry);
      }
      expect(symbols(tune), ['F', 'Bb']);
      expect(tune.keyFifths, -1);
    });

    test('a per-set tempo overrides without touching the chart', () {
      final tune = chart('tempo: 120\n| C |');
      const slow = SetlistEntry(chartName: 'x', tempoBpm: 72);
      expect(resolveEntry(tune, slow).tempoBpm, 72);
      expect(tune.tempoBpm, 120);
    });

    test('key and tempo overrides compose', () {
      final tune = chart('key: C\ntempo: 120\n| C |');
      const entry =
          SetlistEntry(chartName: 'x', transposeSemitones: 2, tempoBpm: 90);
      final played = resolveEntry(tune, entry);
      expect(symbols(played), ['D']);
      expect(played.tempoBpm, 90);
    });

    test('a plain entry returns the chart unchanged', () {
      final tune = chart('| C | G |');
      const entry = SetlistEntry(chartName: 'x');
      expect(entry.isPlain, isTrue);
      expect(identical(resolveEntry(tune, entry), tune), isTrue);
    });
  });

  group('ordering', () {
    Setlist three() => const Setlist(
          name: 'Set 1',
          entries: [
            SetlistEntry(chartName: 'A'),
            SetlistEntry(chartName: 'B'),
            SetlistEntry(chartName: 'C'),
          ],
        );

    test('add appends', () {
      final set = three().add(const SetlistEntry(chartName: 'D'));
      expect(set.entries.map((e) => e.chartName), ['A', 'B', 'C', 'D']);
    });

    test('reorder moves one song', () {
      expect(
        three().reorder(0, 2).entries.map((e) => e.chartName),
        ['B', 'C', 'A'],
      );
      expect(
        three().reorder(2, 0).entries.map((e) => e.chartName),
        ['C', 'A', 'B'],
      );
    });

    test('removeAt drops one', () {
      expect(three().removeAt(1).entries.map((e) => e.chartName), ['A', 'C']);
    });

    test('replaceAt swaps one entry', () {
      final set = three().replaceAt(
        1,
        const SetlistEntry(chartName: 'B', transposeSemitones: 5),
      );
      expect(set.entries[1].transposeSemitones, 5);
      expect(set.entries.map((e) => e.chartName), ['A', 'B', 'C']);
    });

    test('an out-of-range index is a no-op, not a crash', () {
      // A stale index from a list widget must not end a gig.
      for (final set in [
        three().removeAt(-1),
        three().removeAt(99),
        three().reorder(0, 99),
        three().reorder(-1, 0),
        three().replaceAt(99, const SetlistEntry(chartName: 'X')),
      ]) {
        expect(set.entries.map((e) => e.chartName), ['A', 'B', 'C']);
      }
    });

    test('the original set is never mutated by an edit', () {
      final original = three();
      original.add(const SetlistEntry(chartName: 'D'));
      original.removeAt(0);
      original.reorder(0, 2);
      expect(original.entries.map((e) => e.chartName), ['A', 'B', 'C']);
    });
  });

  group('export and import round-trip', () {
    test('everything survives', () {
      const before = Setlist(
        name: 'Friday',
        entries: [
          SetlistEntry(chartName: 'Blue Bossa', transposeSemitones: -2),
          SetlistEntry(chartName: 'Autumn', tempoBpm: 88, note: 'capo 3'),
          SetlistEntry(chartName: 'Blues'),
        ],
      );
      final after = setlistFromJsonString(setlistToJsonString(before))!;

      expect(after.name, before.name);
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(after.entries[i].chartName, before.entries[i].chartName);
        expect(
          after.entries[i].transposeSemitones,
          before.entries[i].transposeSemitones,
        );
        expect(after.entries[i].tempoBpm, before.entries[i].tempoBpm);
        expect(after.entries[i].note, before.entries[i].note);
      }
    });

    test('the order is part of the data', () {
      const before = Setlist(
        name: 'x',
        entries: [
          SetlistEntry(chartName: 'C'),
          SetlistEntry(chartName: 'A'),
          SetlistEntry(chartName: 'B'),
        ],
      );
      final after = setlistFromJsonString(setlistToJsonString(before))!;
      expect(after.entries.map((e) => e.chartName), ['C', 'A', 'B']);
    });

    test('corrupt text is null rather than a throw', () {
      // A corrupt file must not take the screen down mid-gig.
      expect(setlistFromJsonString('not json'), isNull);
      expect(setlistFromJsonString('[]'), isNull);
      expect(setlistFromJsonString('{"entries":[]}'), isNull);
    });

    test('one bad entry does not cost the set', () {
      final set = setlistFromJsonString(
        '{"name":"x","entries":[{"chart":"A"},{"nonsense":1},{"chart":"B"}]}',
      )!;
      expect(set.entries.map((e) => e.chartName), ['A', 'B']);
    });

    test('defaults are omitted from the wire but read back the same', () {
      const plain = Setlist(
        name: 'x',
        entries: [SetlistEntry(chartName: 'A')],
      );
      final json = setlistToJsonString(plain);
      expect(json, isNot(contains('transpose')));
      expect(setlistFromJsonString(json)!.entries.single.isPlain, isTrue);
    });

    test('a nonsense tempo on the wire is ignored, not honoured', () {
      final set = setlistFromJsonString(
        '{"name":"x","entries":[{"chart":"A","tempo":0}]}',
      )!;
      expect(set.entries.single.tempoBpm, isNull);
    });
  });

  group('storage', () {
    Future<SetlistStore> store([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      return SetlistStore(await SharedPreferences.getInstance());
    }

    test('a saved set comes back intact', () async {
      final s = await store();
      await s.save(
        const Setlist(
          name: 'Friday',
          entries: [
            SetlistEntry(chartName: 'Blues', transposeSemitones: 2),
          ],
        ),
      );
      final found = s.find('Friday')!;
      expect(found.entries.single.chartName, 'Blues');
      expect(found.entries.single.transposeSemitones, 2);
    });

    test('an EMPTY set is allowed, unlike an empty chart', () async {
      // You build a set by making it and then adding to it.
      final s = await store();
      await s.save(const Setlist(name: 'New set'));
      expect(s.find('New set'), isNotNull);
    });

    test('a blank name is refused', () async {
      final s = await store();
      await s.save(const Setlist(name: '   '));
      expect(s.list(), isEmpty);
    });

    test('saving the same name replaces', () async {
      final s = await store();
      await s.save(const Setlist(name: 'x'), nowMs: 1);
      await s.save(
        const Setlist(name: 'x', entries: [SetlistEntry(chartName: 'A')]),
        nowMs: 2,
      );
      expect(s.list(), hasLength(1));
      expect(s.find('x')!.length, 1);
    });

    test('newest first, and remove drops one', () async {
      final s = await store();
      await s.save(const Setlist(name: 'old'), nowMs: 1);
      await s.save(const Setlist(name: 'new'), nowMs: 2);
      expect(s.list().map((r) => r.setlist.name), ['new', 'old']);
      await s.remove('old');
      expect(s.list().map((r) => r.setlist.name), ['new']);
    });

    test('a corrupt store reads as empty', () async {
      final s = await store({'setlists_v1': 'not json'});
      expect(s.list(), isEmpty);
    });

    test('a missing chart is REPORTED, not silently dropped', () async {
      // On a gig night the player has to see the gap; removing the song from
      // the set would be the worst possible response.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final charts = ChartStore(prefs);
      final sets = SetlistStore(prefs);

      await charts.save('Here', chart('| C |'));
      const set = Setlist(
        name: 'Friday',
        entries: [
          SetlistEntry(chartName: 'Here'),
          SetlistEntry(chartName: 'Gone'),
        ],
      );

      final missing = sets.missingCharts(set, charts);
      expect(missing.map((e) => e.chartName), ['Gone']);
      // The set still has both songs in it.
      expect(set.length, 2);
    });
  });
}
