// Web / io-less stub: no filesystem, so streaming isn't possible — return false
// and let the caller bake the whole file in memory instead.
Future<bool> streamBytesToFile(
  String path,
  void Function(void Function(List<int> chunk) sink) produce,
) async =>
    false;
