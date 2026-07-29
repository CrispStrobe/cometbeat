// lib/features/games/highway/highway_theme.dart
//
// SKINS for the note highway.
//
// Everything the painter draws takes its colour from a [HighwayPalette], so a
// skin is data, not a code path: one painter, four looks, and a fifth is a
// dozen lines. The skins are ours — authored from the app's own theme
// language, not sampled from anything — and each one has a job:
//
//   midnight — the calm default: deep blue-black, cool blocks, hairline grid.
//   neon     — high-energy arcade, saturated on near-black, strong glow.
//   sunrise  — warm and light, for bright rooms and light-theme users.
//   ink      — near-monochrome, high contrast, voices separated by LIGHTNESS
//              as well as hue so the view still reads for a colour-blind
//              player and at maximum contrast.
//
// Voice colours are indexed by [HighwayEvent.voice], so hand 1 and hand 2 (or
// part 1..4) are always distinguishable in every skin.

import 'package:flutter/material.dart';

/// The available looks.
enum HighwaySkin { midnight, neon, sunrise, ink }

/// Every colour the highway painter needs.
class HighwayPalette {
  const HighwayPalette({
    required this.skin,
    required this.backdropTop,
    required this.backdropBottom,
    required this.grid,
    required this.gridMajor,
    required this.raisedLaneTint,
    required this.voices,
    required this.hitLine,
    required this.glow,
    required this.missed,
    required this.blockText,
    required this.railWhite,
    required this.railBlack,
    required this.railEdge,
    required this.label,
    required this.dark,
    this.glowStrength = 1.0,
  });

  final HighwaySkin skin;

  /// The far end of the highway (top) and the near end (at the rail).
  final Color backdropTop;
  final Color backdropBottom;

  /// Lane separators; [gridMajor] is the octave / anchor rule.
  final Color grid;
  final Color gridMajor;

  /// The darker column behind a raised (black) key, which is what makes a
  /// keyboard highway readable without drawing a single note name.
  final Color raisedLaneTint;

  /// Block fills, indexed by voice — or by LANE on the instruments where the
  /// lane is the note's identity (see the painter). Six of them, because a
  /// guitar has six strings: with four, strings 5 and 6 wore the colours of 1
  /// and 2 and the rail lied about which string to play.
  final List<Color> voices;

  final Color hitLine;
  final Color glow;
  final Color missed;
  final Color blockText;

  /// Instrument-rail colours.
  final Color railWhite;
  final Color railBlack;
  final Color railEdge;

  /// Grid labels (`C4`, string names).
  final Color label;

  final bool dark;

  /// Scales bloom/flash intensity — `neon` turns it up, `ink` turns it off.
  final double glowStrength;

  Color voiceColor(int voice) => voices[voice % voices.length];

  static HighwayPalette of(HighwaySkin skin) => switch (skin) {
        HighwaySkin.midnight => const HighwayPalette(
            skin: HighwaySkin.midnight,
            backdropTop: Color(0xFF070C16),
            backdropBottom: Color(0xFF16203A),
            grid: Color(0x14FFFFFF),
            gridMajor: Color(0x33FFFFFF),
            raisedLaneTint: Color(0x2E000C1E),
            voices: [
              Color(0xFF5CC8FF),
              Color(0xFF3E7FB0),
              Color(0xFF8E7BE8),
              Color(0xFF4FCBA4),
              Color(0xFFE9A85C),
              Color(0xFFE0708F),
            ],
            hitLine: Color(0xCCFFFFFF),
            glow: Color(0xFFAEE8FF),
            missed: Color(0xFFE05B6B),
            blockText: Color(0xFF06121F),
            railWhite: Color(0xFFF2F5FA),
            railBlack: Color(0xFF141A26),
            railEdge: Color(0xFF2A3348),
            label: Color(0x8CFFFFFF),
            dark: true,
          ),
        HighwaySkin.neon => const HighwayPalette(
            skin: HighwaySkin.neon,
            backdropTop: Color(0xFF04030A),
            backdropBottom: Color(0xFF170B2B),
            grid: Color(0x1FE94AFF),
            gridMajor: Color(0x4DE94AFF),
            raisedLaneTint: Color(0x33000000),
            voices: [
              Color(0xFF2BF5D0),
              Color(0xFFFF2E96),
              Color(0xFFC6FF3D),
              Color(0xFFFFB43D),
              Color(0xFF7A5BFF),
              Color(0xFFFF6B3D),
            ],
            hitLine: Color(0xFFFFFFFF),
            glow: Color(0xFF2BF5D0),
            missed: Color(0xFFFF4D4D),
            blockText: Color(0xFF0B0616),
            railWhite: Color(0xFFE8E2F5),
            railBlack: Color(0xFF120B20),
            railEdge: Color(0xFF3A2358),
            label: Color(0x99FFFFFF),
            dark: true,
            glowStrength: 1.6,
          ),
        HighwaySkin.sunrise => const HighwayPalette(
            skin: HighwaySkin.sunrise,
            backdropTop: Color(0xFFFFF3E4),
            backdropBottom: Color(0xFFFFD9BC),
            grid: Color(0x14000000),
            gridMajor: Color(0x33000000),
            raisedLaneTint: Color(0x14000000),
            voices: [
              Color(0xFFE2622B),
              Color(0xFF6C4BC9),
              Color(0xFF1E93A8),
              Color(0xFFB88A17),
              Color(0xFF2E8B57),
              Color(0xFFB5306B),
            ],
            hitLine: Color(0xCC3A2416),
            glow: Color(0xFFFFB067),
            missed: Color(0xFFB3323F),
            blockText: Color(0xFFFFF7EF),
            railWhite: Color(0xFFFFFDF9),
            railBlack: Color(0xFF4A3B2E),
            railEdge: Color(0xFFCBB49E),
            label: Color(0x993A2416),
            dark: false,
            glowStrength: 0.8,
          ),
        HighwaySkin.ink => const HighwayPalette(
            skin: HighwaySkin.ink,
            backdropTop: Color(0xFFFCFCFA),
            backdropBottom: Color(0xFFEDEDE8),
            grid: Color(0x1A000000),
            gridMajor: Color(0x40000000),
            raisedLaneTint: Color(0x0F000000),
            // Separated by LIGHTNESS first, hue second — readable with any
            // colour vision, and at maximum contrast.
            voices: [
              Color(0xFF17202B),
              Color(0xFF5B6B7C),
              Color(0xFF95A3B1),
              Color(0xFF3D4C5C),
              Color(0xFF77879A),
              Color(0xFF232E3C),
            ],
            hitLine: Color(0xFF17202B),
            glow: Color(0xFF17202B),
            missed: Color(0xFF8C1D28),
            blockText: Color(0xFFFCFCFA),
            railWhite: Color(0xFFFFFFFF),
            railBlack: Color(0xFF2A3340),
            railEdge: Color(0xFF9AA3AE),
            label: Color(0xB3000000),
            dark: false,
            glowStrength: 0.0,
          ),
      };

  /// A short human name for the picker (localized by the caller when it has a
  /// string for it; these are the fallbacks).
  static String nameOf(HighwaySkin skin) => switch (skin) {
        HighwaySkin.midnight => 'Midnight',
        HighwaySkin.neon => 'Neon',
        HighwaySkin.sunrise => 'Sunrise',
        HighwaySkin.ink => 'Ink',
      };
}
