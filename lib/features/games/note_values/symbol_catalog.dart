// lib/features/games/note_values/symbol_catalog.dart
//
// The shared catalog of note/rest symbols for the Notenwerte module:
// glyph, localized name, and duration (as a fraction of a whole note).
// Used by the symbol quiz, the duration duel, and the review flow.

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/music_glyph.dart';

class NoteSymbol {
  /// Catalog ID; SRI items use `note_values.symbol.<id>`.
  final String id;
  final String glyph;

  /// Duration as a fraction of a whole note (1.0, 0.5, 0.25, ...).
  final double beats;

  final String Function(AppLocalizations) label;

  const NoteSymbol(this.id, this.glyph, this.beats, this.label);

  /// Full SRI item ID for this symbol.
  String get sriId => 'note_values.symbol.$id';
}

const kNoteSymbols = <NoteSymbol>[
  NoteSymbol('whole_note', Smufl.wholeNote, 1.0, _wholeNote),
  NoteSymbol('half_note', Smufl.halfNote, 0.5, _halfNote),
  NoteSymbol('quarter_note', Smufl.quarterNote, 0.25, _quarterNote),
  NoteSymbol('eighth_note', Smufl.eighthNote, 0.125, _eighthNote),
  NoteSymbol('sixteenth_note', Smufl.sixteenthNote, 0.0625, _sixteenthNote),
  NoteSymbol('whole_rest', Smufl.wholeRest, 1.0, _wholeRest),
  NoteSymbol('half_rest', Smufl.halfRest, 0.5, _halfRest),
  NoteSymbol('quarter_rest', Smufl.quarterRest, 0.25, _quarterRest),
  NoteSymbol('eighth_rest', Smufl.eighthRest, 0.125, _eighthRest),
  NoteSymbol('sixteenth_rest', Smufl.sixteenthRest, 0.0625, _sixteenthRest),
];

/// Looks up a symbol by its catalog [id]; returns null if unknown.
NoteSymbol? symbolById(String id) {
  for (final symbol in kNoteSymbols) {
    if (symbol.id == id) return symbol;
  }
  return null;
}

// Top-level tear-offs so NoteSymbol entries can be const.
String _wholeNote(AppLocalizations l) => l.wholeNote;
String _halfNote(AppLocalizations l) => l.halfNote;
String _quarterNote(AppLocalizations l) => l.quarterNote;
String _eighthNote(AppLocalizations l) => l.eighthNote;
String _sixteenthNote(AppLocalizations l) => l.sixteenthNote;
String _wholeRest(AppLocalizations l) => l.wholeRest;
String _halfRest(AppLocalizations l) => l.halfRest;
String _quarterRest(AppLocalizations l) => l.quarterRest;
String _eighthRest(AppLocalizations l) => l.eighthRest;
String _sixteenthRest(AppLocalizations l) => l.sixteenthRest;
