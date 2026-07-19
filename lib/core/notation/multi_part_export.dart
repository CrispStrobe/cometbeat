// lib/core/notation/multi_part_export.dart
//
// Multi-part notation exporters that crisp_notation_core lacks: it ships
// `multiPartToMusicXml` but its MIDI writer is single-Score / SMF format 0, and
// its ABC writer caps at 4 voices on one staff. Real scores have many parts
// (an orchestra = one staff per instrument, i.e. a MultiPartScore with N parts),
// so these keep EVERY part:
//   • multiPartToMidi  — a format-1 SMF, one MTrk per part (+ split/merge halves)
//   • multiPartToAbc   — one ABC `V:` voice per part (unbounded, each with clef)
//
// Pure Dart, Flutter-free (imports crisp_notation_core only) — used by the module
// bridge (module_notation.dart) AND the Workshop's export sheet.

// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';

// ─── Multi-track MIDI (the format-1 round-trip the library lacks) ────────────

/// Reads one SMF chunk (`type` + big-endian length + body) at [offset]; returns
/// the whole chunk bytes and the offset past it.
(Uint8List chunk, int next) _readChunk(Uint8List smf, int offset) {
  // GUARD:chunkheader >>>
  // Untrusted SMF: bail if the 8-byte chunk header doesn't fit (else the reads
  // below RangeError). Returning EOF lets the caller's walk terminate cleanly.
  if (offset < 0 || offset + 8 > smf.length) return (Uint8List(0), smf.length);
  // GUARD:chunkheader <<<
  final len = (smf[offset + 4] << 24) |
      (smf[offset + 5] << 16) |
      (smf[offset + 6] << 8) |
      smf[offset + 7];
  var end = offset + 8 + len;
  // GUARD:chunkclamp >>>
  // The declared 32-bit length is untrusted; clamp the body to the buffer so a
  // lying / oversized length can't blow up sublistView.
  if (end > smf.length) end = smf.length;
  // GUARD:chunkclamp <<<
  return (Uint8List.sublistView(smf, offset, end), end);
}

/// The first `MTrk` chunk (header + body) of a single-track SMF.
Uint8List _firstTrackChunk(Uint8List smf) {
  // MThd is 14 bytes (8 header + 6 body); the track follows.
  final (chunk, _) = _readChunk(smf, 14);
  return chunk;
}

Uint8List _u32(int v) => Uint8List.fromList(
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff],
    );
Uint8List _u16(int v) => Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);

/// Assembles several single-track SMFs into one format-1 file (one MTrk each) —
/// the multi-track export scoreToMidi can't do alone. All tracks share
/// [ticksPerQuarter], so pass the same value used to write [singleTrackSmfs].
Uint8List mergeToMultiTrackMidi(
  List<Uint8List> singleTrackSmfs, {
  int ticksPerQuarter = 480,
}) {
  final tracks = [for (final smf in singleTrackSmfs) _firstTrackChunk(smf)];
  final out = BytesBuilder();
  out.add(Uint8List.fromList('MThd'.codeUnits));
  out.add(_u32(6));
  out.add(_u16(1)); // format 1
  out.add(_u16(tracks.length));
  out.add(_u16(ticksPerQuarter));
  for (final t in tracks) {
    out.add(t);
  }
  return out.toBytes();
}

/// Splits a (format 0 or 1) SMF into one single-track format-0 SMF per `MTrk`,
/// so each can be read back with `scoreFromMidi`. Inverse of
/// [mergeToMultiTrackMidi] for round-trip verification.
List<Uint8List> splitMultiTrackMidi(Uint8List smf) {
  // GUARD:mthdlen >>>
  // Untrusted SMF: reject anything too short for the 14-byte MThd header before
  // reading the division word at smf[12..13] (else RangeError, not a clean
  // rejection). Callers importing a MIDI file catch FormatException.
  if (smf.length < 14) {
    throw const FormatException('SMF too short for a 14-byte MThd header');
  }
  // GUARD:mthdlen <<<
  final division = (smf[12] << 8) | smf[13];
  final tracks = <Uint8List>[];
  var offset = 14; // past MThd
  while (offset + 8 <= smf.length) {
    final type = String.fromCharCodes(smf.sublist(offset, offset + 4));
    final (chunk, next) = _readChunk(smf, offset);
    if (type == 'MTrk') tracks.add(chunk);
    offset = next;
  }
  return [
    for (final t in tracks)
      (BytesBuilder()
            ..add(Uint8List.fromList('MThd'.codeUnits))
            ..add(_u32(6))
            ..add(_u16(0)) // format 0
            ..add(_u16(1))
            ..add(_u16(division))
            ..add(t))
          .toBytes(),
  ];
}

