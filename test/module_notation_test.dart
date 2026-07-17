// test/module_notation_test.dart
//
// Round-trips across the ModuleDoc ↔ notation bridge (TRACKER_IDEAS §D). The
// point is conservation through a CYCLE, compared in a canonical space:
//   • Score → ModuleDoc → Score        (notes, durations, RESTS via note-off)
//   • ModuleDoc → MultiPartScore → ModuleDoc   (one staff per channel)
//   • MultiPartScore → format-1 MIDI → split → Score  (the multi-track MIDI the
//     library can't write alone)
//   • ModuleDoc → MusicXML → ModuleDoc  (through the library's XML reader/writer)
//   • a real golden module → multi-part → multi-track MIDI end-to-end
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/module_notation_test.dart

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_notation.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Score flattened to canonical `(midi?, steps)` runs: ties merge into one
/// held note (top pitch of a chord), and adjacent rests merge — so two ways of
/// notating the same sound compare equal.
List<(int?, int)> _flat(Score s, int spb) {
  final els = [for (final m in s.measures) ...m.elements];
  final runs = <(int?, int)>[];
  var i = 0;
  while (i < els.length) {
    final el = els[i];
    if (el is RestElement) {
      runs.add((null, durationToSteps(el.duration, spb)));
      i++;
      continue;
    }
    if (el is NoteElement) {
      var steps = durationToSteps(el.duration, spb);
      int? top;
      for (final p in el.pitches) {
        if (top == null || p.midiNumber > top) top = p.midiNumber;
      }
      var cur = el;
      while (cur.tieToNext && i + 1 < els.length && els[i + 1] is NoteElement) {
        final n = els[i + 1] as NoteElement;
        steps += durationToSteps(n.duration, spb);
        cur = n;
        i++;
      }
      runs.add((top, steps));
      i++;
      continue;
    }
    i++;
  }
  // Merge adjacent rests (the duration ladder splits one long rest into pieces).
  final merged = <(int?, int)>[];
  for (final r in runs) {
    if (r.$1 == null && merged.isNotEmpty && merged.last.$1 == null) {
      merged[merged.length - 1] = (null, merged.last.$2 + r.$2);
    } else {
      merged.add(r);
    }
  }
  // Drop a trailing rest (an unterminated tail carries no musical information
  // and the module side can't represent "silence forever").
  if (merged.isNotEmpty && merged.last.$1 == null) merged.removeLast();
  return merged;
}

/// The ordered melody (note pitches, rests dropped, tied continuations merged) —
/// for codecs that re-quantize durations or split a held note into tied pieces
/// but must preserve the tune.
List<int> _pitches(Score s) {
  final out = <int>[];
  for (final r in _flat(s, 4)) {
    if (r.$1 != null) out.add(r.$1!);
  }
  return out;
}

/// Packs per-channel DocCell columns into a one-pattern ModuleDoc.
ModuleDoc _pack(List<List<DocCell>> cols, {String title = 'T'}) {
  final ch = cols.length;
  final len = cols.first.length;
  final rows = [
    for (var r = 0; r < len; r++) [for (var c = 0; c < ch; c++) cols[c][r]],
  ];
  return ModuleDoc(
    title: title,
    channelCount: ch,
    sourceFormat: ModuleFormat.it,
    order: const [0],
    patterns: [DocPattern(rows, ch)],
    samples: [DocSample(name: 'x', pcm: Float64List(8))],
  );
}

DocCell _n(int midi) => DocCell(note: midi, instrument: 1);
const _e = DocCell.empty;
const _off = DocCell.off();

