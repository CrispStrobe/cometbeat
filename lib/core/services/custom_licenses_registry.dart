// lib/core/services/custom_licenses_registry.dart
//
// Ensures asset-bundled font licenses appear on showLicensePage(). Flutter's
// license page auto-discovers each *pub package*'s LICENSE file but not fonts
// shipped as assets, so those must be registered via LicenseRegistry.addLicense.
//
// - Bravura (OFL) is bundled by the crisp_notation package, which owns its
//   registration (crisp_notation's MusicFonts.load calls it on first render). We call
//   it here too so the license page is complete even if opened from Settings
//   before any notation has rendered.
// - Petaluma (OFL) is bundled by THIS app (assets/smufl/, for the "Handwritten
//   notes" theme), so the app registers it here.

import 'package:crisp_notation/crisp_notation.dart'
    show registerBundledFontLicenses;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Register the licenses for fonts this app (transitively) bundles. Idempotent.
Future<void> ensureCustomLicensesRegistered() async {
  registerBundledFontLicenses(); // Bravura (SIL OFL 1.1), owned by crisp_notation.
  _registerPetalumaOfl();
}

bool _petalumaRegistered = false;

void _registerPetalumaOfl() {
  if (_petalumaRegistered) return;
  _petalumaRegistered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/smufl/PETALUMA-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Petaluma'], text);
  });
}
