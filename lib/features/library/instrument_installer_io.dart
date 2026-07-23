// Native (dart:io) batch SFZ-instrument installer. See instrument_installer.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/flac_glint_ffi.dart';
import 'package:comet_beat/core/audio/sf2/sfz.dart';
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart'
    show soundFontInstrument;
import 'package:comet_beat/features/library/content_source.dart' show HttpGet;
import 'package:comet_beat/features/library/instrument_installer_types.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToWav;

bool get instrumentInstallSupported => true;

String _cacheRoot() {
  final env = Platform.environment['COMET_CACHE_DIR'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/comet_beat';
}

/// A stable, filesystem-safe id for [name].
String _idFor(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

/// The directory portion of a URL (everything up to the last `/`).
String _dirOf(String url) {
  final i = url.lastIndexOf('/');
  return i < 0 ? '' : url.substring(0, i + 1);
}

/// Downloads [sfzUrl] and its whole sample tree, caches them under
/// `instruments/<id>/`, and loads a playable voice. WAV and (via the native
/// glint decoder) FLAC samples are supported. Returns null on web, if the SFZ
/// has no samples, or if nothing decodes (e.g. an all-FLAC instrument on a
/// platform where the glint FLAC decoder isn't available).
Future<InstalledInstrument?> installSfzInstrument({
  required String sfzUrl,
  required String name,
  required HttpGet http,
  void Function(int done, int total)? onProgress,
  String? cacheDirOverride,
}) async {
  final text = utf8.decode(await http(Uri.parse(sfzUrl)));

  // Pass 1: discover every `sample=` path by letting the (tested) SFZ parser
  // ask for them — a recording reader returns null so nothing decodes yet.
  final wanted = <String>{};
  try {
    loadSfz(
      text,
      readSample: (p) {
        wanted.add(p);
        return null;
      },
    );
  } catch (_) {
    // expected: no sample resolved yet
  }
  if (wanted.isEmpty) return null;

  final dir = '${cacheDirOverride ?? _cacheRoot()}/instruments/${_idFor(name)}';
  Directory(dir).createSync(recursive: true);
  File('$dir/instrument.sfz').writeAsBytesSync(utf8.encode(text));

  // Download each sample (relative to the .sfz) into the cache, preserving the
  // tree. Skip ones already cached (so a re-install is instant).
  final sfzDir = _dirOf(sfzUrl);
  var done = 0;
  for (final rel in wanted) {
    final dest = File('$dir/$rel');
    if (!dest.existsSync() || dest.lengthSync() == 0) {
      try {
        final bytes = await http(Uri.parse('$sfzDir$rel'));
        dest.parent.createSync(recursive: true);
        dest.writeAsBytesSync(bytes);
      } catch (_) {
        // a missing sample just yields a skipped region below
      }
    }
    done++;
    onProgress?.call(done, wanted.length);
  }

  // Pass 2: load for real, reading samples from the cache. FLAC samples (VCSL,
  // VSCO2, …) are decoded to WAV on the fly via the native glint decoder, so
  // loadSfz — which parses WAV — can build a voice from them. If glint isn't
  // available (e.g. tests / a platform without the plugin) FLAC regions are
  // simply skipped, same as any unresolved sample.
  final FlacDecode? flac = loadGlintFlac();
  Uint8List? readCached(String p) {
    final f = File('$dir/$p');
    if (!f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    if (flac != null && p.toLowerCase().endsWith('.flac')) {
      final pcm = flac(bytes);
      if (pcm == null) return null;
      return pcmFloatToWav(
        pcm.left,
        sampleRate: pcm.sampleRate,
        right: pcm.right,
      );
    }
    return bytes;
  }

  try {
    final loaded = loadSfz(text, readSample: readCached, name: name);
    final inst = soundFontInstrument(loaded, loaded.presets.first, id: name);
    return InstalledInstrument(
      instrument: inst,
      sfzPath: '$dir/instrument.sfz',
      fileCount: wanted.length + 1,
    );
  } catch (_) {
    // e.g. every region is FLAC (no decoder yet) — cache is kept, no voice.
    return null;
  }
}
