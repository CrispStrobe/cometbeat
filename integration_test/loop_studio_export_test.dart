// On-device integration test for every save/export path Loop Studio offers,
// in the REAL app: the real render isolate, the real glint encoder (Opus/AAC),
// the real PDF engraver and real file writes inside the macOS sandbox.
//
// The only thing replaced is the native "Save as…" DIALOG — a fake
// FileSelectorPlatform answers getSaveLocation with a path in the container's
// temp dir. Everything after that (XFile.saveTo, the encoders, the snackbar)
// is the production code path, and each written file is opened and checked:
// RIFF/WAVE header, MP3 frame sync, an Ogg/Opus or MP4 box, MusicXML that
// parses back with notes in it, a MIDI header, a PDF header, a ZIP .mxl…
//
// Run (macOS):
//   flutter test integration_test/loop_studio_export_test.dart -d macos

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/features/games/composition/loop_studio_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:crisp_notation/crisp_notation.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the native save panel: every request is answered with a
/// fresh path in [dir], named after the suggestion, and recorded.
class _FakeSavePanel extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeSavePanel(this.dir);
  final Directory dir;
  final List<String> written = [];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    final path =
        '${dir.path}/${written.length}-${options.suggestedName ?? 'out'}';
    written.add(path);
    return FileSaveLocation(path);
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      dir.path;
}

/// Draws one frame BY HAND. The window of a test run launched from a terminal
/// is often occluded/unfocused ("Failed to foreground app"), and an occluded
/// macOS window gets no vsync — so `tester.pump()`, which waits for the engine
/// to draw, never returns. The binding runs in `benchmark` mode (engine frames
/// off) and this drives the frame pipeline directly instead.
void _frame() {
  final b = WidgetsBinding.instance;
  b.handleBeginFrame(
    Duration(microseconds: DateTime.now().microsecondsSinceEpoch),
  );
  b.handleDrawFrame();
}

/// Draws frames while real time passes until [done] or [limit].
Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 90),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < limit) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _frame();
    if (done()) return true;
  }
  return false;
}

Future<void> _settle(WidgetTester tester, [int ms = 600]) =>
    _waitFor(tester, () => false, limit: Duration(milliseconds: ms));

