import 'package:comet_beat/core/audio/tts/tts_engine.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A platform-voice backend fake: records applyVoice + speak calls and serves a
/// fixed voice list, so the picker/persistence wiring is tested with no plugin.
class _FakePlatformBackend implements TtsBackend, PlatformVoiceControl {
  _FakePlatformBackend(this._voices);
  final List<TtsVoiceOption> _voices;
  final List<TtsVoiceOption?> appliedVoices = [];
  final List<String> spoken = [];

  @override
  Future<List<TtsVoiceOption>> availableVoices(String langPrefix) async =>
      _voices.where((v) => v.locale.startsWith(langPrefix)).toList();

  @override
  Future<void> applyVoice(TtsVoiceOption? voice) async =>
      appliedVoices.add(voice);

  @override
  Future<void> speak(String text, {required String langCode}) async =>
      spoken.add('$langCode:$text');

  @override
  Future<void> stop() async {}
}

void main() {
  const de = Locale('de');
  const samantha = TtsVoiceOption(name: 'Samantha', locale: 'en-US');
  const anna = TtsVoiceOption(name: 'Anna', locale: 'de-DE');
  const petra = TtsVoiceOption(name: 'Petra', locale: 'de-DE');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('TtsVoiceOption round-trips through encode/decode', () {
    expect(TtsVoiceOption.decode(anna.encode()), anna);
    expect(TtsVoiceOption.decode(null), isNull);
    expect(TtsVoiceOption.decode('not json'), isNull);
    // A name with tricky characters survives.
    const tricky =
        TtsVoiceOption(name: 'com.apple.voice x-y.z', locale: 'en-GB');
    expect(TtsVoiceOption.decode(tricky.encode()), tricky);
  });

  test('narrationVoices delegates to the platform backend, filtered by lang',
      () async {
    final tts =
        TtsService(backend: _FakePlatformBackend([samantha, anna, petra]));
    expect(await tts.narrationVoices('de-DE'), [anna, petra]);
    expect(await tts.narrationVoices('en-US'), [samantha]);
  });

  test('choosing a voice persists and is applied before speaking', () async {
    final backend = _FakePlatformBackend([anna, petra]);
    final tts = TtsService(backend: backend);

    await tts.chooseNarrationVoice('de-DE', petra);
    expect(tts.chosenNarrationVoice('de-DE'), petra);

    await tts.speak('Hallo', locale: de);
    expect(backend.appliedVoices.last, petra);
    expect(backend.spoken.single, 'de-DE:Hallo');

    // Persisted?
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts_voice_de'), petra.encode());
  });

  test('loadNarrationPrefs restores the persisted voice + engine choice',
      () async {
    SharedPreferences.setMockInitialValues({
      'tts_voice_de': petra.encode(),
      'tts_engine': TtsEngine.platform.name,
    });
    final tts = TtsService(backend: _FakePlatformBackend([anna, petra]));
    await tts.loadNarrationPrefs();
    expect(tts.chosenNarrationVoice('de-DE'), petra);
    expect(tts.preferredEngine, TtsEngine.platform);
  });

  test('clearing the choice (null) removes it + falls back to OS default',
      () async {
    final backend = _FakePlatformBackend([anna, petra]);
    final tts = TtsService(backend: backend);
    await tts.chooseNarrationVoice('de-DE', petra);
    await tts.chooseNarrationVoice('de-DE', null);
    expect(tts.chosenNarrationVoice('de-DE'), isNull);

    await tts.speak('Hallo', locale: de);
    expect(backend.appliedVoices.last, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts_voice_de'), isNull);
  });

  test('preferredEngine setter persists', () async {
    final tts = TtsService(backend: _FakePlatformBackend(const []));
    tts.preferredEngine = TtsEngine.platform;
    // The setter fires a fire-and-forget write; give it a microtask turn.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts_engine'), TtsEngine.platform.name);
  });
}
