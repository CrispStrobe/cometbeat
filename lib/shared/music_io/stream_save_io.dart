import 'dart:io';

/// Streams bytes to [path] without holding the whole file in memory: opens a
/// sink and feeds it via [produce] (which calls the passed callback with each
/// chunk). Returns true on success. Native only.
Future<bool> streamBytesToFile(
  String path,
  void Function(void Function(List<int> chunk) sink) produce,
) async {
  final sink = File(path).openWrite();
  try {
    produce(sink.add);
    await sink.flush();
    return true;
  } finally {
    await sink.close();
  }
}