String _ascii(Uint8List b, int from, int len) =>
    String.fromCharCodes(b.sublist(from, from + len));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;

  testWidgets('every Loop Studio export writes a valid file', (tester) async {
    SharedPreferences.setMockInitialValues({'studio_mode': true});
    debugPrint('[loop-export] booting');
    await app.main();
    debugPrint('[loop-export] main returned');
    await _settle(tester, 3000);
    debugPrint('[loop-export] booted');

    // The track cards overflow by half a pixel at this 800 px test window —
    // pre-existing, owned elsewhere (see the comment in `_TrackCard`), and not
    // an export path. Counted and reported rather than failing every export.
    final reportError = FlutterError.onError;
    var overflows = 0;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflows++;
        return;
      }
      reportError?.call(details);
    };

    final out = Directory.systemTemp.createTempSync('loop-export');
    final panel = _FakeSavePanel(out);
    FileSelectorPlatform.instance = panel;

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      nav.push(
        MaterialPageRoute<void>(builder: (_) => const LoopStudioScreen()),
      ),
    );
    await _settle(tester, 1500);

    debugPrint('[loop-export] loop studio pushed');
    final mixerFinder = find.byType(LoopMixerScreen);
    expect(mixerFinder, findsOneWidget);
    final mixer = tester.state<State<LoopMixerScreen>>(mixerFinder);
    final loop = mixer as LoopMixerTester;
    final l10n = AppLocalizations.of(tester.element(mixerFinder))!;

    // A full band with something panned, so the render is STEREO.
    for (final id in ['drums', 'bass', 'chords', 'melody']) {
      if (!loop.enabledTracks.contains(id)) loop.toggleTrack(id);
    }
    loop.setTrackPan('chords', -0.6);
    await _settle(tester);
    expect(loop.hasPitchedTrack, isTrue);

    final failures = <String>[];
    void check(bool ok, String what) {
      if (!ok) failures.add(what);
      debugPrint('[loop-export] ${ok ? 'OK  ' : 'FAIL'} $what');
    }

    /// Waits for whichever snackbar the export ends with and reports it.
    Future<String?> snack() async {
      String? text;
      await _waitFor(tester, () {
        final bars = find.byType(SnackBar).evaluate();
        if (bars.isEmpty) return false;
        final texts = find
            .descendant(of: find.byType(SnackBar), matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .toList();
        text = texts.isEmpty ? '' : texts.join(' ');
        return true;
      });
      // Clear it so the next export's snackbar is the one we read.
      ScaffoldMessenger.of(tester.element(mixerFinder)).clearSnackBars();
      await _settle(tester, 400);
      return text;
    }

    // Simple view: its own share button. Advanced view: the overflow menu.
    Future<void> openShareMenu() async {
      debugPrint('[loop-export] open share menu');
      // A game snackbar ("Combo unlocked…") must not be read as an export's.
      ScaffoldMessenger.of(tester.element(mixerFinder)).clearSnackBars();
      await _settle(tester, 300);
      final simple = find.byKey(const ValueKey('loop-share-export'));
      if (simple.evaluate().isNotEmpty) {
        await tester.tap(simple);
        await _settle(tester);
        return;
      }
      await tester.tap(find.byTooltip(l10n.loopMixerMore).first);
      await _settle(tester);
      // The overflow menu is long; its last group scrolls.
      final item = find.text(l10n.loopMixerShareExport).last;
      await tester.ensureVisible(item);
      await _settle(tester, 300);
      await tester.tap(item);
      await _settle(tester);
    }

    Future<void> tapInSheet(String label) async {
      final f = find.text(label).last;
      await tester.ensureVisible(f);
      await _settle(tester, 300);
      await tester.tap(f);
      await _settle(tester);
    }

    /// In the audio sheet: pick [chip], press Export, return the written file.
    Future<Uint8List?> exportAudioAs(String chip, String what) async {
      final ready = await _waitFor(
        tester,
        () =>
            find.text(l10n.audioExportTitle).evaluate().isNotEmpty ||
            find.byType(SnackBar).evaluate().isNotEmpty,
      );
      if (!ready || find.text(l10n.audioExportTitle).evaluate().isEmpty) {
        check(false, '$what: audio sheet never opened (${await snack()})');
        return null;
      }
      await _settle(tester, 800); // let the sheet finish sliding in
      final chipFinder = find.widgetWithText(ChoiceChip, chip);
      if (chipFinder.evaluate().isEmpty) {
        check(false, '$what: format "$chip" not offered');
        Navigator.of(tester.element(find.text(l10n.audioExportTitle))).pop();
        await _settle(tester);
        return null;
      }
      await tester.tap(chipFinder);
      _frame();
      final before = panel.written.length;
      final button = find.widgetWithIcon(FilledButton, Icons.ios_share);
      await tester.ensureVisible(button);
      await tester.tap(button);
      final message = await snack();
      if (panel.written.length == before) {
        check(false, '$what: no save location requested ($message)');
        await Navigator.of(tester.element(mixerFinder)).maybePop();
        await _settle(tester);
        return null;
      }
      final file = File(panel.written.last);
      if (!file.existsSync()) {
        check(false, '$what: nothing written ($message)');
        return null;
      }
      check(
        message == l10n.audioExportSavedTo(file.path),
        '$what: confirmation "$message"',
      );
      return file.readAsBytesSync();
    }

    void checkWav(Uint8List? b, String what, {bool stereo = false}) {
      if (b == null) return;
      final wav = readWavPcm16(b);
      check(
        _ascii(b, 0, 4) == 'RIFF' && wav.samples.isNotEmpty,
        '$what: RIFF/WAVE with ${wav.samples.length} samples',
      );
      if (stereo) check(wav.channels == 2, '$what: stereo (${wav.channels})');
      var peak = 0;
      for (final s in wav.samples) {
        if (s.abs() > peak) peak = s.abs();
      }
      check(peak > 1000, '$what: audible (peak $peak)');
    }

    void checkMp3(Uint8List? b, String what) {
      if (b == null) return;
      final sync = b.length > 2 &&
          (_ascii(b, 0, 3) == 'ID3' || (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0));
      check(sync && b.length > 2000, '$what: MP3 (${b.length} bytes)');
    }

    // ---- 1. Share menu → "Save as audio" (the flat menu entry) ----
    for (final (chip, ext) in [
      (l10n.audioExportWav, 'wav'),
      (l10n.audioExportMp3, 'mp3'),
      (l10n.audioExportOpus, 'opus'),
      (l10n.audioExportAac, 'aac'),
    ]) {
      await openShareMenu();
      await tapInSheet(l10n.loopMixerSaveAudio);
      final b = await exportAudioAs(chip, 'menu audio $ext');
      switch (ext) {
        case 'wav':
          checkWav(b, 'menu audio wav', stereo: true);
        case 'mp3':
          checkMp3(b, 'menu audio mp3');
        case 'opus':
          if (b != null) {
            check(_ascii(b, 0, 4) == 'OggS', 'opus: Ogg container');
          }
        case 'aac':
          if (b != null) {
            // Raw ADTS: 12-bit 0xFFF sync, layer 00.
            check(
              b[0] == 0xFF && (b[1] & 0xF6) == 0xF0,
              'aac: ADTS stream named .aac',
            );
          }
      }
    }

    // ---- 2. Share menu → "Export sheet music (MusicXML)" ----
    await openShareMenu();
    var before = panel.written.length;
    await tapInSheet(l10n.loopMixerExportMusicXml);
    var msg = await snack();
    if (panel.written.length == before ||
        !File(panel.written.last).existsSync()) {
      check(false, 'menu musicxml: nothing written ($msg)');
    } else {
      final xml = File(panel.written.last).readAsStringSync();
      final mp = multiPartScoreFromMusicXml(xml);
      final notes = mp.parts.fold<int>(
        0,
        (n, p) => n + p.measures.fold(0, (m, bar) => m + bar.elements.length),
      );
      check(
        notes > 0,
        'menu musicxml: ${mp.parts.length} parts, $notes events',
      );
    }

    // ---- 3. The export door → Notes → every notation format ----
    final notation = <String, void Function(Uint8List)>{
      'MusicXML': (b) => check(
            multiPartScoreFromMusicXml(utf8.decode(b)).parts.isNotEmpty,
            'door musicxml parses',
          ),
      'MusicXML (.mxl)': (b) => check(
            multiPartScoreFromMusicXml(readMusicXmlFromMxl(b)).parts.isNotEmpty,
            'door mxl parses',
          ),
      'ABC': (b) => check(utf8.decode(b).contains('X:'), 'door abc header'),
      'MIDI': (b) {
        check(_ascii(b, 0, 4) == 'MThd', 'door midi header');
        check(scoreFromMidi(b).measures.isNotEmpty, 'door midi parses');
      },
      'Module (.mod)': (b) => check(b.length > 1084, 'door mod size'),
      'MEI': (b) => check(utf8.decode(b).contains('<mei'), 'door mei'),
      'Humdrum **kern': (b) =>
          check(utf8.decode(b).contains('**kern'), 'door kern'),
      'LilyPond': (b) => check(utf8.decode(b).contains(r'\'), 'door lilypond'),
      'Braille': (b) => check(b.isNotEmpty, 'door braille'),
      'MuseScore': (b) =>
          check(utf8.decode(b).contains('<museScore'), 'door mscx'),
      'PDF': (b) => check(_ascii(b, 0, 5) == '%PDF-', 'door pdf header'),
    };
    for (final entry in notation.entries) {
      await openShareMenu();
      await tapInSheet(l10n.musicExportTitle);
      await tapInSheet(l10n.dawExportNotes);
      final ok = await _waitFor(
        tester,
        () => find.widgetWithText(ActionChip, entry.key).evaluate().isNotEmpty,
        limit: const Duration(seconds: 10),
      );
      if (!ok) {
        check(false, 'door ${entry.key}: format sheet never opened');
        continue;
      }
      before = panel.written.length;
      await tester.tap(find.widgetWithText(ActionChip, entry.key));
      msg = await snack();
      if (panel.written.length == before ||
          !File(panel.written.last).existsSync()) {
        check(false, 'door ${entry.key}: nothing written ($msg)');
        continue;
      }
      try {
        entry.value(File(panel.written.last).readAsBytesSync());
      } catch (e) {
        check(false, 'door ${entry.key}: unreadable ($e)');
      }
    }

    // ---- 4. The export door → Sound file ----
    await openShareMenu();
    await tapInSheet(l10n.musicExportTitle);
    await tapInSheet(l10n.exportSoundFile);
    checkWav(
      await exportAudioAs(l10n.audioExportWav, 'door audio wav'),
      'door audio wav',
      stereo: true,
    );

    // ---- 5. The export door → Share code ----
    await openShareMenu();
    await tapInSheet(l10n.musicExportTitle);
    await tapInSheet(l10n.chartShareCopy);
    msg = await snack();
    final clip = await tester.runAsync(() => Clipboard.getData('text/plain'));
    check(
      clip?.text == loop.grooveToken && loop.grooveToken.startsWith('KU1.'),
      'share code on the clipboard ($msg)',
    );

    // ---- 6. Share menu → Save to Song Book ----
    final songs = Provider.of<UserSongsService>(
      tester.element(mixerFinder),
      listen: false,
    );
    final songsBefore = songs.songs.length;
    await openShareMenu();
    await tapInSheet(l10n.loopMixerSaveSongBook);
    tester.widget<TextField>(find.byType(TextField).last).controller!.text =
        'Export test groove';
    await tester.tap(find.text(l10n.myMelodySave).last);
    msg = await snack();
    check(
      songs.songs.length == songsBefore + 1 &&
          multiPartScoreFromMusicXml(songs.songs.last.musicXml)
              .parts
              .isNotEmpty,
      'song book save ($msg)',
    );

    // ---- 7. Advanced view → sections → "Export the sections as one track" ----
    await tester.tap(find.text(l10n.loopStudioAdvanced).first);
    await _settle(tester, 1000);
    loop.captureScene(0);
    loop.toggleTrack('melody');
    loop.captureScene(1);
    await _settle(tester);
    // The sections row lives in the "Sound & Feel" inspector (closed by
    // default).
    if (!loop.inspectorVisible) loop.toggleInspector();
    await _settle(tester);
    final arrange = find.byTooltip(
      l10n.loopMixerExportArrangement,
      skipOffstage: false,
    );
    if (arrange.evaluate().isEmpty) {
      check(false, 'arrangement export button not shown');
    } else {
      await tester.ensureVisible(arrange.first);
      await tester.tap(arrange.first);
      await _settle(tester);
      checkWav(
        await exportAudioAs(l10n.audioExportWav, 'arrangement wav'),
        'arrangement wav',
      );
      await tester.tap(arrange.first);
      await _settle(tester);
      checkMp3(
        await exportAudioAs(l10n.audioExportMp3, 'arrangement mp3'),
        'arrangement mp3',
      );
    }

    // ---- 8. Advanced view reaches the same sheet through its overflow ----
    await openShareMenu();
    before = panel.written.length;
    await tapInSheet(l10n.loopMixerExportMusicXml);
    msg = await snack();
    check(
      panel.written.length > before && File(panel.written.last).existsSync(),
      'advanced overflow → musicxml ($msg)',
    );

    debugPrint('[loop-export] files: ${panel.written.join('\n  ')}');
    out.deleteSync(recursive: true);
    FlutterError.onError = reportError;
    if (overflows > 0) {
      debugPrint('[loop-export] note: $overflows layout overflow(s) ignored');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
