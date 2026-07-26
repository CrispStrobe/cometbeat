// The cross-platform export delivery helper (io path): a native "Save as…"
// dialog writes the bytes to the chosen path, and a dismissed dialog reports
// cancelled. The web path (browser download) needs a DOM and is exercised by the
// web build, not here.

import 'dart:io';

import 'package:comet_beat/shared/music_io/file_delivery.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeSaver extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  _FakeSaver(this._path);
  final String? _path;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    SaveDialogOptions? options,
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    String? confirmButtonText,
  }) async =>
      _path == null ? null : FileSaveLocation(_path);
}

void main() {
  // The save-dialog path is desktop behaviour; pin a desktop platform so the
  // flutter_test default (android) doesn't route these through the share sheet.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('mobile delivers via the share sheet, desktop via the save dialog', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = p;
      expect(deliveryUsesShareSheet(), isTrue, reason: '$p');
    }
    for (final p in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(deliveryUsesShareSheet(), isFalse, reason: '$p');
    }
  });

  test('deliverBytes writes to the chosen path and reports saved', () async {
    final dir = Directory.systemTemp.createTempSync('deliver');
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = '${dir.path}/out.mid';
    FileSelectorPlatform.instance = _FakeSaver(out);

    final res = await deliverBytes(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      suggestedName: 'out.mid',
      label: 'MIDI',
      extension: 'mid',
      mimeType: 'audio/midi',
    );

    expect(res.kind, DeliveryKind.saved);
    expect(res.path, out);
    expect(File(out).readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('deliverBytes reports cancelled when the dialog is dismissed', () async {
    FileSelectorPlatform.instance = _FakeSaver(null);

    final res = await deliverBytes(
      bytes: Uint8List.fromList([9]),
      suggestedName: 'x.pdf',
      label: 'PDF',
      extension: 'pdf',
      mimeType: 'application/pdf',
    );

    expect(res.kind, DeliveryKind.cancelled);
    expect(res.path, isNull);
  });
}
