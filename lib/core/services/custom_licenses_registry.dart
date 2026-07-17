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
// - Petaluma, Leland and Leipzig (all SIL OFL 1.1) are bundled by THIS app
//   (assets/smufl/, as selectable notation faces), so the app registers them here.

import 'package:crisp_notation/crisp_notation.dart'
    show registerBundledFontLicenses;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Register the licenses for fonts this app (transitively) bundles. Idempotent.
Future<void> ensureCustomLicensesRegistered() async {
  registerBundledFontLicenses(); // Bravura (SIL OFL 1.1), owned by crisp_notation.
  _registerAppBundledOfl();
}

bool _appOflRegistered = false;

/// The app-bundled OFL faces: display name → the OFL text asset.
const _bundledOfl = <String, String>{
  'Petaluma': 'assets/smufl/PETALUMA-OFL.txt',
  'Leland': 'assets/smufl/LELAND-OFL.txt',
  'Leipzig': 'assets/smufl/LEIPZIG-OFL.txt',
};

void _registerAppBundledOfl() {
  if (_appOflRegistered) return;
  _appOflRegistered = true;
  _bundledOfl.forEach((name, asset) {
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle.loadString(asset);
      yield LicenseEntryWithLineBreaks([name], text);
    });
  });
}
