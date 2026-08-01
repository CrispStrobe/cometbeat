// lib/features/harmony/transpose_sheet.dart
//
// BB-T4's surface: the two transpositions, kept visibly apart.
//
// The whole point of the card is that "move the tune" and "change what I read"
// are different operations, so the sheet says so in words rather than offering
// one control that quietly does both. The sounding row warns that it changes
// the audio; the reading rows say they do not.
library;

import 'package:comet_beat/core/harmony/chart_transpose.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Edits a [ChartTransposition]. Returns null if dismissed.
Future<ChartTransposition?> showTransposeSheet(
  BuildContext context, {
  required ChartTransposition current,
}) =>
    showModalBottomSheet<ChartTransposition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TransposeSheet(current: current),
    );

class _TransposeSheet extends StatefulWidget {
  const _TransposeSheet({required this.current});
  final ChartTransposition current;

  @override
  State<_TransposeSheet> createState() => _TransposeSheetState();
}

class _TransposeSheetState extends State<_TransposeSheet> {
  late int _sounding = widget.current.soundingSemitones;
  late TransposingInstrument _instrument = widget.current.instrument;
  late int _capo = widget.current.capo;

  ChartTransposition get _value => ChartTransposition(
        soundingSemitones: _sounding,
        instrument: _instrument,
        capo: _capo,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.chartTransposeSounding,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              l10n.chartTransposeSoundingHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var n = -6; n <= 6; n++)
                  _chip(
                    // A signed label, because "+2" and "2" mean different
                    // things next to a "−2".
                    label: n == 0 ? '0' : (n > 0 ? '+$n' : '−${-n}'),
                    selected: _sounding == n,
                    onTap: () => setState(() => _sounding = n),
                    key: Key('transposeSounding_$n'),
                  ),
              ],
            ),
            const Divider(height: 28),
            Text(l10n.chartTransposeReading, style: theme.textTheme.titleSmall),
            Text(
              l10n.chartTransposeReadingHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (instrument, label) in const [
                  (TransposingInstrument.concert, 'C'),
                  (TransposingInstrument.bFlat, 'B♭'),
                  (TransposingInstrument.eFlat, 'E♭'),
                  (TransposingInstrument.f, 'F'),
                ])
                  _chip(
                    label: label,
                    selected: _instrument == instrument,
                    onTap: () => setState(() => _instrument = instrument),
                    key: Key('transposeInstrument_${instrument.name}'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.chartTransposeCapo, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var fret = 0; fret <= 7; fret++)
                  _chip(
                    label: fret == 0 ? l10n.chartKeypadNone : '$fret',
                    selected: _capo == fret,
                    onTap: () => setState(() => _capo = fret),
                    key: Key('transposeCapo_$fret'),
                  ),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const ChartTransposition()),
                  child: Text(l10n.chartTransposeReset),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.chartCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('transposeApply'),
                  onPressed: () => Navigator.of(context).pop(_value),
                  child: Text(l10n.chartOk),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Key key,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      key: key,
      width: 56,
      height: 40,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
