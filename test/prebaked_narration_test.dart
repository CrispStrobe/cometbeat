import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/prebaked_narration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('narrationKey normalizes whitespace + is lang-prefixed', () {
    expect(narrationKey('  Hello   world ', 'en-US'), 'en|Hello world');
    expect(narrationKey('Guten Morgen', 'de_DE'), 'de|Guten Morgen');
    // Same normalized text + lang → same key regardless of formatting.
    final a = narrationKey('Hello\nworld', 'en');
    final b = narrationKey('Hello world', 'en');
    expect(a, b);
  });

  test('assetFor resolves baked keys, null for unbaked', () async {
    final manifest = jsonEncode({
      'en|Hello world': 'narration/en/abc.wav',
      'de|Guten Morgen': 'narration/de/def.wav',
    });
    final pn = PrebakedNarration(loadManifest: () async => manifest);
    final en = await pn.assetFor('  Hello world  ', 'en-US');
    expect(en, 'narration/en/abc.wav');
    expect(await pn.assetFor('Guten Morgen', 'de'), 'narration/de/def.wav');
    expect(await pn.assetFor('not baked', 'en'), isNull);
  });

  test('missing/broken manifest → nothing prebaked (no crash)', () async {
    final pn = PrebakedNarration(loadManifest: () async => throw 'no asset');
    expect(await pn.assetFor('anything', 'en'), isNull);
  });

  test('backend plays the baked asset; no-ops (falls back) when unbaked',
      () async {
    final played = <Uint8List>[];
    final wav = Uint8List.fromList([1, 2, 3, 4]);
    final backend = PrebakedNarrationBackend(
      play: (w) async => played.add(w),
      narration: PrebakedNarration(
        loadManifest: () async =>
            jsonEncode({'en|Hi there': 'narration/en/x.wav'}),
      ),
      loadAsset: (path) async {
        expect(path, 'narration/en/x.wav');
        return wav;
      },
    );

    expect(await backend.has('Hi there', 'en-US'), isTrue);
    expect(await backend.has('nope', 'en'), isFalse);

    await backend.speak('Hi there', langCode: 'en-US');
    expect(played, [wav]); // played the baked asset

    // 'not baked' → no-op, so the caller falls back to the platform voice.
    await backend.speak('not baked', langCode: 'en');
    expect(played, [wav]); // unchanged
  });
}
