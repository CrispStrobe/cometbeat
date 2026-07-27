// DebugService — the hidden dev/parent escape hatch (seven taps reveal a Debug
// section; a switch unlocks every module). Both flags persist. Used incidentally
// by widget tests but never asserted directly; pin load / enableMenu /
// setUnlockAll, their persistence, notifications, and the no-op early returns.
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to locked with the menu hidden', () {
    SharedPreferences.setMockInitialValues({});
    final s = DebugService();
    expect(s.menuEnabled, isFalse);
    expect(s.unlockAll, isFalse);
  });

  test('load reads persisted flags', () async {
    SharedPreferences.setMockInitialValues({
      'debug_menu_enabled': true,
      'debug_unlock_all': true,
    });
    final s = DebugService();
    await s.load();
    expect(s.menuEnabled, isTrue);
    expect(s.unlockAll, isTrue);
  });

  test('enableMenu flips on, notifies, persists, and is idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final s = DebugService();
    var notifications = 0;
    s.addListener(() => notifications++);

    await s.enableMenu();
    expect(s.menuEnabled, isTrue);
    expect(notifications, 1);

    await s.enableMenu(); // already on → no-op, no extra notification
    expect(notifications, 1);

    // Persisted: a fresh service that loads sees it.
    final reloaded = DebugService();
    await reloaded.load();
    expect(reloaded.menuEnabled, isTrue);
  });

  test('setUnlockAll toggles, notifies, persists, and no-ops on no change',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = DebugService();
    var notifications = 0;
    s.addListener(() => notifications++);

    await s.setUnlockAll(true);
    expect(s.unlockAll, isTrue);
    expect(notifications, 1);

    await s.setUnlockAll(true); // same value → early return, no notification
    expect(notifications, 1);

    await s.setUnlockAll(false);
    expect(s.unlockAll, isFalse);
    expect(notifications, 2);

    final reloaded = DebugService();
    await reloaded.load();
    expect(reloaded.unlockAll, isFalse);
  });
}
