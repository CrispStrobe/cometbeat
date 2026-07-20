// Downloads a diverse corpus of REAL tracker modules (.mod/.xm/.s3m/.it) from
// modland — a long-running public archive — into test/fixtures/wild/<ext>/ so
// the parser can be validated against files real trackers actually wrote, not
// just our tiny self-authored goldens.
//
// The files are GITIGNORED and NEVER committed: they're copyrighted music, and
// we only test the PARSER against them (like a JPEG decoder against sample
// JPEGs), which is ordinary dev practice. Run manually:
//
//   dart run bin/fetch_wild_modules.dart [perFormat=25]
//
// Courteous by design: a small delay between requests, a hard per-format cap,
// and it skips files already present (safe to re-run / resume).

import 'dart:io';

const _base = 'https://ftp.modland.com/pub/modules';

// modland format directory → our extension. These four are what parseAnyModule
// handles; each dir is `<artist>/…/<file>`.
const _formats = <String, String>{
  'Protracker': 'mod',
  'Fasttracker 2': 'xm',
  'Screamtracker 3': 's3m',
  'Impulsetracker': 'it',
};

late final HttpClient _client;

Uri _u(String path) {
  // Percent-encode each segment (artist names have spaces etc.) but keep '/'.
  final segs = path.split('/').map(Uri.encodeComponent).join('/');
  return Uri.parse('$_base/$segs');
}

Future<String?> _getText(String path) async {
  try {
    final resp = await (await _client.getUrl(_u(path))).close();
    if (resp.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    return String.fromCharCodes(bytes);
  } catch (_) {
    return null;
  }
}

Future<List<int>?> _getBytes(String path) async {
  try {
    final resp = await (await _client.getUrl(_u(path))).close();
    if (resp.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

/// The hrefs in an nginx autoindex page (relative, already URL-encoded).
List<String> _hrefs(String html) => [
      for (final m in RegExp('href="([^"?]+)"').allMatches(html))
        Uri.decodeComponent(m.group(1)!),
    ];

/// Recursively collect up to [want] file paths (relative to [dir]) whose name
/// ends in `.[ext]`, descending at most [depth] levels of subdirectories.
Future<List<String>> _collect(
  String dir,
  String ext,
  int want, {
  int depth = 3,
}) async {
  final out = <String>[];
  final html = await _getText(dir);
  if (html == null) return out;
  final entries =
      _hrefs(html).where((h) => h != '../' && !h.startsWith('/')).toList();

  // Files first (so shallow artists contribute), then descend into subdirs.
  for (final h in entries) {
    if (out.length >= want) return out;
    if (h.endsWith('.$ext')) out.add('$dir/$h');
  }
  if (depth <= 0) return out;
  for (final h in entries) {
    if (out.length >= want) return out;
    if (h.endsWith('/')) {
      out.addAll(
        await _collect(
          '$dir/${h.substring(0, h.length - 1)}',
          ext,
          want - out.length,
          depth: depth - 1,
        ),
      );
    }
  }
  return out;
}

Future<void> main(List<String> args) async {
  final perFormat = args.isNotEmpty ? int.tryParse(args.first) ?? 25 : 25;
  _client = HttpClient()..userAgent = 'cometbeat-parser-tests';

  final root = Directory('test/fixtures/wild');
  root.createSync(recursive: true);

  var total = 0;
  for (final entry in _formats.entries) {
    final fmtDir = entry.key;
    final ext = entry.value;
    final outDir = Directory('${root.path}/$ext')..createSync(recursive: true);
    stdout.writeln('▸ $fmtDir → .$ext (up to $perFormat)…');

    final files = await _collect(fmtDir, ext, perFormat);
    var got = 0;
    for (final path in files) {
      final name = path.split('/').last;
      final dest = File('${outDir.path}/$name');
      if (dest.existsSync()) {
        got++;
        continue;
      }
      final bytes = await _getBytes(path);
      if (bytes == null || bytes.length < 16) continue;
      dest.writeAsBytesSync(bytes);
      got++;
      total++;
      stdout.write('\r  $got/${files.length}: $name          ');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    stdout.writeln('\r  $ext: $got files                       ');
  }

  _client.close();
  stdout.writeln('Done — $total new files under ${root.path}/ (gitignored).');
}
