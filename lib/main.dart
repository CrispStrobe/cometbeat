import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/theme.dart';
import 'package:crisp_notation/crisp_notation.dart' show Bravura;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Per the crisp_notation contract (CONTRACT.md §6): await the SMuFL metadata
  // up front so the first StaffView frame is never empty.
  await Bravura.load();
  // Real app only: auto-pop a game's first-run tutorial (off by default so it
  // never interrupts widget tests, which don't run main()).
  autoShowTutorials = true;
  runApp(const CometBeatApp());
}

class CometBeatApp extends StatelessWidget {
  const CometBeatApp({super.key});

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
        Provider<AudioService>(
          // Route playback to the speaker up front (see configurePlaybackRoute:
          // guards against the mic leaving the session on the quiet earpiece).
          create: (_) => AudioService()..configurePlaybackRoute(),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProgressService()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => UserSongsService()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => DebugService()..load(),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          // Keep the audio voice + master sound switch in sync with settings.
          context.read<AudioService>().instrument = settings.instrument;
          context.read<AudioService>().soundOn = settings.soundOn;
          return MaterialApp(
            onGenerateTitle: (context) =>
                AppLocalizations.of(context)?.appTitle ?? 'CometBeat',
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
            home: const _StartupRouter(),
          );
        },
      ),
    );
  }
}

/// Shows the home screen; on web, a `?game=<gameId>` query parameter opens
/// that game directly — deep links for testing and sharing.
class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gameId = Uri.base.queryParameters['game'];
      if (gameId == null || !mounted) return;
      for (final games in kGamesByModule.values) {
        for (final game in games) {
          if (game.id == gameId) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: game.builder));
            return;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
