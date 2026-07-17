// Notation-font selection — proves the three self-bundled SMuFL faces (Petaluma,
// Leland, Leipzig) are wired without any crisp_notation change: (1) the setting
// swaps the app score font and the shared theme, (2) selection persists and the
// legacy "handwritten notes" bool migrates to Petaluma, and (3) each vendored
// *_metadata.json is valid SMuFL that crisp_notation can parse. (The rest of the
// suite renders with the default Bravura, so this is where the alt-font paths are
// exercised.)

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

  test(
    'selecting a face swaps the app score font and the shared kids theme',
    () async {
      final settings = SettingsService();

      // Default: Bravura, and the theme stays the shared const.
      expect(appScoreFont, MusicFont.bravura);
      expect(kidsScoreTheme.musicFont, MusicFont.bravura);

      for (final (font, expected) in const [
        (ScoreFont.petaluma, kPetalumaFont),
        (ScoreFont.leland, kLelandFont),
        (ScoreFont.leipzig, kLeipzigFont),
      ]) {
        await settings.setScoreFont(font);
        expect(settings.scoreFont, font);
        expect(appScoreFont, expected);
        expect(kidsScoreTheme.musicFont, expected);
      }

      await settings.setScoreFont(ScoreFont.bravura);
      expect(appScoreFont, MusicFont.bravura);
      expect(kidsScoreTheme.musicFont, MusicFont.bravura);
    },
  );

  test('the legacy handwritten bool still maps onto Petaluma', () async {
    final settings = SettingsService();
    await settings.setHandwrittenNotes(true);
    expect(settings.scoreFont, ScoreFont.petaluma);
    expect(settings.handwrittenNotes, isTrue);
    expect(appScoreFont, kPetalumaFont);

    await settings.setHandwrittenNotes(false);
    expect(settings.scoreFont, ScoreFont.bravura);
    expect(settings.handwrittenNotes, isFalse);
  });

  test('selection persists across a reload', () async {
    await SettingsService().setScoreFont(ScoreFont.leland);
    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.scoreFont, ScoreFont.leland);
    expect(appScoreFont, kLelandFont);
  });

  test(
    'an upgrading user with only the legacy bool migrates to Petaluma',
    () async {
      SharedPreferences.setMockInitialValues({'handwritten_notes': true});
      final settings = SettingsService();
      await settings.load();
      expect(settings.scoreFont, ScoreFont.petaluma);
      expect(appScoreFont, kPetalumaFont);
    },
  );

  test(
    'the descriptors point at the app bundle, not the crisp_notation package',
    () {
      // package == null is what makes each resolve mus's own asset + font family,
      // so no crisp_notation change is needed.
      for (final (font, family) in const [
        (kPetalumaFont, 'Petaluma'),
        (kLelandFont, 'Leland'),
        (kLeipzigFont, 'Leipzig'),
      ]) {
        expect(font.package, isNull);
        expect(font.family, family);
        expect(font.metadataAsset, startsWith('assets/smufl/'));
      }
    },
  );

  test('every vendored *_metadata.json is valid SMuFL', () {
    for (final name in const [
      'petaluma_metadata.json',
      'leland_metadata.json',
      'leipzig_metadata.json',
    ]) {
      final file = File('assets/smufl/$name');
      expect(file.existsSync(), isTrue, reason: '$name must be vendored');
      // Parses through crisp_notation's own reader → the render path can consume it.
      final metadata = SmuflMetadata.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
      expect(metadata, isNotNull);
    }
  });
}
