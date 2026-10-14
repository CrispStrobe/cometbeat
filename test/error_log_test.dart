// The on-device error log: uncaught errors are recorded, bounded, survive a
// restart, and the handlers keep the framework's own reporting.

import 'package:comet_beat/core/services/error_log.dart';
import 'package:comet_beat/features/settings/screens/error_log_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('records newest first, with a trimmed stack', () async {
    final log = ErrorLog(now: () => DateTime.utc(2026, 10, 13, 12));
    log.record(StateError('first'), null, source: 'platform');
    log.record(
      const FormatException('second'),
      StackTrace.fromString(
        List.generate(40, (i) => '#$i frame').join('\n'),
      ),
      source: 'flutter',
    );
    expect(log.entries, hasLength(2));
    expect(log.entries.first.message, contains('second'));
    expect(log.entries.first.source, 'flutter');
    expect(
      log.entries.first.stack.split('\n'),
      hasLength(ErrorLog.maxStackLines),
    );
    expect(log.entries.last.stack, isEmpty);
    expect(log.asText(), contains('2026-10-13T12:00:00.000Z'));
  });

  test('keeps only the most recent entries', () {
    final log = ErrorLog();
    for (var i = 0; i < ErrorLog.maxEntries + 20; i++) {
      log.record('error $i', null, source: 'platform');
    }
    expect(log.entries, hasLength(ErrorLog.maxEntries));
    expect(log.entries.first.message, 'error ${ErrorLog.maxEntries + 19}');
  });

  test('survives a restart, and clear() empties the stored log too', () async {
    final log = ErrorLog();
    await log.load();
    log.record(StateError('kept'), StackTrace.current, source: 'platform');
    await _settle();

    final again = ErrorLog();
    await again.load();
    expect(again.entries.single.message, contains('kept'));

    await again.clear();
    final third = ErrorLog();
    await third.load();
    expect(third.isEmpty, isTrue);
  });

  test('an error during start-up is not lost when the stored log loads',
      () async {
    final first = ErrorLog();
    await first.load();
    first.record('old', null, source: 'platform');
    await _settle();

    final log = ErrorLog();
    log.record('during start-up', null, source: 'flutter');
    await log.load();
    expect(log.entries.map((e) => e.message), ['during start-up', 'old']);
    // …and the merged log is what gets stored.
    final next = ErrorLog();
    await next.load();
    expect(next.entries.map((e) => e.message), ['during start-up', 'old']);
  });

  test('an unreadable stored log is ignored, not thrown', () async {
    SharedPreferences.setMockInitialValues({'error_log_v1': 'not json'});
    final log = ErrorLog();
    await log.load();
    expect(log.isEmpty, isTrue);
  });

  test('the handlers record both kinds and keep the previous reporter', () {
    final log = ErrorLog();
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    var forwarded = 0;
    FlutterError.onError = (_) => forwarded++;
    try {
      installErrorHandlers(log);
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('in build')),
      );
      final handled = PlatformDispatcher.instance.onError!(
        StateError('in a future'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(forwarded, 1);
      expect(log.entries.map((e) => e.source), ['platform', 'flutter']);
    } finally {
      FlutterError.onError = oldFlutter;
      PlatformDispatcher.instance.onError = oldPlatform;
    }
  });

  testWidgets('the screen lists entries and clears them', (tester) async {
    final log = ErrorLog()..record(StateError('boom'), null, source: 'flutter');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ErrorLogScreen(log: log),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.textContaining('boom'), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.errorLogClear));
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorLogEmpty), findsOneWidget);
  });
}
