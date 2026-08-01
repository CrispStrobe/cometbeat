// Acceptance probe: run melodic search against the REAL shipped catalog.
//
// The unit tests use three nursery tunes, which proves the algorithm but not
// that it is useful — a search is only worth shipping if a few remembered notes
// actually pull the right piece out of 38,427 real ones. This loads the live
// catalog shard and asks it real questions.
//
//   dart run tool/melodic_search_probe.dart /tmp/score.json.gz
//
// Fetch the shard first (it is our own, licence-cleared, catalog):
//   curl -sL "https://huggingface.co/datasets/cstr/cometbeat-assets/resolve/\
//   main/catalog/score.json.gz" -o /tmp/score.json.gz

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/music/melodic_search.dart';

void main(List<String> args) {
  final path = args.isEmpty ? '/tmp/score.json.gz' : args.first;
  final raw = File(path).readAsBytesSync();
  final text = utf8.decode(
    path.endsWith('.gz') ? gzip.decode(raw) : raw,
    allowMalformed: true,
  );
  final decoded = jsonDecode(text);
  final rows = (decoded is List ? decoded : decoded['items'] as List)
      .cast<Map<String, dynamic>>();

  final pool = <MelodicCandidate>[];
  final titleOf = <String, String>{};
  for (final r in rows) {
    final music = r['music'];
    if (music is! Map) continue;
    final inc = (music['incipit'] as List?)?.cast<int>();
    if (inc == null || inc.length < 2) continue;
    final id = '${r['id']}';
    pool.add(MelodicCandidate(id, inc));
    titleOf[id] = '${r['name'] ?? r['id']}';
  }
  stdout.writeln('pool: ${pool.length} searchable of ${rows.length} rows\n');

  // A self-test over the corpus itself: take a row's own opening N notes,
  // TRANSPOSE it (so nothing can match on absolute pitch), and check the row
  // comes back. This is the honest measure — it asks the corpus about itself.
  for (final n in [4, 6, 8]) {
    var hitTop = 0;
    var hitTen = 0;
    var asked = 0;
    // A deterministic spread rather than the first N (which would be one
    // source, i.e. one engraver's habits).
    for (var i = 0; i < pool.length; i += pool.length ~/ 200) {
      final c = pool[i];
      if (c.incipit.length < n) continue;
      asked++;
      final query = [for (final p in c.incipit.take(n)) p + 5];
      final hits = searchMelodies(query, pool, limit: 10);
      if (hits.isNotEmpty && hits.first.id == c.id) hitTop++;
      if (hits.any((h) => h.id == c.id)) hitTen++;
    }
    stdout.writeln(
      '$n-note transposed query over $asked probes: '
      'top-1 ${(100 * hitTop / asked).toStringAsFixed(1)}% · '
      'top-10 ${(100 * hitTen / asked).toStringAsFixed(1)}%',
    );
  }

  // And a human-style query: the opening of Ode to Joy, in a key nobody
  // wrote it in.
  stdout.writeln('\n"Ode to Joy" opening, transposed up a tritone:');
  final ode = [
    for (final p in [64, 64, 65, 67, 67, 65, 64, 62]) p + 6,
  ];
  for (final h in searchMelodies(ode, pool, limit: 5)) {
    stdout.writeln(
      '  ${h.score.toStringAsFixed(3)}  ${titleOf[h.id]}',
    );
  }
}
