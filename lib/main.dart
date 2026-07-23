import 'package:comet_beat/core/audio/tts/tts_neural.dart';
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/soundfont_persist.dart';
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
        ChangeNotifierProvider(
          create: (_) => TranscriptionConfigService()..load(),
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
        ChangeNotifierProvider(
          create: (_) => DawService(),
        ),
        ChangeNotifierProvider(
          create: (context) {
            // Prefer the neural (CrispASR/Kokoro) voice where it can run; the
            // platform voice (flutter_tts) covers everywhere else. Playback goes
            // through AudioService so the master sound switch still governs it.
            final audio = context.read<AudioService>();
            final neural = createNeuralTts(
              play: audio.playWavBytes,
              stopPlayback: audio.stop,
            );
            return TtsService(neural: neural);
          },
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          // Keep the audio voice + master sound switch in sync with settings.
          context.read<AudioService>()
            ..instrument = settings.instrument
            ..voice = settings.voice;
          context.read<AudioService>().soundOn = settings.soundOn;
          context.read<TtsService>().soundOn = settings.soundOn;
          _ensureLibraryVoiceResolved(settings);
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

/// Library voices persist as a `lib:<name>` id that [resolveVoiceSync] can't
/// build (it needs the InstrumentLibraryStore). On startup, resolve it ONCE per
/// id: load the store, find the saved instrument, and hand its built voice back
/// to settings (which pushes it to AudioService on the next rebuild).
final Set<String> _attemptedLibraryVoices = <String>{};

void _ensureLibraryVoiceResolved(SettingsService settings) {
  final name = libraryVoiceName(settings.voiceId);
  if (name == null ||
      settings.voice != null ||
      !_attemptedLibraryVoices.add(settings.voiceId)) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final items = await InstrumentLibraryStore().load();
    final matches = items.where((s) => s.name == name);
    if (matches.isEmpty) return;
    final inst =
        await resolveSavedVoice(matches.first); // handles soundfont_ref
    if (inst != null) {
      await settings.setVoiceId(settings.voiceId, resolvedVoice: inst);
    }
  });
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
