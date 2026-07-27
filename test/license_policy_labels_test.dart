// LicenseKind labels + the LicenseBlocked exception. The classifier itself is
// tested via the connector suites; these pin the per-kind UI label (every arm)
// and the blocked-exception message, which the coverage map flagged as gaps.
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every LicenseKind has its UI label', () {
    expect(LicenseKind.publicDomain.label, 'Public Domain');
    expect(LicenseKind.cc0.label, 'CC0');
    expect(LicenseKind.mit.label, 'MIT');
    expect(LicenseKind.apache2.label, 'Apache-2.0');
    expect(LicenseKind.bsd.label, 'BSD');
    expect(LicenseKind.ccBy.label, 'CC BY');
    expect(LicenseKind.ccBySa.label, 'CC BY-SA');
    expect(LicenseKind.ccByNc.label, 'CC BY-NC');
    expect(LicenseKind.ccByNd.label, 'CC BY-ND');
    expect(LicenseKind.allRightsReserved.label, 'All rights reserved');
    expect(LicenseKind.unknown.label, 'Unknown license');
  });

  test('kind predicates classify the families', () {
    expect(LicenseKind.cc0.isUnconditional, isTrue);
    expect(LicenseKind.mit.isUnconditional, isFalse);
    expect(LicenseKind.apache2.isPermissiveNotice, isTrue);
    expect(LicenseKind.ccBy.isPermissiveNotice, isFalse);
    expect(LicenseKind.ccBySa.needsAttribution, isTrue);
    expect(LicenseKind.ccByNc.needsAttribution, isFalse);
  });

  test('LicenseBlocked names the item and why it is blocked', () {
    final item = LibraryItem(
      sourceId: 's',
      sourceName: 'Src',
      id: 'i',
      title: 'A Proprietary Tune',
      composer: 'X',
      declaredLicense: 'All rights reserved',
      downloadUrl: Uri.parse('https://example.test/x.mid'),
      format: 'midi',
    );
    final ex = LicenseBlocked(item, LicenseKind.allRightsReserved);
    final s = ex.toString();
    expect(s, contains('A Proprietary Tune'));
    expect(s, contains('All rights reserved'));
    expect(s, contains('not permissive'));
  });
}
