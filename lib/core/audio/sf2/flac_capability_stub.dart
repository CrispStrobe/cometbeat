import 'dart:typed_data';

class FlacPcm {
  const FlacPcm({
    required this.left,
    required this.right,
    required this.sampleRate,
  });

  final Float64List left;
  final Float64List? right;
  final int sampleRate;
}

typedef FlacDecode = FlacPcm? Function(Uint8List flac);

FlacDecode? loadGlintFlac({String? libraryPath}) => null;
