// lib/features/games/cello/cello_first_position.dart
//
// Cello first-position map (naturals): which string a bass-clef note is
// played on and which finger stops it (0 = open string). Standard first
// position: finger 1 a whole step above open, fingers 2/3 a half step
// apart, finger 4 a fourth above open.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// The four cello strings, low to high.
enum CelloString {
  c(Pitch(Step.c, octave: 2)),
  g(Pitch(Step.g, octave: 2)),
  d(Pitch(Step.d, octave: 3)),
  a(Pitch(Step.a, octave: 3));

  const CelloString(this.openPitch);

  /// The open-string pitch.
  final Pitch openPitch;

  /// Localized display name (German B = H handled by the ARB files).
  String label(AppLocalizations l10n) => switch (this) {
        CelloString.c => l10n.noteNameC,
        CelloString.g => l10n.noteNameG,
        CelloString.d => l10n.noteNameD,
        CelloString.a => l10n.noteNameA,
      };
}

class CelloNote {
  final Pitch pitch;
  final CelloString string;
  final int finger; // 0 (open), 1..4

  const CelloNote(this.pitch, this.string, this.finger);
}

/// Naturals in first position, C2 (open C) to D4 (4th finger on A).
const kCelloFirstPosition = <CelloNote>[
  // C string: C(0) D(1) E(3) F(4)
  CelloNote(Pitch(Step.c, octave: 2), CelloString.c, 0),
  CelloNote(Pitch(Step.d, octave: 2), CelloString.c, 1),
  CelloNote(Pitch(Step.e, octave: 2), CelloString.c, 3),
  CelloNote(Pitch(Step.f, octave: 2), CelloString.c, 4),
  // G string: G(0) A(1) B(3) C(4)
  CelloNote(Pitch(Step.g, octave: 2), CelloString.g, 0),
  CelloNote(Pitch(Step.a, octave: 2), CelloString.g, 1),
  CelloNote(Pitch(Step.b, octave: 2), CelloString.g, 3),
  CelloNote(Pitch(Step.c, octave: 3), CelloString.g, 4),
  // D string: D(0) E(1) F(2) G(4)
  CelloNote(Pitch(Step.d, octave: 3), CelloString.d, 0),
  CelloNote(Pitch(Step.e, octave: 3), CelloString.d, 1),
  CelloNote(Pitch(Step.f, octave: 3), CelloString.d, 2),
  CelloNote(Pitch(Step.g, octave: 3), CelloString.d, 4),
  // A string: A(0) B(1) C(2) D(4)
  CelloNote(Pitch(Step.a, octave: 3), CelloString.a, 0),
  CelloNote(Pitch(Step.b, octave: 3), CelloString.a, 1),
  CelloNote(Pitch(Step.c), CelloString.a, 2),
  CelloNote(Pitch(Step.d), CelloString.a, 4),
];
