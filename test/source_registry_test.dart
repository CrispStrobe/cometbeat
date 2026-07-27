// source_registry.dart — the library's built-in content sources. Constructing
// a source doesn't hit the network (the injected HttpGet is only used when
// browsing), so the registry's shape — non-empty, uniquely-identified,
// named — is safe to assert.
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final builders = {
    'buildSources': buildSources,
    'buildSampleSources': buildSampleSources,
    'buildSamplePackSources': buildSamplePackSources,
    'buildCatalogSources': buildCatalogSources,
  };

  builders.forEach((label, build) {
    group(label, () {
      test('is non-empty', () {
        expect(build(), isNotEmpty);
      });

      test('every source has a unique, non-empty id and a non-empty name', () {
        final sources = build();
        final ids = <String>[];
        for (final s in sources) {
          expect(s.id, isNotEmpty, reason: 'a source id is empty');
          expect(s.name, isNotEmpty, reason: '${s.id} has no name');
          ids.add(s.id);
        }
        expect(ids.toSet().length, ids.length, reason: 'duplicate source id');
      });
    });
  });

  test('sample and score sources are distinct registries', () {
    // Samples/sample-packs don't decode to MusicXML, so they must not leak into
    // the score-source list.
    final scoreIds = buildSources().map((s) => s.id).toSet();
    final sampleIds = buildSampleSources().map((s) => s.id).toSet();
    expect(scoreIds.intersection(sampleIds), isEmpty);
  });
}
