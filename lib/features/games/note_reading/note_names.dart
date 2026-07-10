// lib/features/games/note_reading/note_names.dart
//
// Localized note letter names. German uses H for the natural B — that's why
// these go through the ARB files instead of Step.name.toUpperCase().

import 'package:partitura/partitura.dart';

import '../../../l10n/app_localizations.dart';

String noteName(AppLocalizations l10n, Step step) => switch (step) {
      Step.c => l10n.noteNameC,
      Step.d => l10n.noteNameD,
      Step.e => l10n.noteNameE,
      Step.f => l10n.noteNameF,
      Step.g => l10n.noteNameG,
      Step.a => l10n.noteNameA,
      Step.b => l10n.noteNameB,
    };
