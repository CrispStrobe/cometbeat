// Web delivery: the browser has no filesystem, so hand the bytes to it as a
// download via an object-URL + a synthetic anchor click. This is what makes
// binary exports (PDF, MusicXML .mxl, MIDI, PNG, …) work on the web build,
// where the desktop save dialog is unavailable.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:comet_beat/shared/music_io/file_delivery_types.dart';
import 'package:web/web.dart' as web;

/// Trigger a browser download of [bytes] named [suggestedName]. Always reports
/// [DeliveryKind.downloaded] — the browser owns the rest of the flow.
Future<DeliveryResult> deliverBytes({
  required Uint8List bytes,
  required String suggestedName,
  required String label,
  required String extension,
  required String mimeType,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = suggestedName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return const DeliveryResult(DeliveryKind.downloaded);
}
