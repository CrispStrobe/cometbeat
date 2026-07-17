// bin/notaconv.dart
//
// Headless notation bridge — converts BETWEEN tracker modules and notation files
// (Standard MIDI + MusicXML), both directions, through the ModuleDoc ↔ Score
// bridge (lib/core/audio/mod/module_notation.dart). Pure Dart, runs under plain
// `dart run` like bin/listen.dart. The conversion logic lives in lib and is
// unit-tested (test/module_notation_test.dart); this file is just I/O + routing.
//
//   Module → notation
//     dart run bin/notaconv.dart song.xm out.mid            # busiest channel → MIDI
//     dart run bin/notaconv.dart song.it out.mid --channel 2
//     dart run bin/notaconv.dart song.it out.mid --multi    # every channel → a MIDI track
//     dart run bin/notaconv.dart song.s3m out.xml           # all channels → MusicXML
//
//   Notation → module (the reverse)
//     dart run bin/notaconv.dart tune.mid out.it            # MIDI → a playable .it
//     dart run bin/notaconv.dart score.xml out.xm           # MusicXML → .xm (one channel/part)
//
//   Notation → notation
//     dart run bin/notaconv.dart tune.mid out.xml           # MIDI → MusicXML (and vice-versa)
//
// Rows quantize to a --steps-per-beat grid (default 4 = sixteenths); held runs
// become tied notes; a rest round-trips via a neutral note-off.

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_notation.dart';
// crisp_notation_core is the Flutter-free notation core (a dependency_override,
// re-exported via crisp_notation) — import it directly to stay Flutter-free.
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

const _extToFormat = <String, ModuleFormat>{
  'mod': ModuleFormat.mod,
  'xm': ModuleFormat.xm,
  's3m': ModuleFormat.s3m,
  'it': ModuleFormat.it,
};

const _extToText = <String, TextNotation>{
  'abc': TextNotation.abc,
  'krn': TextNotation.kern,
  'kern': TextNotation.kern,
  'mei': TextNotation.mei,
  'mscx': TextNotation.musescore,
  'ly': TextNotation.lilypond,
  'lily': TextNotation.lilypond,
};

String _ext(String path) => path.split('.').last.toLowerCase();
bool _isMidi(String e) => e == 'mid' || e == 'midi';
bool _isXml(String e) => e == 'xml' || e == 'musicxml';
bool _isMscz(String e) => e == 'mscz'; // MuseScore zipped container (binary)

void main(List<String> args) {
  final positional = <String>[];
  int? channel;
  var stepsPerBeat = 4;
  var multi = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--channel':
        channel = int.tryParse(i + 1 < args.length ? args[++i] : '');
      case '--steps-per-beat':
        stepsPerBeat = int.tryParse(i + 1 < args.length ? args[++i] : '') ?? 4;
      case '--multi':
        multi = true;
      default:
        if (a.startsWith('-')) {
          stderr.writeln('notaconv: unknown option $a');
          exitCode = 2;
          return;
        }
        positional.add(a);
    }
  }
  if (positional.length < 2 || stepsPerBeat < 1) {
    stderr.writeln('usage: dart run bin/notaconv.dart <in> <out> '
        '[--channel N] [--steps-per-beat K] [--multi]\n'
        '  in/out by extension: module (.mod/.xm/.s3m/.it), MIDI (.mid), '
        'MusicXML (.xml)');
    exitCode = 2;
    return;
  }

  final inPath = positional[0], outPath = positional[1];
  final inFile = File(inPath);
  if (!inFile.existsSync()) {
    stderr.writeln('notaconv: no such file: $inPath');
    exitCode = 2;
    return;
  }
  final bytes = inFile.readAsBytesSync();
  final outExt = _ext(outPath);

  try {
    // ── Source: a module, a MIDI file, or a MusicXML file ─────────────────────
    if (sniffModuleFormat(bytes) != null) {
      _fromModule(
        parseAnyModule(bytes),
        outPath,
        outExt,
        channel: channel,
        stepsPerBeat: stepsPerBeat,
        multi: multi,
      );
    } else if (_isMidi(_ext(inPath))) {
      // A multi-track MIDI keeps every track as a part; a single-track one is a
      // plain Score.
      final mp = multiTrackMidiToMultiPart(bytes);
      if (mp.parts.length > 1) {
        _fromMultiPart(mp, outPath, outExt: outExt, stepsPerBeat: stepsPerBeat);
      } else {
        _fromScore(
          mp.parts.isNotEmpty ? mp.parts.first : scoreFromMidi(bytes),
          outPath,
          outExt,
          stepsPerBeat: stepsPerBeat,
        );
      }
    } else if (_isXml(_ext(inPath))) {
      _fromMultiPart(
        multiPartScoreFromMusicXml(String.fromCharCodes(bytes)),
        outPath,
        outExt: outExt,
        stepsPerBeat: stepsPerBeat,
      );
    } else if (_isMscz(_ext(inPath))) {
      _fromScore(
        scoreFromMscz(bytes),
        outPath,
        outExt,
        stepsPerBeat: stepsPerBeat,
      );
    } else if (_extToText[_ext(inPath)] != null) {
      final inFmt = _extToText[_ext(inPath)]!;
      final score = textNotationToScore(String.fromCharCodes(bytes), inFmt);
      if (score == null) {
        stderr.writeln('notaconv: ${inFmt.name} is write-only (no reader)');
        exitCode = 2;
      } else {
        _fromScore(score, outPath, outExt, stepsPerBeat: stepsPerBeat);
      }
    } else {
      stderr.writeln('notaconv: unrecognized input '
          '(not a module, .mid, .xml, .abc/.krn/.mei/.mscx)');
      exitCode = 1;
    }
  } catch (e) {
    stderr.writeln('notaconv: $e');
    exitCode = 1;
  }
}

