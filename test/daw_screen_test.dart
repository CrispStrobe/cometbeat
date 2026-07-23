// The Multitrack (DAW) arranger surface: add clips from modules, bake the
// arrangement, mute tracks. Audio is a no-op in the headless binding; assertions
// are on the arrangement + the bake.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart'
    show DawClipEffectType, DawFadeCurve, kDawSampleRate;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

Future<void> _pumpDaw(WidgetTester tester) => pumpGame(
      tester,
      const DawScreen(),
      extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
    );

class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this._file);

  final XFile? _file;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      _file;
}

Float64List _tone(int n) => Float64List.fromList([
      for (var i = 0; i < n; i++)
        0.4 * math.sin(2 * math.pi * 220 * i / kDawSampleRate),
    ]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('starts empty with two tracks', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.trackCount, 2);
    expect(daw.clipCount, 0);
    expect(daw.debugBakeLength(), 0); // nothing to bake
  });

  testWidgets('adding clips from modules bakes real, layered audio',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);

    daw.addDemoBeat(); // a DrumSource on track A
    daw.addDemoTune(); // a ScoreSource on track B, 2 s later
    await tester.pump();
    expect(daw.clipCount, 2);

    // The arrangement bakes to a non-empty buffer that runs at least until the
    // second clip's placement (2 s in).
    final len = daw.debugBakeLength();
    expect(len, greaterThan(2 * 44100));
  });

  testWidgets('muting a track shortens/changes the bake', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // track A at 0
    await tester.pump();
    final withBeat = daw.debugBakeLength();
    expect(withBeat, greaterThan(0));

    daw.toggleTrackMute(0);
    await tester.pump();
    expect(daw.isTrackMuted(0), isTrue);
    expect(daw.debugBakeLength(), 0); // the only track is muted → silence
  });

  testWidgets('merge all flattens the arrangement into one baked take',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);
    final before = daw.debugBakeLength();

    daw.mergeAll();
    await tester.pump();
    expect(daw.clipCount, 1);
    expect(daw.trackCount, 2); // lanes stay; only the clips collapse
    expect(daw.isClipFrozen(0, 0), isTrue);
    // Merging preserves the arrangement, so the bake length is unchanged.
    expect(daw.debugBakeLength(), before);
  });

  testWidgets('freeze converts a live clip to audio; remove drops it',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // a live DrumSource
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isFalse);

    daw.freezeClip(0, 0);
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isTrue);
    expect(daw.debugBakeLength(), greaterThan(0));

    daw.removeClip(0, 0);
    await tester.pump();
    expect(daw.clipCount, 0);
  });

  testWidgets('clips draw to scale and can be dragged along the lane',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // track A @ 0 ms
    await tester.pump();

    // A real, non-zero duration (drawn to scale), and it starts at 0.
    expect(daw.clipDurationMs(0, 0), greaterThan(0));
    expect(daw.clipStartMs(0, 0), 0);
    expect(daw.canExport, isTrue);

    // Long-press then drag the clip box to the right → later in time.
    final center = tester.getCenter(find.text('🥁'));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600)); // arm the long press
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(daw.clipStartMs(0, 0), greaterThan(0));
  });

  testWidgets('export is gated on having content', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.canExport, isFalse);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.canExport, isTrue);
  });

  testWidgets('export dialog previews mix and opens format chooser',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester)..addDemoBeat();
    daw.setTrackGain(0, 0.2);
    await tester.pump();

    await tester.tap(find.byTooltip('Export sound'));
    await tester.pumpAndSettle();
    expect(find.text('Export mix'), findsOneWidget);
    expect(find.text('Full mix'), findsOneWidget);
    expect(find.text('Marked range'), findsOneWidget);
    expect(find.textContaining('Duration'), findsOneWidget);
    expect(find.textContaining('Peak'), findsOneWidget);
    expect(find.text('Normalize peak'), findsOneWidget);
    expect(find.text('Export peak 0.98'), findsNothing);

    await tester.tap(find.text('Normalize peak'));
    await tester.pumpAndSettle();
    expect(find.text('Export peak 0.98'), findsOneWidget);

    await tester.tap(find.text('Choose format'));
    await tester.pumpAndSettle();
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('WAV (uncompressed)'), findsOneWidget);
    expect(find.text('MP3 (smaller)'), findsOneWidget);
    expect(find.text('Sample rate'), findsOneWidget);
    expect(find.text('44.1 kHz'), findsOneWidget);
    expect(find.text('48 kHz'), findsOneWidget);
    expect(find.text('32 kHz'), findsOneWidget);
    expect(find.text('Bit depth'), findsOneWidget);
    expect(find.text('8-bit'), findsOneWidget);
    expect(find.text('16-bit'), findsOneWidget);
    expect(find.text('24-bit'), findsOneWidget);
    expect(find.text('32-bit'), findsOneWidget);
    expect(find.text('Export WAV'), findsOneWidget);

    await tester.tap(find.text('MP3 (smaller)'));
    await tester.pumpAndSettle();
    expect(find.text('Bitrate'), findsOneWidget);
    expect(find.text('128 kbps'), findsOneWidget);
    expect(find.text('192 kbps'), findsOneWidget);
    expect(find.text('320 kbps'), findsOneWidget);
    expect(find.text('Export MP3'), findsOneWidget);
    expect(daw.canExport, isTrue);
  });

  testWidgets('export dialog can target the marked range', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester)..addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pump();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pump();

    await tester.tap(find.byTooltip('Export sound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marked range'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.50 s'), findsWidgets);
    expect(find.text('Choose format'), findsOneWidget);
  });

  testWidgets('Add clip can import an audio file directly', (tester) async {
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(pcmFloatToWav(_tone(4410)), name: 'Direct Loop.wav'),
    );
    await _pumpDaw(tester);
    final daw = _daw(tester);

    await tester.tap(find.text('Add clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import audio file'));
    await tester.pumpAndSettle();

    expect(daw.clipCount, 1);
    expect(daw.debugBakeLength(), 4410);
  });

  testWidgets('track menu edits an ordered FX chain with sliders',
      (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.byTooltip('Select track for FX').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Deselect track for FX'), findsOneWidget);

    await tester.tap(find.text('A').first);
    await tester.pumpAndSettle();
    expect(find.text('Track FX'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distortion').last);
    await tester.pumpAndSettle();

    expect(service.trackEffects(0).single.type, DawClipEffectType.distortion);
    await tester.tap(find.text('Distortion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Drive'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy chain to selected tracks'));
    await tester.pumpAndSettle();
    expect(service.trackEffects(1).single.type, DawClipEffectType.distortion);

    await tester.tap(find.byTooltip('Add effect to selected tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High Pass').last);
    await tester.pumpAndSettle();
    expect(service.trackEffects(0).single.type, DawClipEffectType.distortion);
    expect(
      service.trackEffects(1).map((fx) => fx.type),
      [DawClipEffectType.distortion, DawClipEffectType.highpass],
    );
  });

  testWidgets('master FX dialog edits the output bus chain', (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    expect(find.text('Output bus'), findsOneWidget);
    expect(find.text('No master effects'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distortion').last);
    await tester.pumpAndSettle();

    expect(service.masterEffects().single.type, DawClipEffectType.distortion);
    await tester.tap(find.text('Distortion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Drive'), findsOneWidget);
  });

  testWidgets('voice FX modules expose a wet/dry mix slider', (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice: Robot').last);
    await tester.pumpAndSettle();

    expect(service.masterEffects().single.type, DawClipEffectType.voiceRobot);
    await tester.tap(find.text('Voice: Robot'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mix'), findsOneWidget);
  });

  testWidgets('voice shape FX exposes adjustable shaping sliders',
      (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice Shape').last);
    await tester.pumpAndSettle();

    expect(service.masterEffects().single.type, DawClipEffectType.voiceShape);
    await tester.tap(find.text('Voice Shape'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Formant'), findsOneWidget);
    expect(find.textContaining('Robot Hz'), findsOneWidget);
    expect(find.textContaining('Robot Mix'), findsOneWidget);
    expect(find.textContaining('Grit'), findsOneWidget);
    expect(find.textContaining('Radio Mix'), findsOneWidget);
    expect(find.textContaining('Mix'), findsWidgets);
  });

  testWidgets('pitch and time FX expose CrispAudio-style sliders',
      (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pitch Shift').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time Stretch').last);
    await tester.pumpAndSettle();

    expect(
      service.masterEffects().map((fx) => fx.type),
      [DawClipEffectType.pitchShift, DawClipEffectType.timeStretch],
    );
    await tester.tap(find.text('Pitch Shift'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Semitones'), findsOneWidget);
    await tester.tap(find.text('Time Stretch'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Speed'), findsOneWidget);
  });

  testWidgets('tremolo and vocoder FX expose voice control sliders',
      (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tremolo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vocoder').last);
    await tester.pumpAndSettle();

    expect(
      service.masterEffects().map((fx) => fx.type),
      [DawClipEffectType.tremolo, DawClipEffectType.vocoder],
    );
    await tester.tap(find.text('Tremolo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rate Hz'), findsOneWidget);
    await tester.tap(find.text('Vocoder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carrier Hz'), findsOneWidget);
    expect(find.textContaining('Depth'), findsWidgets);
  });

  testWidgets('gain FX exposes output gain sliders', (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gain').last);
    await tester.pumpAndSettle();

    expect(service.masterEffects().single.type, DawClipEffectType.gain);
    await tester.tap(find.text('Gain'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gain dB'), findsOneWidget);
    expect(find.textContaining('Mix'), findsOneWidget);
  });

  testWidgets('FX slider auto writes marked-range automation points',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw.addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pumpAndSettle();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Master FX'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tremolo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tremolo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto').first);
    await tester.pumpAndSettle();
    expect(find.text('Automate Rate Hz'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final points = service.masterEffects().single.automation['rateHz'];
    expect(points, hasLength(2));
    expect(points!.first.ms, 250);
    expect(points.last.ms, 750);
    expect(find.textContaining('Rate Hz automation:'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Rate Hz automation'), findsOneWidget);
    await tester.tap(find.text('Linear').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('S-Curve').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.masterEffects().single.automation['rateHz'], hasLength(2));
    expect(
      service.masterEffects().single.automation['rateHz']!.first.curve,
      DawFadeCurve.sCurve,
    );

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(service.masterEffects().single.automation['rateHz'], isNull);
    expect(find.textContaining('Rate Hz automation:'), findsNothing);
  });

  testWidgets('bus dialog routes selected tracks and edits bus FX',
      (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.byTooltip('Select track for FX').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buses'));
    await tester.pumpAndSettle();
    expect(find.text('No buses'), findsOneWidget);

    await tester.tap(find.text('Add bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Route selected tracks to this bus'));
    await tester.pumpAndSettle();
    expect(service.trackBus(1), 0);

    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distortion').last);
    await tester.pumpAndSettle();

    expect(service.busEffects(0).single.type, DawClipEffectType.distortion);
    await tester.tap(find.text('Distortion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Drive'), findsOneWidget);
  });

  testWidgets('bus dialog edits selected-track send amount', (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.byTooltip('Select track for FX').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bus'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected send'), findsOneWidget);
    expect(find.text('Mixer'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('bus-send-1-0')),
      const Offset(160, 0),
    );
    await tester.pumpAndSettle();

    expect(service.trackSend(1, 0), greaterThan(0));
  });

  testWidgets('bus mixer matrix routes individual tracks', (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Buses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bus'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bus-route-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus 1').last);
    await tester.pumpAndSettle();

    expect(service.trackBus(0), 0);
    expect(service.trackBus(1), isNull);
  });

  testWidgets('bus dialog renames buses for mixer routes', (tester) async {
    await _pumpDaw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );

    await tester.tap(find.text('Buses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bus'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rename bus'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Vocal Plate');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(service.buses().single.name, 'Vocal Plate');
    expect(find.text('Vocal Plate'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('bus-route-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vocal Plate').last);
    await tester.pumpAndSettle();
    expect(service.trackBus(0), 0);
  });

  testWidgets('tapping a clip opens the inspector; gain slider changes gain',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.clipGain(0, 0), 1.0);

    // Tap the clip box → the inspector sheet. Besides the gutter track faders
    // in the body, the inspector adds 5 sliders (gain, 2 fades, 2 trims); the
    // modal renders after the body, so those are the LAST 5.
    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    final sliders = find.byType(Slider);
    final total = tester.widgetList(sliders).length;
    expect(total, greaterThanOrEqualTo(5));

    // Drag the gain slider (first of the inspector's 5) down; gain drops.
    await tester.drag(sliders.at(total - 5), const Offset(-80, 0));
    await tester.pump();
    expect(daw.clipGain(0, 0), lessThan(1.0));
  });

  testWidgets('clip inspector targets selected clips with FX', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw
      ..addDemoBeat()
      ..addDemoTune();
    await tester.pump();

    await tester.tap(find.byTooltip('Select clip for FX').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Deselect clip for FX'), findsOneWidget);

    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    expect(find.text('Clip FX'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distortion').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy FX to selected clips'));
    await tester.pumpAndSettle();
    expect(service.clipEffects(1, 0).single.type, DawClipEffectType.distortion);

    await tester.tap(find.byTooltip('Add effect to selected clips'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High Pass').last);
    await tester.pumpAndSettle();
    expect(service.clipEffects(0, 0).single.type, DawClipEffectType.distortion);
    expect(
      service.clipEffects(1, 0).map((fx) => fx.type),
      [DawClipEffectType.distortion, DawClipEffectType.highpass],
    );
  });

  testWidgets('copy and paste selected clips preserves lane timing',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw
      ..addDemoBeat()
      ..addDemoTune();
    daw.seekTo(10000);
    await tester.pump();

    await tester.tap(find.byTooltip('Select clip for FX').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select clip for FX').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy selected clips'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste clips at playhead'));
    await tester.pumpAndSettle();

    expect(service.timeline.tracks[0].clips, hasLength(2));
    expect(service.timeline.tracks[1].clips, hasLength(2));
    expect(service.clipStartMs(0, 1), closeTo(10000, 0.1));
    expect(service.clipStartMs(1, 1), closeTo(12000, 0.1));
    expect(find.byTooltip('Deselect clip for FX'), findsNWidgets(2));
  });

  testWidgets('cut selected clips removes them and keeps paste available',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw
      ..addDemoBeat()
      ..addDemoTune();
    daw.seekTo(9000);
    await tester.pump();

    await tester.tap(find.byTooltip('Select clip for FX').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select clip for FX').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cut selected clips'));
    await tester.pumpAndSettle();
    expect(service.timeline.tracks[0].clips, isEmpty);
    expect(service.timeline.tracks[1].clips, isEmpty);

    await tester.tap(find.byTooltip('Paste clips at playhead'));
    await tester.pumpAndSettle();
    expect(service.timeline.tracks[0].clips, hasLength(1));
    expect(service.timeline.tracks[1].clips, hasLength(1));
    expect(service.clipStartMs(0, 0), closeTo(9000, 0.1));
    expect(service.clipStartMs(1, 0), closeTo(11000, 0.1));
  });

  testWidgets('range FX splits and effects the marked clip segment',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw.addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pumpAndSettle();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Range 0.25-0.75 s'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Effect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distortion').last);
    await tester.pumpAndSettle();

    expect(service.timeline.tracks[0].clips, hasLength(3));
    expect(service.clipEffects(0, 0), isEmpty);
    expect(service.clipEffects(0, 1).single.type, DawClipEffectType.distortion);
    expect(service.clipEffects(0, 2), isEmpty);
  });

  testWidgets('range gain splits and scales the marked clip segment',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw.addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pumpAndSettle();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Range Gain'));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(service.timeline.tracks[0].clips, hasLength(3));
    expect(service.clipGain(0, 0), closeTo(1, 1e-9));
    expect(service.clipGain(0, 1), closeTo(0.5, 1e-9));
    expect(service.clipGain(0, 2), closeTo(1, 1e-9));
  });

  testWidgets('track automation writes gain ramp points over the marked range',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw.addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pumpAndSettle();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Track Auto'));
    await tester.pumpAndSettle();
    expect(find.text('Track Automation'), findsOneWidget);
    expect(find.text('Start 100%'), findsOneWidget);
    expect(find.text('End 50%'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(service.timeline.tracks[0].gainAutomation, hasLength(2));
    expect(service.timeline.tracks[0].gainAutomation.first.ms, 250);
    expect(service.timeline.tracks[0].gainAutomation.last.ms, 750);
    expect(
      service.timeline.tracks[0].gainAutomation.last.value,
      closeTo(0.5, 1e-9),
    );
    expect(service.timeline.tracks[1].gainAutomation, hasLength(2));
  });

  testWidgets('range fade applies a curve to the marked clip segment',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw.addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pumpAndSettle();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Range Fade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fade In Exponential'));
    await tester.pumpAndSettle();

    expect(service.timeline.tracks[0].clips, hasLength(3));
    expect(service.clipFadeInMs(0, 0), 0);
    expect(service.clipFadeInMs(0, 1), closeTo(500, 0.1));
    expect(service.clipFadeInCurve(0, 1), DawFadeCurve.exponential);
    expect(service.clipFadeInMs(0, 2), 0);
  });

  testWidgets('range mute silences only the marked clip segment',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    final service = Provider.of<DawService>(
      tester.element(find.byType(DawScreen)),
      listen: false,
    );
    daw.addDemoBeat();
    await tester.pump();

    daw.seekTo(250);
    await tester.pump();
    await tester.tap(find.text('Mark In'));
    await tester.pumpAndSettle();
    daw.seekTo(750);
    await tester.pump();
    await tester.tap(find.text('Mark Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Range Mute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    expect(service.timeline.tracks[0].clips, hasLength(3));
    expect(service.timeline.tracks[0].clips[0].muted, isFalse);
    expect(service.timeline.tracks[0].clips[1].muted, isTrue);
    expect(service.timeline.tracks[0].clips[2].muted, isFalse);
  });

  testWidgets('Split cuts a clip in two at the playhead', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.clipCount, 1);

    // Put the playhead inside the clip, then open the inspector.
    daw.seekTo(daw.clipDurationMs(0, 0) / 2);
    await tester.pump();
    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();

    // Tap Split → the one clip becomes two.
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(daw.clipCount, 2);
  });

  testWidgets('Reverse bakes the clip to a backwards take', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isFalse); // a live DrumSource

    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reverse'));
    await tester.pumpAndSettle();

    expect(daw.clipCount, 1); // reverse replaces in place
    expect(daw.isClipFrozen(0, 0), isTrue); // now a baked SampleSource take
  });

  testWidgets('Faster resamples the clip to a shorter baked take',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    final before = daw.clipDurationMs(0, 0);

    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faster'));
    await tester.pumpAndSettle();

    expect(daw.isClipFrozen(0, 0), isTrue); // baked take
    expect(daw.clipDurationMs(0, 0), closeTo(before / 2, before * 0.1)); // ~½
  });

  testWidgets('the snap toggle flips snapping and a ruler labels the timeline',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();

    // The time ruler labels seconds (0s at the origin).
    expect(find.text('0s'), findsOneWidget);
    expect(find.text('1s'), findsWidgets);

    // The grid button toggles snapping.
    expect(daw.snapOn, isFalse);
    await tester.tap(find.byTooltip('Snap to grid'));
    await tester.pump();
    expect(daw.snapOn, isTrue);
  });

  testWidgets('undo/redo reverse and replay edits', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.canUndo, isFalse);

    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);
    expect(daw.canUndo, isTrue);

    daw.undo();
    await tester.pump();
    expect(daw.clipCount, 1);

    daw.redo();
    await tester.pump();
    expect(daw.clipCount, 2);
  });

  testWidgets('clear empties every track', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);

    daw.clear();
    await tester.pump();
    expect(daw.clipCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a My Samples clip is arranged, resampled to the timeline rate',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);

    // 0.5 s at HALF the timeline rate → after resampling it should bake to
    // ~0.5 s at the timeline rate (twice as many samples as the source).
    const half = kDawSampleRate ~/ 2;
    final src = Float64List.fromList([
      for (var i = 0; i < half ~/ 2; i++)
        0.3 * math.sin(2 * math.pi * 220 * i / half),
    ]);
    daw.addSampleClip(
      SampleClip(name: 'zap', sampleRate: half, pcm: src),
    );

    expect(daw.clipCount, 1);
    expect(daw.trackCount, greaterThan(2)); // landed on a fresh lane
    // The bake spans the resampled clip: ~2x the source length (half-rate → full).
    expect(daw.debugBakeLength(), greaterThan(src.length));
  });

  testWidgets('the playhead advances during play and resets on stop',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // gives the arrangement some length
    await tester.pump();

    expect(daw.playheadMs, 0);
    daw.play();
    expect(daw.isPlaying, isTrue);

    // The Ticker drives the playhead off its own elapsed, so tester.pump
    // advances it deterministically (no wall-clock). The first frame after
    // start() establishes the baseline (elapsed 0); it grows after that.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(daw.playheadMs, greaterThan(0));
    final mid = daw.playheadMs;
    await tester.pump(const Duration(milliseconds: 250));
    expect(daw.playheadMs, greaterThan(mid)); // it moved forward

    daw.stop();
    expect(daw.isPlaying, isFalse);
    expect(daw.playheadMs, 0); // reset
  });

  testWidgets('playback auto-stops when the playhead reaches the end',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    daw.play();

    // Pump well past the arrangement length; the ticker should trip stop().
    await tester.pump(); // baseline frame
    await tester.pump(const Duration(seconds: 30));
    expect(daw.isPlaying, isFalse);
    expect(daw.playheadMs, 0);
  });

  testWidgets('loop keeps playing past the end instead of stopping',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();

    expect(daw.loopOn, isFalse);
    daw.toggleLoop();
    expect(daw.loopOn, isTrue);

    daw.play();
    await tester.pump(); // baseline
    // Pump well past the arrangement length: without loop it would stop; with
    // loop it restarts and is still playing.
    await tester.pump(const Duration(seconds: 20));
    expect(daw.isPlaying, isTrue);

    daw.stop();
    expect(daw.isPlaying, isFalse);
  });

  testWidgets('seekTo moves the playhead and playback starts from it',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();

    // Click-to-seek (via the seam): the resting playhead moves to the marker.
    daw.seekTo(400);
    await tester.pump();
    expect(daw.playheadMs, 400);

    // Playback begins from the marker (not 0), so after a baseline frame the
    // playhead is already at/after the seek point.
    daw.play();
    await tester.pump(); // ticker baseline
    expect(daw.playheadMs, greaterThanOrEqualTo(400));

    // Stop rests back at the marker, not 0.
    daw.stop();
    expect(daw.playheadMs, 400);
  });
}
