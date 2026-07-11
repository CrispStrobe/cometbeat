// lib/features/progress/sri_item_label.dart
//
// Turns an opaque SRI item ID (`<module>.<skill>.<detail>`) into a readable
// label for the "tricky notes" list. Common namespaces get a tailored label;
// everything else falls back to a prettified detail.

import 'package:klang_universum/features/games/note_values/symbol_catalog.dart';
import 'package:klang_universum/l10n/app_localizations.dart';

String _prettify(String s) => s
    .replaceAll(RegExp(r'[._]'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String describeSriItem(AppLocalizations l10n, String id) {
  final parts = id.split('.');
  final module = parts.isNotEmpty ? parts[0] : '';
  final skill = parts.length > 1 ? parts[1] : '';
  final detail = parts.length > 2 ? parts.sublist(2).join('.') : '';

  switch (module) {
    case 'note_values':
      if (skill == 'symbol') {
        return symbolById(detail)?.label(l10n) ?? _prettify(detail);
      }
      return _prettify(detail.isEmpty ? skill : detail);
    case 'note_reading':
      // skill = clef, detail = pitch like "g4".
      return '${detail.toUpperCase()} · ${_prettify(skill)}';
    case 'chords':
      if (skill == 'triad') {
        final seg = detail.split('_');
        final root = seg.isNotEmpty ? seg.first.toUpperCase() : '';
        final quality = seg.length > 1 ? seg.sublist(1).join(' ') : '';
        return '$root $quality'.trim();
      }
      return _prettify(detail.isEmpty ? skill : detail);
    case 'harmony':
      // skill = function | hear, detail = "<tonic>_<function>".
      final seg = detail.split('_');
      final root = seg.isNotEmpty ? seg.first.toUpperCase() : '';
      final fn = seg.length > 1 ? seg[1] : '';
      final fnLabel = switch (fn) {
        'tonic' => l10n.harmonicTonic,
        'subdominant' => l10n.harmonicSubdominant,
        'dominant' => l10n.harmonicDominant,
        _ => _prettify(fn),
      };
      return '$root · $fnLabel'.trim();
    default:
      return _prettify(detail.isEmpty ? skill : detail);
  }
}
