// Native delivery. Desktop has a "Save as…" dialog; mobile (iOS/Android) has no
// save dialog, so getSaveLocation throws there — hand the file to the OS share
// sheet (AirDrop / Files / Messages …) instead. Web has its own implementation
// (browser download).

import 'package:comet_beat/shared/music_io/file_delivery_types.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Whether this platform delivers via the OS share sheet rather than a save
/// dialog — true on mobile, where no comfortable file picker exists. Driven by
/// [defaultTargetPlatform] so a test can pin it via `debugDefaultTargetPlatform`.
@visibleForTesting
bool deliveryUsesShareSheet() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// Deliver [bytes] to the user. On desktop, a native "Save as…" dialog
/// ([DeliveryKind.saved] / [DeliveryKind.cancelled]); on mobile, the OS share
/// sheet ([DeliveryKind.shared], or cancelled when dismissed).
Future<DeliveryResult> deliverBytes({
  required Uint8List bytes,
  required String suggestedName,
  required String label,
  required String extension,
  required String mimeType,
}) async {
  if (deliveryUsesShareSheet()) {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: mimeType, name: suggestedName),
        ],
        fileNameOverrides: [suggestedName],
      ),
    );
    return result.status == ShareResultStatus.success
        ? const DeliveryResult(DeliveryKind.shared)
        : const DeliveryResult(DeliveryKind.cancelled);
  }
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
