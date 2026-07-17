// lib/features/games/songs/chord_sheet_screen.dart
//
// Renders an imported ChordPro sheet: lyrics with tappable chord chips
// above the syllables — every chip plays its triad. Guitar-campfire mode
// for the notation-shy.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChordSheetScreen extends StatelessWidget {
  final String title;
  final ChordSheet sheet;

  const ChordSheetScreen({
    super.key,
    required this.title,
    required this.sheet,
  });

  @override
  Widget build(BuildContext context) {
    final audio = context.read<AudioService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // All chords once, as a strummable header row.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chord in sheet.chords)
                  ActionChip(
                    label: Text(
                      chord,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: scheme.primaryContainer,
                    onPressed: () {
                      final midis = chordMidis(chord);
                      if (midis != null) audio.playMidiChord(midis);
                    },
                  ),
              ],
            ),
            const Divider(height: 32),
            for (final line in sheet.lines)
              line.isEmpty
                  ? const SizedBox(height: 16)
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          for (final segment in line)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 26,
                                  child: segment.chord == null
                                      ? null
                                      : GestureDetector(
                                          onTap: () {
                                            final midis = chordMidis(
                                              segment.chord!,
                                            );
                                            if (midis != null) {
                                              audio.playMidiChord(midis);
                                            }
                                          },
                                          child: Text(
                                            segment.chord!,
                                            style: TextStyle(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ),
                                Text(
                                  segment.text,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}
