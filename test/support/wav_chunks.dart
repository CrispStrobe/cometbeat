import 'dart:convert';
import 'dart:typed_data';

/// Reads the RIFF chunk table independently of the narration encoder.
Map<String, Uint8List> wavChunks(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  if (ascii.decode(wav.sublist(0, 4)) != 'RIFF' ||
      ascii.decode(wav.sublist(8, 12)) != 'WAVE' ||
      data.getUint32(4, Endian.little) != wav.length - 8) {
    throw const FormatException('Invalid RIFF header');
  }
  final result = <String, Uint8List>{};
  var offset = 12;
  while (offset < wav.length) {
    if (offset + 8 > wav.length) {
      throw const FormatException('Truncated chunk header');
    }
    final id = ascii.decode(wav.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final end = offset + 8 + size;
    if (end + (size.isOdd ? 1 : 0) > wav.length) {
      throw const FormatException('Truncated chunk payload');
    }
    result[id] = Uint8List.sublistView(wav, offset + 8, end);
    offset = end + (size.isOdd ? 1 : 0);
  }
  return result;
}

Map<String, dynamic> narrationReceipt(Uint8List wav) =>
    jsonDecode(utf8.decode(wavChunks(wav)['cbpr']!)) as Map<String, dynamic>;
