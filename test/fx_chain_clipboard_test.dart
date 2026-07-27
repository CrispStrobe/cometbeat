// F3 — the chain string as a copy/paste preset, which closes the loop the whole
// arc was built on.
//
// The codec has always been able to print a chain and read one back; what was
// missing was any way to get the text OUT of the app or INTO it. Without these
// two buttons the CLI and the GUI shared a format they could never actually
// exchange, so the interesting assertion here is the round trip through the
// real clipboard: copy from a chain in the app, paste it back, get the same
// chain — and the same text a terminal would have accepted.

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Future<void> _pumpDaw(WidgetTester tester) => pumpGame(
      tester,
      const DawScreen(),
      extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
    );

DawService _service(WidgetTester tester) => Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A fake clipboard, since the real platform channel is not available in a
  /// widget test.
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return clipboard == null ? null : {'text': clipboard};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> openMasterFx(WidgetTester tester) async {
    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
  }

  testWidgets('copying a chain puts the CLI text on the clipboard',
      (tester) async {
    await _pumpDaw(tester);
    final service = _service(tester);
    service.setMasterEffects([
      defaultDawClipEffect(DawClipEffectType.highpass)
          .copyWith(params: {'freq': 120, 'q': 0.707, 'mix': 1}),
      defaultDawClipEffect(DawClipEffectType.reverb),
    ]);
    await tester.pumpAndSettle();

    await openMasterFx(tester);
    await tester.tap(find.byTooltip('Copy chain'));
    await tester.pumpAndSettle();

    // Exactly what `--chain` would take, and only what differs from defaults.
    expect(clipboard, 'highpass freq=120 | reverb');
  });

  testWidgets('pasting a chain replaces the rack', (tester) async {
    await _pumpDaw(tester);
    final service = _service(tester);
    expect(service.masterEffects(), isEmpty);

    clipboard = 'lowpass freq=800 | limiter ceilingDb=-6';
    await openMasterFx(tester);
    await tester.tap(find.byTooltip('Paste chain'));
    await tester.pumpAndSettle();

    final chain = service.masterEffects();
    expect(chain.map((f) => f.type), [
      DawClipEffectType.lowpass,
      DawClipEffectType.limiter,
    ]);
    expect(chain.first.params['freq'], 800);
    expect(chain.last.params['ceilingDb'], -6);
  });

  testWidgets('copy → paste is a round trip', (tester) async {
    // The property that makes the format worth sharing between the two faces.
    await _pumpDaw(tester);
    final service = _service(tester);
    final original = [
      defaultDawClipEffect(DawClipEffectType.tilt)
          .copyWith(params: {'tiltDb': 6, 'pivotHz': 1000, 'mix': 1}),
      defaultDawClipEffect(DawClipEffectType.compressor),
      defaultDawClipEffect(DawClipEffectType.limiter),
    ];
    service.setMasterEffects(original);
    await tester.pumpAndSettle();

    await openMasterFx(tester);
    await tester.tap(find.byTooltip('Copy chain'));
    await tester.pumpAndSettle();

    service.setMasterEffects(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste chain'));
    await tester.pumpAndSettle();

    final back = service.masterEffects();
    expect(back.map((f) => f.type), original.map((f) => f.type));
    for (var i = 0; i < original.length; i++) {
      expect(back[i].params, original[i].params, reason: 'effect $i');
    }
  });

  testWidgets('pasting nonsense reports it instead of doing nothing',
      (tester) async {
    // The user just pasted something they believed was a chain; silence would
    // read as "the button is broken".
    await _pumpDaw(tester);
    clipboard = 'this is not a chain';
    await openMasterFx(tester);
    await tester.tap(find.byTooltip('Paste chain'));
    await tester.pumpAndSettle();

    expect(_service(tester).masterEffects(), isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('copying an automated chain warns that automation is dropped',
      (tester) async {
    // The one thing the string form cannot carry. An obligation to say so:
    // silently losing an automation curve on a copy/paste would be discovered
    // much later, after the user had edited the pasted copy.
    await _pumpDaw(tester);
    _service(tester).setMasterEffects([
      defaultDawClipEffect(DawClipEffectType.gain).copyWith(
        automation: {
          'gainDb': const [DawAutomationPoint(ms: 0, value: -6)],
        },
      ),
    ]);
    await tester.pumpAndSettle();

    await openMasterFx(tester);
    await tester.tap(find.byTooltip('Copy chain'));
    await tester.pumpAndSettle();

    expect(find.textContaining('automation is not copied'), findsOneWidget);
  });

  testWidgets('the copy button is disabled on an empty rack', (tester) async {
    await _pumpDaw(tester);
    await openMasterFx(tester);
    // Every scope that offers the action has one of these (master, track), and
    // with nothing anywhere to copy they must ALL be disabled — asserting on
    // the set rather than picking one avoids depending on which editors happen
    // to be built.
    final buttons = tester.widgetList<IconButton>(
      find.widgetWithIcon(IconButton, Icons.content_copy),
    );
    expect(buttons, isNotEmpty);
    for (final button in buttons) {
      expect(button.onPressed, isNull);
    }
  });

  test('the service replaces a chain undoably, and clones it', () {
    final service = DawService();
    final chain = [defaultDawClipEffect(DawClipEffectType.reverb)];
    service.setMasterEffects(chain);
    expect(service.masterEffects(), hasLength(1));

    // Cloned: mutating the caller's list must not reach the timeline.
    chain.add(defaultDawClipEffect(DawClipEffectType.delay));
    expect(service.masterEffects(), hasLength(1));

    service.undo();
    expect(service.masterEffects(), isEmpty);
  });
}
