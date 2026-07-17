// lib/core/audio/mod/module_convert.dart
//
// Cross-format module conversion via the neutral [ModuleDoc] hub (module_doc.dart).
// Readers (parseMod/parseS3m/parseXm/parseIt) → ModuleDoc adapters here; a writer
// (writeMod, so far) turns a ModuleDoc back into bytes. Any A→B = parseAnyModule
// (→ ModuleDoc) then convertToMod / a future writer. See docs/TRACKER_IDEAS.md §A.
//
// ─── Contract for the implementer ────────────────────────────────────────────
// sniffModuleFormat(bytes): detect by signature, return null if unknown.
//   • XM  : bytes[0..17]  == "Extended Module: "
//   • IT  : bytes[0..4]   == "IMPM"
//   • S3M : bytes[0x2C..0x30] == "SCRM"  (offset 44)
//   • MOD : bytes[1080..1084] is a known tag: "M.K.","M!K!","M&K!","FLT4","FLT8",
//           "4CHN","6CHN","8CHN","2CHN","OKTA","CD81", or "<n>CH"/"<nn>CHN". If
//           none of XM/IT/S3M match and the buffer is long enough with a MOD tag,
//           it's MOD; otherwise null.
//
// parseAnyModule(bytes): sniff, dispatch to the right reader, adapt to ModuleDoc.
//   Throws ArgumentError if the format is unrecognized. Propagates the reader's
//   own *FormatException on malformed input.
//
// docFrom*(module): map each reader model → ModuleDoc.
//   • title/channelCount/order/speed/tempo from the source (MOD has no stored
//     speed/tempo → use 6/125).
//   • Notes → MIDI via the existing helpers: periodToMidi (MOD), s3mNoteToMidi,
//     xmNoteToMidi, itNoteToMidi. -1 stays -1 (absent/off/cut).
//   • instrument: MOD cell.sample; S3M/XM/IT cell.instrument (0 = none).
//   • volume column: MOD → -1 (none). S3M cell.volume (255 → -1). XM volume byte
//     0x10..0x50 → (byte-0x10) else -1. IT volpan 0..64 → volpan else -1.
//   • samples: build a FULL, index-aligned list (instrument k → samples[k-1]);
//     unused slots = DocSample.empty(). PCM → Float64List normalized: MOD/S3M
//     Int8List /128; XM/IT pcm is already normalized (copy). loop: MOD
//     repeatPoint/repeatLength (length ≤1 → 0); S3M loopStart / (loopEnd-loopStart
//     if loop else 0); XM loopStart/loopLength; IT loopStart / (loopEnd-loopStart
//     if the loop flag/loopEnd>loopStart else 0). volume from the source's default
//     volume. c5speed: MOD finetuneToC5speed(finetune); S3M c2spd; XM
//     xmTuningToC5speed(relativeNote, finetune); IT c5speed.
//     XM instruments hold multiple samples → use instrument.samples.first (or
//     empty). IT is read in sample mode → cell.instrument indexes samples directly.
//
// docToMod(doc): neutral → ModModule (canonical 4-channel MOD).
//   • title ≤20 chars; channelCount = 4 (map doc channels 0..3; pad missing with
//     empty cells, DROP channels ≥4 — note the loss). order = doc.order; restart 0.
//   • samples: exactly 31 ModSample. For k in 1..31: if doc.samples[k-1] exists and
//     is non-empty → ModSample(name ≤22, volume, finetune = c5speedToFinetune(
//     c5speed), repeatPoint = loopStart, repeatLength = loopLength (0 → 0),
//     pcm = Int8List from (normalized*127) rounded & clamped to [-128,127]); else
//     ModSample.empty().
//   • patterns: each DocPattern → a 64-row × 4-channel ModPattern (pad/truncate
//     rows to 64, channels to 4). cell: period = note<0 ? 0 : midiToPeriod(note),
//     sample = instrument.clamp(0,31), effect 0, param 0 (effects/volume dropped).
//
// convertToMod(doc) = writeMod(docToMod(doc)).
//
// Tuning helpers (put them in this file):
//   finetuneToC5speed(ft)  = (8363 * pow(2, ft/(12*8))).round()        // MOD ft −8..7
//   c5speedToFinetune(hz)  = (96 * log2(hz/8363)).round().clamp(-8,7)
//   xmTuningToC5speed(rel,ft) = (8363 * pow(2,(rel*128+ft)/(12*128))).round()
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/it_writer.dart';
import 'package:comet_beat/core/audio/mod/mod_module.dart';
import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/mod_writer.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:comet_beat/core/audio/mod/xm_module.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:comet_beat/core/audio/mod/xm_writer.dart';

