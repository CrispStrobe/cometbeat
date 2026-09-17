// Native-only regression: redirect the plugin to an isolated, missing cache.
import 'dart:io';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _IsolatedCache extends PathProviderPlatform {
  _IsolatedCache(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AudioService recreates a missing cache before playback',
      (tester) async {
    final root = await Directory.systemTemp.createTemp('service-cache-test-');
    final cache = Directory('${root.path}/missing/cache');
    final originalPaths = PathProviderPlatform.instance;
    final originalDebugPrint = debugPrint;
    final errors = <String>[];
    final audio = AudioService();
    addTearDown(() async {
      await audio.stop();
      audio.dispose();
      PathProviderPlatform.instance = originalPaths;
      debugPrint = originalDebugPrint;
      await root.delete(recursive: true);
    });
    PathProviderPlatform.instance = _IsolatedCache(cache.path);
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains('[AUDIO] playback unavailable')) {
        errors.add(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    // Exercise the service, not the preparation helper. No earlier test can
    // prime this directory; deleting it also models OS cache eviction.
    for (var attempt = 0; attempt < 2; attempt++) {
      expect(cache.existsSync(), isFalse);
      await audio.playMidiNote(69, ms: 500);
      expect(errors, isEmpty);
      expect(cache.existsSync(), isTrue);
      expect(cache.listSync().whereType<File>(), isNotEmpty);
      await audio.stop();
      await cache.delete(recursive: true);
    }
  });
}
