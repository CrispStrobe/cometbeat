import 'package:comet_beat/core/harmony/chart_search.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finding a saved chart (BB-U4b).
///
/// One free-text box, because that is how a player asks for a tune. The rule
/// under test is that ALL tokens must match SOMETHING — typing a second word
/// narrows the result, it never widens it.
bool matches(String name, String source, String query) =>
    chartMatchesQuery(name, parseChartText(source).chart, query);

void main() {
  group('key names', () {
    test('major and minor across the circle', () {
      expect(keyNameOf(0), 'C');
      expect(keyNameOf(-1), 'F');
      expect(keyNameOf(-2), 'Bb');
      expect(keyNameOf(2), 'D');
      expect(keyNameOf(0, minor: true), 'Am');
      expect(keyNameOf(-3, minor: true), 'Cm');
      expect(keyNameOf(1, minor: true), 'Em');
    });

    test('past the circle it returns null rather than inventing a name', () {
      expect(keyNameOf(8), isNull);
      expect(keyNameOf(-8), isNull);
    });
  });

  group('what a query can find', () {
    const blues = 'title: Slow Blues\nkey: F\ntempo: 90\n[A]\n| F7 | Bb7 |';

    test('the name', () {
      expect(matches('My Blues', blues, 'blues'), isTrue);
      expect(matches('My Blues', blues, 'waltz'), isFalse);
    });

    test('the title, even when the saved name differs', () {
      expect(matches('untitled-3', blues, 'slow'), isTrue);
    });

    test('the key, written the way a player would type it', () {
      expect(matches('x', blues, 'f'), isTrue);
      expect(matches('x', blues, 'g'), isFalse);
    });

    test('a minor key answers to both spellings', () {
      const tune = 'key: Am\ntempo: 100\n| Am | Dm |';
      expect(matches('x', tune, 'am'), isTrue);
      expect(matches('x', tune, 'a'), isTrue);
    });

    test('the tempo', () {
      expect(matches('x', blues, '90'), isTrue);
      expect(matches('x', blues, '120'), isFalse);
    });

    test('the meter', () {
      const waltz = 'meter: 3/4\n| C |';
      expect(matches('x', waltz, '3/4'), isTrue);
    });

    test('a section label', () {
      expect(matches('x', blues, 'a'), isTrue);
      const named = 'key: C\n[Chorus]\n| C |';
      expect(matches('x', named, 'chorus'), isTrue);
    });

    test('the composer', () {
      const withComposer = 'title: T\ncomposer: Kenny Dorham\n| C |';
      expect(matches('x', withComposer, 'dorham'), isTrue);
    });
  });

  group('several words NARROW the result', () {
    const fastF = 'title: One\nkey: F\ntempo: 160\n| F |';
    const slowF = 'title: Two\nkey: F\ntempo: 90\n| F |';

    test('every token must match something', () {
      expect(matches('x', fastF, 'f 160'), isTrue);
      // The same key, the wrong tempo: a second word must EXCLUDE.
      expect(matches('x', slowF, 'f 160'), isFalse);
    });

    test('a token matching nothing eliminates the row', () {
      // Otherwise the search would quietly widen as the query got longer,
      // which is the opposite of what typing more means.
      expect(matches('x', fastF, 'f zebra'), isFalse);
    });

    test('order does not matter', () {
      expect(matches('x', fastF, '160 f'), isTrue);
    });

    test('case does not matter', () {
      expect(matches('My Tune', fastF, 'MY tUnE'), isTrue);
    });
  });

  group('degenerate input', () {
    test('an empty query matches everything', () {
      expect(matches('x', '| C |', ''), isTrue);
      expect(matches('x', '| C |', '   '), isTrue);
    });

    test('an unreadable chart still matches on its NAME', () {
      // A chart that no longer decodes must remain findable, or the player
      // cannot get to it to delete it.
      expect(chartMatchesQuery('Broken Tune', null, 'broken'), isTrue);
      expect(chartMatchesQuery('Broken Tune', null, 'f'), isFalse);
    });
  });

  group('filterCharts', () {
    final rows = [
      ('Blues', 'key: F\ntempo: 90\n| F |', true),
      ('Waltz', 'meter: 3/4\nkey: C\n| C |', false),
      ('Bossa', 'key: C\ntempo: 140\n| C |', false),
    ];

    List<String> run({String query = '', bool favouritesOnly = false}) =>
        filterCharts(
          rows,
          nameOf: (r) => r.$1,
          chartOf: (r) => parseChartText(r.$2).chart,
          isFavourite: (r) => r.$3,
          query: query,
          favouritesOnly: favouritesOnly,
        ).map((r) => r.$1).toList();

    test('no filter is everything, in order', () {
      expect(run(), ['Blues', 'Waltz', 'Bossa']);
    });

    test('a query narrows it', () {
      expect(run(query: '140'), ['Bossa']);
      expect(run(query: 'c'), ['Waltz', 'Bossa']);
    });

    test('starred-only narrows it', () {
      expect(run(favouritesOnly: true), ['Blues']);
    });

    test('the two combine', () {
      expect(run(query: 'c', favouritesOnly: true), isEmpty);
      expect(run(query: 'f', favouritesOnly: true), ['Blues']);
    });
  });
}
