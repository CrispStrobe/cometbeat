// Desktop/native delivery: the platform "Save as…" dialog, then write the bytes
// to the chosen path. Mobile has no save dialog, so getSaveLocation throws there
// and the caller falls back (e.g. copy-to-clipboard for text formats).

import 'dart:typed_data';

import 'package:comet_beat/shared/music_io/file_delivery_types.dart';
import 'package:file_selector/file_selector.dart';

/// Save [bytes] via a native "Save as…" dialog. Returns [DeliveryKind.saved]
/// with the path, or [DeliveryKind.cancelled] if the user dismissed the dialog.
Future<DeliveryResult> deliverBytes({
  required Uint8List bytes,
  required String suggestedName,
  required String label,
  required String extension,
  required String mimeType,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: [extension]),
    ],
  );
  if (location == null) return const DeliveryResult(DeliveryKind.cancelled);
  await XFile.fromData(
    bytes,
    mimeType: mimeType,
    name: suggestedName,
  ).saveTo(location.path);
  return DeliveryResult(DeliveryKind.saved, path: location.path);
}