// ── module → MIDI / MusicXML ──────────────────────────────────────────────────
void _fromModule(
  ModuleDoc doc,
  String outPath,
  String outExt, {
  int? channel,
  required int stepsPerBeat,
  required bool multi,
}) {
  if (doc.channelCount == 0) {
    stderr.writeln('notaconv: the module has no channels');
    exitCode = 1;
    return;
  }
  final tempo = doc.initialTempo.toDouble();
  if (_isMidi(outExt)) {
    if (multi) {
      final mp = moduleToMultiPart(doc, stepsPerBeat: stepsPerBeat);
      final smf = multiPartToMidi(mp.score, quarterBpm: tempo);
      File(outPath).writeAsBytesSync(smf);
      _ok(doc, outPath, '${mp.score.parts.length} tracks, ${smf.length} bytes');
    } else {
      final ch = channel ?? busiestChannel(doc);
      if (ch < 0 || ch >= doc.channelCount) {
        stderr.writeln('notaconv: channel $ch out of range '
            '(0..${doc.channelCount - 1})');
        exitCode = 2;
        return;
      }
      final score = moduleChannelToScore(doc, ch, stepsPerBeat: stepsPerBeat);
      final smf = scoreToMidi(score, quarterBpm: tempo);
      File(outPath).writeAsBytesSync(smf);
      _ok(doc, outPath, 'channel $ch, ${smf.length} bytes');
    }
  } else if (_isXml(outExt)) {
    final xml = moduleToMusicXml(doc, stepsPerBeat: stepsPerBeat);
    File(outPath).writeAsStringSync(xml);
    _ok(doc, outPath, '${xml.length} bytes MusicXML');
  } else if (_extToText[outExt] != null) {
    final fmt = _extToText[outExt]!;
    final txt = moduleToTextNotation(
      doc,
      fmt,
      channel: channel,
      stepsPerBeat: stepsPerBeat,
    );
    File(outPath).writeAsStringSync(txt);
    _ok(
      doc,
      outPath,
      '${_voiceDetail(doc, channel, fmt)}, ${txt.length} bytes ${fmt.name}',
    );
  } else if (_isMscz(outExt)) {
    final data =
        moduleToMscz(doc, channel: channel, stepsPerBeat: stepsPerBeat);
    File(outPath).writeAsBytesSync(data);
    _ok(
      doc,
      outPath,
      '${_voiceDetail(doc, channel, TextNotation.musescore)}, '
      '${data.length} bytes mscz',
    );
  } else {
    stderr.writeln('notaconv: module → .$outExt not supported (use .mid/.xml/'
        '.abc/.krn/.mei/.mscx/.mscz/.ly; module→module = modconv)');
    exitCode = 2;
  }
}

