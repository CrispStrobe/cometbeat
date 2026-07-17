// lib/shared/score_theme.dart
//
// The music (SMuFL) font used for all rendered notation, chosen by the "Notation
// font" setting. Four faces ship:
//   • Bravura  — the crisp_notation default (bundled by that package).
//   • Petaluma — a jazz / handwritten face (SIL OFL 1.1, Steinberg).
//   • Leland   — MuseScore's engraving face (SIL OFL 1.1).
//   • Leipzig  — Verovio's own face (SIL OFL 1.1, RISM).
// The three non-default faces are bundled by THIS app under assets/smufl/.
//
// Exposed as a no-arg getter so every StaffView / MultiSystemView site can use
// `kidsScoreTheme` in place of the const `CrispNotationTheme.kids` without threading
// a BuildContext. SettingsService mutates [appScoreFont] when the choice changes;
// screens entered afterwards pick up the new font (games are pushed fresh).

import 'package:crisp_notation/crisp_notation.dart';

/// The selectable notation faces. Names are persisted (SettingsService), so keep
/// them stable.
enum ScoreFont { bravura, petaluma, leland, leipzig }

/// This app's bundled Petaluma face (SIL OFL 1.1). `package` is null, so the
/// family + metadata resolve from the app's own bundle (declared in pubspec).
const MusicFont kPetalumaFont = MusicFont(
  family: 'Petaluma',
  metadataAsset: 'assets/smufl/petaluma_metadata.json',
);

/// This app's bundled Leland face (SIL OFL 1.1, MuseScore).
const MusicFont kLelandFont = MusicFont(
  family: 'Leland',
  metadataAsset: 'assets/smufl/leland_metadata.json',
);

/// This app's bundled Leipzig face (SIL OFL 1.1, Verovio / RISM).
const MusicFont kLeipzigFont = MusicFont(
  family: 'Leipzig',
  metadataAsset: 'assets/smufl/leipzig_metadata.json',
);

/// The [MusicFont] backing each [ScoreFont] choice.
MusicFont musicFontFor(ScoreFont font) => switch (font) {
  ScoreFont.bravura => MusicFont.bravura,
  ScoreFont.petaluma => kPetalumaFont,
  ScoreFont.leland => kLelandFont,
  ScoreFont.leipzig => kLeipzigFont,
};

/// The notation font currently in effect. Set by [SettingsService].
MusicFont appScoreFont = MusicFont.bravura;

/// The kids theme with the selected music font applied. Stays the shared const
/// for the default (Bravura) so nothing changes when the default is in effect.
CrispNotationTheme get kidsScoreTheme => appScoreFont == MusicFont.bravura
    ? CrispNotationTheme.kids
    : CrispNotationTheme.kids.copyWith(musicFont: appScoreFont);
