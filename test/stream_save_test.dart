// The native streaming-save seam behind the DAW's bounded-memory WAV export.

import 'dart:io';

import 'package:comet_beat/shared/music_io/stream_save.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streamBytesToFile writes the produced chunks to disk in order',
      () async {
    final tmp = File(
      '${Directory.systemTemp.path}/stream_save_'
      '${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });

    final ok = await streamBytesToFile(tmp.path, (sink) {
      sink([1, 2, 3]);
      sink([4, 5]);
      sink(List<int>.filled(1000, 7)); // a bigger chunk, like a WAV data block
    });

    expect(ok, isTrue);
    final written = tmp.readAsBytesSync();
    expect(written.length, 1005);
    expect(written.sublist(0, 5), [1, 2, 3, 4, 5]);
    expect(written[1004], 7);
  });
}
