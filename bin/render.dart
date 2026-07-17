// bin/render.dart
//
// Headless groove renderer — turns a Loop Mixer groove into a WAV using the SAME
// pure-Dart LoopEngine the app uses, no device or Flutter needed. Pairs with
// bin/listen.dart for round-trip acceptance (render → detect the notes).
//
//   dart run bin/render.dart out.wav --demo            # the default 5-track band
//   dart run bin/render.dart out.wav --groove "KU1.…"  # a share token
//   dart run bin/render.dart out.wav --groove-file token.txt --send reverb
//   dart run bin/render.dart --print-token --demo       # emit the groove's token
//
// Flutter-free (like bin/listen.dart) — lib/core/audio is pure Dart.

import 'dart:io';

import 'package:comet_beat/core/audio/loop_engine.dart';

const _baseTracks = ['drums', 'bass', 'chords', 'melody', 'sparkle'];

void main(List<String> args) {
  String? out;
  String? token;
  String? tokenFile;
  var demo = false;
  var printToken = false;
  LoopSend send = LoopSend.none;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--demo':
        demo = true;
      case '--print-token':
        printToken = true;
      case '--groove':
        token = (++i < args.length) ? args[i] : null;
      case '--groove-file':
        tokenFile = (++i < args.length) ? args[i] : null;
      case '--send':
        final v = (++i < args.length) ? args[i] : '';
        send = LoopSend.values.firstWhere(
          (s) => s.name == v,
          orElse: () => LoopSend.none,
        );
      default:
        if (a.startsWith('-')) {
          stderr.writeln('render: unknown option $a');
          exitCode = 2;
          return;
        }
        out ??= a;
    }
  }

  if (tokenFile != null) {
    final f = File(tokenFile);
    if (!f.existsSync()) {
      stderr.writeln('render: no such file: $tokenFile');
      exitCode = 2;
      return;
    }
    token = f.readAsStringSync().trim();
  }

  final engine = LoopEngine();

  if (token != null) {
    final spec = decodeGrooveToken(token);
    if (spec == null) {
      stderr.writeln('render: not a valid groove token (expected "KU1.…")');
      exitCode = 1;
      return;
    }
    engine.applySpec(spec);
  } else if (demo) {
    for (final id in _baseTracks) {
      engine.enabled.add(id);
    }
  }

  engine.send = send;

  if (printToken) {
    stdout.writeln(encodeGrooveToken(engine.spec));
    if (out == null) return; // token only
  }

  if (out == null) {
    stderr.writeln('usage: dart run bin/render.dart <out.wav> '
        '[--demo | --groove <token> | --groove-file <path>] [--send reverb|delay]');
    exitCode = 2;
    return;
  }

  final wav = engine.renderLoop();
  File(out).writeAsBytesSync(wav);
  final enabled =
      engine.enabled.isEmpty ? '(silent)' : engine.enabled.join(', ');
  stdout.writeln('render: wrote $out  '
      '(${wav.length} bytes · tempo ${engine.tempoBpm} · $enabled'
      '${send == LoopSend.none ? '' : ' · send:${send.name}'})');
}
