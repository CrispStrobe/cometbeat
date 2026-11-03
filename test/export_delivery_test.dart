// Exports reach the user on every platform.
//
// The Tracker (and the Tab Workshop, and the Audio Editor's project save)
// called file_selector's getSaveLocation directly. That only exists on
// desktop: on iOS, Android and the web it throws, so every one of those
// exports ended in a "failed" snackbar there. They now go through
// [deliverExport], which picks a Save dialog on desktop, the share sheet on
// mobile and a download on the web — the route Loop Studio already used.

import 'dart:io';

import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/deliver_export.dart';
import 'package:comet_beat/shared/music_io/file_delivery.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

class _FakeSaver extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  _FakeSaver(this.path);
  final String path;
  int asked = 0;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    SaveDialogOptions? options,
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    String? confirmButtonText,
  }) async {
    asked++;
    return FileSaveLocation(path);
  }
}

/// Stands in for the OS share sheet (and the temp dir share_plus writes the
/// file to). Records the paths of every file handed to it.
List<String> _mockShareSheet(Directory tmp) {
  final shared = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tmp.path,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      shared.addAll([for (final p in args['paths']! as List) p as String]);
      return 'dev.fluttercommunity.plus/share/success';
    },
  );
  addTearDown(() {
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        null,
      );
  });
  return shared;
}

Future<ScaffoldMessengerState> _messenger(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: SizedBox.expand())),
  );
  return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'desktop: a Save dialog, and the saved path is reported',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('deliver-export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/tracker.mid';
      final saver = _FakeSaver(out);
      FileSelectorPlatform.instance = saver;
      final messenger = await _messenger(tester);

      DeliveryKind? kind;
      await tester.runAsync(() async {
        kind = await deliverExport(
          messenger,
          bytes: Uint8List.fromList([1, 2, 3]),
          suggestedName: 'tracker.mid',
          label: 'MIDI',
          extension: 'mid',
          savedMessage: (p) => 'saved $p',
          sharedMessage: 'shared',
          failedMessage: 'failed',
        );
      });
      await tester.pump();

      expect(kind, DeliveryKind.saved);
      expect(saver.asked, 1);
      expect(File(out).readAsBytesSync(), [1, 2, 3]);
      expect(find.text('saved $out'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'mobile: the share sheet, never the desktop-only Save dialog',
    (tester) async {
      final tmp = Directory.systemTemp.createTempSync('deliver-share');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final shared = _mockShareSheet(tmp);
      final saver = _FakeSaver('/nowhere');
      FileSelectorPlatform.instance = saver;
      final messenger = await _messenger(tester);

      DeliveryKind? kind;
      await tester.runAsync(() async {
        kind = await deliverExport(
          messenger,
          bytes: Uint8List.fromList([4, 5, 6]),
          suggestedName: 'tracker.abc',
          label: 'ABC',
          extension: 'abc',
          savedMessage: (p) => 'saved $p',
          sharedMessage: 'shared',
          failedMessage: 'failed',
        );
      });
      await tester.pump();

      expect(kind, DeliveryKind.shared);
      expect(saver.asked, 0, reason: 'no Save dialog on a phone');
      expect(shared.single, endsWith('tracker.abc'));
      expect(File(shared.single).readAsBytesSync(), [4, 5, 6]);
      expect(find.text('shared'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a delivery error reports the caller\'s failure message',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/share'),
              (call) async => throw PlatformException(code: 'boom'),
            );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          null,
        ),
      );
      final tmp = Directory.systemTemp.createTempSync('deliver-fail');
      addTearDown(() => tmp.deleteSync(recursive: true));
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      final scaffold = await _messenger(tester);

      DeliveryKind? kind = DeliveryKind.saved;
      await tester.runAsync(() async {
        kind = await deliverExport(
          scaffold,
          bytes: Uint8List.fromList([1]),
          suggestedName: 'x.mid',
          label: 'MIDI',
          extension: 'mid',
          savedMessage: (p) => 'saved $p',
          sharedMessage: 'shared',
          failedMessage: 'failed',
        );
      });
      await tester.pump();
      expect(kind, isNull);
      expect(find.text('failed'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'the Tracker\'s MIDI export reaches the share sheet on a phone',
    (tester) async {
      final tmp = Directory.systemTemp.createTempSync('tracker-share');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final shared = _mockShareSheet(tmp);
      // The Tracker makes a mic recorder up front; letting real async run (below)
      // would surface its missing plugin as an error.
      const recorder = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recorder, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recorder, null),
      );
      await pumpGame(tester, const TrackerScreen());
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TrackerScreen)))!;

      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(l10n.trackerExportMidi));
      // share_plus writes the bytes to a temp file with real I/O, whose
      // completions land back in the test's fake-async zone: alternate letting
      // the real event loop run with pumping those completions through.
      for (var i = 0; i < 40 && shared.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(shared, hasLength(1));
      expect(shared.single, endsWith('tracker.mid'));
      expect(File(shared.single).readAsBytesSync().take(4), 'MThd'.codeUnits);
      expect(find.text(l10n.musicExportShared), findsOneWidget);
      expect(find.text(l10n.trackerModFailed), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('MIME types follow the extension', () {
    expect(exportMimeType('mid'), 'audio/midi');
    expect(
      exportMimeType('MusicXML'),
      'application/vnd.recordare.musicxml+xml',
    );
    expect(exportMimeType('xm'), 'application/octet-stream');
  });
}
