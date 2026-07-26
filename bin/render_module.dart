// Render a module (.mod/.s3m/.xm/.it) through OUR import + replay pipeline to a
// WAV — the "mine" side of the libopenmpt oracle comparison. Compare its note
// trajectory (via `dart run bin/listen.dart --wav`) against the reference from
// `openmpt123 --render <module>`. Dev / verification tool (Flutter-free).
//
//   dart run bin/render_module.dart <module> <out.wav>
//
// Bounded-memory streaming / range export (never touches the DEFAULT render):
//   --stream            render the whole song in chunks and STREAM it to
//                       <out.wav>, holding ~one chunk of PCM in memory at a time
//                       instead of the whole song (bounded peak memory).
//   --from-order N      render only order entries [N, ...)   (default 0)
//   --to-order N        render only order entries [..., N)   (default order len)
//   --chunk-orders K    chunk size in order entries          (default 1)
//
// QUALITY (opt-in; OFF by default so the default render stays byte-identical +
// reproducible):
//   --dither            add deterministic TPDF dither at the float→Int16
//                       quantisation (decorrelates quantisation noise). Seeded,
//                       so a dithered render is reproducible run-to-run; the SAME
//                       dither is applied on the buffered and --stream paths.
//   --dither-seed N     seed the dither PRNG (default a fixed constant).
//
// FIDELITY: for a UNIFORM / non-command song the whole-song render is already a
// concatenation of independent per-order renders, so --stream is BYTE-IDENTICAL
// to the default render at any chunk size. For a COMMAND-HEAVY song (commands /
// envelopes / pan / flow) the normal render carries voice state (portamento,
// envelopes, NNA, flow) ACROSS order boundaries; chunked rendering RESETS that
// state at each chunk boundary, trading exact cross-boundary continuity for
// bounded memory. Use `--chunk-orders <order-length>` for a single chunk == the
// exact full render (unbounded). The default (no flags) path is unchanged.
//
// See docs/ORACLE.md for the full A/B workflow used to verify the S3M/IT
// cross-format effect table against libopenmpt.
import 'dart:io';

import 'package:comet_beat/core/audio/tracker_song_module.dart';

int? _intArg(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? int.tryParse(args[i + 1]) : null;
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run bin/render_module.dart <module> <out.wav> '
      '[--pattern N] [--stream] [--from-order N] [--to-order N] '
      '[--chunk-orders K]',
    );
    exit(2);
  }
  final bytes = File(args[0]).readAsBytesSync();
  final song = songFromModuleBytes(bytes);

  final patternArg = args.indexOf('--pattern');
  final pattern = patternArg >= 0 && patternArg + 1 < args.length
      ? int.tryParse(args[patternArg + 1])
      : null;
  final stream = args.contains('--stream');
  final fromOrder = _intArg(args, '--from-order');
  final toOrder = _intArg(args, '--to-order');
  final chunkOrders = _intArg(args, '--chunk-orders') ?? 1;
  final dither = args.contains('--dither');
  final ditherSeed = _intArg(args, '--dither-seed');

  if (pattern != null) {
    if (stream || fromOrder != null || toOrder != null) {
      stderr.writeln('--pattern cannot combine with the streaming/range flags');
      exit(2);
    }
    if (pattern < 0 || pattern >= song.patterns.length) {
      stderr.writeln('pattern index out of range: $pattern');
      exit(2);
    }
    song.selectPattern(pattern);
    File(args[1]).writeAsBytesSync(song.renderCurrentPatternWav());
    stdout.writeln(
      'wrote ${args[1]}: ${song.channelCount} ch · '
      '${song.patterns.length} pat · pattern $pattern · '
      'usesCommands=${song.usesCommands} usesPan=${song.usesPan}',
    );
    return;
  }

  final lo = fromOrder ?? 0;
  final hi = toOrder ?? song.order.length;

  if (stream) {
    // Bounded-memory: chunks are streamed straight to the file.
    final dataBytes = await song.streamSongWavToFile(
      args[1],
      chunkOrders: chunkOrders,
      fromOrder: lo,
      toOrder: hi,
      dither: dither,
      ditherSeed: ditherSeed,
    );
    stdout.writeln(
      'wrote ${args[1]} (stream): ${song.channelCount} ch · '
      '${song.patterns.length} pat · order [$lo,$hi) of ${song.order.length} · '
      'chunkOrders=$chunkOrders · ${dataBytes ~/ 2} samples · '
      'usesCommands=${song.usesCommands} usesPan=${song.usesPan}',
    );
    return;
  }

  if (fromOrder != null || toOrder != null) {
    // Range render (bounded chunked internally; returns the range's PCM).
    final wav = song.renderOrderRangeWav(lo, hi, chunkOrders: chunkOrders);
    File(args[1]).writeAsBytesSync(wav);
    stdout.writeln(
      'wrote ${args[1]} (range): ${song.channelCount} ch · '
      '${song.patterns.length} pat · order [$lo,$hi) of ${song.order.length} · '
      'chunkOrders=$chunkOrders · '
      'usesCommands=${song.usesCommands} usesPan=${song.usesPan}',
    );
    return;
  }

  // DEFAULT path — bounded-memory streaming write (byte-identical to
  // renderSongWav): the whole-song render is converted to PCM16 and streamed to
  // disk in blocks, so the int16 PCM + WAV copy are never held alongside the
  // float mix accumulator.
  await song.writeSongWavStreaming(
    args[1],
    dither: dither,
    ditherSeed: ditherSeed,
  );
  stdout.writeln(
    'wrote ${args[1]}: ${song.channelCount} ch · ${song.patterns.length} pat · '
    'order ${song.order.length} · song · '
    'usesCommands=${song.usesCommands} usesPan=${song.usesPan}',
  );
}
