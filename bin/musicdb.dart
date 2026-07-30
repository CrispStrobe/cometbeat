// musicdb — query the corpus from the command line.
//
// WHY THIS EXISTS. Every corpus question in a long session ("how many ABC files
// do we have?", "which sources carry lyrics?", "what is actually in the shipped
// catalog?") used to be answered with ad-hoc Python over ssh, and several of
// those answers were wrong on the first attempt: a regex escaped through ssh
// reported "0 of 854" for a construct present in 110 files; a date sweep matched
// death years inside provenance prose and reported 91 hits that were all
// artefacts; a lyric-coverage figure came back 28%, then 73%, then 35% as the
// extraction was fixed. Ad-hoc one-liners have no tests and no memory. This does.
//
// Two shapes of input, because there are two artefacts worth asking about and
// they use DIFFERENT field names:
//   * `db.json`   — the master registry (a JSON list). `title`/`source`/
//                   `licence`/`rights_status`/`format`/`path`.
//   * `catalog/*` — what the app actually ships (a map with `items`).
//                   `name`/`license`/`tier`/`format`/`path`, and NO `source`.
// Conflating the two is exactly how "is it in the DB?" gets confused with "does
// it ship?" — they differ by ~7,500 deliberately-held rows — so `--db` reports
// which shape it read, every time.
//
// Usage:
//   dart run bin/musicdb.dart stats  --db /path/db.json
//   dart run bin/musicdb.dart query --db /path/db.json --source CPDL --format mxl
//   dart run bin/musicdb.dart query --db catalog/score.json.gz --title "kyrie"
//   dart run bin/musicdb.dart show  --db /path/db.json <id>
//
// Accepts `.json` and `.gz` (the published shards are gzipped).
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:archive/archive.dart';

/// One corpus row, normalised across the two artefact shapes.
class Row {
  Row(this.raw, {required this.fromCatalog});

  final Map<String, dynamic> raw;

  /// True when this came from a catalog shard rather than `db.json`. Kept
  /// because the two carry different truth: a catalog row has passed the rights
  /// gate and the content denylist, a db.json row has not necessarily.
  final bool fromCatalog;

  String get id => '${raw['id'] ?? raw['path'] ?? ''}';
  // `title` in db.json, `name` in a catalog shard.
  String get title => '${raw['title'] ?? raw['name'] ?? ''}';
  String get source => '${raw['source'] ?? (fromCatalog ? '(catalog)' : '')}';
  String get format => '${raw['format'] ?? ''}';
  String get kind => '${raw['kind'] ?? 'score'}';
  // `licence` (en-GB) in db.json, `license` (en-US) in the catalog. Both spellings
  // are load-bearing in their own artefact; neither is a typo to be "fixed".
  String get licence => '${raw['licence'] ?? raw['license'] ?? ''}';
  String get tier => '${raw['tier'] ?? raw['rights_status'] ?? ''}';
  String get path => '${raw['path'] ?? ''}';
  String get attribution => '${raw['attribution'] ?? raw['author'] ?? ''}';
  String get year => '${raw['year'] ?? ''}';

  /// Everything searchable as one lowercased haystack.
  String get haystack =>
      [id, title, source, attribution, licence, path].join(' ').toLowerCase();
}

/// Reads a `db.json` list or a catalog shard map, gzipped or not.
({List<Row> rows, bool catalog, String note}) load(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('no such file: $path');
    exit(2);
  }
  var bytes = f.readAsBytesSync();
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = const GZipDecoder().decodeBytes(bytes);
  }
  final v = jsonDecode(utf8.decode(bytes));
  if (v is List) {
    return (
      rows: [
        for (final e in v)
          if (e is Map<String, dynamic>) Row(e, fromCatalog: false),
      ],
      catalog: false,
      note: 'db.json (master registry — includes held/non-shipping rows)',
    );
  }
  if (v is Map<String, dynamic>) {
    final items = v['items'];
    if (items is List) {
      return (
        rows: [
          for (final e in items)
            if (e is Map<String, dynamic>) Row(e, fromCatalog: true),
        ],
        catalog: true,
        note: 'catalog shard v${v['version'] ?? '?'} '
            '(SHIPPED rows only — rights gate + content denylist applied)',
      );
    }
  }
  stderr.writeln('unrecognised shape: expected a db.json list or a shard map');
  exit(2);
}

/// Positional arguments — everything that is neither a `--flag` nor the value
/// consumed by one. Kept separate from [parseFlags] so the two cannot disagree
/// about which tokens are values.
List<String> positionals(List<String> args) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      // a space-separated flag eats the next token unless it used `--k=v`
      if (!a.contains('=') &&
          i + 1 < args.length &&
          !args[i + 1].startsWith('--')) {
        i++;
      }
      continue;
    }
    out.add(a);
  }
  return out;
}

