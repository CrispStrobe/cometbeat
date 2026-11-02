// Web: only the pure-Dart decoders (WAV, MP3).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/song_audio.dart';

Future<SongAudio?> decodeSongFile(String path, Uint8List bytes) =>
    decodeSongBytes(bytes);
