// "Handwritten notes" theme — proves the self-bundled Petaluma face is wired
// without any crisp_notation change: (1) the settings toggle swaps the app score font
// and the shared theme, and (2) the vendored petaluma_metadata.json is valid
// SMuFL that crisp_notation can parse. (The rest of the suite renders with the
// default Bravura, so this is where the Petaluma path is exercised.)

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appScoreFont = MusicFont.bravura; // reset the global between tests
  });

  test('the toggle swaps the app score font and the shared kids theme',
      () async {
    final settings = SettingsService();

    // Default: Bravura, and the theme stays the shared const.
    expect(appScoreFont, MusicFont.bravura);
    expect(kidsScoreTheme.musicFont, MusicFont.bravura);

    await settings.setHandwrittenNotes(true);
    expect(settings.handwrittenNotes, isTrue);
    expect(appScoreFont, kPetalumaFont);
    expect(kidsScoreTheme.musicFont, kPetalumaFont);

    await settings.setHandwrittenNotes(false);
    expect(appScoreFont, MusicFont.bravura);
    expect(kidsScoreTheme.musicFont, MusicFont.bravura);
  });

  test(
      'the descriptor points at the app bundle, not the crisp_notation package',
      () {
    // package == null is what makes it resolve mus's own asset + font family,
    // so no crisp_notation change is needed.
    expect(kPetalumaFont.package, isNull);
    expect(kPetalumaFont.family, 'Petaluma');
    expect(kPetalumaFont.metadataAsset, startsWith('assets/smufl/'));
  });

  test('the vendored petaluma_metadata.json is valid SMuFL', () {
    final file = File('assets/smufl/petaluma_metadata.json');
    expect(file.existsSync(), isTrue, reason: 'font metadata must be vendored');
    // Parses through crisp_notation's own reader → the render path can consume it.
    final metadata = SmuflMetadata.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
    expect(metadata, isNotNull);
  });
}
