import 'dart:io';

import 'package:path_provider/path_provider.dart';

// audioplayers writes BytesSource data to a platform temporary directory on
// these platforms, but does not create missing parent directories itself.
Future<void> prepareAudioCacheDirectory({
  Future<Directory> Function()? temporaryDirectory,
}) async {
  if (temporaryDirectory == null &&
      !Platform.isMacOS &&
      !Platform.isIOS &&
      !Platform.isLinux) {
    return;
  }
  final directory = await (temporaryDirectory ?? getTemporaryDirectory)();
  await directory.create(recursive: true);
}
