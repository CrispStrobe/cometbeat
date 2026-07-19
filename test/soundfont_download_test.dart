// The in-app GM SoundFont download manager: the catalog is free-licensed and
// full-GM, the size hint reads right, the download gates on licence + caches
// (fetches once), and the io cache round-trips.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2_remote.dart';
import 'package:comet_beat/features/library/soundfont_download.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory [SoundFontCache] for tests (no disk).
class _MemCache implements SoundFontCache {
  final Map<String, Uint8List> store = {};
  @override
  Future<Uint8List?> read(String id) async => store[id];
  @override
  Future<void> write(String id, Uint8List bytes) async => store[id] = bytes;
}

void main() {
  test('the catalog is free-licensed, full-GM, smallest first', () {
    expect(kGmSoundFonts, isNotEmpty);
    for (final s in kGmSoundFonts) {
      expect(
        isPermissiveLicense(s.license),
        isTrue,
        reason: '${s.name} must be permissively licensed',
      );
      expect(s.approxBytes, isNotNull);
      expect(s.url, startsWith('http'));
    }
    // The compact .sf3 is the recommended default (listed first, smaller).
    expect(kGmSoundFonts.first.id, 'fluidr3mono_gm');
    expect(
      kGmSoundFonts.first.approxBytes!,
      lessThan(kGmSoundFonts.last.approxBytes!),
    );
  });

  test('size hint formats megabytes', () {
    expect(soundFontSizeHint(kFluidR3MonoGm), '~14 MB');
    expect(soundFontSizeHint(kMuseScoreGeneralSf3), '~38 MB');
    expect(soundFontSizeHint(kMuseScoreGeneralSf2), '~206 MB');
  });

  test('download gates on licence, fetches once, then serves from cache',
      () async {
    var fetches = 0;
    Future<Uint8List> fetch(Uri url) async {
      fetches++;
      return Uint8List.fromList([1, 2, 3, 4]);
    }

    final cache = _MemCache();
    final a = await downloadGmSoundFontBytes(
      kFluidR3MonoGm,
      fetch: fetch,
      cache: cache,
    );
    expect(a, [1, 2, 3, 4]);
    expect(fetches, 1);

    // Second call is a cache hit — no new fetch.
    final b = await downloadGmSoundFontBytes(
      kFluidR3MonoGm,
      fetch: fetch,
      cache: cache,
    );
    expect(b, [1, 2, 3, 4]);
    expect(fetches, 1);
  });

  test('a non-permissive source is refused before any fetch', () async {
    var fetched = false;
    Future<Uint8List> fetch(Uri url) async {
      fetched = true;
      return Uint8List(0);
    }

    const nc = SoundFontSource(
      id: 'nope',
      name: 'Proprietary GM',
      url: 'https://example.com/x.sf2',
      license: 'All-Rights-Reserved',
      attribution: '',
    );
    await expectLater(
      downloadGmSoundFontBytes(nc, fetch: fetch, cache: _MemCache()),
      throwsStateError,
    );
    expect(fetched, isFalse, reason: 'gate runs before the network');
  });

  test('the io cache round-trips through a temp dir', () async {
    final dir = Directory.systemTemp.createTempSync('sf_cache_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cache = IoSoundFontCache(cacheDirOverride: dir.path);

    expect(await cache.read('x'), isNull);
    await cache.write('x', Uint8List.fromList([9, 8, 7]));
    expect(await cache.read('x'), [9, 8, 7]);
    expect(cache.pathFor('x'), '${dir.path}/x.sf');
  });
}
