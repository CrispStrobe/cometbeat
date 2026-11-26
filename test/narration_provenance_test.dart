import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/narration_provenance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wav_chunks.dart';

Uint8List sampleWav() {
  final wav = Uint8List(50);
  wav.setRange(0, 4, ascii.encode('RIFF'));
  wav.setRange(8, 16, ascii.encode('WAVEfmt '));
  wav.setRange(36, 40, ascii.encode('data'));
  final header = ByteData.sublistView(wav);
  header.setUint32(4, wav.length - 8, Endian.little);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 22050, Endian.little);
  header.setUint32(28, 44100, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  header.setUint32(40, 6, Endian.little);
  wav.setRange(44, 50, [0, 0, 255, 127, 0, 128]);
  return wav;
}

void main() {
  test('synthetic narration carries an honest, portable unsigned receipt', () {
    final original = sampleWav();
    final marked = markSyntheticNarrationWav(
      original,
      engine: 'piper-dart',
      model: 'voice.onnx',
      voice: 'voice-medium',
      language: 'de',
      generatedAt: DateTime.utc(2026, 11, 26),
    );

    final chunks = wavChunks(marked);
    expect(chunks['data'], wavChunks(original)['data']);
    expect(chunks['fmt '], wavChunks(original)['fmt ']);
    expect(original.length, 50); // Caller retains its unmodified source WAV.
    final receipt = narrationReceipt(marked);
    expect(receipt, {
      'schema': 'urn:cometbeat:synthetic-narration:1',
      'generator': 'CometBeat',
      'content_type': 'synthetic-speech',
      'ai_generated': true,
      'text_origin': 'supplied-text',
      'provider': 'local',
      'engine': 'piper-dart',
      'model': 'voice.onnx',
      'voice': 'voice-medium',
      'language': 'de',
      'generated_at': '2026-11-26T00:00:00.000Z',
      'signature': 'unsigned',
    });
    expect(chunks.containsKey('c2pa'), isFalse);
    expect(
      utf8.decode(chunks['LIST']!),
      contains('AI-generated synthetic narration'),
    );
    expect(receipt.containsKey('text'), isFalse);
    expect(receipt.containsKey('user'), isFalse);
  });

  test('RIFF odd-byte padding and offset views remain readable', () {
    for (final model in ['a', 'ab']) {
      final source = sampleWav();
      final storage = Uint8List(source.length + 9)
        ..setRange(9, source.length + 9, source);
      final marked = markSyntheticNarrationWav(
        Uint8List.sublistView(storage, 9),
        engine: 'test',
        model: model,
        voice: 'test',
        language: 'en',
        generatedAt: DateTime.utc(2026),
      );
      expect(narrationReceipt(marked)['model'], model);
      expect(wavChunks(marked)['data'], wavChunks(source)['data']);
    }
  });

  test('non-WAV input cannot silently acquire a narration claim', () {
    expect(
      () => markSyntheticNarrationWav(
        Uint8List(50),
        engine: 'test',
        model: 'test',
        voice: 'test',
        language: 'en',
      ),
      throwsFormatException,
    );
  });
}
