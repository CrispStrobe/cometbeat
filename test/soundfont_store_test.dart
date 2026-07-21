// SoundFontStore — the CLI's --sf2 resolver. The network fetch is injected, so
// the resolve/gate/cache flow is tested without a real (~140 MB) download.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2_remote.dart' show SoundFontSource;
import 'package:comet_beat/core/audio/sf2/soundfont_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _permissive = SoundFontSource(
  id: 'test_gm',
  name: 'Test GM',
  url: 'https://example.test/test_gm.sf2',
  license: 'MIT',
  attribution: 'Test',
  approxBytes: 200000,
);

const _restricted = SoundFontSource(
  id: 'nope_gm',
  name: 'Restricted GM',
  url: 'https://example.test/nope.sf2',
  license: 'CC-BY-NC-4.0', // non-commercial → not permissive
  attribution: 'Test',
);

Uint8List _fakeBytes([int n = 300000]) => Uint8List(n)..fillRange(0, n, 7);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sf_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('an existing file path is returned unchanged (no fetch)', () async {
    final f = File('${tmp.path}/mine.sf2')..writeAsBytesSync(_fakeBytes());
    var fetched = false;
    final s = SoundFontStore(
      cacheDirOverride: tmp.path,
      fetch: (_) async {
        fetched = true;
        return _fakeBytes();
      },
      log: (_) {},
    );
    expect(await s.resolve(f.path), f.path);
    expect(fetched, isFalse);
  });

  test('a catalog id downloads once, then serves from cache', () async {
    var fetches = 0;
    final s = SoundFontStore(
      cacheDirOverride: tmp.path,
      catalog: const [_permissive],
      log: (_) {},
      fetch: (_) async {
        fetches++;
        return _fakeBytes();
      },
    );

    final p1 = await s.resolve('test_gm');
    expect(File(p1).existsSync(), isTrue);
    expect(p1, endsWith('test_gm.sf2'));
    expect(fetches, 1);

    // Second resolve hits the on-disk cache — no second download.
    final p2 = await s.resolve('test_gm');
    expect(p2, p1);
    expect(fetches, 1);
  });

  test('an unknown name is a clear ArgumentError', () async {
    final s = SoundFontStore(
      cacheDirOverride: tmp.path,
      catalog: const [_permissive],
      log: (_) {},
      fetch: (_) async => _fakeBytes(),
    );
    expect(
      () => s.resolve('does_not_exist'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a non-permissive license is refused BEFORE any fetch', () async {
    var fetched = false;
    final s = SoundFontStore(
      cacheDirOverride: tmp.path,
      catalog: const [_restricted],
      log: (_) {},
      fetch: (_) async {
        fetched = true;
        return _fakeBytes();
      },
    );
    await expectLater(s.resolve('nope_gm'), throwsA(isA<StateError>()));
    expect(fetched, isFalse);
  });

  test('a suspiciously small download is rejected', () async {
    final s = SoundFontStore(
      cacheDirOverride: tmp.path,
      catalog: const [_permissive],
      log: (_) {},
      fetch: (_) async => Uint8List(10), // far below the min-size guard
    );
    await expectLater(s.resolve('test_gm'), throwsA(isA<StateError>()));
  });

  test('the real catalog offers the working GeneralUser GS default', () {
    expect(kSoundFontCatalog, isNotEmpty);
    final s = SoundFontStore(cacheDirOverride: tmp.path);
    final desc = s.describeCatalog();
    expect(desc, contains('generaluser_gs'));
    expect(desc, contains('fluidr3_gm'));
  });

  test('GeneralUser GS (a verified non-SPDX license) is allowlisted', () async {
    // The REAL catalog (no override) — proves the custom GeneralUser GS license
    // passes the download gate (an SPDX-only gate would refuse it).
    final s = SoundFontStore(
      cacheDirOverride: tmp.path,
      log: (_) {},
      fetch: (_) async => _fakeBytes(),
    );
    final p = await s.resolve('generaluser_gs');
    expect(p, endsWith('generaluser_gs.sf2'));
    expect(File(p).existsSync(), isTrue);
  });
}