Map<String, String> parseFlags(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq > 0) {
      out[a.substring(2, eq)] = a.substring(eq + 1);
    } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[a.substring(2)] = args[++i];
    } else {
      out[a.substring(2)] = 'true';
    }
  }
  return out;
}

List<Row> applyFilters(List<Row> rows, Map<String, String> f) {
  bool ci(String hay, String? needle) =>
      needle == null || hay.toLowerCase().contains(needle.toLowerCase());
  return [
    for (final r in rows)
      if (ci(r.source, f['source']) &&
          ci(r.kind, f['kind']) &&
          ci(r.format, f['format']) &&
          ci(r.tier, f['tier']) &&
          ci(r.licence, f['licence'] ?? f['license']) &&
          ci(r.title, f['title']) &&
          ci(r.year, f['year']) &&
          (f['text'] == null || r.haystack.contains(f['text']!.toLowerCase())))
        r,
  ];
}

void printStats(List<Row> rows, String note) {
  stdout.writeln('source: $note');
  stdout.writeln('rows:   ${rows.length}\n');
  void tally(String label, String Function(Row) key, {int top = 25}) {
    final c = <String, int>{};
    for (final r in rows) {
      final k = key(r).isEmpty ? '(none)' : key(r);
      c[k] = (c[k] ?? 0) + 1;
    }
    final e = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln('$label (${c.length} distinct)');
    for (final x in e.take(top)) {
      stdout.writeln('  ${x.value.toString().padLeft(7)}  ${x.key}');
    }
    if (e.length > top) stdout.writeln('  … ${e.length - top} more');
    stdout.writeln();
  }

  tally('by kind', (r) => r.kind);
  tally('by format', (r) => r.format);
  tally('by source', (r) => r.source);
  tally('by tier/rights', (r) => r.tier, top: 12);
}

const _usage = '''
musicdb — query the music corpus.

  musicdb stats --db <db.json|catalog/*.json[.gz]>
  musicdb query --db <file> [filters] [--limit N] [--json] [--count]
  musicdb show  --db <file> <id>

filters:  --source --kind --format --tier --licence --title --year --text
          (all case-insensitive substring matches; --text searches
           id+title+source+attribution+licence+path)

Reads db.json (the master registry, INCLUDING held rows) or a published catalog
shard (SHIPPED rows only). It always says which, because the two differ by the
deliberately-held material and confusing them misreports what users can see.
''';

// ⚠️ Dart does NOT use an `int` returned from `main` as the process exit code —
// it is silently discarded. Every error path here (missing --db, unknown command,
// unreadable file, id not found) was therefore exiting 0, which is the worst
// possible failure for a tool meant to be used in scripts and pipes. Set
// `exitCode` and let the VM exit normally so stdout is flushed first.
void main(List<String> args) {
  exitCode = _run(args);
}

int _run(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return args.isEmpty ? 1 : 0;
  }
  final cmd = args.first;
  final flags = parseFlags(args);
  final dbPath = flags['db'];
  if (dbPath == null) {
    stderr.writeln('--db is required (a db.json or a catalog shard)');
    return 2;
  }
  final loaded = load(dbPath);

  switch (cmd) {
    case 'stats':
      printStats(loaded.rows, loaded.note);
      return 0;

    case 'query':
      final hits = applyFilters(loaded.rows, flags);
      if (flags['count'] != null) {
        stdout.writeln(hits.length);
        return 0;
      }
      final limit = int.tryParse(flags['limit'] ?? '') ?? 40;
      if (flags['json'] != null) {
        const enc = JsonEncoder.withIndent(' ');
        stdout.writeln(enc.convert([for (final r in hits.take(limit)) r.raw]));
        return 0;
      }
      stdout.writeln('${hits.length} match(es) in ${loaded.note}'
          '${hits.length > limit ? ' — showing $limit' : ''}\n');
      for (final r in hits.take(limit)) {
        stdout.writeln('${r.title.padRight(48).substring(0, 48)}  '
            '${r.format.padRight(9)}${r.source.padRight(26)}${r.id}');
      }
      return 0;

    case 'show':
      final id =
          // NOT `firstWhere(!startsWith('--'))`: that cannot tell a positional
          // from a FLAG'S VALUE, so `show --db <path> a2` took the path as the
          // id and every lookup reported "no such row".
          positionals(args).skip(1).join();
      if (id.isEmpty) {
        stderr.writeln('show needs an id');
        return 2;
      }
      final hit = loaded.rows.where((r) => r.id == id);
      if (hit.isEmpty) {
        // A miss is worth distinguishing: absent from db.json means we never
        // ingested it; absent from a catalog shard may mean it is HELD.
        stderr.writeln('no row with id "$id" in ${loaded.note}');
        return 1;
      }
      stdout.writeln(const JsonEncoder.withIndent(' ').convert(hit.first.raw));
      return 0;

    default:
      stderr.writeln('unknown command "$cmd"\n');
      stdout.write(_usage);
      return 2;
  }
}