void main() {
  group('Score ↔ ModuleDoc round-trip', () {
    test('notes + rest + held note survive Score→doc→Score', () {
      // C quarter, quarter REST, D half, E quarter.
      const runs = [(60, 4), (null, 4), (62, 8), (64, 4)];
      final s = runsToScore(runs, 4);
      final doc = scoreToModuleDoc(s);
      final back = moduleChannelToScore(doc, 0);
      expect(_flat(back, 4), _flat(s, 4));
      expect(_flat(back, 4), runs);
    });

    test('a rest becomes a DocCell.off (so it is not swallowed)', () {
      const runs = [(60, 4), (null, 4), (67, 4)];
      final doc = scoreToModuleDoc(runsToScore(runs, 4));
      // Row 4 (after the quarter note) is the key-off that ends the ring.
      expect(doc.patterns.first.rows[4][0], const DocCell.off());
      expect(doc.patterns.first.rows[4][0].noteOff, isTrue);
    });

    test('doc→Score→doc preserves the played run sequence', () {
      // C rings 4, key-off, rest 3, G rings 4.
      final col = [_n(60), _e, _e, _e, _off, _e, _e, _n(67), _e, _e, _e];
      final doc = _pack([col]);
      final s = moduleChannelToScore(doc, 0);
      final doc2 = scoreToModuleDoc(s);
      expect(
        _flat(moduleChannelToScore(doc2, 0), 4),
        _flat(s, 4),
      );
    });
  });

  group('ModuleDoc ↔ MultiPartScore', () {
    // Two channels: a treble melody + a bass line.
    final doc = _pack([
      [_n(72), _e, _e, _e, _n(74), _e, _e, _e],
      [_n(48), _e, _e, _e, _e, _e, _e, _e],
    ]);

    test('one part per sounding channel, named + clef-picked', () {
      final mp = moduleToMultiPart(doc);
      expect(mp.score.parts.length, 2);
      expect(mp.partNames, ['Channel 1', 'Channel 2']);
      // Channel 2's mean pitch (48) is below middle C → bass clef.
      expect(mp.score.parts[1].clef, Clef.bass);
      expect(mp.score.parts[0].clef, Clef.treble);
    });

    test('custom part names', () {
      final mp = moduleToMultiPart(doc, nameOf: (c) => 'Voice $c');
      expect(mp.partNames, ['Voice 0', 'Voice 1']);
    });

    test('multiPart → doc → multiPart preserves each channel', () {
      final mp = moduleToMultiPart(doc);
      final doc2 = multiPartToModuleDoc(mp.score);
      expect(doc2.channelCount, 2);
      final mp2 = moduleToMultiPart(doc2);
      for (var p = 0; p < 2; p++) {
        expect(_flat(mp2.score.parts[p], 4), _flat(mp.score.parts[p], 4));
      }
    });

    test('silent channels are skipped', () {
      final d = _pack([
        [_n(60), _e],
        [_e, _e], // no notes
      ]);
      expect(moduleToMultiPart(d).score.parts.length, 1);
    });
  });

  group('multi-track MIDI (format-1 build + split + read)', () {
    final mp = moduleToMultiPart(
      _pack([
        [_n(72), _e, _e, _e, _n(76), _e, _e, _e],
        [_n(48), _e, _e, _e, _n(50), _e, _e, _e],
      ]),
    ).score;

    test('multiPartToMidi writes an SMF format 1 with one track per part', () {
      final smf = multiPartToMidi(mp);
      expect(String.fromCharCodes(smf.sublist(0, 4)), 'MThd');
      expect((smf[8] << 8) | smf[9], 1); // format 1
      expect((smf[10] << 8) | smf[11], 2); // ntrks = 2
    });

    test('split → scoreFromMidi recovers each part\'s pitches', () {
      final smf = multiPartToMidi(mp);
      final tracks = splitMultiTrackMidi(smf);
      expect(tracks.length, 2);
      for (var p = 0; p < 2; p++) {
        final recovered = _pitches(scoreFromMidi(tracks[p]));
        expect(
          recovered,
          _pitches(mp.parts[p]),
          reason: 'part $p melody survives MIDI round-trip',
        );
      }
    });

    test('multiPart → MIDI → multiTrackMidiToMultiPart keeps all parts', () {
      final back = multiTrackMidiToMultiPart(multiPartToMidi(mp));
      expect(back.parts.length, 2);
      for (var p = 0; p < 2; p++) {
        expect(_pitches(back.parts[p]), _pitches(mp.parts[p]));
      }
    });

    test('a single-track MIDI reads back as a 1-part score', () {
      final single = scoreToMidi(mp.parts.first);
      expect(multiTrackMidiToMultiPart(single).parts.length, 1);
    });
  });

  group('ModuleDoc ↔ MusicXML', () {
    final doc = _pack([
      [_n(60), _e, _e, _e, _n(64), _e, _e, _e, _n(67), _e, _e, _e],
    ]);

    test('moduleToMusicXml emits partwise XML', () {
      final xml = moduleToMusicXml(doc);
      expect(xml, contains('score-partwise'));
    });

    test('module → XML → module preserves the melody', () {
      final xml = moduleToMusicXml(doc);
      final back = musicXmlToModuleDoc(xml);
      expect(
        _pitches(moduleChannelToScore(back, 0)),
        _pitches(moduleChannelToScore(doc, 0)),
      );
    });
  });

  group('a rest survives a real module-bytes round-trip (note-off codec)', () {
    // C quarter, quarter REST, G quarter. The rest must come back a rest, not be
    // swallowed by the C ringing on — which needs the format's key-off byte.
    const runs = [(60, 4), (null, 4), (67, 4)];
    final score = runsToScore(runs, 4);

    for (final fmt in [ModuleFormat.it, ModuleFormat.xm, ModuleFormat.s3m]) {
      test('${fmt.name}: Score → doc → bytes → doc → Score keeps the rest', () {
        final doc = scoreToModuleDoc(score, format: fmt);
        final bytes = convertDocTo(doc, fmt);
        final back = moduleChannelToScore(parseAnyModule(bytes), 0);
        expect(_flat(back, 4), runs, reason: 'the middle rest survived $fmt');
      });
    }

    test('MOD has no key-off, so the note rings through the rest (documented)',
        () {
      final doc = scoreToModuleDoc(score, format: ModuleFormat.mod);
      final back = moduleChannelToScore(
        parseAnyModule(convertDocTo(doc, ModuleFormat.mod)),
        0,
      );
      // The rest is absorbed: C rings 8 steps, then G — no (null, 4) in between.
      expect(_flat(back, 4).any((r) => r.$1 == null), isFalse);
    });
  });

  group('module ↔ text notations (ABC / kern / MEI / MuseScore)', () {
    final doc = _pack([
      [_n(60), _e, _e, _e, _n(64), _e, _e, _e, _n(67), _e, _e, _e],
    ]);

    for (final fmt in [
      TextNotation.abc,
      TextNotation.kern,
      TextNotation.mei,
      TextNotation.musescore,
    ]) {
      test('${fmt.name}: module → text → module preserves the melody', () {
        final text = moduleToTextNotation(doc, fmt);
        expect(text, isNotEmpty);
        final back = textNotationToModuleDoc(text, fmt);
        expect(back, isNotNull);
        expect(
          _pitches(moduleChannelToScore(back!, 0)),
          _pitches(moduleChannelToScore(doc, 0)),
          reason: '${fmt.name} round-trip melody',
        );
      });
    }

    test('LilyPond is write-only (text out, no reader)', () {
      expect(moduleToTextNotation(doc, TextNotation.lilypond), isNotEmpty);
      expect(textNotationToScore('x', TextNotation.lilypond), isNull);
      expect(textNotationReadable(TextNotation.lilypond), isFalse);
      expect(textNotationReadable(TextNotation.abc), isTrue);
    });
  });

  group('multi-voice: up to 4 channels become overlay voices', () {
    test('four channels → four populated voices in one Score', () {
      final doc4 = _pack([
        [_n(72), _e, _n(74), _e],
        [_n(67), _e, _n(69), _e],
        [_n(60), _e, _n(62), _e],
        [_n(48), _e, _n(50), _e],
      ]);
      final m = moduleToVoicedScore(doc4).measures.first;
      expect(m.elements, isNotEmpty); // voice 1
      expect(m.voice2, isNotEmpty);
      expect(m.voice3, isNotEmpty);
      expect(m.voice4, isNotEmpty);
    });

    test('two channels → voice 1 + voice 2 only', () {
      final doc2 = _pack([
        [_n(72), _e],
        [_n(48), _e],
      ]);
      final m = moduleToVoicedScore(doc2).measures.first;
      expect(m.elements, isNotEmpty);
      expect(m.voice2, isNotEmpty);
      expect(m.voice3, isEmpty);
      expect(m.voice4, isEmpty);
    });

    test('ABC keeps EVERY channel as a V: voice (unbounded — orchestra case)',
        () {
      // 6 channels → 6 ABC voices (well past the 4-voice single-staff cap).
      final doc6 = _pack([
        for (var c = 0; c < 6; c++) [_n(55 + c), _e],
      ]);
      final abc = moduleToTextNotation(doc6, TextNotation.abc);
      final voices = RegExp(r'^V:\d+ name=', multiLine: true).allMatches(abc);
      expect(voices.length, 6);
      expect(soundingChannelCount(doc6), 6);
    });

    test('multiPartToAbc voices carry their part clef', () {
      final mp = moduleToMultiPart(
        _pack([
          [_n(72), _e], // treble
          [_n(40), _e], // low → bass clef
        ]),
      );
      final abc = multiPartToAbc(mp.score, partNames: mp.partNames);
      expect(abc, contains('clef=treble'));
      expect(abc, contains('clef=bass'));
    });

    test('more than 4 channels: keep the busiest 4, report the rest', () {
      final doc6 = _pack([
        for (var c = 0; c < 6; c++) [_n(55 + c), _e],
      ]);
      expect(voicedDroppedChannels(doc6), 2);
      final m = moduleToVoicedScore(doc6).measures.first;
      expect(
        [m.elements, m.voice2, m.voice3, m.voice4].every((v) => v.isNotEmpty),
        isTrue,
      );
    });

    test('the busiest channel becomes voice 1', () {
      // Channel 1 has 2 notes, channel 0 has 1 → channel 1 is voice 1.
      final doc = _pack([
        [_n(60), _e, _e, _e],
        [_n(72), _e, _n(74), _e],
      ]);
      final v1 = moduleToVoicedScore(doc).measures.first.elements.first;
      expect((v1 as NoteElement).pitches.first.midiNumber, 72);
    });
  });

  group('.mscz (zipped MuseScore) round-trip', () {
    final doc = _pack([
      [_n(60), _e, _e, _e, _n(64), _e, _e, _e, _n(67), _e, _e, _e],
    ]);

    test('module → .mscz bytes → module preserves the melody', () {
      final bytes = moduleToMscz(doc);
      expect(bytes.length, greaterThan(0));
      // It really is a zip (PK\x03\x04 local-file header).
      expect(bytes.sublist(0, 2), [0x50, 0x4b]);
      final back = msczToModuleDoc(bytes);
      expect(
        _pitches(moduleChannelToScore(back, 0)),
        _pitches(moduleChannelToScore(doc, 0)),
      );
    });
  });

  group('notation ↔ module cycle is a fixed point (no drift)', () {
    // C E G quarters, then a rest — the note-off terminator used to leave a
    // trailing empty bar that grew the ABC on the first pass. It shouldn't now.
    const runs = [(60, 4), (64, 4), (67, 4), (null, 4)];
    final score0 = runsToScore(runs, 4);

    test('abc: score → abc → score → abc is byte-identical after round 1', () {
      final abc1 = scoreToTextNotation(score0, TextNotation.abc);
      final score1 = textNotationToScore(abc1, TextNotation.abc)!;
      final abc2 = scoreToTextNotation(score1, TextNotation.abc);
      expect(abc2, abc1, reason: 'ABC is a fixed point (no drift, no growth)');
    });

    test('no trailing empty bar (the note-off terminator is trimmed)', () {
      // runsToScore drops the trailing rest, so the ABC has no dangling "z8".
      final abc = scoreToTextNotation(score0, TextNotation.abc);
      expect(abc.trimRight(), isNot(endsWith('z8 |')));
    });
  });

  group('end-to-end from a real golden module', () {
    test('golden.it → multi-part → multi-track MIDI → readable', () {
      final path = File('test/fixtures/golden.it');
      final doc = parseAnyModule(path.readAsBytesSync());
      final mp = moduleToMultiPart(doc);
      expect(mp.score.parts, isNotEmpty);
      final smf = multiPartToMidi(mp.score);
      final tracks = splitMultiTrackMidi(smf);
      expect(tracks.length, mp.score.parts.length);
      // Every part yields at least one readable note.
      for (final t in tracks) {
        expect(_pitches(scoreFromMidi(t)), isNotEmpty);
      }
    });
  });
}
