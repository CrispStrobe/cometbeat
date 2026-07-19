// General-MIDI song rendering: split a multi-track SMF into parts that each know
// their GM program + whether they're the percussion channel, so bin/rendersong
// can voice every part with its OWN instrument from a SoundFont (piano on one
// track, bass on another, a drum kit on channel 10) instead of one voice for the
// whole song.
//
// The notation core reads a MIDI's notes but DISCARDS program-change and channel
// info (it merges everything to pitches), so this scans each track's raw MTrk for
// the program (0xC0) and the percussion channel (GM channel 10 = index 9). The
// notes themselves still come from the core's `scoreFromMidi`, so nothing about
// pitch/rhythm parsing is re-implemented — only the GM voice metadata is added.
//
// Pure Dart, Flutter-free (crisp_notation_core + the split helper only).

// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';

import 'package:comet_beat/core/notation/multi_part_export.dart'
    show splitMultiTrackMidi;
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// One part of a General-MIDI song: its notes ([score]), the GM [program] it
/// should be voiced with (0..127, 0 = Acoustic Grand Piano), and whether it is
/// the GM percussion channel ([isDrum] → a bank-128 drum kit, where each note
/// key is a different drum rather than a pitch).
class GmPart {
  const GmPart({
    required this.score,
    required this.program,
    required this.isDrum,
    this.name = '',
  });

  final Score score;
  final int program;
  final bool isDrum;
  final String name;
}

/// The GM program + percussion flag scanned from a single-track SMF's events:
/// the first program-change (0xC0) seen, and whether any note plays on GM
/// channel 10 (index 9). Robust to untrusted input — every read is bounds-checked
/// and a malformed track just yields whatever was found so far.
({int program, bool isDrum, String name}) _scanGmMeta(Uint8List smf) {
  var program = 0;
  var isDrum = false;
  var name = '';

  // A split single-track SMF is MThd (14 bytes) + an MTrk chunk (8-byte header,
  // then events). Walk the events only.
  if (smf.length < 22) return (program: 0, isDrum: false, name: '');
  var offset = 22; // 14 (MThd) + 8 (MTrk header)
  var runningStatus = 0;
  var sawProgram = false;

  int readVarLen() {
    var value = 0;
    while (offset < smf.length) {
      final byte = smf[offset++];
      value = (value << 7) | (byte & 0x7f);
      if (byte & 0x80 == 0) break;
    }
    return value;
  }

  while (offset < smf.length) {
    readVarLen(); // delta time (ignored — we only want the events)
    if (offset >= smf.length) break;
    var status = smf[offset];
    if (status & 0x80 != 0) {
      offset++;
    } else {
      status = runningStatus; // running status
    }

    if (status == 0xff) {
      if (offset >= smf.length) break;
      final metaType = smf[offset++];
      final length = readVarLen();
      if (offset + length > smf.length) break;
      // Track name / instrument name meta → a best-effort label.
      if ((metaType == 0x03 || metaType == 0x04) && name.isEmpty) {
        name =
            String.fromCharCodes(smf.sublist(offset, offset + length)).trim();
      }
      offset += length;
      continue;
    }
    if (status == 0xf0 || status == 0xf7) {
      final length = readVarLen();
      offset += length;
      continue;
    }

    runningStatus = status;
    final kind = status & 0xf0;
    final channel = status & 0x0f;
    final dataLength = (kind == 0xc0 || kind == 0xd0) ? 1 : 2;
    if (offset + dataLength > smf.length) break;
    final d1 = smf[offset];
    offset += dataLength;

    if (kind == 0xc0 && !sawProgram) {
      program = d1 & 0x7f; // first program-change wins
      sawProgram = true;
    } else if (kind == 0x90 && channel == 9) {
      isDrum = true; // a note on GM channel 10 → percussion
    }
  }
  return (program: program, isDrum: isDrum, name: name);
}

/// Split [smf] (a format 0 or 1 SMF) into [GmPart]s — one per `MTrk` that has
/// notes, each carrying its GM program + percussion flag. Note-less tracks (a
/// format-1 tempo/meta track 0) are skipped; a single-track MIDI yields one part.
/// Mirrors [multiTrackMidiToMultiPart] but keeps the GM voice metadata.
List<GmPart> gmPartsFromMidi(Uint8List smf) {
  final parts = <GmPart>[];
  for (final track in splitMultiTrackMidi(smf)) {
    try {
      final score = scoreFromMidi(track);
      final hasNotes =
          score.measures.any((m) => m.elements.any((e) => e is NoteElement));
      if (!hasNotes) continue;
      final meta = _scanGmMeta(track);
      parts.add(
        GmPart(
          score: score,
          program: meta.program,
          isDrum: meta.isDrum,
          name: meta.name,
        ),
      );
    } catch (_) {
      // A meta-only / unparseable track — skip it.
    }
  }
  return parts;
}
