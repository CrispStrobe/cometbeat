// ProTracker channel panning — the Amiga's L-R-R-L layout.
//
// A `.mod` stores NO panning. The layout is a property of the hardware (the
// Amiga wires its four voices L R R L), so it has to be supplied on import or
// every channel lands dead centre — which is what we were doing, rendering
// every MOD mono-in-stereo and losing the wide ping-pong image that is one of
// the format's defining sounds.
//
// It also cost us level: with no pan, FULL amplitude went into BOTH channels
// instead of being split across them, which is why an A/B against openmpt123
// measured us a consistent +4.0 dB hot on every module regardless of channel
// count or sample volume. Panning recovers ~1.3 dB of that; the rest is a
// separate per-voice gain convention (see `_channelGain`).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 4-channel MOD in which only [only] ever plays a note.
Uint8List _oneChannelModule(int only) {
  const rows = 32;
  const channels = 4;
  final wave = Float64List(256);
  for (var i = 0; i < wave.length; i++) {
    wave[i] = math.sin(2 * math.pi * i / wave.length);
  }
  return convertToMod(
    ModuleDoc(
      sourceFormat: ModuleFormat.mod,
      channelCount: channels,
      order: const [0],
      samples: [DocSample(name: 's', pcm: wave, loopLength: wave.length)],
      patterns: [
        DocPattern(
          [
            for (var r = 0; r < rows; r++)
              [
                for (var c = 0; c < channels; c++)
                  if (c == only && r % 8 == 0)
                    const DocCell(note: 60, instrument: 1)
                  else
                    DocCell.empty,
              ],
          ],
          channels,
        ),
      ],
    ),
  );
}

void main() {
  group('ProTracker L-R-R-L panning', () {
    test('channels 0 and 3 go left, 1 and 2 go right', () {
      for (final channel in [0, 1, 2, 3]) {
        final song = songFromModuleDoc(
          parseAnyModule(_oneChannelModule(channel)),
        );
        final pan = song.channels[channel].pan;
        final expectLeft = channel == 0 || channel == 3;
        expect(
          expectLeft ? pan < 0 : pan > 0,
          isTrue,
          reason: 'channel $channel should sit '
              '${expectLeft ? "LEFT" : "RIGHT"} but its pan is $pan',
        );
      }
    });

    test('the layout repeats every four channels', () {
      // Multi-channel MOD variants (6CHN/8CHN) keep repeating L-R-R-L rather
      // than inventing a new spread, so channel 4 sits where channel 0 does.
      final song = songFromModuleDoc(parseAnyModule(_oneChannelModule(0)));
      final base = song.channels[0].pan;
      expect(base, lessThan(0));
      // Same rule, checked directly on the sequence it generates.
      for (final (channel, isLeft) in [
        (0, true),
        (1, false),
        (2, false),
        (3, true),
      ]) {
        final s = songFromModuleDoc(parseAnyModule(_oneChannelModule(channel)));
        expect(s.channels[channel].pan.isNegative, isLeft);
      }
    });

    test('it is a SPLIT, not a hard pan — both sides still sound', () {
      // Real hardware is panned fully hard; that is exhausting on headphones,
      // so trackers soften it and we follow the reference player's 3:1 split.
      // A hard pan would silence one side entirely, which is a different and
      // more tiring sound.
      final song = songFromModuleDoc(parseAnyModule(_oneChannelModule(0)));
      expect(song.channels[0].pan.abs(), lessThan(1.0));
      expect(song.channels[0].pan.abs(), greaterThan(0.3));
    });

    test('formats that DO store panning are left alone', () {
      // MOD gets the hardware layout precisely because it stores nothing. A
      // format carrying its own pan table must keep it — overriding an IT's
      // authored panning with the Amiga layout would be a regression, not a
      // fix.
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.it,
        channelCount: 4,
        order: const [0],
        channelPans: const [32, 32, 32, 32], // all centre, authored
        samples: [DocSample(name: 's', pcm: Float64List(64))],
        patterns: [
          DocPattern(
            [
              for (var r = 0; r < 8; r++)
                List<DocCell>.filled(4, DocCell.empty),
            ],
            4,
          ),
        ],
      );
      final song = songFromModuleDoc(doc);
      for (var c = 0; c < 4; c++) {
        expect(
          song.channels[c].pan,
          0.0,
          reason: 'IT channel $c authored centre; the MOD layout must not '
              'override it',
        );
      }
    });
  });
}
