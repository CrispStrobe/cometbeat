// test/fx_rack_test.dart
//
// A4 — the shared FX rack widget. It is the one panel all five modes use, and
// it is fully table-driven, so the tests check that it renders whatever the
// descriptor table says and that every edit produces a correct NEW chain (it is
// controlled — it must never mutate the list it was handed, or a host's undo
// stack silently loses its history).

import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/shared/widgets/fx_rack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts the rack the way a real screen does: owns the chain, rebuilds on edit.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.initial, this.onChanged});
  final List<FxSpec> initial;
  final ValueChanged<List<FxSpec>>? onChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<FxSpec> chain = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FxRack(
              chain: chain,
              title: 'Channel FX',
              onChanged: (next) {
                widget.onChanged?.call(next);
                setState(() => chain = next);
              },
            ),
          ),
        ),
      );
}

var _pumpSeq = 0;

Future<_HostState> _pump(
  WidgetTester tester,
  List<FxSpec> initial, {
  ValueChanged<List<FxSpec>>? onChanged,
}) async {
  // A fresh key per pump. Without one, pumping a second _Host of the same type
  // REUSES the State, so `late chain = widget.initial` never re-runs and the
  // test silently keeps the previous chain.
  await tester.pumpWidget(
    _Host(
      key: ValueKey('host-${_pumpSeq++}'),
      initial: initial,
      onChanged: onChanged,
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('an empty chain says so instead of showing nothing', (t) async {
    await _pump(t, const []);
    expect(find.textContaining('No effects'), findsOneWidget);
    expect(find.text('Channel FX'), findsOneWidget);
    expect(find.byKey(const ValueKey('fx-add')), findsOneWidget);
  });

  testWidgets('an effect renders its label and one control per param',
      (t) async {
    await _pump(t, [defaultFx(FxType.delay)]);
    expect(find.text(fxTypeLabel(FxType.delay)), findsOneWidget);
    for (final spec in fxParamSpecs(FxType.delay)) {
      expect(
        find.text(fxParamLabel(spec.key)),
        findsOneWidget,
        reason: '${spec.key} has no control',
      );
    }
  });

  testWidgets('every FxType renders without throwing', (t) async {
    // The rack is table-driven, so this is the test that a new effect is
    // editable the moment it exists.
    for (final type in FxType.values) {
      await _pump(t, [defaultFx(type)]);
      // By key, not by text: an effect's name can collide with one of its own
      // param labels (Gain / gainDb), which is fine in the UI but ambiguous
      // for a finder.
      expect(
        t.widget<Text>(find.byKey(const ValueKey('fx-title-0'))).data,
        fxTypeLabel(type),
        reason: '$type',
      );
      expect(find.byType(Switch), findsOneWidget, reason: '$type');
    }
  });

  testWidgets('adding an effect appends it with its defaults', (t) async {
    List<FxSpec>? emitted;
    final host = await _pump(t, const [], onChanged: (c) => emitted = c);

    await t.tap(find.byKey(const ValueKey('fx-add')));
    await t.pumpAndSettle();
    // Pick from the FIRST category — the menu holds 28 effects across 8
    // headings, so a later one needs scrolling and the tap silently misses.
    await t.tap(find.text(fxTypeLabel(FxType.gain)).last);
    await t.pumpAndSettle();

    expect(emitted, hasLength(1));
    expect(emitted!.single.type, FxType.gain);
    expect(emitted!.single.params, defaultFx(FxType.gain).params);
    expect(host.chain, hasLength(1));
  });

  testWidgets('the add button disables at the cap', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxRack(
            chain: [defaultFx(FxType.gain), defaultFx(FxType.pan)],
            maxEffects: 2,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final button = t.widget<PopupMenuButton<FxType>>(
      find.byKey(const ValueKey('fx-add')),
    );
    expect(button.enabled, isFalse);
  });

  testWidgets('bypass toggles enabled without dropping the effect', (t) async {
    List<FxSpec>? emitted;
    await _pump(t, [defaultFx(FxType.reverb)], onChanged: (c) => emitted = c);

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();

    expect(emitted, hasLength(1), reason: 'bypass must not remove the effect');
    expect(emitted!.single.enabled, isFalse);
    expect(emitted!.single.type, FxType.reverb);
    // Its params survive, so switching it back restores the same sound.
    expect(emitted!.single.params, defaultFx(FxType.reverb).params);
  });

  testWidgets('removing takes out the right one', (t) async {
    List<FxSpec>? emitted;
    await _pump(
      t,
      [
        defaultFx(FxType.gain),
        defaultFx(FxType.reverb),
        defaultFx(FxType.delay),
      ],
      onChanged: (c) => emitted = c,
    );

    await t.tap(find.byIcon(Icons.close).at(1));
    await t.pumpAndSettle();

    expect(emitted!.map((f) => f.type).toList(), [FxType.gain, FxType.delay]);
  });

  testWidgets('reordering moves an effect and respects the ends', (t) async {
    List<FxSpec>? emitted;
    await _pump(
      t,
      [defaultFx(FxType.gain), defaultFx(FxType.reverb)],
      onChanged: (c) => emitted = c,
    );

    // The first row cannot move up, the last cannot move down.
    expect(
      t
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_upward).first,
          )
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_downward).last,
          )
          .onPressed,
      isNull,
    );

    // Chain ORDER is audible (it is a signal path), so this is a real edit.
    await t.tap(find.byIcon(Icons.arrow_upward).last);
    await t.pumpAndSettle();
    expect(emitted!.map((f) => f.type).toList(), [FxType.reverb, FxType.gain]);
  });

  testWidgets('dragging a slider writes a value inside the param range',
      (t) async {
    List<FxSpec>? emitted;
    await _pump(t, [defaultFx(FxType.lowpass)], onChanged: (c) => emitted = c);

    final slider = find.byType(Slider).first;
    await t.drag(slider, const Offset(-200, 0));
    await t.pumpAndSettle();

    expect(emitted, isNotNull);
    final spec = fxParamSpec(FxType.lowpass, 'freq');
    final value = emitted!.single.params['freq']!;
    expect(value, inInclusiveRange(spec.min, spec.max));
    expect(
      value,
      lessThan(defaultFx(FxType.lowpass).params['freq']!),
      reason: 'dragging left should lower the frequency',
    );
  });

  testWidgets('a choice param renders a picker and selects by index',
      (t) async {
    List<FxSpec>? emitted;
    await _pump(
      t,
      [defaultFx(FxType.distortion)],
      onChanged: (c) => emitted = c,
    );

    final dropdown = find.byKey(const ValueKey('fx-choice-kind'));
    expect(dropdown, findsOneWidget, reason: 'the curve must not be a slider');

    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text('Fuzz').last);
    await t.pumpAndSettle();

    expect(emitted!.single.params['kind'], 2);
  });

  testWidgets('the rack never mutates the chain it was handed', (t) async {
    // A host that keeps snapshots for undo relies on this absolutely.
    final original = [defaultFx(FxType.gain), defaultFx(FxType.reverb)];
    final snapshot = List<FxSpec>.of(original);
    await _pump(t, original);

    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();

    expect(original, hasLength(2));
    expect(original.map((f) => f.type), snapshot.map((f) => f.type));
  });

  testWidgets('a chain of every effect renders in one rack', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FxRack(
              chain: [for (final type in FxType.values) defaultFx(type)],
              maxEffects: 99,
              dense: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(FxType.values.length));
  });
}