// ── a single Score (from MIDI) → module / MusicXML ───────────────────────────
void _fromScore(
  Score score,
  String outPath,
  String outExt, {
  required int stepsPerBeat,
}) {
  final fmt = _extToFormat[outExt];
  if (fmt != null) {
    final doc =
        scoreToModuleDoc(score, stepsPerBeat: stepsPerBeat, format: fmt);
    File(outPath).writeAsBytesSync(convertDocTo(doc, fmt));
    stdout.writeln('notaconv: notation → .$outExt ($outPath)');
  } else if (_isXml(outExt)) {
    File(outPath).writeAsStringSync(scoreToMusicXml(score));
    stdout.writeln('notaconv: notation → MusicXML ($outPath)');
  } else if (_isMidi(outExt)) {
    File(outPath).writeAsBytesSync(scoreToMidi(score));
    stdout.writeln('notaconv: notation → MIDI ($outPath)');
  } else if (_extToText[outExt] != null) {
    File(outPath)
        .writeAsStringSync(scoreToTextNotation(score, _extToText[outExt]!));
    stdout.writeln('notaconv: notation → .$outExt ($outPath)');
  } else if (_isMscz(outExt)) {
    File(outPath).writeAsBytesSync(scoreToMscz(score));
    stdout.writeln('notaconv: notation → .mscz ($outPath)');
  } else {
    stderr.writeln('notaconv: notation → .$outExt not supported');
    exitCode = 2;
  }
}

// ── a MultiPartScore (from MusicXML) → module / MIDI ─────────────────────────
void _fromMultiPart(
  MultiPartScore mp,
  String outPath, {
  required String outExt,
  required int stepsPerBeat,
}) {
  final parts = mp.parts.length;
  final fmt = _extToFormat[outExt];
  if (fmt != null) {
    final doc =
        multiPartToModuleDoc(mp, stepsPerBeat: stepsPerBeat, format: fmt);
    File(outPath).writeAsBytesSync(convertDocTo(doc, fmt));
    stdout.writeln('notaconv: notation → .$outExt '
        '($parts parts → ${doc.channelCount} ch, $outPath)');
  } else if (_isMidi(outExt)) {
    File(outPath).writeAsBytesSync(multiPartToMidi(mp));
    stdout.writeln('notaconv: notation → MIDI ($parts tracks, $outPath)');
  } else if (_isXml(outExt)) {
    File(outPath).writeAsStringSync(multiPartToMusicXml(mp));
    stdout.writeln('notaconv: notation → MusicXML ($parts parts, $outPath)');
  } else if (_extToText[outExt] == TextNotation.abc) {
    File(outPath).writeAsStringSync(multiPartToAbc(mp));
    stdout.writeln('notaconv: notation → ABC ($parts voices, $outPath)');
  } else if (mp.parts.isEmpty) {
    stderr.writeln('notaconv: nothing to write (no parts)');
    exitCode = 1;
  } else {
    // Single-Score formats (MEI/kern/MuseScore/LilyPond/.mscz) can't carry N
    // parts — write the first one.
    stderr
        .writeln('notaconv: .$outExt is single-part; writing part 1 of $parts');
    _fromScore(mp.parts.first, outPath, outExt, stepsPerBeat: stepsPerBeat);
  }
}

/// Describes how many voices a module→text export kept, for the status line.
String _voiceDetail(ModuleDoc doc, int? channel, TextNotation fmt) {
  if (channel != null) return 'channel $channel';
  // ABC has unbounded V: voices → every sounding channel.
  if (fmt == TextNotation.abc) {
    return '${soundingChannelCount(doc)} voices (all channels)';
  }
  // MEI/kern writers are single-voice; MuseScore renders up to 4 overlays.
  if (fmt == TextNotation.mei || fmt == TextNotation.kern) {
    return 'voice 1 (single-voice format)';
  }
  final dropped = voicedDroppedChannels(doc);
  return dropped > 0
      ? 'up to 4 voices (+$dropped channels dropped)'
      : 'up to 4 voices';
}

void _ok(ModuleDoc doc, String outPath, String detail) {
  stdout.writeln('notaconv: ${doc.title.isEmpty ? '(untitled)' : doc.title} '
      '→ $outPath  ($detail)');
}
