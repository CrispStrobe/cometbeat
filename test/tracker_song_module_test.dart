// songFromModuleBytes — imports a real module (.mod/.s3m/.xm/.it) into a
// TrackerSong. Runs against the committed license-clean golden fixtures; asserts
// structure (channels/patterns/order) and that authored notes survive the
// row-major -> channel-major transpose. Pure Dart, no device audio.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_writer.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show convertDocTo, parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:comet_beat/core/audio/mod/xm_module.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show replaySong, songUsesVariableTiming;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  test('sample-free Advanced Tracker voices export as playable samples', () {
    final song = TrackerSong();
    song.engine.setCell(0, 0, const TrackerCell(midi: 60));

    for (final format in ModuleFormat.values) {
      final bytes = convertDocTo(
        moduleDocFromSong(song, targetFormat: format),
        format,
      );
      final doc = parseAnyModule(bytes);
      expect(
        doc.samples.any((sample) => !sample.isEmpty),
        isTrue,
        reason: '${format.name} export lost its generated sample',
      );
    }
  });

  test('native S3M and IT channel pans reach imported channel state', () {
    final sample = DocSample(
      pcm: Float64List.fromList([0.2, -0.2]),
      pan: 128,
    );
    final pattern = const [
      [DocCell(note: 60, instrument: 1)],
    ];
    final s3m = songFromModuleDoc(
      ModuleDoc(
        sourceFormat: ModuleFormat.s3m,
        channelCount: 1,
        order: const [0],
        patterns: [DocPattern(pattern, 1)],
        samples: [sample],
        s3mDefaultPans: const [0x0F],
      ),
    );
    expect(s3m.channels.single.pan, closeTo(1.0, 0.001));

    final it = songFromModuleDoc(
      ModuleDoc(
        sourceFormat: ModuleFormat.it,
        channelCount: 1,
        order: const [0],
        patterns: [DocPattern(pattern, 1)],
        samples: [sample],
        channelPans: const [0],
        channelVolumes: const [32],
      ),
    );
    expect(it.channels.single.pan, closeTo(-1.0, 0.001));
    expect(it.channels.single.gain, closeTo(0.3, 0.001));

    final exported = parseAnyModule(
      convertDocTo(
        moduleDocFromSong(it, targetFormat: ModuleFormat.it),
        ModuleFormat.it,
      ),
    );
    expect(exported.channelPans.first, 0);
    expect(exported.channelVolumes.first, 32);
  });

  for (final name in ['golden.mod', 'golden.s3m', 'golden.xm', 'golden.it']) {
    test('$name imports into a consistent TrackerSong', () {
      final bytes = _fixture(name);
      final doc = parseAnyModule(bytes);
      final song = songFromModuleBytes(bytes);

      // Structure matches the module.
      expect(song.channelCount, doc.channelCount < 1 ? 1 : doc.channelCount);
      expect(song.patterns.length, doc.patterns.length);
      expect(song.order, isNotEmpty);

      // Every pattern is channel-major and row-sized (the model invariant).
      for (final p in song.patterns) {
        expect(p.cells.length, song.channelCount);
        for (final col in p.cells) {
          expect(col.length, song.rows);
        }
      }

      // The module's first authored note survives the import somewhere.
      final firstNote = _firstDocNote(doc);
      if (firstNote != null) {
        final found = song.patterns.any(
          (p) => p.cells.any((col) => col.any((c) => c.midi == firstNote)),
        );
        expect(found, isTrue, reason: 'first module note $firstNote not found');
      }

      // Rendering the imported song produces audio (no crash, non-trivial).
      expect(song.renderCurrentPatternWav().length, greaterThan(44));
    });
  }

  group('MOD effect column import (replayer feed)', () {
    test('XM native keymap selects the zone for the played note', () {
      final loud = Float64List.fromList([for (var i = 0; i < 44100; i++) 0.5]);
      final quiet =
          Float64List.fromList([for (var i = 0; i < 44100; i++) -0.5]);
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.xm,
        channelCount: 1,
        order: const [0],
        patterns: [
          const DocPattern(
            [
              [
                DocCell(
                  note: 60,
                  instrument: 1,
                  nativeInstrument: 1,
                  nativeInstrumentSet: true,
                ),
              ],
              [
                DocCell(
                  note: 72,
                  instrument: 1,
                  nativeInstrument: 1,
                  nativeInstrumentSet: true,
                ),
              ],
            ],
            1,
          ),
        ],
        xmInstruments: [
          XmInstrument(
            samples: [
              XmSample(pcm: loud),
              XmSample(pcm: quiet),
            ],
            keymap: [
              for (var i = 0; i < 96; i++) i >= 61 ? 1 : 0,
            ],
          ),
        ],
        samples: [
          DocSample(pcm: loud),
          DocSample(pcm: quiet),
        ],
      );
      final song = songFromModuleDoc(doc);
      expect(song.instruments, hasLength(1));
      expect(song.instruments.single, isA<MultiSampleInstrument>());
      final instrument = song.instruments.single as MultiSampleInstrument;
      expect(instrument.zones[60], isA<SampleInstrument>());
      expect(instrument.zones[72], isA<SampleInstrument>());
      expect(
        (instrument.zones[72]! as SampleInstrument).sample[1000],
        lessThan(0),
      );
      final out = instrument.renderChannel(
        song.patterns.first.cells.first,
        song.timing,
      );
      final directCells = [
        TrackerCell.empty,
        song.patterns.first.cells.first[1],
      ];
      final direct = (instrument.zones[72]! as SampleInstrument)
          .renderChannel(directCells, song.timing);
      final multiDirect = instrument.renderChannel(directCells, song.timing);
      expect(out[1000], greaterThan(0));
      expect(direct[song.timing.stepStartSample(1) + 1000], lessThan(0));
      expect(multiDirect[song.timing.stepStartSample(1) + 1000], lessThan(0));
    });

    test('effect nibble → tracker fxCmd/fxParam (note + effect-only cells)',
        () {
      final rows = <List<DocCell>>[
        // A note WITH a porta-up effect (1xx).
        [
          const DocCell(
            note: 60,
            instrument: 1,
            effect: 0x1,
            effectParam: 0x08,
          ),
        ],
        // An effect-ONLY cell (no note) — how a slide continues on a ring.
        [const DocCell(effect: 0x1)],
      ];
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.mod,
        channelCount: 1,
        order: [0],
        patterns: [DocPattern(rows, 1)],
        samples: [DocSample.empty()],
      );
      final song = songFromModuleDoc(doc);
      expect(song.usesCommands, isTrue); // routes through the replayer now

      final c0 = song.patterns[0].cells[0][0];
      expect(c0.midi, 60);
      expect(c0.fxCmd, 0x1);
      expect(c0.fxParam, 0x08);

      final c1 = song.patterns[0].cells[0][1];
      expect(c1.midi, isNull); // effect-only cell keeps no note
      expect(c1.hasCommand, isTrue);
      expect(c1.fxCmd, 0x1);

      // The whole chain (import → replayer) renders without throwing.
      expect(song.renderSongWav().length, greaterThan(44));
    });

    test('volume column is carried on import — incl. a note-less cell (BUG3)',
        () {
      final rows = <List<DocCell>>[
        // A note with a REDUCED volume column (16/64).
        [const DocCell(note: 60, instrument: 1, volume: 16)],
        // A volume-column-ONLY cell (no note) — a mid-note volume change.
        [const DocCell(volume: 8)],
        // A note at full volume (64) — no reduction, so no volume carried.
        [const DocCell(note: 62, instrument: 1, volume: 64)],
      ];
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.s3m,
        channelCount: 1,
        order: [0],
        patterns: [DocPattern(rows, 1)],
        samples: [DocSample.empty()],
      );
      final song = songFromModuleDoc(doc);
      final col = song.patterns[0].cells[0];

      expect(col[0].midi, 60);
      expect(col[0].volume, closeTo(16 / 64, 1e-9)); // reduced volume carried

      expect(col[1].midi, isNull); // note-less…
      expect(col[1].volume, closeTo(8 / 64, 1e-9)); // …but the volume survives

      expect(col[2].midi, 62);
      expect(col[2].volume, isNull); // full volume (64) → no reduction stored
    });

    test('golden.mod: every parsed effect becomes a command, none invented',
        () {
      final bytes = _fixture('golden.mod');
      final doc = parseAnyModule(bytes);
      var docFx = 0;
      for (final p in doc.patterns) {
        for (final row in p.rows) {
          for (final dc in row) {
            if (dc.effect != 0 || dc.effectParam != 0) docFx++;
          }
        }
      }
      final song = songFromModuleBytes(bytes);
      var songCmd = 0;
      for (final p in song.patterns) {
        for (final col in p.cells) {
          for (final c in col) {
            if (c.hasCommand) songCmd++;
          }
        }
      }
      if (docFx > 0) {
        expect(songCmd, greaterThan(0), reason: 'MOD effects should carry');
      }
      expect(songCmd, lessThanOrEqualTo(docFx)); // never invents commands
    });

    test('golden.xm: nibble effects carry, letter effects (G+) drop', () {
      final bytes = _fixture('golden.xm');
      final doc = parseAnyModule(bytes);
      var docFx = 0;
      for (final p in doc.patterns) {
        for (final row in p.rows) {
          for (final dc in row) {
            // The XM carry filter kept only fxCmd-nibble effects (0x0..0xF).
            expect(dc.effect, lessThanOrEqualTo(0xF));
            if (dc.effect != 0 || dc.effectParam != 0) docFx++;
          }
        }
      }
      final song = songFromModuleBytes(bytes);
      var songCmd = 0;
      for (final p in song.patterns) {
        for (final col in p.cells) {
          for (final c in col) {
            if (c.hasCommand) songCmd++;
          }
        }
      }
      if (docFx > 0) {
        expect(songCmd, greaterThan(0), reason: 'XM effects should carry');
      }
      expect(songCmd, lessThanOrEqualTo(docFx));
    });

    test('import builds the instrument pool + carries per-cell instrument', () {
      final bytes = _fixture('golden.mod');
      final doc = parseAnyModule(bytes);
      final song = songFromModuleBytes(bytes);

      // The pool has one entry per module sample.
      expect(song.instruments.length, doc.samples.length);

      var docInst = 0;
      for (final p in doc.patterns) {
        for (final row in p.rows) {
          for (final dc in row) {
            if (dc.instrument != 0) docInst++;
          }
        }
      }
      var songInst = 0;
      for (final p in song.patterns) {
        for (final col in p.cells) {
          for (final c in col) {
            if (c.instrument != 0) songInst++;
          }
        }
      }
      // Per-cell instrument survives the import, and routes via the replayer.
      expect(songInst, lessThanOrEqualTo(docInst));
      if (docInst > 0) {
        expect(songInst, greaterThan(0));
        expect(song.usesInstruments, isTrue);
      }
    });

    test('imported speed affects row duration relative to tracker speed 6', () {
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.mod,
        channelCount: 1,
        order: [0],
        patterns: [
          const DocPattern(
            [
              [
                DocCell(
                  note: 60,
                  instrument: 1,
                  effect: 0xF,
                  effectParam: 0x03,
                ),
              ],
              [DocCell()],
              [DocCell()],
              [DocCell()],
            ],
            1,
          ),
        ],
        samples: [DocSample.empty()],
      );

      final song = songFromModuleDoc(doc);
      expect(song.initialSpeed, 6);
      expect(songUsesVariableTiming(song), isTrue);
      expect(song.songTotalMs, 240); // 4 rows * (120 ms * 3/6)
      expect(replaySong(song).pcm.length, kSampleRate * 240 ~/ 1000);
    });

    test('S3M letter-commands map to the right fxCmd/fxParam on import', () {
      // Author a 1-channel S3M whose rows carry known S3M commands, write it,
      // import it, and assert the cross-format mapping (verified vs libopenmpt —
      // see docs/ORACLE.md).
      final rows = <List<S3mCell>>[
        [const S3mCell(note: 0x40, instrument: 1, volume: 64)], // C-5
        [const S3mCell(command: 6, info: 0x20)], // F — porta up  → 0x1
        [const S3mCell(command: 8, info: 0x34)], // H — vibrato   → 0x4
        [const S3mCell(command: 3, info: 0x08)], // C — break     → 0xD
        [const S3mCell(command: 20, info: 0x80)], // T — set tempo → 0xF
      ];
      final m = S3mModule(
        title: 'fxmap',
        channelCount: 1,
        order: [0],
        samples: [S3mSample.empty(), S3mSample(pcm: _sine())],
        patterns: [S3mPattern(rows)],
      );
      final song = songFromModuleBytes(writeS3m(m));
      final col = song.patterns[0].cells[0];
      expect((col[1].fxCmd, col[1].fxParam), (0x1, 0x20)); // porta up
      expect((col[2].fxCmd, col[2].fxParam), (0x4, 0x34)); // vibrato
      expect(col[3].fxCmd, 0xD); // pattern break
      expect((col[4].fxCmd, col[4].fxParam), (0xF, 0x80)); // tempo
    });

    test('IT letter-commands map to the right fxCmd/fxParam on import', () {
      final rows = <List<ItCell>>[
        [const ItCell(note: 60, instrument: 1, volpan: 64)], // C-5
        [const ItCell(command: 6, commandValue: 0x20)], // F — porta up → 0x1
        [const ItCell(command: 8, commandValue: 0x34)], // H — vibrato  → 0x4
        [const ItCell(command: 24, commandValue: 0xC0)], // X — set pan → 0x8
        [const ItCell(command: 20, commandValue: 0x80)], // T — tempo   → 0xF
      ];
      final m = ItModule(
        name: 'fxmap',
        channelCount: 1,
        order: [0],
        samples: [ItSample.empty(), ItSample(pcm: _sineF())],
        patterns: [ItPattern(rows, 1)],
      );
      final song = songFromModuleBytes(writeIt(m));
      final col = song.patterns[0].cells[0];
      expect((col[1].fxCmd, col[1].fxParam), (0x1, 0x20)); // porta up
      expect((col[2].fxCmd, col[2].fxParam), (0x4, 0x34)); // vibrato
      expect((col[3].fxCmd, col[3].fxParam), (0x8, 0xC0)); // set pan (direct)
      expect((col[4].fxCmd, col[4].fxParam), (0xF, 0x80)); // tempo
    });
  });

  group('imported-module effects sound on SAMPLE channels (end-to-end)', () {
    // The headline of the sample tick voice: an imported module's per-tick pitch
    // effect must actually BEND its own sampled instrument, not fall back to a
    // flat one-shot-per-note. This drives the SAME import entry point real bytes
    // take (songFromModuleDoc), then renders through the replayer and reads the
    // rendered audio back — proving the whole chain, not just a hand-built song.
    test('a porta-up on a sampled channel raises the pitch on render', () {
      // A long, low sine sample stored at the engine rate (c5speed = engine rate
      // → the bridge passes the PCM through unresampled; note 60 = baseMidi plays
      // it 1:1), long enough to ring across the porta.
      final pcm = Float64List(150000);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = sin(2 * pi * 110 * i / kSampleRate);
      }
      final rows = <List<DocCell>>[
        // Row 0: trigger the sample at its base note.
        [const DocCell(note: 60, instrument: 1)],
        // Rows 1..7: effect-only porta-up (0x1) — continues on the ringing note.
        for (var r = 1; r < 8; r++)
          [const DocCell(effect: 0x1, effectParam: 0x06)],
      ];
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.xm,
        channelCount: 1,
        order: [0],
        patterns: [DocPattern(rows, 1)],
        samples: [DocSample(pcm: pcm, c5speed: kSampleRate)],
      );

      final song = songFromModuleDoc(doc);
      expect(song.usesCommands, isTrue); // routes through the tick replayer

      // Render the whole song and decode the PCM back.
      final mono = wavToMonoFloat(readWavPcm16(song.renderSongWav()));
      expect(mono.length, greaterThan(kSampleRate ~/ 2)); // non-trivial audio

      int crossings(int lo, int hi) {
        var c = 0;
        for (var i = lo + 1; i < hi; i++) {
          if ((mono[i - 1] < 0) != (mono[i] < 0)) c++;
        }
        return c;
      }

      // A rising pitch crosses zero more often later than earlier — the porta
      // bent the SAMPLE, so it isn't a flat per-note one-shot.
      final n = mono.length;
      expect(
        crossings(n ~/ 2, n),
        greaterThan(crossings(0, n ~/ 2)),
        reason: 'porta on a sampled channel should raise the pitch',
      );
    });
  });

  group('module envelopes import onto the channel', () {
    test('a sample volume/pan envelope becomes the channel envelope', () {
      final pcm = Float64List.fromList([
        for (var i = 0; i < 64; i++) sin(2 * pi * 4 * i / 64),
      ]);
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.xm,
        channelCount: 1,
        initialTempo: 100, // one tick = 2500/100 = 25 ms
        order: [0],
        patterns: [
          const DocPattern(
            [
              [DocCell(note: 60, instrument: 1)],
            ],
            1,
          ),
        ],
        samples: [
          DocSample(
            pcm: pcm,
            volumeEnvelope: const DocEnvelope(
              points: [(0, 64), (5, 0)],
              enabled: true,
            ),
            panEnvelope: const DocEnvelope(
              points: [(0, 32), (10, 64)], // centre → hard right
              enabled: true,
            ),
          ),
        ],
      );

      final song = songFromModuleDoc(doc);
      final ch = song.channels.first;

      final vol = ch.volumeEnvelope!;
      expect(vol.points.length, 2);
      expect(vol.points[0].ms, 0);
      expect(vol.points[0].level, closeTo(1.0, 1e-9)); // 64/64
      expect(vol.points[1].ms, 125); // 5 ticks × 25 ms
      expect(vol.points[1].level, closeTo(0.0, 1e-9));

      final pan = ch.panEnvelope!;
      expect(pan.points[0].pan, closeTo(0.0, 1e-9)); // 32 → centre
      expect(pan.points[1].ms, 250); // 10 ticks × 25 ms
      expect(pan.points[1].pan, closeTo(1.0, 1e-9)); // 64 → hard right
    });

    test('a sample default pan becomes the channel pan', () {
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.xm,
        channelCount: 1,
        order: [0],
        patterns: [
          const DocPattern(
            [
              [DocCell(note: 60, instrument: 1)],
            ],
            1,
          ),
        ],
        samples: [DocSample(pcm: Float64List(64), pan: 32)], // hard-ish left
      );
      final ch = songFromModuleDoc(doc).channels.first;
      expect(ch.pan, closeTo((32 - 128) / 128, 1e-9)); // −0.75
    });

    test('no envelope → the channel has none', () {
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.mod,
        channelCount: 1,
        order: [0],
        patterns: [
          const DocPattern(
            [
              [DocCell(note: 60, instrument: 1)],
            ],
            1,
          ),
        ],
        samples: [DocSample(pcm: Float64List(64))],
      );
      final ch = songFromModuleDoc(doc).channels.first;
      expect(ch.volumeEnvelope, isNull);
      expect(ch.panEnvelope, isNull);
    });

    test('disabled native envelope points do not affect playback state', () {
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.it,
        channelCount: 1,
        order: [0],
        patterns: [
          const DocPattern(
            [
              [DocCell(note: 60, instrument: 1)],
            ],
            1,
          ),
        ],
        samples: [
          DocSample(
            pcm: Float64List(64),
            volumeEnvelope: const DocEnvelope(
              points: [(0, 0), (4, 64)],
              enabled: false,
            ),
            panEnvelope: const DocEnvelope(
              points: [(0, 64), (4, 0)],
              enabled: false,
            ),
          ),
        ],
      );

      final ch = songFromModuleDoc(doc).channels.first;
      expect(ch.volumeEnvelope, isNull);
      expect(ch.panEnvelope, isNull);
    });

    test('IT pitch envelope reaches the sampled native zone', () {
      final doc = ModuleDoc(
        sourceFormat: ModuleFormat.it,
        channelCount: 1,
        initialTempo: 120,
        order: [0],
        patterns: [
          DocPattern([
            [
              const DocCell(
                note: 60,
                instrument: 1,
                nativeInstrument: 1,
                nativeInstrumentSet: true,
              ),
            ],
          ], 1),
        ],
        samples: [
          DocSample(pcm: Float64List(44100 * 2), c5speed: kSampleRate),
        ],
        itInstruments: [
          DocInstrument(
            keymap: List<int>.filled(120, 1),
            pitchEnvelope: const DocEnvelope(
              points: [(0, 12), (4, 0)],
              enabled: true,
            ),
          ),
        ],
      );

      final song = songFromModuleDoc(doc);
      final multi = song.instruments.single as MultiSampleInstrument;
      final zone = multi.zones[60]! as SampleInstrument;
      expect(zone.nativePitchEnvelope, isNotNull);
      expect(zone.nativePitchEnvelope!.semitonesAt(0), 12);
      expect(zone.nativePitchEnvelope!.semitonesAt(1000), 0);
    });
  });

  test('imports XM/IT-style patterns with their individual row counts', () {
    final doc = ModuleDoc(
      sourceFormat: ModuleFormat.xm,
      channelCount: 1,
      order: [0, 1],
      patterns: [
        const DocPattern(
          [
            [DocCell(note: 60)],
            [DocCell.empty],
            [DocCell.empty],
            [DocCell.empty],
          ],
          1,
        ),
        const DocPattern(
          [
            [DocCell(note: 62)],
            [DocCell.empty],
            [DocCell.empty],
            [DocCell.empty],
            [DocCell.empty],
            [DocCell.empty],
            [DocCell.empty],
            [DocCell.empty],
          ],
          1,
        ),
      ],
      samples: [
        DocSample(pcm: Float64List.fromList([0.5, 0.0, -0.5]))
      ],
    );
    final song = songFromModuleDoc(doc);
    expect(song.patterns[0].rows, 4);
    expect(song.patterns[1].rows, 8);
    song.selectPattern(1);
    expect(song.rows, 8);
    expect(song.renderSongWav().length, greaterThan(44));
  });
}

Float64List _sineF() {
  final s = Float64List(512);
  for (var i = 0; i < s.length; i++) {
    s[i] = 0.8 * sin(2 * pi * 4 * i / s.length);
  }
  return s;
}

Float64List _sine() {
  final s = Float64List(512);
  for (var i = 0; i < s.length; i++) {
    s[i] = (100 / 128) * sin(2 * pi * 4 * i / s.length);
  }
  return s;
}

int? _firstDocNote(ModuleDoc doc) {
  for (final p in doc.patterns) {
    for (var r = 0; r < p.numRows; r++) {
      for (final cell in p.rows[r]) {
        if (cell.note >= 0) return cell.note;
      }
    }
  }
  return null;
}
