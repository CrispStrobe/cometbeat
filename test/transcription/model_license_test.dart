// The non-permissive model-weight acceptance gate (BTC's CC-BY-NC-SA weights).
import 'package:comet_beat/core/audio/transcription/model_license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(resetModelLicenseAcceptance);
  tearDown(resetModelLicenseAcceptance);

  const spdx = 'CC-BY-NC-SA-4.0';

  test('unaccepted → not allowed, and requireModelLicense throws', () {
    expect(modelLicenseAccepted(spdx, env: const {}), isFalse);
    expect(
      () => requireModelLicense('BTC', spdx),
      throwsA(isA<ModelLicenseNotAccepted>()),
    );
  });

  test('COMET_ACCEPT_LICENSES with the exact SPDX accepts it', () {
    expect(
      modelLicenseAccepted(spdx, env: const {'COMET_ACCEPT_LICENSES': spdx}),
      isTrue,
    );
    // case/space tolerant, comma-separated
    expect(
      modelLicenseAccepted(
        spdx,
        env: const {'COMET_ACCEPT_LICENSES': 'mit, cc-by-nc-sa-4.0'},
      ),
      isTrue,
    );
  });

  test('"all" accepts any restrictive licence', () {
    expect(
      modelLicenseAccepted(spdx, env: const {'COMET_ACCEPT_LICENSES': 'all'}),
      isTrue,
    );
  });

  test('a different accepted SPDX does NOT accept this one', () {
    expect(
      modelLicenseAccepted(spdx, env: const {'COMET_ACCEPT_LICENSES': 'MIT'}),
      isFalse,
    );
  });

  test('programmatic acceptModelLicense (consent) accepts it', () {
    expect(modelLicenseAccepted(spdx, env: const {}), isFalse);
    acceptModelLicense(spdx);
    expect(modelLicenseAccepted(spdx, env: const {}), isTrue);
    expect(() => requireModelLicense('BTC', spdx), returnsNormally);
  });
}