/// Detects the module container format by signature; null if unrecognized.
ModuleFormat? sniffModuleFormat(Uint8List bytes) {
  if (_asciiAt(bytes, 0, 'Extended Module: ')) return ModuleFormat.xm;
  if (_asciiAt(bytes, 0, 'IMPM')) return ModuleFormat.it;
  if (_asciiAt(bytes, 0x2C, 'SCRM')) return ModuleFormat.s3m;
  if (bytes.length >= 1084) {
    final tag = String.fromCharCodes(bytes.sublist(1080, 1084));
    if (_isModTag(tag)) return ModuleFormat.mod;
  }
  return null;
}

/// True if [bytes] equals the ASCII [s] starting at [off] (guarded by length).
bool _asciiAt(Uint8List bytes, int off, String s) {
  if (off + s.length > bytes.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (bytes[off + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

/// Recognizes a 4-byte MOD signature tag (known tags + `NCHN`/`NNCH`).
bool _isModTag(String tag) {
  const known = {
    'M.K.', 'M!K!', 'M&K!', 'FLT4', 'FLT8', //
    '4CHN', '6CHN', '8CHN', '2CHN', 'OKTA', 'OCTA', 'CD81',
  };
  if (known.contains(tag)) return true;
  if (tag.length != 4) return false;
  final u = tag.codeUnits;
  bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  // single digit + "CHN" (e.g. "6CHN")
  if (isDigit(u[0]) && tag.substring(1) == 'CHN') return true;
  // two digits + "CH" (e.g. "16CH", "32CH")
  if (isDigit(u[0]) && isDigit(u[1]) && tag.substring(2) == 'CH') return true;
  return false;
}

/// Sniffs [bytes], parses with the right reader, and adapts to a [ModuleDoc].
ModuleDoc parseAnyModule(Uint8List bytes) {
  final fmt = sniffModuleFormat(bytes);
  switch (fmt) {
    case ModuleFormat.mod:
      return docFromMod(parseMod(bytes));
    case ModuleFormat.s3m:
      return docFromS3m(parseS3m(bytes));
    case ModuleFormat.xm:
      return docFromXm(parseXm(bytes));
    case ModuleFormat.it:
      return docFromIt(parseIt(bytes));
    case null:
      throw ArgumentError('Unrecognized module format');
  }
}

/// Int8 PCM (−128..127) → normalized Float64 in [-1, 1] (v / 128).
Float64List _normInt8(Int8List src) {
  final out = Float64List(src.length);
  for (var i = 0; i < src.length; i++) {
    out[i] = src[i] / 128.0;
  }
  return out;
}

ModuleDoc docFromMod(ModModule m) {
  final samples = <DocSample>[];
  for (final s in m.samples) {
    if (s.isEmpty) {
      samples.add(DocSample.empty());
    } else {
      final ds = DocSample(
        name: s.name,
        volume: s.volume,
        loopStart: s.repeatPoint,
        loopLength: s.repeatLength <= 1 ? 0 : s.repeatLength,
        c5speed: finetuneToC5speed(s.finetune),
        pcm: _normInt8(s.pcm),
      );
      samples.add(ds);
    }
  }

  final patterns = <DocPattern>[];
  for (final pat in m.patterns) {
    final ch = pat.channelCount;
    final rows = <List<DocCell>>[];
    for (final row in pat.rows) {
      final cells = <DocCell>[];
      for (final c in row) {
        cells.add(
          DocCell(note: periodToMidi(c.period), instrument: c.sample),
        );
      }
      rows.add(cells);
    }
    patterns.add(DocPattern(rows, ch));
  }

  return ModuleDoc(
    title: m.title,
    channelCount: m.channelCount,
    sourceFormat: ModuleFormat.mod,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

ModuleDoc docFromS3m(S3mModule m) {
  final samples = <DocSample>[];
  for (final s in m.samples) {
    if (s.isEmpty) {
      samples.add(DocSample.empty());
    } else {
      final ds = DocSample(
        name: s.name,
        volume: s.volume,
        loopStart: s.loopStart,
        loopLength: s.loop ? (s.loopEnd - s.loopStart) : 0,
        c5speed: s.c2spd,
        pcm: _normInt8(s.pcm),
      );
      samples.add(ds);
    }
  }

  final patterns = <DocPattern>[];
  for (final pat in m.patterns) {
    final ch = pat.channelCount;
    final rows = <List<DocCell>>[];
    for (final row in pat.rows) {
      final cells = <DocCell>[];
      for (final c in row) {
        cells.add(
          DocCell(
            note: s3mNoteToMidi(c.note),
            instrument: c.instrument,
            volume: c.volume == S3mCell.noVolume ? -1 : c.volume,
          ),
        );
      }
      rows.add(cells);
    }
    patterns.add(DocPattern(rows, ch));
  }

  return ModuleDoc(
    title: m.title,
    channelCount: m.channelCount,
    initialSpeed: m.initialSpeed,
    initialTempo: m.initialTempo,
    sourceFormat: ModuleFormat.s3m,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

ModuleDoc docFromXm(XmModule m) {
  final samples = <DocSample>[];
  for (final inst in m.instruments) {
    if (inst.samples.isEmpty || inst.samples.first.isEmpty) {
      samples.add(DocSample.empty());
    } else {
      final s = inst.samples.first;
      final ds = DocSample(
        name: s.name,
        volume: s.volume,
        loopStart: s.loopStart,
        loopLength: s.loopLength,
        c5speed: xmTuningToC5speed(s.relativeNote, s.finetune),
        pcm: Float64List.fromList(s.pcm),
      );
      samples.add(ds);
    }
  }

  final patterns = <DocPattern>[];
  for (final pat in m.patterns) {
    final ch = pat.channelCount;
    final rows = <List<DocCell>>[];
    for (final row in pat.rows) {
      final cells = <DocCell>[];
      for (final c in row) {
        final vol =
            (c.volume >= 0x10 && c.volume <= 0x50) ? c.volume - 0x10 : -1;
        cells.add(
          DocCell(
            note: xmNoteToMidi(c.note),
            instrument: c.instrument,
            volume: vol,
          ),
        );
      }
      rows.add(cells);
    }
    patterns.add(DocPattern(rows, ch));
  }

  return ModuleDoc(
    title: m.name,
    channelCount: m.channelCount,
    initialSpeed: m.defaultTempo,
    initialTempo: m.defaultBpm,
    sourceFormat: ModuleFormat.xm,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

ModuleDoc docFromIt(ItModule m) {
  final samples = <DocSample>[];
  for (final s in m.samples) {
    if (s.isEmpty) {
      samples.add(DocSample.empty());
    } else {
      final looped = s.loopEnd > s.loopStart;
      final ds = DocSample(
        name: s.name,
        volume: s.defaultVolume,
        loopStart: s.loopStart,
        loopLength: looped ? (s.loopEnd - s.loopStart) : 0,
        c5speed: s.c5speed,
        pcm: Float64List.fromList(s.pcm),
      );
      samples.add(ds);
    }
  }

  final patterns = <DocPattern>[];
  for (final pat in m.patterns) {
    final ch = pat.channelCount;
    final rows = <List<DocCell>>[];
    for (final row in pat.rows) {
      final cells = <DocCell>[];
      for (final c in row) {
        final vol = (c.volpan >= 0 && c.volpan <= 64) ? c.volpan : -1;
        cells.add(
          DocCell(
            note: itNoteToMidi(c.note),
            instrument: c.instrument,
            volume: vol,
          ),
        );
      }
      rows.add(cells);
    }
    patterns.add(DocPattern(rows, ch));
  }

  return ModuleDoc(
    title: m.name,
    channelCount: m.channelCount,
    initialSpeed: m.initialSpeed,
    initialTempo: m.initialTempo,
    sourceFormat: ModuleFormat.it,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

/// Neutral → canonical 4-channel ProTracker [ModModule].
ModModule docToMod(ModuleDoc doc) {
  // Exactly 31 sample slots.
  final samples = <ModSample>[];
  for (var k = 1; k <= 31; k++) {
    final ds = (k - 1) < doc.samples.length ? doc.samples[k - 1] : null;
    if (ds != null && !ds.isEmpty) {
      final pcm = Int8List(ds.pcm.length);
      for (var i = 0; i < ds.pcm.length; i++) {
        pcm[i] = (ds.pcm[i] * 127).round().clamp(-128, 127);
      }
      samples.add(
        ModSample(
          name: ds.name,
          volume: ds.volume.clamp(0, 64),
          finetune: c5speedToFinetune(ds.c5speed),
          repeatPoint: ds.loopStart,
          repeatLength: ds.loopLength,
          pcm: pcm,
        ),
      );
    } else {
      samples.add(ModSample.empty());
    }
  }

  // Each pattern → 64 rows × 4 channels (first 4 doc channels; drop the rest).
  final patterns = <ModPattern>[];
  for (final dp in doc.patterns) {
    final rows = <List<ModCell>>[];
    for (var r = 0; r < 64; r++) {
      final srcRow = r < dp.rows.length ? dp.rows[r] : const <DocCell>[];
      final cells = <ModCell>[];
      for (var ch = 0; ch < 4; ch++) {
        if (ch < srcRow.length) {
          final c = srcRow[ch];
          cells.add(
            ModCell(
              sample: c.instrument.clamp(0, 31),
              period: c.note < 0 ? 0 : midiToPeriod(c.note),
            ),
          );
        } else {
          cells.add(ModCell.empty);
        }
      }
      rows.add(cells);
    }
    patterns.add(ModPattern(rows));
  }

  return ModModule(
    title: doc.title,
    restart: 0,
    samples: samples,
    order: List<int>.from(doc.order),
    patterns: patterns,
  );
}

/// Convenience: convert a neutral module straight to `.mod` bytes.
///
/// Note: `.mod` sample PCM is word-aligned, so [writeMod] pads an odd-length
/// sample up by one trailing byte (a harmless zero) — a re-read sample can be
/// one longer than the neutral source. That's the format, not a lossy step.
Uint8List convertToMod(ModuleDoc doc) => writeMod(docToMod(doc));

/// Neutral → [XmModule] (one single-sample XM instrument per neutral sample).
///
/// v1 writes 8-bit samples (the neutral model doesn't carry bit depth); notes,
/// instruments, the volume column, samples, loops and structure convert.
XmModule docToXm(ModuleDoc doc) {
  final instruments = <XmInstrument>[];
  for (final ds in doc.samples) {
    if (ds.isEmpty) {
      instruments.add(const XmInstrument(samples: []));
      continue;
    }
    final (rel, ft) = _c5speedToXmTuning(ds.c5speed);
    instruments.add(
      XmInstrument(
        name: ds.name,
        samples: [
          XmSample(
            name: ds.name,
            volume: ds.volume.clamp(0, 64),
            finetune: ft,
            relativeNote: rel,
            loopStart: ds.loopStart,
            loopLength: ds.loopLength,
            pcm: Float64List.fromList(ds.pcm),
          ),
        ],
      ),
    );
  }

  final patterns = <XmPattern>[];
  for (final dp in doc.patterns) {
    final rows = <List<XmCell>>[];
    for (final srcRow in dp.rows) {
      final cells = <XmCell>[];
      for (var ch = 0; ch < doc.channelCount; ch++) {
        if (ch < srcRow.length) {
          final c = srcRow[ch];
          cells.add(
            XmCell(
              note: c.note < 0 ? 0 : (c.note - 11).clamp(1, 96),
              instrument: c.instrument.clamp(0, 255),
              volume: c.volume < 0 ? 0 : (0x10 + c.volume).clamp(0x10, 0x50),
            ),
          );
        } else {
          cells.add(XmCell.empty);
        }
      }
      rows.add(cells);
    }
    patterns.add(XmPattern(rows));
  }

  return XmModule(
    name: doc.title,
    channelCount: doc.channelCount,
    defaultTempo: doc.initialSpeed,
    defaultBpm: doc.initialTempo,
    order: List<int>.from(doc.order),
    patterns: patterns,
    instruments: instruments,
  );
}

/// Convenience: convert a neutral module straight to `.xm` bytes.
Uint8List convertToXm(ModuleDoc doc) => writeXm(docToXm(doc));

/// MIDI note → S3M note byte ((octave << 4) | semitone). Inverse of
/// [s3mNoteToMidi]; -1 → the empty-note sentinel.
int _midiToS3mNote(int midi) {
  if (midi < 0) return S3mCell.emptyNote;
  final rel = midi - 12;
  final octave = (rel ~/ 12).clamp(0, 15);
  final semitone = rel % 12;
  return (octave << 4) | semitone;
}

/// Neutral → [S3mModule] (one PCM sample per neutral sample).
///
/// Samples convert exactly (normalized ×128 inverts the reader's /128); notes,
/// instruments, the volume column, loops and structure convert. Per-cell effects
/// are already dropped on the neutral model.
S3mModule docToS3m(ModuleDoc doc) {
  final samples = <S3mSample>[];
  for (final ds in doc.samples) {
    if (ds.isEmpty) {
      samples.add(S3mSample.empty());
      continue;
    }
    final pcm = Int8List(ds.pcm.length);
    for (var i = 0; i < ds.pcm.length; i++) {
      pcm[i] = (ds.pcm[i] * 128).round().clamp(-128, 127);
    }
    samples.add(
      S3mSample(
        name: ds.name,
        volume: ds.volume.clamp(0, 64),
        c2spd: ds.c5speed,
        loop: ds.loopLength > 0,
        loopStart: ds.loopStart,
        loopEnd: ds.loopStart + ds.loopLength,
        pcm: pcm,
      ),
    );
  }

  final patterns = <S3mPattern>[];
  for (final dp in doc.patterns) {
    final rows = <List<S3mCell>>[];
    for (final srcRow in dp.rows) {
      final cells = <S3mCell>[];
      for (var ch = 0; ch < doc.channelCount; ch++) {
        if (ch < srcRow.length) {
          final c = srcRow[ch];
          cells.add(
            S3mCell(
              note: _midiToS3mNote(c.note),
              instrument: c.instrument.clamp(0, 255),
              volume: c.volume < 0 ? S3mCell.noVolume : c.volume.clamp(0, 64),
            ),
          );
        } else {
          cells.add(S3mCell.empty);
        }
      }
      rows.add(cells);
    }
    patterns.add(S3mPattern(rows));
  }

  return S3mModule(
    title: doc.title,
    channelCount: doc.channelCount,
    initialSpeed: doc.initialSpeed,
    initialTempo: doc.initialTempo,
    order: List<int>.from(doc.order),
    samples: samples,
    patterns: patterns,
  );
}

/// Convenience: convert a neutral module straight to `.s3m` bytes.
Uint8List convertToS3m(ModuleDoc doc) => writeS3m(docToS3m(doc));

/// Neutral → [ItModule] (sample mode; one PCM sample per neutral sample).
///
/// IT note numbers equal MIDI (itNoteToMidi is identity for 0..119), so notes map
/// directly. Samples convert exactly (×128/×32768 inverts the reader's /128//32768;
/// v1 writes 8-bit — the neutral model carries no bit depth). Written uncompressed.
ItModule docToIt(ModuleDoc doc) {
  final samples = <ItSample>[];
  for (final ds in doc.samples) {
    if (ds.isEmpty) {
      samples.add(ItSample.empty());
      continue;
    }
    samples.add(
      ItSample(
        name: ds.name,
        defaultVolume: ds.volume.clamp(0, 64),
        length: ds.pcm.length,
        loopStart: ds.loopStart,
        loopEnd: ds.loopStart + ds.loopLength,
        c5speed: ds.c5speed,
        pcm: Float64List.fromList(ds.pcm),
      ),
    );
  }

  final patterns = <ItPattern>[];
  for (final dp in doc.patterns) {
    final rows = <List<ItCell>>[];
    for (final srcRow in dp.rows) {
      final cells = <ItCell>[];
      for (var ch = 0; ch < doc.channelCount; ch++) {
        if (ch < srcRow.length) {
          final c = srcRow[ch];
          cells.add(
            ItCell(
              note: c.note < 0 ? -1 : c.note.clamp(0, 119),
              instrument: c.instrument.clamp(0, 255),
              volpan: c.volume < 0 ? -1 : c.volume.clamp(0, 64),
            ),
          );
        } else {
          cells.add(ItCell.empty);
        }
      }
      rows.add(cells);
    }
    patterns.add(ItPattern(rows, doc.channelCount));
  }

  return ItModule(
    name: doc.title,
    channelCount: doc.channelCount,
    initialSpeed: doc.initialSpeed,
    initialTempo: doc.initialTempo,
    order: List<int>.from(doc.order),
    patterns: patterns,
    samples: samples,
  );
}

/// Convenience: convert a neutral module straight to `.it` bytes.
Uint8List convertToIt(ModuleDoc doc) => writeIt(docToIt(doc));

// ─── Tuning helpers ──────────────────────────────────────────────────────────

double _log2(num x) => math.log(x) / math.ln2;

/// MOD finetune (−8..7) → C-5 playback rate (Hz).
int finetuneToC5speed(int ft) => (8363 * math.pow(2, ft / (12 * 8))).round();

/// C-5 playback rate (Hz) → nearest MOD finetune, clamped to [-8, 7].
int c5speedToFinetune(int hz) => (96 * _log2(hz / 8363)).round().clamp(-8, 7);

/// XM relativeNote + finetune → C-5 playback rate (Hz).
int xmTuningToC5speed(int rel, int ft) =>
    (8363 * math.pow(2, (rel * 128 + ft) / (12 * 128))).round();

/// C-5 playback rate (Hz) → XM (relativeNote, finetune). Inverse of
/// [xmTuningToC5speed]: total 1/128-semitone units split into whole semitones
/// (relativeNote) and the finetune remainder, clamped to signed-byte ranges.
(int, int) _c5speedToXmTuning(int hz) {
  if (hz <= 0) return (0, 0);
  final total = (12 * 128 * _log2(hz / 8363)).round();
  var rel = (total / 128).round();
  var ft = total - rel * 128;
  if (ft > 127) {
    ft -= 128;
    rel += 1;
  } else if (ft < -128) {
    ft += 128;
    rel -= 1;
  }
  return (rel.clamp(-128, 127), ft.clamp(-128, 127));
}
