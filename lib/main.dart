import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/services/settings_service.dart';
import 'core/services/sri_service.dart';
import 'features/home/screens/home_screen.dart';
import 'l10n/app_localizations.dart';
import 'shared/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KlangUniversumApp());
}

class KlangUniversumApp extends StatelessWidget {
  const KlangUniversumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SriService()..loadSriData(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsService()..load(),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) => MaterialApp(
          onGenerateTitle: (context) =>
              AppLocalizations.of(context)?.appTitle ?? 'KlangUniversum',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: settings.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
