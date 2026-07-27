// TtsService: narration gating + locale→voice mapping, tested against a fake
// backend (no `flutter_tts` method channel involved).
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements TtsBackend {
  final List<(String, String)> spoken = []; // (text, langCode)
  int stops = 0;

  @override
  Future<void> speak(String text, {required String langCode}) async {
    spoken.add((text, langCode));
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  test('voiceTag maps de→de-DE and everything else→en-US', () {
    expect(TtsService.voiceTag(const Locale('de')), 'de-DE');
    expect(TtsService.voiceTag(const Locale('en')), 'en-US');
    expect(TtsService.voiceTag(const Locale('fr')), 'en-US');
  });

  test('speaks the text in the locale voice when sound is on', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake);
    await tts.speak('Ein gleichmäßiger Puls', locale: const Locale('de'));
    await tts.speak('A steady beat', locale: const Locale('en'));
    expect(fake.spoken, [
      ('Ein gleichmäßiger Puls', 'de-DE'),
      ('A steady beat', 'en-US'),
    ]);
  });

  test('the master sound switch silences narration', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake)..soundOn = false;
    await tts.speak('should stay silent', locale: const Locale('en'));
    expect(fake.spoken, isEmpty);
  });

  test('the narration switch silences narration but is independent of soundOn',
      () async {
    final fake = _FakeBackend();
    // Narration off while sound stays on → no speech.
    final tts = TtsService(backend: fake)..narrationOn = false;
    expect(tts.soundOn, isTrue);
    await tts.speak('should stay silent', locale: const Locale('en'));
    expect(fake.spoken, isEmpty);
    // Turning it back on speaks again.
    tts.narrationOn = true;
    await tts.speak('now audible', locale: const Locale('en'));
    expect(fake.spoken, [('now audible', 'en-US')]);
  });

  test('blank text is a no-op', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake);
    await tts.speak('   ', locale: const Locale('en'));
    expect(fake.spoken, isEmpty);
  });

  test('stop forwards to the backend and clears speaking', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake);
    await tts.speak('hi', locale: const Locale('en'));
    expect(tts.isSpeaking, isTrue);
    await tts.stop();
    expect(tts.isSpeaking, isFalse);
    expect(fake.stops, greaterThanOrEqualTo(1));
  });

  test('prefers the neural backend when it reports ready', () async {
    final platform = _FakeBackend();
    final neural = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      neural: _holder(neural, ready: true),
    );
    await tts.speak('Ein Test', locale: const Locale('de'));
    expect(neural.spoken, [('Ein Test', 'de-DE')]);
    expect(platform.spoken, isEmpty);
  });

  test('falls back to the platform backend when neural is not ready', () async {
    final platform = _FakeBackend();
    final neural = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      neural: _holder(neural, ready: false),
    );
    await tts.speak('A test', locale: const Locale('en'));
    expect(platform.spoken, [('A test', 'en-US')]);
    expect(neural.spoken, isEmpty);
  });

  test('falls back when the neural readiness check throws', () async {
    final platform = _FakeBackend();
    final neural = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      neural: NeuralTts(
        backend: neural,
        ready: () async => throw StateError('lib missing'),
        supported: () async => true,
        download: (_) async => false,
      ),
    );
    await tts.speak('A test', locale: const Locale('en'));
    expect(platform.spoken, [('A test', 'en-US')]);
    expect(neural.spoken, isEmpty);
  });

  test('hasNeural + supported reflect the holder', () async {
    final withNeural = TtsService(
      backend: _FakeBackend(),
      neural: _holder(_FakeBackend(), ready: false),
    );
    expect(withNeural.hasNeural, isTrue);
    expect(await withNeural.neuralSupported(), isTrue);

    final without = TtsService(backend: _FakeBackend());
    expect(without.hasNeural, isFalse);
    expect(await without.neuralSupported(), isFalse);
    expect(await without.downloadNeuralVoice(const Locale('en')), isFalse);
  });

  test('routes to the onnxFfi backend when it reports ready (no crispasr)',
      () async {
    final platform = _FakeBackend();
    final onnx = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      onnx: _holder(onnx, ready: true),
    );
    await tts.speak('Ein Test', locale: const Locale('de'));
    expect(onnx.spoken, [('Ein Test', 'de-DE')]);
    expect(platform.spoken, isEmpty);
  });

  test('falls back to platform when the onnxFfi backend is not ready',
      () async {
    final platform = _FakeBackend();
    final onnx = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      onnx: _holder(onnx, ready: false),
    );
    await tts.speak('A test', locale: const Locale('en'));
    expect(platform.spoken, [('A test', 'en-US')]);
    expect(onnx.spoken, isEmpty);
  });

  test('crispasr-FFI outranks onnxFfi when both are ready', () async {
    final platform = _FakeBackend();
    final crispasr = _FakeBackend();
    final onnx = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      neural: _holder(crispasr, ready: true),
      onnx: _holder(onnx, ready: true),
    );
    await tts.speak('A test', locale: const Locale('en'));
    expect(crispasr.spoken, [('A test', 'en-US')]);
    expect(onnx.spoken, isEmpty);
    expect(platform.spoken, isEmpty);
  });

  test('onnxFfi is used over crispasr-FFI when only onnx is ready', () async {
    final platform = _FakeBackend();
    final crispasr = _FakeBackend();
    final onnx = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      neural: _holder(crispasr, ready: false),
      onnx: _holder(onnx, ready: true),
    );
    await tts.speak('A test', locale: const Locale('en'));
    expect(onnx.spoken, [('A test', 'en-US')]);
    expect(crispasr.spoken, isEmpty);
  });

  test('an onnxFfi readiness throw is treated as not available', () async {
    final platform = _FakeBackend();
    final onnx = _FakeBackend();
    final tts = TtsService(
      backend: platform,
      onnx: NeuralTts(
        backend: onnx,
        ready: () async => throw StateError('no ORT'),
        supported: () async => true,
        download: (_) async => false,
      ),
    );
    await tts.speak('A test', locale: const Locale('en'));
    expect(platform.spoken, [('A test', 'en-US')]);
    expect(onnx.spoken, isEmpty);
  });

  test('downloadNeuralVoice forwards the locale tag + notifies', () async {
    String? gotLang;
    var notified = 0;
    final tts = TtsService(
      backend: _FakeBackend(),
      neural: NeuralTts(
        backend: _FakeBackend(),
        ready: () async => false,
        supported: () async => true,
        download: (lang) async {
          gotLang = lang;
          return true;
        },
      ),
    )..addListener(() => notified++);

    final ok = await tts.downloadNeuralVoice(const Locale('de'));
    expect(ok, isTrue);
    expect(gotLang, 'de-DE');
    expect(notified, greaterThanOrEqualTo(1));
  });
}

NeuralTts _holder(
  TtsBackend backend, {
  required bool ready,
  bool supported = true,
}) =>
    NeuralTts(
      backend: backend,
      ready: () async => ready,
      supported: () async => supported,
      download: (_) async => true,
    );
