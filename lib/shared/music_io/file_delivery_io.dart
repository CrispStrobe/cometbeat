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

/// Whether [chooseSavePath] can hand back a filesystem path here — true where a
/// native save dialog exists (desktop). Callers that must write the file
/// themselves (streaming a long WAV straight to disk) check this first and use
/// [deliverBytes] everywhere else.
bool deliveryHasSavePath() => !deliveryUsesShareSheet();

/// Asks the user where to save [suggestedName]; null when they cancelled.
/// Desktop only — see [deliveryHasSavePath].
Future<String?> chooseSavePath({
  required String suggestedName,
  required String label,
  required String extension,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: [extension]),
    ],
  );
  return location?.path;
}

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
  final path = await chooseSavePath(
    suggestedName: suggestedName,
    label: label,
    extension: extension,
  );
  if (path == null) return const DeliveryResult(DeliveryKind.cancelled);
  await XFile.fromData(bytes, mimeType: mimeType, name: suggestedName)
      .saveTo(path);
  return DeliveryResult(DeliveryKind.saved, path: path);
}
