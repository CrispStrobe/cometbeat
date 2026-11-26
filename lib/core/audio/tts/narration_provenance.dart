import 'dart:convert';
import 'dart:typed_data';

/// Marks a WAV immediately after neural speech synthesis. This is an unsigned
/// application receipt, not a C2PA signature or a statistical watermark.
///
/// Call only for audio the caller just synthesised. Importing an old clip, a
/// recording, a composition or a DSP render does not establish its AI origin.
/// The input text, filesystem paths and user identity are deliberately absent.
Uint8List markSyntheticNarrationWav(
  Uint8List wav, {
  required String engine,
  required String model,
  required String voice,
  required String language,
  DateTime? generatedAt,
}) {
  if (wav.length < 12 ||
      ascii.decode(wav.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
      ascii.decode(wav.sublist(8, 12), allowInvalid: true) != 'WAVE') {
    throw const FormatException('Narration provenance requires a RIFF WAV');
  }
  final receipt = <String, Object>{
    'schema': 'urn:cometbeat:synthetic-narration:1',
    'generator': 'CometBeat',
    'content_type': 'synthetic-speech',
    'ai_generated': true,
    'text_origin': 'supplied-text',
    'provider': 'local',
    'engine': engine,
    'model': model,
    'voice': voice,
    'language': language,
    'generated_at': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'signature': 'unsigned',
  };
  final info = BytesBuilder(copy: false)..add(ascii.encode('INFO'));
  for (final entry in <String, String>{
    'ISFT': 'CometBeat',
    'ICMT': 'AI-generated synthetic narration of supplied text; '
        'unsigned application metadata.',
    'IART': model,
    'IGNR': 'Synthetic narration',
  }.entries) {
    info.add(_chunk(entry.key, [...utf8.encode(entry.value), 0]));
  }
  final out = (BytesBuilder(copy: false)
        ..add(wav)
        ..add(_chunk('LIST', info.takeBytes()))
        ..add(_chunk('cbpr', utf8.encode(jsonEncode(receipt)))))
      .takeBytes();
  ByteData.sublistView(out).setUint32(4, out.length - 8, Endian.little);
  return out;
}

Uint8List _chunk(String id, List<int> payload) {
  final out = Uint8List(8 + payload.length + (payload.length.isOdd ? 1 : 0));
  out.setRange(0, 4, ascii.encode(id));
  ByteData.sublistView(out).setUint32(4, payload.length, Endian.little);
  out.setRange(8, 8 + payload.length, payload);
  return out;
}