/// A [multiPart] score → a format-1 SMF, one track per part.
///
/// [quarterBpm] is optional: when omitted each part falls back to its own
/// [Score.tempo] (see [scoreToMidi]), so the file plays at the notated tempo
/// instead of a fixed 120.
Uint8List multiPartToMidi(
  MultiPartScore multiPart, {
  double? quarterBpm,
  int ticksPerQuarter = 480,
}) =>
    mergeToMultiTrackMidi(
      [
        for (final part in multiPart.parts)
          scoreToMidi(
            part,
            quarterBpm: quarterBpm,
            ticksPerQuarter: ticksPerQuarter,
          ),
      ],
      ticksPerQuarter: ticksPerQuarter,
    );

/// A (format 0 or 1) SMF → a [MultiPartScore], one part per `MTrk` that has
/// notes. The mirror of [multiPartToMidi]: note-less tracks (a format-1 file's
/// tempo/meta track 0, say) are skipped; if none has notes, the whole file is
/// parsed as one part. So a single-track MIDI yields a 1-part score, and a
/// DAW's N-instrument export yields N parts.
MultiPartScore multiTrackMidiToMultiPart(Uint8List smf) {
  final parts = <Score>[];
  for (final track in splitMultiTrackMidi(smf)) {
    try {
      final score = scoreFromMidi(track);
      final hasNotes =
          score.measures.any((m) => m.elements.any((e) => e is NoteElement));
      if (hasNotes) parts.add(score);
    } catch (_) {
      // A meta-only track (no notes) — scoreFromMidi throws; skip it.
    }
  }
  if (parts.isEmpty) parts.add(scoreFromMidi(smf));
  return MultiPartScore(parts);
}

// ─── Multi-voice ABC (unbounded V: voices — the orchestra case) ──────────────

/// A [multiPart] score as ONE multi-voice ABC tune — each part becomes an ABC
/// `V:` voice. Unlike [scoreToAbc]'s 4-voices-on-one-staff cap, ABC `V:` voices
/// are separate staves and UNBOUNDED, so this keeps every instrument. [partNames]
/// label the voices; each voice carries its part's clef. (crisp_notation_core has
/// no multi-part ABC writer, so we assemble it from the per-part single tunes.)
String multiPartToAbc(MultiPartScore multiPart, {List<String>? partNames}) {
  final parts = multiPart.parts;
  final out = StringBuffer()
    ..writeln('X:1')
    ..writeln('L:1/8')
    ..writeln('K:C');
  if (parts.isEmpty) return out.toString();

  String clefOf(Clef c) => c == Clef.bass ? 'bass' : 'treble';
  // Declare all voices first (readers expect the V: roster before the bodies).
  for (var i = 0; i < parts.length; i++) {
    final name = (partNames != null && i < partNames.length)
        ? partNames[i]
        : 'V${i + 1}';
    out.writeln('V:${i + 1} name="$name" clef=${clefOf(parts[i].clef)}');
  }
  // Then each voice's body — the per-part tune with its header fields stripped.
  final headerField = RegExp(r'^[A-Za-z]:');
  for (var i = 0; i < parts.length; i++) {
    out.writeln('V:${i + 1}');
    for (final line in scoreToAbc(parts[i]).split('\n')) {
      if (line.trim().isEmpty || headerField.hasMatch(line)) continue;
      out.writeln(line);
    }
  }
  return out.toString();
}
