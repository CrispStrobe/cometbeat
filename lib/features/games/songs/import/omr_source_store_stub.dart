// Web stub: no filesystem, and no OMR to feed either, so retained scans are a
// no-op. Signatures match `_io` so the facade presents one surface.
import 'dart:typed_data';

/// Unused on web; present so the facade surface matches `_io`.
String Function()? debugOmrSourcesDirOverride;

Future<bool> saveOmrSource(String songId, Uint8List bytes) async => false;

Future<Uint8List?> loadOmrSource(String songId) async => null;

Future<void> deleteOmrSource(String songId) async {}
