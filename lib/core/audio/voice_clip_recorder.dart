// lib/core/audio/voice_clip_recorder.dart
//
// Records a short mono PCM16 mic clip into a Float64 buffer — the capture half of
// the Tracker's "record your voice → play a tune with it" instrument. Uses the
// same `record` plugin path as MicrophonePitchService (startStream of PCM16 at
// kSampleRate), but accumulates a fixed-length clip instead of streaming to a
// pitch analyzer. The captured buffer is handed to SampleInstrument.recorded.
//
// This is the only mic-facing file for the Tracker; it can't run under the
// headless test binding (no device), so the screen guards it and the widget test
// injects a synthetic clip via the tester seam instead.

import 'dart:async';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:record/record.dart';

class VoiceClipRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  bool _recording = false;

  bool get isRecording => _recording;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Records mono PCM16 at [kSampleRate] for up to [maxDuration], then returns
  /// the captured samples as Float64 in [-1, 1]. Throws [StateError] if the mic
  /// permission is denied or PCM16 is unsupported.
  Future<Float64List> record({
    Duration maxDuration = const Duration(seconds: 2),
  }) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('microphone permission denied');
    }
    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw StateError('pcm16 not supported');
    }

    _buffer.clear();
    // autoGain/noiseSuppress off — keep the natural waveform (as the pitch
    // service does); we want the child's actual voice, warts and all.
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        // Stated explicitly: the capture rate MUST equal playback's kSampleRate
        // or every recorded note plays back at the wrong pitch.
        // ignore: avoid_redundant_argument_values
        sampleRate: kSampleRate,
      ),
    );

    _recording = true;
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    _sub = stream.listen(
      _buffer.add,
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: false,
    );
    final timer = Timer(maxDuration, finish);

    await done.future;
    timer.cancel();
    await stop();
    return pcm16ToFloat(_buffer.toBytes());
  }

  Future<void> stop() async {
    _recording = false;
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}

/// Decodes little-endian mono PCM16 [bytes] to Float64 in [-1, 1].
Float64List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float64List(n);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
