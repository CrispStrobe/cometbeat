// source_registry.dart — the library's built-in content sources. Constructing
// a source doesn't hit the network (the injected HttpGet is only used when
// browsing), so the registry's shape — non-empty, uniquely-identified,
// named — is safe to assert. defaultHttpGet (the production fetch) is exercised
// over a MockClient so both its success and non-2xx paths are covered without a
// real network.
import 'dart:convert';

import 'package:comet_beat/features/library/source_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  group('defaultHttpGet', () {
    test('returns the body bytes on 2xx and sends a User-Agent', () async {
      http.Request? seen;
      final bytes = await http.runWithClient(
        () => defaultHttpGet(Uri.parse('https://example.test/tune.abc')),
        () => MockClient((req) async {
          seen = req;
          return http.Response('X:1\nK:C\nCDEF|', 200);
        }),
      );
      expect(utf8.decode(bytes), contains('K:C'));
      // GitHub's API rejects UA-less requests, so the fetch must set one.
      expect(seen!.headers['User-Agent'], isNotEmpty);
    });

    test('throws ClientException on a non-2xx status', () async {
      await expectLater(
        http.runWithClient(
          () => defaultHttpGet(Uri.parse('https://example.test/missing')),
          () => MockClient((req) async => http.Response('nope', 404)),
        ),
        throwsA(isA<http.ClientException>()),
      );
    });
  });
}
