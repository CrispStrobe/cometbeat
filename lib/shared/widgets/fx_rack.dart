// lib/shared/widgets/fx_rack.dart
//
// A4 — one FX rack for all five modes.
//
// The Audio Editor, the Tracker, the Instrument Builder, Loop Studio and the Tab
// editor all need the same thing: show an ordered effect chain, let the user add
// / remove / reorder / bypass, and expose each effect's params. Before this each
// mode either hand-wrote that panel or (Tab) had no way to reach effects at all.
//
// The rack knows NOTHING about any individual effect. Everything it renders
// comes from `fx_params.dart`'s descriptor table, so adding a new [FxType] is a
// table entry, not a UI change in five places — which was the whole reason the
// per-mode panels drifted apart.
//
// Stateless and controlled: it never mutates the chain it is given, it calls
// [onChanged] with a new list. That keeps undo/redo, cache invalidation, and
// "which document owns this chain" the host's business, which differs per mode
// (a tracker channel invalidates a stem cache, a DAW clip invalidates a bake).

import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter/material.dart';

/// An ordered [FxSpec] chain, editable.
class FxRack extends StatelessWidget {
  const FxRack({
    super.key,
    required this.chain,
    required this.onChanged,
    this.title,
    this.maxEffects = 8,
    this.dense = false,
  });

  /// The chain to show. Never mutated — edits go through [onChanged].
  final List<FxSpec> chain;

  /// Called with the NEW chain after any edit.
  final ValueChanged<List<FxSpec>> onChanged;

  /// An optional heading ("Channel FX", "Track inserts", "Guitar rig").
  final String? title;

  /// A cap, so a kid cannot stack forty reverbs and wonder why it crawls.
  final int maxEffects;

  /// Tighter spacing, for hosting inside an already-busy inspector.
  final bool dense;

  void _replace(int index, FxSpec fx) {
    final next = [...chain];
    next[index] = fx;
    onChanged(next);
  }

  void _remove(int index) {
    final next = [...chain]..removeAt(index);
    onChanged(next);
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= chain.length) return;
    final next = [...chain];
    final fx = next.removeAt(index);
    next.insert(target, fx);
    onChanged(next);
  }

  void _add(FxType type) => onChanged([...chain, defaultFx(type)]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 4 : 8),
            child: Text(title!, style: theme.textTheme.titleSmall),
          ),
        if (chain.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No effects — the sound passes through unchanged.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < chain.length; i++)
          _FxRow(
            key: ValueKey('fx-$i-${chain[i].type.name}'),
            fx: chain[i],
            index: i,
            isFirst: i == 0,
            isLast: i == chain.length - 1,
            dense: dense,
            onChanged: (fx) => _replace(i, fx),
            onRemove: () => _remove(i),
            onMoveUp: () => _move(i, -1),
            onMoveDown: () => _move(i, 1),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: _AddFxButton(
            enabled: chain.length < maxEffects,
            onSelected: _add,
          ),
        ),
      ],
    );
  }
}

class _FxRow extends StatelessWidget {
  const _FxRow({
    super.key,
    required this.fx,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.dense,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final FxSpec fx;
  final int index;
  final bool isFirst;
  final bool isLast;
  final bool dense;
  final ValueChanged<FxSpec> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  void _setParam(String key, double value) => onChanged(
        fx.copyWith(params: {...fx.params, key: value}),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specs = fxParamSpecs(fx.type);
    return Card(
      margin: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
      child: Padding(
        padding: EdgeInsets.all(dense ? 6 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Bypass. A bypassed effect stays in the chain at its position,
                // so toggling it back does not cost the user their ordering.
                Semantics(
                  identifier: 'fx-enabled-$index',
                  child: Switch(
                    value: fx.enabled,
                    onChanged: (v) => onChanged(fx.copyWith(enabled: v)),
                  ),
                ),
                Expanded(
                  child: Text(
                    key: ValueKey('fx-title-$index'),
                    fxTypeLabel(fx.type),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fx.enabled ? null : theme.disabledColor,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Move earlier',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: isFirst ? null : onMoveUp,
                ),
                IconButton(
                  tooltip: 'Move later',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: isLast ? null : onMoveDown,
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                ),
              ],
            ),
            // Params stay visible while bypassed but read as inactive, so the
            // user can dial one in before switching it on.
            Opacity(
              opacity: fx.enabled ? 1 : 0.45,
              child: Column(
                children: [
                  for (final spec in specs)
                    _FxParamControl(
                      spec: spec,
                      value: fx.params[spec.key] ??
                          defaultFx(fx.type).params[spec.key] ??
                          spec.min,
                      dense: dense,
                      onChanged: (v) => _setParam(spec.key, v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FxParamControl extends StatelessWidget {
  const _FxParamControl({
    required this.spec,
    required this.value,
    required this.dense,
    required this.onChanged,
  });

  final FxParamSpec spec;
  final double value;
  final bool dense;
  final ValueChanged<double> onChanged;

  String get _readout {
    if (spec.isChoice) {
      final i = value.round().clamp(0, spec.choices!.length - 1);
      return spec.choices![i];
    }
    // Enough precision to see a change, not so much it looks like telemetry.
    final text = spec.integer
        ? value.round().toString()
        : (value.abs() >= 100
            ? value.round().toString()
            : value.toStringAsFixed(2));
    return spec.unit.isEmpty ? text : '$text${spec.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 0 : 2),
      child: Row(
        children: [
          SizedBox(
            width: dense ? 76 : 92,
            child: Text(
              fxParamLabel(spec.key),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: spec.isChoice
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: DropdownButton<int>(
                      key: ValueKey('fx-choice-${spec.key}'),
                      isDense: true,
                      value: value.round().clamp(0, spec.choices!.length - 1),
                      onChanged: (v) =>
                          v == null ? null : onChanged(v.toDouble()),
                      items: [
                        for (var i = 0; i < spec.choices!.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(spec.choices![i]),
                          ),
                      ],
                    ),
                  )
                : Semantics(
                    identifier: 'fx-param-${spec.key}',
                    child: Slider(
                      value: spec.normalize(value),
                      onChanged: (t) => onChanged(spec.denormalize(t)),
                    ),
                  ),
          ),
          SizedBox(
            width: dense ? 52 : 62,
            child: Text(
              _readout,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The add button — effects grouped by category, so 28 of them do not arrive as
/// one flat list.
class _AddFxButton extends StatelessWidget {
  const _AddFxButton({required this.enabled, required this.onSelected});

  final bool enabled;
  final ValueChanged<FxType> onSelected;

  @override
  Widget build(BuildContext context) {
    final byCategory = <FxCategory, List<FxType>>{};
    for (final type in FxType.values) {
      (byCategory[fxCategory(type)] ??= []).add(type);
    }
    return PopupMenuButton<FxType>(
      key: const ValueKey('fx-add'),
      enabled: enabled,
      tooltip: enabled ? 'Add an effect' : 'The chain is full',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final category in FxCategory.values) ...[
          PopupMenuItem<FxType>(
            enabled: false,
            height: 28,
            child: Text(
              fxCategoryLabel(category),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final type in byCategory[category] ?? const <FxType>[])
            PopupMenuItem<FxType>(
              value: type,
              child: Text(fxTypeLabel(type)),
            ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: enabled ? null : Theme.of(context).disabledColor,
            ),
            const SizedBox(width: 4),
            Text(
              'Add effect',
              style: TextStyle(
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
