// About screen — renders the header, the Impressum/contact/privacy/disclaimer/
// credits sections, and the open-source-licenses button.

import 'package:comet_beat/features/settings/screens/about_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

Widget _app() => const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('en'), Locale('de')],
      home: AboutScreen(),
    );

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'CometBeat',
      packageName: 'com.crispstrobe.cometBeat',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('renders the sections and the licenses button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.aboutProvider), findsOneWidget);
    expect(find.text(l10n.aboutContact), findsOneWidget);
    expect(find.text(l10n.aboutPrivacy), findsOneWidget);
    expect(find.text(l10n.aboutDisclaimer), findsOneWidget);
    expect(find.text(l10n.aboutCredits), findsOneWidget);
    expect(find.text(l10n.aboutOpenSourceLicenses), findsOneWidget);
    // Contact email + phone are shown as tappable links.
    expect(find.text('postmaster@crispstro.be'), findsOneWidget);
    expect(find.text('+49 176 6421 8601'), findsOneWidget);
  });
}
