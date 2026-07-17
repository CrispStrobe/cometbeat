// test/custom_licenses_test.dart
//
// Proves the compliance fix: after ensureCustomLicensesRegistered(), the
// bundled Bravura (OFL) font license is present in the LicenseRegistry, so it
// shows up on showLicensePage() alongside the auto-discovered pub licenses.

import 'package:comet_beat/core/services/custom_licenses_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers the Bravura OFL font license', () async {
    await ensureCustomLicensesRegistered();

    final entries = await LicenseRegistry.licenses.toList();
    final bravura = entries.where(
      (e) => e.packages.contains('Bravura (SMuFL music font)'),
    );
    expect(bravura, isNotEmpty, reason: 'Bravura license should be registered');

    // And the actual OFL text should have come through (not just the header).
    final text = bravura.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License'));
  });
}
