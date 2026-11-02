// TtsService: narration gating, locale→voice mapping and NEURAL voice
// resolution / fallback / persistence, tested against a fake platform backend
// and a fake neural runtime (no `flutter_tts` channel, no libcrispasr).
import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_runtime.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Fake runtime: [installed] voice ids are "on disk"; [failSpeak] makes
/// synthesis throw; [unavailable] makes the engine report a load error.
class _FakeRuntime implements NeuralVoiceRuntime {
  _FakeRuntime({
    Set<String>? installed,
    this.unavailable,
    this.failSpeak = false,
    this.failDownload,
  }) : installed = installed ?? {};

  final Set<String> installed;
  String? unavailable;
  bool failSpeak;
  String? failDownload;
  final List<(String, String)> spoken = []; // (voice id, text)
  final List<String> downloaded = [];
  int stops = 0;

  @override
  Future<String?> unavailableReason() async => unavailable;

  @override
  Future<bool> isInstalled(NeuralVoice voice) async =>
      installed.contains(voice.id);

  @override
  Future<void> download(
    NeuralVoice voice, {
    TtsDownloadProgress? onProgress,
  }) async {
    onProgress?.call(1, 2);
    if (failDownload != null) {
      throw TtsVoiceException(TtsFailure.downloadFailed, failDownload!);
    }
    downloaded.add(voice.id);
    installed.add(voice.id);
    onProgress?.call(2, 2);
  }

  @override
  Future<void> remove(NeuralVoice voice) async => installed.remove(voice.id);

  @override
  Future<void> speak(NeuralVoice voice, String text) async {
    if (failSpeak) {
      throw const TtsVoiceException(TtsFailure.synthFailed, 'boom');
    }
    spoken.add((voice.id, text));
  }

  @override
  Future<void> stop() async => stops++;
}

