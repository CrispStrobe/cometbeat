// Verifies the bundled pre-baked narration assets (assets/narration/, generated
// by tool/bake_narration.dart) resolve and are valid WAVs. Skips gracefully
// when nothing is baked (empty manifest), so CI stays green either way.

import 'package:comet_beat/core/audio/tts/prebaked_narration.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled narration assets resolve + are valid WAVs (skips if unbaked)',
      () async {
    // The Loop Studio first-run tutorial's opening step (see primers.dart /
    // app_en.arb firstRunLoopStart) — baked by tool/narration_strings.json.
    const en =
        "Tap a card — your band starts playing the instant you do. That's your loop, going round and round.";
    final pn = PrebakedNarration();
    final asset = await pn.assetFor(en, 'en');
    if (asset == null) {
      // Nothing baked in this build → the app falls back to the platform voice.
      return;
    }
    final bytes = (await rootBundle.load('assets/$asset')).buffer.asUint8List();
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  });
}
