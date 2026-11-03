// lib/shared/music_io/deliver_export.dart
//
// One call for "hand these export bytes to the user and say what happened":
// [deliverBytes] picks the platform route (a Save dialog on desktop, the share
// sheet on iOS/Android, a browser download on the web), and this reports the
// outcome in a SnackBar — the saved path, "shared", nothing on a cancel, or the
// caller's failure message.
//
// Screens used to call file_selector's getSaveLocation directly. That exists
// only on desktop; on iOS, Android and the web it throws, so every one of
// those exports failed there with nothing but a "failed" snackbar. Route new
// exports through here rather than through getSaveLocation.

import 'package:comet_beat/shared/music_io/file_delivery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The MIME type a share sheet / browser download should carry for a file
/// with [extension] (no dot). Unknown types go out as raw bytes, which every
/// share target accepts.
String exportMimeType(String extension) => switch (extension.toLowerCase()) {
      'mid' || 'midi' => 'audio/midi',
      'musicxml' || 'xml' => 'application/vnd.recordare.musicxml+xml',
      'mxl' => 'application/vnd.recordare.musicxml',
      'abc' => 'text/vnd.abc',
      'pdf' => 'application/pdf',
      'json' || 'cbdaw' => 'application/json',
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      _ => 'application/octet-stream',
    };

/// Delivers [bytes] as [suggestedName] and shows the outcome on [messenger]:
/// [savedMessage] with the path when a file was written, [sharedMessage] when
/// it went to the share sheet or a download, nothing when the user cancelled,
/// and [failedMessage] when delivery threw. Returns how it was delivered, or
/// null on failure.
///
/// [label] names the file type in the desktop Save dialog; [extension] (no
/// dot) is its filter and, unless [mimeType] is given, picks the MIME type.
Future<DeliveryKind?> deliverExport(
  ScaffoldMessengerState messenger, {
  required Uint8List bytes,
  required String suggestedName,
  required String label,
  required String extension,
  String? mimeType,
  required String Function(String path) savedMessage,
  required String sharedMessage,
  required String failedMessage,
}) async {
  try {
    final result = await deliverBytes(
      bytes: bytes,
      suggestedName: suggestedName,
      label: label,
      extension: extension,
      mimeType: mimeType ?? exportMimeType(extension),
    );
    final message = switch (result.kind) {
      DeliveryKind.saved => savedMessage(result.path ?? ''),
      DeliveryKind.shared || DeliveryKind.downloaded => sharedMessage,
      DeliveryKind.cancelled => null, // a cancel is not an error
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    return result.kind;
  } catch (e, st) {
    debugPrint('[EXPORT] delivering $suggestedName failed: $e\n$st');
    messenger.showSnackBar(SnackBar(content: Text(failedMessage)));
    return null;
  }
}
