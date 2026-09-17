import 'dart:io';

import 'package:comet_beat/core/services/audio_cache_directory_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates missing cache parents before a byte-source write', () async {
    final root = await Directory.systemTemp.createTemp('audio-cache-test-');
    addTearDown(() => root.delete(recursive: true));
    final cache = Directory('${root.path}/missing/app-cache');
    expect(cache.existsSync(), isFalse);

    await prepareAudioCacheDirectory(temporaryDirectory: () async => cache);

    expect(cache.existsSync(), isTrue);
    final file = File('${cache.path}/clip');
    await file.writeAsBytes([1, 2, 3]);
    await prepareAudioCacheDirectory(temporaryDirectory: () async => cache);
    expect(await file.readAsBytes(), [1, 2, 3]);

    // Cache eviction must not leave a stale successful-initialization flag.
    await cache.delete(recursive: true);
    await prepareAudioCacheDirectory(temporaryDirectory: () async => cache);
    expect(cache.existsSync(), isTrue);
  });
}