const _de = Locale('de');
const _en = Locale('en');
const _thorsten = 'piper-de-thorsten-medium';
const _kerstin = 'piper-de-kerstin-low';
const _cori = 'piper-en-cori-medium';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  group('resolveNarrationVoice (pure)', () {
    final thorsten = neuralVoiceById(_thorsten)!;
    NarrationPlan plan(
      String choice, {
      String lang = 'de',
      String? unavailable,
      Set<String> installed = const {},
    }) =>
        resolveNarrationVoice(
          choice: choice,
          lang: lang,
          runtimeUnavailable: unavailable,
          installed: (v) => installed.contains(v.id),
        );

    test('device choice → device voice, no complaint', () {
      final p = plan(kNarrationVoiceDevice, installed: {_thorsten});
      expect(p.voice, isNull);
      expect(p.fallback, isNull);
    });

    test('an installed explicit choice is used', () {
      expect(plan(_thorsten, installed: {_thorsten}).voice, thorsten);
    });

    test('explicit choice not downloaded → device + notDownloaded', () {
      final p = plan(_thorsten);
      expect(p.voice, isNull);
      expect(p.fallback!.kind, TtsFailure.notDownloaded);
      expect(p.fallback!.voice, thorsten);
    });

    test('explicit choice with no engine → device + runtimeUnavailable', () {
      final p = plan(
        _thorsten,
        unavailable: 'dlopen failed',
        installed: {_thorsten},
      );
      expect(p.voice, isNull);
      expect(p.fallback!.kind, TtsFailure.runtimeUnavailable);
      expect(p.fallback!.detail, 'dlopen failed');
    });

    test('auto picks the first DOWNLOADED voice of the language', () {
      expect(
        plan(kNarrationVoiceAuto, installed: {_kerstin}).voice!.id,
        _kerstin,
      );
      // English voices never serve German text.
      expect(plan(kNarrationVoiceAuto, installed: {_cori}).voice, isNull);
    });

    test('auto with nothing downloaded → device voice, no complaint', () {
      final p = plan(kNarrationVoiceAuto);
      expect(p.voice, isNull);
      expect(p.fallback, isNull);
    });

    test('auto without an engine → device voice, no complaint', () {
      final p =
          plan(kNarrationVoiceAuto, unavailable: 'x', installed: {_kerstin});
      expect(p.voice, isNull);
      expect(p.fallback, isNull);
    });

    test('an unknown id behaves like auto', () {
      expect(plan('gone-voice', installed: {_thorsten}).voice, thorsten);
    });
  });

  group('neural narration', () {
    test('a chosen, downloaded voice is actually used (Thorsten)', () async {
      final platform = _FakeBackend();
      final rt = _FakeRuntime(installed: {_thorsten});
      final tts = TtsService(backend: platform, neural: rt);
      await tts.setVoiceChoice('de-DE', _thorsten);
      await tts.speak('Die Viertelnote', locale: _de);
      expect(rt.spoken, [(_thorsten, 'Die Viertelnote')]);
      expect(platform.spoken, isEmpty);
      expect(tts.lastNeuralVoice?.id, _thorsten);
      expect(tts.lastFallback, isNull);
    });

    test('auto uses a downloaded voice without any choice being made',
        () async {
      final platform = _FakeBackend();
      final rt = _FakeRuntime(installed: {_cori});
      final tts = TtsService(backend: platform, neural: rt);
      await tts.speak('A quarter note', locale: _en);
      expect(rt.spoken.single.$1, _cori);
      expect(platform.spoken, isEmpty);
    });

    test('chosen but not downloaded → device voice + visible reason', () async {
      final platform = _FakeBackend();
      final rt = _FakeRuntime();
      final tts = TtsService(backend: platform, neural: rt);
      await tts.setVoiceChoice('de', _thorsten);
      await tts.speak('Hallo', locale: _de);
      expect(platform.spoken, [('Hallo', 'de-DE')]);
      expect(tts.lastFallback!.kind, TtsFailure.notDownloaded);
      expect(tts.lastFallback!.voice.id, _thorsten);
    });

    test('engine missing → device voice + the load error as the reason',
        () async {
      final platform = _FakeBackend();
      final rt =
          _FakeRuntime(installed: {_thorsten}, unavailable: 'image not found');
      final tts = TtsService(backend: platform, neural: rt);
      await tts.setVoiceChoice('de', _thorsten);
      await tts.speak('Hallo', locale: _de);
      expect(platform.spoken, [('Hallo', 'de-DE')]);
      expect(tts.lastFallback!.kind, TtsFailure.runtimeUnavailable);
      expect(tts.lastFallback!.detail, 'image not found');
    });

    test('a synthesis failure still speaks (device) and says why', () async {
      final platform = _FakeBackend();
      final rt = _FakeRuntime(installed: {_thorsten}, failSpeak: true);
      final tts = TtsService(backend: platform, neural: rt);
      await tts.setVoiceChoice('de', _thorsten);
      await tts.speak('Hallo', locale: _de);
      expect(platform.spoken, [('Hallo', 'de-DE')]);
      expect(tts.lastFallback!.kind, TtsFailure.synthFailed);
      expect(tts.lastFallback!.detail, 'boom');
      // Next success clears the note.
      rt.failSpeak = false;
      await tts.speak('Hallo', locale: _de);
      expect(tts.lastFallback, isNull);
    });

    test('device choice never touches the neural runtime', () async {
      final platform = _FakeBackend();
      final rt = _FakeRuntime(installed: {_thorsten});
      final tts = TtsService(backend: platform, neural: rt);
      await tts.setVoiceChoice('de', kNarrationVoiceDevice);
      await tts.speak('Hallo', locale: _de);
      expect(rt.spoken, isEmpty);
      expect(platform.spoken.single.$1, 'Hallo');
      expect(tts.lastFallback, isNull);
    });

    test('no runtime (web) → device voice, hasNeural false', () async {
      final platform = _FakeBackend();
      final tts = TtsService(backend: platform);
      expect(tts.hasNeural, isFalse);
      expect(await tts.neuralUnavailableReason(), isNotNull);
      await tts.speak('Hi', locale: _en);
      expect(platform.spoken.single.$1, 'Hi');
    });
  });

  group('lesson override', () {
    test('lessons follow Settings until overridden, then use the override',
        () async {
      final rt = _FakeRuntime(installed: {_thorsten, _kerstin});
      final tts = TtsService(backend: _FakeBackend(), neural: rt);
      await tts.setVoiceChoice('de', _thorsten);
      await tts.speak('a', locale: _de, scope: NarrationScope.lesson);
      expect(rt.spoken.last.$1, _thorsten);

      await tts.setVoiceChoice('de', _kerstin, scope: NarrationScope.lesson);
      await tts.speak('b', locale: _de, scope: NarrationScope.lesson);
      expect(rt.spoken.last.$1, _kerstin);
      // Global narration is unaffected by the lesson override.
      await tts.speak('c', locale: _de);
      expect(rt.spoken.last.$1, _thorsten);

      // Clearing the override → lessons follow Settings again.
      await tts.setVoiceChoice('de', null, scope: NarrationScope.lesson);
      expect(tts.lessonVoiceOverride('de'), isNull);
      await tts.speak('d', locale: _de, scope: NarrationScope.lesson);
      expect(rt.spoken.last.$1, _thorsten);
    });

    test('global + lesson choices persist and reload', () async {
      final tts = TtsService(backend: _FakeBackend(), neural: _FakeRuntime());
      await tts.setVoiceChoice('de-DE', _thorsten);
      await tts.setVoiceChoice('de-DE', _kerstin, scope: NarrationScope.lesson);
      await tts.setVoiceChoice('en-US', kNarrationVoiceDevice);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_voice_choice_de'), _thorsten);
      expect(prefs.getString('tts_lesson_voice_de'), _kerstin);

      final again = TtsService(backend: _FakeBackend(), neural: _FakeRuntime());
      await again.loadNarrationPrefs();
      expect(again.globalVoiceChoice('de'), _thorsten);
      expect(again.lessonVoiceOverride('de'), _kerstin);
      expect(
        again.voiceChoice('de', scope: NarrationScope.lesson),
        _kerstin,
      );
      expect(again.globalVoiceChoice('en'), kNarrationVoiceDevice);
      expect(again.lessonVoiceOverride('en'), isNull);
    });
  });

  group('downloads', () {
    test('success marks the voice installed and clears progress', () async {
      final rt = _FakeRuntime();
      final tts = TtsService(backend: _FakeBackend(), neural: rt);
      final v = neuralVoiceById(_thorsten)!;
      final ok = await tts.downloadVoice(v);
      expect(ok, isTrue);
      expect(rt.downloaded, [_thorsten]);
      expect(tts.isInstalledCached(_thorsten), isTrue);
      expect(tts.downloadProgress(_thorsten), isNull);
      expect(tts.downloadError(_thorsten), isNull);
    });

    test('a failure is surfaced with its cause, not swallowed', () async {
      final rt = _FakeRuntime(failDownload: 'HTTP 404 for https://x');
      final tts = TtsService(backend: _FakeBackend(), neural: rt);
      final ok = await tts.downloadVoice(neuralVoiceById(_thorsten)!);
      expect(ok, isFalse);
      expect(tts.downloadError(_thorsten), 'HTTP 404 for https://x');
      expect(tts.isInstalledCached(_thorsten), isFalse);
      expect(tts.downloadProgress(_thorsten), isNull);
    });
  });
}
