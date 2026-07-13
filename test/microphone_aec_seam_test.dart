// Proves the AEC Tier-3b seam in MicrophonePitchService WITHOUT any native
// plugin or mic: a FakeAecEngine stands in for the native full-duplex engine.
// When an AecEngine is attached, the service must analyze the engine's cleaned
// stream (never the `record` mic — touching it here would throw
// MissingPluginException), forward backing PCM via pushReference, and drive the
// same analyzer path as the real capture. When no engine is attached, behaviour
// is unchanged. This is the app-side half of milestone (c); the native engine
// binds to the same [AecEngine] contract via an adapter in milestone (d).

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/aec_engine.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';

/// Test double for the native engine: capture a start, collect references, and
/// let the test push cleaned PCM on demand.
class FakeAecEngine implements AecEngine {
  final _cleaned = StreamController<Uint8List>.broadcast();
  final List<Uint8List> references = [];
  bool started = false;
  bool stopped = false;
  int? startSampleRate;

  @override
  Future<void> start({int sampleRate = 44100, int frame = 256}) async {
    started = true;
    startSampleRate = sampleRate;
  }

  @override
  void reference(Uint8List pcm16) => references.add(pcm16);

  @override
  Stream<Uint8List> get cleaned => _cleaned.stream;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_cleaned.isClosed) await _cleaned.close();
  }

  void emit(Uint8List pcm) {
    if (!_cleaned.isClosed) _cleaned.add(pcm);
  }
}

/// Mono PCM16 of a sine at [freq] Hz.
Uint8List _sinePcm16(double freq, int sampleRate, double seconds) {
  final n = (sampleRate * seconds).round();
  final bytes = Uint8List(n * 2);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    final v = 0.5 * sin(2 * pi * freq * i / sampleRate);
    bd.setInt16(i * 2, (v * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return bytes;
}

Iterable<Uint8List> _chunks(Uint8List data, int size) sync* {
  for (var o = 0; o < data.length; o += size) {
    yield Uint8List.sublistView(data, o, min(o + size, data.length));
  }
}

void main() {
  test('usesAec reflects whether an engine is attached', () {
    expect(MicrophonePitchService().usesAec, isFalse);
    expect(MicrophonePitchService(aec: FakeAecEngine()).usesAec, isTrue);
  });

  test('pushReference forwards to the engine (and is a no-op without one)', () {
    final fake = FakeAecEngine();
    final svc = MicrophonePitchService(aec: fake);
    final ref = Uint8List.fromList([1, 2, 3, 4]);
    svc.pushReference(ref);
    expect(fake.references, [ref]);

    // No engine → silently ignored, never throws.
    expect(
      () => MicrophonePitchService().pushReference(Uint8List(4)),
      returnsNormally,
    );
  });

  test('analyzes the AEC cleaned stream and recovers the pitch (no record mic)',
      () async {
    const sr = 22050; // non-default, so we can assert it's forwarded to start()
    final fake = FakeAecEngine();
    final svc = MicrophonePitchService(aec: fake, sampleRate: sr);

    final readings = <PitchReading>[];
    final sub = svc.readings.listen(readings.add);

    await svc.start();
    expect(fake.started, isTrue);
    expect(fake.startSampleRate, sr);

    // Feed ~1s of 220 Hz (A3) as the "cleaned" near-end, chunked like a stream.
    final pcm = _sinePcm16(220, sr, 1.0);
    for (final chunk in _chunks(pcm, 4096)) {
      fake.emit(chunk);
      await pumpEventQueue();
    }

    await svc.stop();
    await sub.cancel();
    expect(fake.stopped, isTrue);

    final voiced = readings.where((r) => r.hasPitch).toList();
    expect(voiced, isNotEmpty, reason: 'expected voiced readings from cleaned');
    expect(
      voiced.any((r) => (r.frequency - 220).abs() < 5),
      isTrue,
      reason: 'expected a reading near 220 Hz, got '
          '${voiced.map((r) => r.frequency.toStringAsFixed(1)).toList()}',
    );
  });
}
