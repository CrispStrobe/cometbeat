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
//     sample = instrument.clamp(0,31). A volume-column value is carried as a Cxx
//     set-volume effect (MOD has no volume column) and a note-off as C00 (MOD has
//     no note-off — C00 silences the note); source effects still drop.
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
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show
        kFxGlobalVolSlide,
        kFxPanbrello,
        kFxPanSlide,
        kFxRetrigVolSlide,
        kFxSetFilter,
        kFxSetGlobalVolume,
        kFxSetHighOffset,
        kFxSetPanbrelloWaveform,
        kFxSetPastNote,
        kFxSetSoundControl,
        kFxSetSpeedFull,
        kFxTremor;

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
///
/// Throws a [FormatException] on unrecognized input — a data error for the
/// untrusted file bytes, consistent with the per-format readers (which throw
/// their own *FormatException on malformed-but-recognized input) rather than an
/// ArgumentError, which would signal a caller/programming mistake.
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
      throw const FormatException('Unrecognized module format');
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
        // ModSample.repeatLength is stored in bytes, while the MOD header
        // stores words. A one-word (two-byte) repeat is the no-loop sentinel.
        loopLength: s.repeatLength <= 2 ? 0 : s.repeatLength,
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
          DocCell(
            note: periodToMidi(c.period),
            instrument: c.sample,
            // MOD's effect nibble maps 1:1 onto the replayer's fxCmd/fxParam.
            effect: c.effect,
            effectParam: c.effectParam,
            nativeEffect: c.effect == 0 && c.effectParam == 0 ? -1 : c.effect,
            nativeEffectParam: c.effectParam,
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
    sourceFormat: ModuleFormat.mod,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

/// Maps an S3M letter-command (A=1..Z=26) + info byte to our MOD-numbered
/// `(fxCmd, fxParam)` (the DocCell effect column). S3M's command SET differs from
/// MOD's numbering, so this is a real translation. Verified against libopenmpt
/// (`openmpt123 --render`) — see docs/ORACLE.md. Commands with no equivalent in
/// our set return `(0, 0)` (dropped). fxCmd values match the replayer's `kFx*`.
(int, int) _s3mEffectToFx(int cmd, int info) {
  switch (cmd) {
    case 1: // A — set speed (ticks/row), full 1..255 range
      // NOT Fxx: S3M/IT keep speed (Axx) and tempo (Txx) as separate commands,
      // so a speed of e.g. 153 is legal and has no Fxx encoding (there, >= 0x20
      // means tempo). It used to be clamped to 0x1F here, which silently sped up
      // every passage built on a slow speed.
      return info == 0 ? (0, 0) : (kFxSetSpeedFull, info.clamp(1, 255));
    case 2: // B — position jump
      return (0xB, info);
    case 3: // C — pattern break (row param, decimal like MOD's Dxx)
      return (0xD, info);
    case 4: // D — volume slide (Dxy: x up / y down — matches our Axy; fine
      //     slides with an 0xF nibble are approximated as a normal slide)
      return (0xA, info);
    case 5: // E — portamento down
      return (0x2, info);
    case 6: // F — portamento up
      return (0x1, info);
    case 7: // G — tone portamento
      return (0x3, info);
    case 8: // H — vibrato
      return (0x4, info);
    case 13: // M — set channel volume
      return (0xC, info.clamp(0, 64));
    case 14: // N — channel volume slide
      return (0xA, info);
    case 16: // P — pan slide
      return (kFxPanSlide, info);
    case 17: // Q — retrigger + volume action
      return (kFxRetrigVolSlide, info);
    case 10: // J — arpeggio
      return (0x0, info);
    case 11: // K — vibrato + volume slide
      return (0x6, info);
    case 12: // L — tone porta + volume slide
      return (0x5, info);
    case 15: // O — set sample offset
      return (0x9, info);
    case 18: // R — tremolo
      return (0x7, info);
    case 19: // S — special/extended: remap the sub-command nibble
      return _s3mSpecialToFx(info);
    case 20: // T — set tempo (BPM); our Fxx >= 0x20 = tempo
      return info < 0x20 ? (0x1F, info) : (0xF, info);
    case 9: // I — tremor
      return (kFxTremor, info);
    case 21: // U — fine vibrato (approximated as vibrato)
      return (0x4, info);
    case 22: // V — set global volume
      return (kFxSetGlobalVolume, info.clamp(0, 64));
    case 23: // W — global volume slide
      return (kFxGlobalVolSlide, info);
    case 24: // X — set pan (0x00..0x80) → our 8xx (0x00..0xFF)
      return (0x8, (info * 2).clamp(0, 0xFF));
    case 25: // Y — panbrello
      return (kFxPanbrello, info);
    default:
      // Y panbrello · Z MIDI — no neutral equivalent (dropped).
      return (0, 0);
  }
}

/// S3M/IT `Sxy` special sub-commands → our neutral extended effects (where an
/// equivalent exists). S6x and SEx both extend the current row in the
/// renderer; the source command remains in nativeEffect for same-format
/// export, so this translation only supplies playback semantics.
(int, int) _s3mSpecialToFx(int info) {
  final sub = (info >> 4) & 0xF, val = info & 0xF;
  switch (sub) {
    case 0x1: // S1x — glissando control → E3x (kExGlissando)
      return (0xE, (0x3 << 4) | val);
    case 0x2: // S2x — set finetune → E5x (kExSetFinetune)
      return (0xE, (0x5 << 4) | val);
    case 0x3: // S3x — set vibrato waveform → E4x (kExVibratoWaveform)
      return (0xE, (0x4 << 4) | val);
    case 0x4: // S4x — set tremolo waveform → E7x (kExTremoloWaveform)
      return (0xE, (0x7 << 4) | val);
    case 0x5: // S5x — set panbrello waveform → kFxSetPanbrelloWaveform (0x15)
      return (kFxSetPanbrelloWaveform, val);
    case 0xA: // SAx — high sample offset
      return (kFxSetHighOffset, val);
    case 0x9: // S9x — sound control (surround/reverse)
      // Carry the sound-control sub-nibble; the replayer acts on the audible
      // ones (S90/S91 surround, S9E/S9F reverse) and ignores the rest.
      //
      // Named, NOT a literal: this READ path kept its raw 0x14 when the
      // constant moved, so an S9x came back in as whatever then owned 0x14
      // (set-speed). The writer had been converted to names; this side had not.
      return (kFxSetSoundControl, val);
    case 0x7: // S7x — past-note / NNA control
      // Carry the S7 sub-nibble; the replayer acts on the implemented ones
      // (S70/S71/S72 past-note cut/off/fade, S73–S76 set-NNA) and carries the
      // deferred envelope toggles (S77–S7C) as data.
      return (kFxSetPastNote, val);
    case 0x6: // S6x — fine pattern delay; EEx is row delay in our engine
    case 0xE: // SEx — coarse pattern delay
      return (0xE, (0xE << 4) | val);
    case 0x8: // S8x — coarse pan (0..15) → MOD 8xx (0..255)
      return (0x8, val * 0x11);
    case 0xB: // SBx — pattern loop → E6x
      return (0xE, (0x6 << 4) | val);
    case 0xC: // SCx — note cut → ECx
      return (0xE, (0xC << 4) | val);
    case 0xD: // SDx — note delay → EDx
      return (0xE, (0xD << 4) | val);
    default:
      // No faithful replayer equivalent → dropped (surfaced by the export-loss
      // report). Re-examined now that kFxSetFilter (Zxx resonant low-pass)
      // exists, and each still genuinely fails to map:
      //   • S0x set filter — a COARSE hardware on/off toggle (the ST3 SB/GUS
      //     output filter, cf. the Amiga LED filter), NOT the IT resonant
      //     filter. kFxSetFilter needs a 0..127 cutoff/resonance value; "filter
      //     on" carries no cutoff, so mapping it to Zxx would fabricate one.
      //   • SFx set active MIDI macro — MIDI to external gear, no audible target.
      // (SAx high sample offset → kFxSetHighOffset; S9x surround / reverse play →
      // kFxSetSoundControl; S7x past-note / NNA control → kFxSetPastNote, all
      // above. Names, not numbers — the numbers in comments went stale repeatedly.)
      return (0, 0);
  }
}

/// XM volume-column mini-commands that have a direct neutral/replayer form.
/// The raw XM byte remains in [DocCell.nativeVolpan] for same-format export.
(int, int)? _xmVolumeColumnToFx(int volume) {
  final nibble = volume & 0xF;
  if (volume >= 0x60 && volume <= 0x6F) return (0xA, nibble);
  if (volume >= 0x70 && volume <= 0x7F) return (0xA, nibble << 4);
  if (volume >= 0x80 && volume <= 0x8F) return (0xE, 0xB0 | nibble);
  if (volume >= 0x90 && volume <= 0x9F) return (0xE, 0xA0 | nibble);
  if (volume >= 0xA0 && volume <= 0xAF) return (0x4, nibble << 4);
  if (volume >= 0xB0 && volume <= 0xBF) return (0x4, nibble);
  if (volume >= 0xC0 && volume <= 0xCF) return (0x8, nibble * 0x11);
  if (volume >= 0xD0 && volume <= 0xDF) return (kFxPanSlide, nibble);
  if (volume >= 0xE0 && volume <= 0xEF) return (kFxPanSlide, nibble << 4);
  if (volume >= 0xF0 && volume <= 0xFF) return (0x3, nibble);
  return null;
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
        sixteenBit: s.sixteenBit,
        pcm: Float64List.fromList(s.pcm), // already normalized by the reader
        // AdLib (type-2): carry the 12 OPL register bytes so the import can
        // build a dynamic OplInstrument instead of the static preview PCM.
        adlibData: s.adlib ? List<int>.from(s.adlibData) : null,
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
        final (fxCmd, fxParam) = _s3mEffectToFx(c.command, c.info);
        cells.add(
          DocCell(
            note: s3mNoteToMidi(c.note),
            noteOff: c.note == S3mCell.noteOff,
            instrument: c.instrument,
            volume: c.volume == S3mCell.noVolume ? -1 : c.volume,
            effect: fxCmd,
            effectParam: fxParam,
            nativeEffect: c.command == 0 && c.info == 0 ? -1 : c.command,
            nativeEffectParam: c.info,
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
    globalVolume: m.globalVolume * 2,
    s3mMasterVolume: m.masterVolume,
    s3mUltraClick: m.ultraClick,
    s3mDefaultPan: m.defaultPan,
    s3mChannelSettings: List<int>.from(m.channelSettings),
    s3mSampleFormat: m.sampleFormat,
    s3mFlags: m.flags,
    s3mCreatedWith: m.createdWith,
    s3mDefaultPans: List<int>.from(m.defaultPans),
    s3mRawOrder: List<int>.from(m.rawOrder),
    s3mPatterns: List<S3mPattern>.from(m.patterns),
    s3mSamples: List<S3mSample>.from(m.samples),
    sourceFormat: ModuleFormat.s3m,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

// Envelopes map 1:1 between the XM-native and neutral shapes (same fields).
DocEnvelope _docEnvFromXm(XmEnvelope e) => DocEnvelope(
      points: e.points,
      sustain: e.sustain,
      loopStart: e.loopStart,
      loopEnd: e.loopEnd,
      enabled: e.enabled,
    );

DocEnvelope _docEnvFromIt(ItEnvelope e) => DocEnvelope(
      points: List<(int, int)>.from(e.points),
      enabled: e.enabled,
      loopStart: e.loopEnabled ? e.loopStart : null,
      loopEnd: e.loopEnabled ? e.loopEnd : null,
      sustain: e.sustainEnabled ? e.sustainStart : null,
    );

XmEnvelope _xmEnvFromDoc(DocEnvelope e) => XmEnvelope(
      points: e.points,
      sustain: e.sustain,
      loopStart: e.loopStart,
      loopEnd: e.loopEnd,
      enabled: e.enabled,
    );

/// Converts one neutral sample to the XM sample representation. Kept public so
/// the song-to-module bridge can build native multi-sample instruments without
/// duplicating the tuning and PCM conversion rules.
XmSample xmSampleFromDoc(DocSample ds) {
  final (rel, ft) = _c5speedToXmTuning(ds.c5speed);
  return XmSample(
    name: ds.name,
    volume: ds.volume.clamp(0, 64),
    finetune: ft,
    relativeNote: rel,
    pan: ds.pan,
    loopStart: ds.loopStart,
    loopLength: ds.loopLength,
    pingPong: ds.pingPong,
    sixteenBit: ds.sixteenBit,
    pcm: Float64List.fromList(ds.pcm),
  );
}

ModuleDoc docFromXm(XmModule m) {
  final samples = <DocSample>[];
  final sampleOffsets = <int>[];
  for (final inst in m.instruments) {
    sampleOffsets.add(samples.length);
    for (final s in inst.samples) {
      if (s.isEmpty) {
        samples.add(DocSample.empty());
        continue;
      }
      final ds = DocSample(
        name: s.name,
        volume: s.volume,
        loopStart: s.loopStart,
        loopLength: s.loopLength,
        c5speed: xmTuningToC5speed(s.relativeNote, s.finetune),
        pan: s.pan,
        pingPong: s.loopLength > 0 && s.pingPong,
        sixteenBit: s.sixteenBit,
        volumeEnvelope: _docEnvFromXm(inst.volumeEnvelope),
        panEnvelope: _docEnvFromXm(inst.panEnvelope),
        pcm: Float64List.fromList(s.pcm),
      );
      samples.add(ds);
    }
  }

  final patterns = <DocPattern>[];
  for (final pat in m.patterns) {
    final ch = pat.channelCount;
    final lastInstrument = <int, int>{};
    final rows = <List<DocCell>>[];
    for (final row in pat.rows) {
      final cells = <DocCell>[];
      for (var channel = 0; channel < row.length; channel++) {
        final c = row[channel];
        // XM's Txy tremor uses effect byte 14h, while the neutral replayer
        // reserves 1Dh for tremor so it cannot collide with MOD effects. Keep
        // the original byte in nativeEffect for same-format export.
        var effect = c.effect == 0x14 ? 0x1D : c.effect;
        var effectParam = c.effectParam;
        final hasVolpan =
            c.presentMask < 0 ? c.volume != 0 : (c.presentMask & 0x04) != 0;
        final vol =
            (c.volume >= 0x10 && c.volume <= 0x50) ? c.volume - 0x10 : -1;
        if (effect == 0 && hasVolpan) {
          final mini = _xmVolumeColumnToFx(c.volume);
          if (mini != null) {
            effect = mini.$1;
            effectParam = mini.$2;
          }
        }
        if (c.instrument > 0) lastInstrument[channel] = c.instrument;
        final effectiveInstrument =
            c.instrument > 0 ? c.instrument : (lastInstrument[channel] ?? 0);
        var instrument = effectiveInstrument;
        if (effectiveInstrument > 0 &&
            effectiveInstrument <= m.instruments.length) {
          final inst = m.instruments[effectiveInstrument - 1];
          final key = c.note >= 1 && c.note <= 96 ? c.note - 1 : 0;
          final sample = inst.keymap.length > key ? inst.keymap[key] : 0;
          if (sample >= 0 && sample < inst.samples.length) {
            instrument = sampleOffsets[effectiveInstrument - 1] + sample + 1;
          }
        }
        cells.add(
          DocCell(
            note: xmNoteToMidi(c.note),
            noteOff: c.note == XmCell.noteOff,
            instrument: instrument,
            volume: vol,
            // Keep the full XM command byte in the neutral model. Cross-format
            // writers may still degrade commands without an equivalent, but a
            // same-format XM round-trip must not erase G+ effects.
            effect: effect,
            effectParam: effectParam,
            nativeEffect: c.effect == 0 && c.effectParam == 0 ? -1 : c.effect,
            nativeEffectParam: c.effectParam,
            nativeInstrument: effectiveInstrument,
            nativeInstrumentSet: effectiveInstrument != 0,
            nativeNote: xmNoteToMidi(c.note),
            nativeVolpan: hasVolpan ? c.volume : -1,
          ),
        );
      }
      rows.add(cells);
    }
    patterns.add(DocPattern(rows, ch));
  }

  return ModuleDoc(
    title: m.name,
    xmTrackerName: m.trackerName,
    xmVersion: m.version,
    xmRestart: m.restart,
    xmRawHeader: List<int>.from(m.rawHeader),
    channelCount: m.channelCount,
    initialSpeed: m.defaultTempo,
    initialTempo: m.defaultBpm,
    linearFrequency: m.linearFrequency,
    xmInstruments: List<XmInstrument>.from(m.instruments),
    xmPatterns: List<XmPattern>.from(m.patterns),
    sourceFormat: ModuleFormat.xm,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

/// Maps an IT letter-command (A=1..Z=26) + value → our MOD-numbered `(fxCmd,
/// fxParam)`. IT is Scream Tracker 3's successor, so the letters match S3M — the
/// differences are `X` (pan is 0x00..0xFF, not ..0x80) and `T` (T0x/T1x are tempo
/// SLIDES, only T20+ sets tempo). Shares [_s3mSpecialToFx] for `Sxy`. Verified
/// against libopenmpt — see docs/ORACLE.md. No-equivalents return `(0, 0)`.
(int, int) _itEffectToFx(
  int cmd,
  int value,
  ItMidiMacros? macros, [
  int activeMacro = 0,
]) {
  switch (cmd) {
    case 1: // A — set speed (ticks/row), full 1..255 range
      // See the note in _s3mEffectToFx: Axx is always a speed in IT, so it maps
      // to kFxSetSpeedFull rather than being squeezed into MOD's Fxx.
      return value == 0 ? (0, 0) : (kFxSetSpeedFull, value.clamp(1, 255));
    case 2: // B — position jump
      return (0xB, value);
    case 3: // C — pattern break
      return (0xD, value);
    case 4: // D — volume slide
      return (0xA, value);
    case 5: // E — portamento down
      return (0x2, value);
    case 6: // F — portamento up
      return (0x1, value);
    case 7: // G — tone portamento
      return (0x3, value);
    case 8: // H — vibrato
      return (0x4, value);
    case 13: // M — set channel volume
      return (0xC, value.clamp(0, 64));
    case 14: // N — channel volume slide
      return (0xA, value);
    case 16: // P — pan slide
      return (kFxPanSlide, value);
    case 17: // Q — retrigger + volume action
      return (kFxRetrigVolSlide, value);
    case 10: // J — arpeggio
      return (0x0, value);
    case 11: // K — vibrato + volume slide
      return (0x6, value);
    case 12: // L — tone porta + volume slide
      return (0x5, value);
    case 15: // O — sample offset
      return (0x9, value);
    case 18: // R — tremolo
      return (0x7, value);
    case 19: // S — special/extended (same sub-commands as S3M)
      return _s3mSpecialToFx(value);
    case 20: // T — set tempo (T20+); T0x/T1x are tempo slides
      return value >= 0x20 ? (0xF, value) : (0x1F, value);
    case 9: // I — tremor
      return (kFxTremor, value);
    case 21: // U — fine vibrato (approximated as vibrato)
      return (0x4, value);
    case 22: // V — set global volume
      return (kFxSetGlobalVolume, value.clamp(0, 64));
    case 23: // W — global volume slide
      return (kFxGlobalVolSlide, value);
    case 24: // X — set panning (0x00..0xFF, direct → our 8xx)
      return (0x8, value);
    case 25: // Y — panbrello
      return (kFxPanbrello, value);
    case 26: // Z — MIDI-macro / set filter cutoff (Z00..Z7F) / resonance (Z80..ZFF)
      // No embedded MidiCfg ⇒ the implicit IT default macro set: map directly to
      // the replayer's kFxSetFilter (0x1C), whose param carries the cutoff/
      // resonance selector in its high bit (decoded in ReplayVoice). This is the
      // pre-macro behavior, kept byte-identical for every file without a MidiCfg.
      if (macros == null) return (kFxSetFilter, value);
      // With a MidiCfg, resolve Zxx THROUGH the module's macro table, running the
      // channel's active parametric macro ([activeMacro], set by SFx) for the
      // 0x00..0x7F range. A recognized filter macro (F0F000 cutoff / F0F001
      // resonance) routes to kFxSetFilter; a non-filter macro (MIDI to external
      // gear) has no audible target → dropped.
      final filterParam = macros.resolveZxxFilterParam(value, activeMacro);
      return filterParam == null ? (0, 0) : (kFxSetFilter, filterParam);
    default:
      // Z MIDI-macro (\x87…) — no neutral equivalent (dropped).
      return (0, 0);
  }
}

ModuleDoc docFromIt(ItModule m) {
  final samples = <DocSample>[];
  for (final s in m.samples) {
    if (s.isEmpty) {
      samples.add(DocSample.empty());
    } else {
      final looped = s.loop && s.loopEnd > s.loopStart;
      final sampleIndex = samples.length;
      // The neutral cell model resolves IT instrument keymaps to sample
      // numbers. Carry the first instrument envelope that references this
      // sample along with it so the renderer does not lose envelope shaping.
      // Files with the same sample shared by differently enveloped instruments
      // still need a native instrument-zone model; this fixes the common case
      // without changing the existing sample-number semantics.
      ItInstrument? owner;
      for (final instrument in m.instruments) {
        if (instrument.keymap.contains(sampleIndex + 1)) {
          owner = instrument;
          break;
        }
      }
      final ds = DocSample(
        name: s.name,
        globalVolume: s.globalVolume,
        volume: s.defaultVolume,
        loopStart: s.loopStart,
        loopLength: looped ? (s.loopEnd - s.loopStart) : 0,
        sustainLoopStart: s.sustainStart,
        sustainLoopLength: s.sustain && s.sustainEnd > s.sustainStart
            ? s.sustainEnd - s.sustainStart
            : 0,
        sustainPingPong: s.sustain && s.sustainPingPong,
        c5speed: s.c5speed,
        pan: s.pan,
        pingPong: looped && s.pingPong,
        sixteenBit: s.sixteenBit,
        filterCutoff: owner?.initialFilterCutoff ?? -1,
        filterResonance: owner?.initialFilterResonance ?? 0,
        pcm: Float64List.fromList(s.pcm),
        pcmRight: s.pcmRight == null ? null : Float64List.fromList(s.pcmRight!),
        volumeEnvelope: owner == null
            ? const DocEnvelope()
            : _docEnvFromIt(owner.volumeEnvelope),
        panEnvelope: owner == null
            ? const DocEnvelope()
            : _docEnvFromIt(owner.panEnvelope),
      );
      samples.add(ds);
    }
  }

  // In INSTRUMENT mode a cell's `instrument` selects an instrument whose keymap
  // resolves the PLAYED note → the actual sample (and the note to sound). A note
  // without its own instrument reuses the channel's last one. Sample-mode files
  // keep `instrument` as the sample number directly.
  // Per-channel active parametric MIDI macro (0..15), set by the `SFx` effect
  // (IT `S` command value 0xF0..0xFF → SF0..SFF). Default 0 (SF0). This is
  // runtime playback state; the Doc model is static per pattern, so we carry it
  // across patterns in storage order — the order-list play sequence is not
  // simulated. The common case (SFx then Zxx in the same pattern/channel) is
  // exact, and with no SFx anywhere every channel stays 0, byte-identical to the
  // pre-active-macro behavior.
  final activeMacro = <int, int>{};
  final patterns = <DocPattern>[];
  for (final pat in m.patterns) {
    final ch = pat.channelCount;
    final lastIns = <int, int>{}; // channel → last instrument number
    final rows = <List<DocCell>>[];
    for (final row in pat.rows) {
      final cells = <DocCell>[];
      for (var ci = 0; ci < row.length; ci++) {
        final c = row[ci];
        if (c.instrument > 0) lastIns[ci] = c.instrument;
        final hasPitch = c.note >= 0 && c.note <= 119;

        var docNote = itNoteToMidi(c.note);
        var docInstrument = c.instrument;
        if (m.usesInstruments) {
          if (hasPitch) {
            final eff = c.instrument > 0 ? c.instrument : (lastIns[ci] ?? 0);
            if (eff >= 1 && eff <= m.instruments.length) {
              final inst = m.instruments[eff - 1];
              docInstrument = inst.keymap[c.note]; // 1-based sample (0 = none)
              docNote = itNoteToMidi(inst.noteMap[c.note]); // keymap transpose
            } else {
              docInstrument = 0;
            }
          } else {
            docInstrument =
                0; // instrument-only / effect cell triggers no sample
          }
        }

        final vol = (c.volpan >= 0 && c.volpan <= 64) ? c.volpan : -1;
        // SFx (S command, value 0xF0..0xFF) selects this channel's active
        // parametric macro; apply it before resolving this row's effect so a
        // Zxx later in the channel resolves through the selected SFx macro.
        if (c.command == 19 && c.commandValue >= 0xF0) {
          activeMacro[ci] = c.commandValue & 0x0F;
        }
        final (fxCmd, fxParam) = _itEffectToFx(
          c.command,
          c.commandValue,
          m.midiMacros,
          activeMacro[ci] ?? 0,
        );
        cells.add(
          DocCell(
            note: docNote,
            noteOff: c.note == 255 || c.note == ItCell.noteCut,
            instrument: docInstrument,
            volume: vol,
            effect: fxCmd,
            effectParam: fxParam,
            nativeEffect:
                c.command == 0 && c.commandValue == 0 ? -1 : c.command,
            nativeEffectParam: c.commandValue,
            nativeInstrument: c.instrument,
            nativeInstrumentSet: true,
            nativeNote: itNoteToMidi(c.note),
            nativeVolpan: c.volpan,
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
    globalVolume: m.globalVolume,
    itCreatedWith: m.createdWith,
    itCompatibleWith: m.compatibleWith,
    itSpecial: m.special,
    itRowHighlight: m.rowHighlight,
    itFlags: m.flags,
    itMixVolume: m.mixVolume,
    itPanSeparation: m.panSeparation,
    itPitchWheelDepth: m.pitchWheelDepth,
    channelPans: List<int>.from(m.channelPans),
    channelVolumes: List<int>.from(m.channelVolumes),
    itInstrumentHeaders: [
      for (final instrument in m.instruments)
        List<int>.from(instrument.rawHeader),
    ],
    itInstruments: [
      for (final instrument in m.instruments)
        DocInstrument(
          name: instrument.name,
          nna: instrument.nna,
          dct: instrument.dct,
          dca: instrument.dca,
          fadeout: instrument.fadeout,
          pps: instrument.pps,
          ppc: instrument.ppc,
          globalVolume: instrument.globalVolume,
          defaultPan: instrument.defaultPan,
          randomVolume: instrument.randomVolume,
          randomPan: instrument.randomPan,
          filterCutoff: instrument.initialFilterCutoff,
          filterResonance: instrument.initialFilterResonance,
          filterEnvelope: instrument.filterEnvelope,
          keymap: List<int>.from(instrument.keymap),
          noteMap: List<int>.from(instrument.noteMap),
          volumeEnvelope: _docEnvFromIt(instrument.volumeEnvelope),
          panEnvelope: _docEnvFromIt(instrument.panEnvelope),
          pitchEnvelope: _docEnvFromIt(instrument.pitchEnvelope),
          rawHeader: List<int>.from(instrument.rawHeader),
        ),
    ],
    itSamples: List<ItSample>.from(m.samples),
    sourceFormat: ModuleFormat.it,
    order: List<int>.from(m.order),
    patterns: patterns,
    samples: samples,
  );
}

/// The MOD `(effect, param)` for a doc cell: a real MOD-numbered effect
/// (0x0–0xF) if present, else a Cxx synthesised from the volume column, else a
/// C00 for a note-off, else none. Effects > 0xF (our internal extended set) and
/// the arp/none ambiguity are handled: effect 0 with a non-zero param is a real
/// `0xy` arpeggio, effect 0 with param 0 is "no command".
(int, int) _modEffectFor(DocCell c) {
  final hasEffect = (c.effect != 0 || c.effectParam != 0) && c.effect <= 0xF;
  if (hasEffect) return (c.effect, c.effectParam & 0xFF);
  if (c.volume >= 0) return (0xC, c.volume.clamp(0, 64));
  if (c.noteOff) return (0xC, 0);
  return (0, 0);
}

/// Doc MOD-numbered `(fxCmd, fxParam)` → an S3M/IT letter-command number
/// (A=1, B=2, …) and its info/value byte — the inverse of [_s3mEffectToFx] /
/// [_itEffectToFx]. [directPan] true for IT (its X pan is 0x00–0xFF direct),
/// false for S3M (X pan is 0x00–0x80, so halve). `0xC` set-volume routes to the
/// volume column instead (see the writers). Supported extended commands are
/// emitted as their S3M/IT special equivalents; unknown commands return
/// `(0, 0)` (no command).
(int, int) _fxToLetterEffect(int cmd, int param, {required bool directPan}) {
  switch (cmd) {
    case 0x0:
      return param == 0 ? (0, 0) : (10, param); // J arpeggio (0 = none)
    case 0x1:
      return (6, param); // F porta up
    case 0x2:
      return (5, param); // E porta down
    case 0x3:
      return (7, param); // G tone porta
    case 0x4:
      return (8, param); // H vibrato
    case 0x5:
      return (12, param); // L tone porta + vol slide
    case 0x6:
      return (11, param); // K vibrato + vol slide
    case 0x7:
      return (18, param); // R tremolo
    case 0x8:
      // X pan: IT is 0x00–0xFF direct; S3M is 0x00–0x80, so halve. ROUND (not
      // truncate) so full-right 0xFF → 0x80 and the reader's ×2 recovers 0xFF
      // exactly, instead of 0x7F → 0xFE.
      return (24, directPan ? param : (param / 2).round().clamp(0, 0x80));
    case 0x9:
      return (15, param); // O sample offset
    case kFxSetPanbrelloWaveform: // 0x15
      return (19, (0x5 << 4) | (param & 0xF)); // S5x set panbrello waveform
    case 0x13:
      return (19, (0xA << 4) | (param & 0xF)); // SAx high sample offset
    // Named, not a raw literal: a bare `case 0x14:` is how this switch kept
    // silently shadowing whichever command had been given that number most
    // recently.
    case kFxSetSoundControl:
      return (
        19,
        (0x9 << 4) | (param & 0xF)
      ); // S9x sound control (surround/rev)
    case kFxSetPastNote: // 0x16
      return (19, (0x7 << 4) | (param & 0xF)); // S7x past-note / NNA control
    case kFxSetGlobalVolume:
      return (22, param.clamp(0, 64)); // V global volume
    case kFxGlobalVolSlide:
      return (23, param); // W global volume slide
    case 0xA:
      return (4, param); // D volume slide
    case 0xB:
      return (2, param); // B position jump
    case 0xD:
      return (3, param); // C pattern break
    case 0xE:
      // Exy extended → S3M/IT `Sxy` (command 19). The sub-commands our readers
      // round-trip survive; other Exy have no S3M/IT equivalent and are dropped
      // (MOD/XM still carry them 1:1).
      final val = param & 0xF;
      return switch ((param >> 4) & 0xF) {
        0x3 => (19, (0x1 << 4) | val), // E3x glissando      → S1x
        0x4 => (19, (0x3 << 4) | val), // E4x vibrato wave   → S3x
        0x5 => (19, (0x2 << 4) | val), // E5x set finetune   → S2x
        0x6 => (19, (0xB << 4) | val), // E6x pattern loop   → SBx
        0x7 => (19, (0x4 << 4) | val), // E7x tremolo wave   → S4x
        0xC => (19, (0xC << 4) | val), // ECx note cut       → SCx
        0xD => (19, (0xD << 4) | val), // EDx note delay     → SDx
        0xE => (19, (0xE << 4) | val), // EEx row delay      → SEx
        _ => (0, 0),
      };
    case kFxPanSlide:
      return (16, param); // P pan slide
    case kFxRetrigVolSlide:
      return (17, param); // Q retrigger + volume action
    case kFxTremor:
      return (9, param); // I tremor
    case kFxPanbrello:
      return (25, param); // Y panbrello
    case 0x1F:
      return (20, param); // T tempo slide
    // Reachable again: S9x sound control moved to 0x16, so 0x14 is this
    // command alone. Dropping the case silenced the analyzer but also silently
    // dropped every IT/S3M full-range speed on export, which is the thing the
    // command exists for.
    case kFxSetSpeedFull: // A — set speed, full 1..255
      return (1, param.clamp(1, 255));
    case 0xF:
      return param < 0x20 ? (1, param) : (20, param); // A speed / T tempo
    default:
      return (0, 0);
  }
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
          // The doc effect is MOD-numbered (0x0–0xF), so it carries 1:1. MOD has
          // one effect slot: a real effect wins; otherwise synthesise a Cxx from
          // the volume column, or C00 from a note-off (MOD has neither — Cxx sets
          // the volume, C00 silences the note as a rest). Effects > 0xF are our
          // internal extended commands, which MOD can't represent → dropped.
          final (eff, param) =
              doc.sourceFormat == ModuleFormat.mod && c.nativeEffect >= 0
                  ? (c.nativeEffect, c.nativeEffectParam)
                  : _modEffectFor(c);
          cells.add(
            ModCell(
              sample: c.instrument.clamp(0, 31),
              period: c.note < 0 ? 0 : midiToPeriod(c.note),
              effect: eff,
              effectParam: param,
            ),
          );
        } else {
          cells.add(ModCell.empty);
        }
      }
      rows.add(cells);
    }
    // A source pattern shorter than MOD's fixed 64 rows would otherwise play
    // through all 64 — padding a short loop with 48 silent rows. Emit a Dxx
    // pattern break on the last real row (in a free effect slot) so playback
    // advances at the intended length and the loop stays its authored size.
    final srcRows = dp.rows.length;
    if (srcRows > 0 && srcRows < 64) {
      final breakRow = rows[srcRows - 1];
      for (var ch = 0; ch < 4; ch++) {
        final o = breakRow[ch];
        // Use only a fully-empty cell so the break never overwrites a note or
        // an authored effect (there are 4 channels; a short loop's last row
        // almost always has a free one).
        if (o.period == 0 && o.effect == 0 && o.effectParam == 0) {
          breakRow[ch] = ModCell(
            sample: o.sample,
            effect: 0xD, // Dxx pattern break
          );
          break;
        }
      }
    }
    patterns.add(ModPattern(rows));
  }

  return ModModule(
    title: doc.title,
    restart: 0,
    samples: samples,
    // IT/XM order lists may carry 0xFF as an explicit end marker. MOD has no
    // end-marker value; copying it would make a reader allocate pattern 255.
    order: doc.order
        .where((pattern) => pattern >= 0 && pattern < doc.patterns.length)
        .take(128)
        .toList(),
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
/// Sample bit depth is honoured: a neutral [DocSample.sixteenBit] sample is
/// emitted as a 16-bit XM sample (via [xmSampleFromDoc]), otherwise 8-bit.
/// Notes, instruments, the volume column, samples, loops and structure convert.
XmModule docToXm(ModuleDoc doc) {
  if (doc.sourceFormat == ModuleFormat.xm &&
      doc.xmInstruments.isNotEmpty &&
      doc.xmPatterns.isNotEmpty) {
    return XmModule(
      name: doc.title,
      trackerName: doc.xmTrackerName,
      version: doc.xmVersion,
      restart: doc.xmRestart,
      rawHeader: List<int>.from(doc.xmRawHeader),
      channelCount: doc.channelCount,
      defaultTempo: doc.initialSpeed,
      defaultBpm: doc.initialTempo,
      linearFrequency: doc.linearFrequency,
      order: List<int>.from(doc.order),
      patterns: List<XmPattern>.from(doc.xmPatterns),
      instruments: List<XmInstrument>.from(doc.xmInstruments),
    );
  }
  if (doc.sourceFormat == ModuleFormat.xm && doc.xmInstruments.isNotEmpty) {
    return XmModule(
      name: doc.title,
      trackerName: doc.xmTrackerName,
      version: doc.xmVersion,
      restart: doc.xmRestart,
      rawHeader: List<int>.from(doc.xmRawHeader),
      channelCount: doc.channelCount,
      defaultTempo: doc.initialSpeed,
      defaultBpm: doc.initialTempo,
      linearFrequency: doc.linearFrequency,
      order: List<int>.from(doc.order),
      patterns: _docPatternsToXm(doc, preserveNativeInstruments: true),
      instruments: List<XmInstrument>.from(doc.xmInstruments),
    );
  }
  final instruments = <XmInstrument>[];
  for (final ds in doc.samples) {
    if (ds.isEmpty) {
      instruments.add(const XmInstrument(samples: []));
      continue;
    }
    instruments.add(
      XmInstrument(
        name: ds.name,
        volumeEnvelope: _xmEnvFromDoc(ds.volumeEnvelope),
        panEnvelope: _xmEnvFromDoc(ds.panEnvelope),
        samples: [xmSampleFromDoc(ds)],
      ),
    );
  }

  final patterns = _docPatternsToXm(doc);
  return XmModule(
    name: doc.title,
    trackerName: doc.xmTrackerName,
    version: doc.xmVersion,
    restart: doc.xmRestart,
    rawHeader: List<int>.from(doc.xmRawHeader),
    channelCount: doc.channelCount,
    defaultTempo: doc.initialSpeed,
    defaultBpm: doc.initialTempo,
    linearFrequency: doc.linearFrequency,
    order: List<int>.from(doc.order),
    patterns: patterns,
    instruments: instruments,
  );
}

List<XmPattern> _docPatternsToXm(
  ModuleDoc doc, {
  bool preserveNativeInstruments = false,
}) {
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
              note: preserveNativeInstruments && c.nativeNote >= 0
                  ? c.nativeNote
                  : (c.noteOff
                      ? XmCell.noteOff
                      : (c.note < 0 ? 0 : (c.note - 11).clamp(1, 96))),
              instrument: (preserveNativeInstruments && c.nativeInstrumentSet
                      ? c.nativeInstrument
                      : c.instrument)
                  .clamp(0, 255),
              volume: doc.sourceFormat == ModuleFormat.xm && c.nativeVolpan >= 0
                  ? c.nativeVolpan & 0xFF
                  : c.volume < 0
                      ? 0
                      : (0x10 + c.volume).clamp(0x10, 0x50),
              effect: doc.sourceFormat == ModuleFormat.xm && c.nativeEffect >= 0
                  ? c.nativeEffect & 0xFF
                  : (c.effect == 0x1D ? 0x14 : c.effect) & 0xFF,
              effectParam:
                  doc.sourceFormat == ModuleFormat.xm && c.nativeEffect >= 0
                      ? c.nativeEffectParam & 0xFF
                      : c.effectParam & 0xFF,
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
  return patterns;
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
/// A doc cell → an [S3mCell]: note/instrument, the volume column (a MOD `Cxx`
/// set-volume effect routes here, since S3M keeps volume in the column), and the
/// translated effect command/info.
S3mCell _s3mCellFrom(DocCell c, {required bool preserveNative}) {
  final vol = c.volume >= 0
      ? c.volume.clamp(0, 64)
      : (c.effect == 0xC ? c.effectParam.clamp(0, 64) : S3mCell.noVolume);
  final (command, info) = preserveNative && c.nativeEffect >= 0
      ? (c.nativeEffect, c.nativeEffectParam)
      : _fxToLetterEffect(c.effect, c.effectParam & 0xFF, directPan: false);
  return S3mCell(
    note: c.noteOff ? S3mCell.noteOff : _midiToS3mNote(c.note),
    instrument: c.instrument.clamp(0, 255),
    volume: vol,
    command: command,
    info: info,
  );
}

S3mModule docToS3m(ModuleDoc doc) {
  final samples = <S3mSample>[];
  if (doc.sourceFormat == ModuleFormat.s3m && doc.s3mSamples.isNotEmpty) {
    samples.addAll(doc.s3mSamples);
  }
  for (final ds in doc.samples) {
    if (doc.sourceFormat == ModuleFormat.s3m && doc.s3mSamples.isNotEmpty) {
      break;
    }
    if (ds.isEmpty) {
      samples.add(S3mSample.empty());
      continue;
    }
    samples.add(
      S3mSample(
        name: ds.name,
        volume: ds.volume.clamp(0, 64),
        c2spd: ds.c5speed,
        loop: ds.loopLength > 0,
        loopStart: ds.loopStart,
        loopEnd: ds.loopStart + ds.loopLength,
        sixteenBit: ds.sixteenBit,
        // The writer quantizes to 8- or 16-bit per sixteenBit.
        pcm: Float64List.fromList(ds.pcm),
      ),
    );
  }

  final patterns = <S3mPattern>[];
  if (doc.sourceFormat == ModuleFormat.s3m && doc.s3mPatterns.isNotEmpty) {
    patterns.addAll(doc.s3mPatterns);
  }
  for (final dp in doc.patterns) {
    if (doc.sourceFormat == ModuleFormat.s3m && doc.s3mPatterns.isNotEmpty) {
      break;
    }
    final rows = <List<S3mCell>>[];
    for (final srcRow in dp.rows) {
      final cells = <S3mCell>[];
      for (var ch = 0; ch < doc.channelCount; ch++) {
        if (ch < srcRow.length) {
          final c = srcRow[ch];
          cells.add(
            _s3mCellFrom(
              c,
              preserveNative: doc.sourceFormat == ModuleFormat.s3m,
            ),
          );
        } else {
          cells.add(S3mCell.empty);
        }
      }
      rows.add(cells);
    }
    // writeS3m pads a short pattern to S3M's fixed 64 rows; without a break a
    // short loop would then play 64 rows. Emit a `C` pattern break (command 3)
    // on the last real row (a free command slot) so it advances at its authored
    // length, matching the MOD path.
    if (rows.isNotEmpty && rows.length < 64) {
      final breakRow = rows.last;
      for (var ch = 0; ch < breakRow.length; ch++) {
        final o = breakRow[ch];
        // Only a fully-empty cell, so the break never clobbers a note/effect.
        if (o.note == S3mCell.emptyNote && o.command == 0 && o.info == 0) {
          breakRow[ch] = const S3mCell(command: 3); // C — pattern break
          break;
        }
      }
    }
    patterns.add(S3mPattern(rows));
  }

  return S3mModule(
    title: doc.title,
    channelCount: doc.channelCount,
    initialSpeed: doc.initialSpeed,
    initialTempo: doc.initialTempo,
    globalVolume: (doc.globalVolume / 2).round().clamp(0, 64),
    masterVolume: doc.s3mMasterVolume,
    ultraClick: doc.s3mUltraClick,
    defaultPan: doc.s3mDefaultPan,
    channelSettings: List<int>.from(doc.s3mChannelSettings),
    sampleFormat: doc.s3mSampleFormat,
    flags: doc.s3mFlags,
    createdWith: doc.s3mCreatedWith,
    defaultPans: List<int>.from(doc.s3mDefaultPans),
    rawOrder: List<int>.from(doc.s3mRawOrder),
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
/// A doc cell → an [ItCell]: note/instrument, the volume-column (a MOD `Cxx` set-
/// volume routes here), and the translated effect command/value (IT X pan is
/// direct 0x00–0xFF).
ItCell _itCellFrom(DocCell c, {required bool preserveNative}) {
  // Imported IT M/V commands normalize to the neutral C/G command space for
  // playback, but their original command must remain the only volume control.
  // Do not synthesize an IT volume-column value when the native source had no
  // vol/pan byte; doing so doubles the command on native export.
  final vol = preserveNative && c.nativeEffect >= 0 && c.nativeVolpan < 0
      ? -1
      : c.volume >= 0
          ? c.volume.clamp(0, 64)
          : (c.effect == 0xC ? c.effectParam.clamp(0, 64) : -1);
  final (command, value) = preserveNative && c.nativeEffect >= 0
      ? (c.nativeEffect, c.nativeEffectParam)
      : _fxToLetterEffect(c.effect, c.effectParam & 0xFF, directPan: true);
  return ItCell(
    // IT note 255 = note-off (writeIt emits it since it != -1).
    note: preserveNative && c.nativeNote >= 0
        ? c.nativeNote
        : (c.noteOff ? 255 : (c.note < 0 ? -1 : c.note.clamp(0, 119))),
    instrument: preserveNative && c.nativeInstrumentSet
        ? c.nativeInstrument
        : c.instrument.clamp(0, 255),
    volpan: preserveNative && c.nativeVolpan >= 0 ? c.nativeVolpan : vol,
    command: command,
    commandValue: value,
  );
}

void _writeItEnvelope(
  List<int> raw,
  int offset,
  DocEnvelope envelope, {
  required bool signedValue,
}) {
  var flags = envelope.enabled ? 1 : 0;
  if (envelope.loopStart != null && envelope.loopEnd != null) flags |= 2;
  if (envelope.sustain != null) flags |= 4;
  raw[offset] = flags;
  raw[offset + 1] = envelope.points.length.clamp(0, 25);
  raw[offset + 2] = (envelope.loopStart ?? 0).clamp(0, 24);
  raw[offset + 3] = (envelope.loopEnd ?? 0).clamp(0, 24);
  raw[offset + 4] = (envelope.sustain ?? 0).clamp(0, 24);
  raw[offset + 5] = (envelope.sustain ?? 0).clamp(0, 24);
  for (var i = 0; i < envelope.points.length && i < 25; i++) {
    final p = offset + 6 + i * 3;
    final (tick, pointValue) = envelope.points[i];
    final value =
        signedValue ? pointValue.clamp(-32, 32) : pointValue.clamp(0, 64);
    raw[p] = value & 0xFF;
    raw[p + 1] = tick.clamp(0, 9999) & 0xFF;
    raw[p + 2] = (tick.clamp(0, 9999) >> 8) & 0xFF;
  }
}

ItInstrument _itInstrumentFromDoc(DocInstrument d, List<int> rawHeader) {
  final raw = rawHeader.length >= 554
      ? List<int>.from(rawHeader.take(554))
      : List<int>.filled(554, 0);
  if (rawHeader.length < 554) {
    raw.setAll(0, const [0x49, 0x4D, 0x50, 0x49]);
    void u16(int offset, int value) {
      raw[offset] = value & 0xFF;
      raw[offset + 1] = (value >> 8) & 0xFF;
    }

    raw[0x11] = d.nna.clamp(0, 255);
    raw[0x12] = d.dct.clamp(0, 255);
    raw[0x13] = d.dca.clamp(0, 255);
    u16(0x14, d.fadeout.clamp(0, 65535));
    raw[0x16] = d.pps & 0xFF;
    raw[0x17] = d.ppc & 0xFF;
    raw[0x18] = d.globalVolume.clamp(0, 255);
    raw[0x19] = d.defaultPan.clamp(0, 255);
    raw[0x1A] = d.randomVolume.clamp(0, 255);
    raw[0x1B] = d.randomPan.clamp(0, 255);
    final name = d.name.codeUnits;
    for (var i = 0; i < 26 && i < name.length; i++) {
      raw[0x1C + i] = name[i] & 0xFF;
    }
  }
  final keymap = d.keymap.isEmpty ? List<int>.filled(120, 0) : d.keymap;
  final noteMap =
      d.noteMap.isEmpty ? [for (var i = 0; i < 120; i++) i] : d.noteMap;
  if (rawHeader.length < 554) {
    raw[0x11] = d.nna.clamp(0, 255);
    raw[0x12] = d.dct.clamp(0, 255);
    raw[0x13] = d.dca.clamp(0, 255);
    raw[0x14] = d.fadeout.clamp(0, 65535) & 0xFF;
    raw[0x15] = (d.fadeout.clamp(0, 65535) >> 8) & 0xFF;
    raw[0x16] = d.pps & 0xFF;
    raw[0x17] = d.ppc & 0xFF;
    raw[0x18] = d.globalVolume.clamp(0, 255);
    raw[0x19] = d.defaultPan.clamp(0, 255);
    raw[0x1A] = d.randomVolume.clamp(0, 255);
    raw[0x1B] = d.randomPan.clamp(0, 255);
    _writeItEnvelope(raw, 0x130, d.volumeEnvelope, signedValue: false);
    _writeItEnvelope(raw, 0x182, d.panEnvelope, signedValue: true);
    _writeItEnvelope(raw, 0x1D4, d.pitchEnvelope, signedValue: true);
    for (var i = 0; i < 120; i++) {
      raw[0x40 + i * 2] = noteMap[i.clamp(0, noteMap.length - 1)] & 0xFF;
      raw[0x41 + i * 2] = keymap[i.clamp(0, keymap.length - 1)] & 0xFF;
    }
  }
  return ItInstrument(
    keymap: List<int>.from(keymap),
    noteMap: List<int>.from(noteMap),
    name: d.name,
    nna: d.nna,
    dct: d.dct,
    dca: d.dca,
    fadeout: d.fadeout,
    pps: d.pps,
    ppc: d.ppc,
    globalVolume: d.globalVolume,
    defaultPan: d.defaultPan,
    randomVolume: d.randomVolume,
    randomPan: d.randomPan,
    rawHeader: raw,
  );
}

ItModule docToIt(ModuleDoc doc) {
  final samples = <ItSample>[];
  if (doc.sourceFormat == ModuleFormat.it && doc.itSamples.isNotEmpty) {
    samples.addAll(doc.itSamples);
  }
  for (final ds
      in doc.itSamples.isNotEmpty && doc.sourceFormat == ModuleFormat.it
          ? const <DocSample>[]
          : doc.samples) {
    if (ds.isEmpty) {
      samples.add(ItSample.empty());
      continue;
    }
    samples.add(
      ItSample(
        name: ds.name,
        globalVolume: ds.globalVolume.clamp(0, 64),
        defaultVolume: ds.volume.clamp(0, 64),
        length: ds.pcm.length,
        loopStart: ds.loopStart,
        loopEnd: ds.loopStart + ds.loopLength,
        loop: ds.loopLength > 0,
        sustainStart: ds.sustainLoopStart,
        sustainEnd: ds.sustainLoopStart + ds.sustainLoopLength,
        sustain: ds.sustainLoopLength > 0,
        sustainPingPong: ds.sustainPingPong,
        c5speed: ds.c5speed,
        pan: ds.pan,
        pingPong: ds.pingPong,
        sixteenBit: ds.sixteenBit,
        pcm: Float64List.fromList(ds.pcm),
        pcmRight:
            ds.pcmRight == null ? null : Float64List.fromList(ds.pcmRight!),
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
            _itCellFrom(
              c,
              preserveNative: doc.sourceFormat == ModuleFormat.it,
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
    globalVolume: doc.globalVolume.clamp(0, 128),
    createdWith: doc.itCreatedWith,
    compatibleWith: doc.itCompatibleWith,
    special: doc.itSpecial,
    rowHighlight: doc.itRowHighlight,
    flags: doc.itFlags,
    mixVolume: doc.itMixVolume,
    panSeparation: doc.itPanSeparation,
    pitchWheelDepth: doc.itPitchWheelDepth,
    channelPans: doc.sourceFormat == ModuleFormat.it
        ? List<int>.from(doc.channelPans)
        : const [],
    channelVolumes: doc.sourceFormat == ModuleFormat.it
        ? List<int>.from(doc.channelVolumes)
        : const [],
    instruments: [
      for (var i = 0; i < doc.itInstruments.length; i++)
        _itInstrumentFromDoc(
          doc.itInstruments[i],
          i < doc.itInstrumentHeaders.length
              ? doc.itInstrumentHeaders[i]
              : const [],
        ),
      if (doc.itInstruments.isEmpty)
        for (final header in doc.itInstrumentHeaders)
          ItInstrument(
            keymap: const [],
            noteMap: const [],
            rawHeader: List<int>.from(header),
          ),
    ],
    order: List<int>.from(doc.order),
    patterns: patterns,
    samples: samples,
  );
}

/// Convenience: convert a neutral module straight to `.it` bytes.
Uint8List convertToIt(ModuleDoc doc) => writeIt(docToIt(doc));

/// Convert a neutral [doc] to any target format — the single dispatch point for
/// the full N×N converter matrix. `bin/modconv.dart` and the in-app "convert"
/// path both funnel through here so a new format is wired in exactly one place.
Uint8List convertDocTo(ModuleDoc doc, ModuleFormat target) => switch (target) {
      ModuleFormat.mod => convertToMod(doc),
      ModuleFormat.xm => convertToXm(doc),
      ModuleFormat.s3m => convertToS3m(doc),
      ModuleFormat.it => convertToIt(doc),
    };

/// Convert raw module [bytes] of ANY recognized format straight to [target]
/// bytes, through the neutral hub — sniff → parse → convert. Throws the same
/// [FormatException] as [parseAnyModule] on an unrecognized input.
Uint8List convertModule(Uint8List bytes, ModuleFormat target) =>
    convertDocTo(parseAnyModule(bytes), target);

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
