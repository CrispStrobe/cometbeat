// lib/shared/widgets/transport_bar.dart
//
// WS-W3 — one transport bar.
//
// The Tracker, the Audio Editor and Loop Studio each drew their own, with their
// own play/stop semantics and their own labels — the ARBs carry SIX redo keys
// (`daw`/`loopMixer`/`perform`/`tab`/`workshop`/`voiceLab`) for one button. This
// is the single widget all three host, driven entirely by [TransportService]
// (WS-W2), so the transport looks and behaves the same wherever a user meets it.
//
// IT OWNS NO STATE. Everything it shows comes from the service; everything it
// does is a call on the service. That is what lets two surfaces show this bar at
// once and stay in agreement — and it is why there is no `TransportBarState`.
//
// UNDO/REDO ARE OPTIONAL CALLBACKS, not a dependency on WS-W4 (one undo
// history). The card says this bar is "driven entirely by WS-W2 + WS-W4", but
// W4 does not exist yet and blocking on it would leave three divergent bars
// standing for no gain. A surface passes its OWN undo today; when W4 lands it
// passes that instead, and nothing here changes.
//
// PER-SURFACE EXTRAS GO IN [trailing], never in a fork of this widget. The
// Audio Editor's snap toggle, the Tracker's follow toggle and Loop Studio's
// scene launcher are all legitimately different — but the transport is not.

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The shared transport: play/pause · stop · record · loop · position · tempo ·
/// undo/redo · metronome, plus whatever the host adds in [trailing].
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.transport,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.showRecord = true,
    this.showMetronome = true,
    this.trailing = const [],
    this.compactWidth = 560,
  });

  final TransportService transport;

  /// The host's undo, until WS-W4 gives every surface the same one. A null
  /// callback hides the pair rather than showing two dead buttons — a surface
  /// with no undo should not imply it has one.
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;

  /// Loop Studio and the Audio Editor record; a Tracker pattern editor does not
  /// (yet — WS-T7), so the button is optional rather than permanently disabled.
  final bool showRecord;
  final bool showMetronome;

  /// Per-surface controls, shown after the shared ones.
  final List<Widget> trailing;

  /// Below this width the labelled readouts collapse to the bar/beat counter
  /// alone. Injectable so a test can force either layout without resizing.
  final double compactWidth;

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder rather than a StatefulWidget listener: the service is the
    // only source of truth, so there is nothing to hold and nothing to dispose.
    return AnimatedBuilder(
      animation: transport,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < compactWidth;
          return _bar(context, compact: compact);
        },
      ),
    );
  }

  Widget _bar(BuildContext context, {required bool compact}) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // ⚠️ SCROLLS rather than overflows. `compactWidth` collapses the
        // READOUTS but not the button set, so a host that passes undo/redo and
        // a record button still overflowed a phone — by 51 px in the Audio
        // Editor, and by 2.8 px even after dropping the metronome. A shared bar
        // that overflows on a phone is a bug in the WIDGET, not in whichever
        // host happened to find it, and dropping controls until it fits would
        // make the fix a guess about which one matters least.
        //
        // `Spacer` cannot live in a scrollable Row (it needs bounded width), so
        // the layout keeps its spread when there is room and gives it up when
        // there is not.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: _row(context, l10n, scheme, compact: compact),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme, {
    required bool compact,
  }) =>
      IntrinsicWidth(
        child: Row(
          children: [
            _playPause(l10n, scheme),
            _stop(l10n),
            if (showRecord) _record(l10n, scheme),
            _loop(l10n, scheme),
            const SizedBox(width: 8),
            _position(context, l10n, compact: compact),
            const SizedBox(width: 8),
            if (!compact) _tempo(context, l10n),
            const Spacer(),
            if (showMetronome) _metronome(l10n, scheme),
            if (onUndo != null || onRedo != null) ...[
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: l10n.transportUndo,
                onPressed: canUndo ? onUndo : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: l10n.transportRedo,
                onPressed: canRedo ? onRedo : null,
              ),
            ],
            ...trailing,
          ],
        ),
      );

  // --------------------------------------------------------------- controls

  Widget _playPause(AppLocalizations l10n, ColorScheme scheme) {
    final playing = transport.isPlaying;
    return IconButton(
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      tooltip: playing ? l10n.transportPause : l10n.transportPlay,
      color: playing ? scheme.primary : null,
      onPressed: transport.togglePlay,
    );
  }

  Widget _stop(AppLocalizations l10n) => IconButton(
        icon: const Icon(Icons.stop),
        tooltip: l10n.transportStop,
        onPressed: transport.stop,
      );

  Widget _record(AppLocalizations l10n, ColorScheme scheme) {
    // Lit while ARMED, not only while rolling: the point of arming is to see it
    // before you press play.
    final armed = transport.isRecordArmed;
    return IconButton(
      icon: const Icon(Icons.fiber_manual_record),
      tooltip: l10n.transportRecord,
      color: armed ? scheme.error : null,
      onPressed: () => transport.setRecordArmed(!armed),
    );
  }

  Widget _loop(AppLocalizations l10n, ColorScheme scheme) => IconButton(
        icon: const Icon(Icons.repeat),
        tooltip: l10n.transportLoop,
        color: transport.isLoopEnabled ? scheme.primary : null,
        onPressed: transport.toggleLoop,
      );

  Widget _metronome(AppLocalizations l10n, ColorScheme scheme) => IconButton(
        icon: const Icon(Icons.av_timer),
        tooltip: l10n.transportMetronome,
        color: transport.metronomeEnabled ? scheme.primary : null,
        onPressed: () =>
            transport.metronomeEnabled = !transport.metronomeEnabled,
      );

  // --------------------------------------------------------------- readouts

  Widget _position(
    BuildContext context,
    AppLocalizations l10n, {
    required bool compact,
  }) {
    final theme = Theme.of(context);
    // During a count-in the bar/beat has not started moving, and showing a
    // frozen "1.1" reads as a hang. Say what is actually happening instead.
    final counting = transport.isCountingIn;
    return Tooltip(
      message: counting ? l10n.transportCountingIn : l10n.transportPosition,
      child: Text(
        counting ? l10n.transportCountingIn : transport.barBeatLabel,
        // Tabular figures so the readout does not jitter as digits change —
        // a proportional font makes a running counter shuffle sideways.
        style:
            (compact ? theme.textTheme.bodyMedium : theme.textTheme.titleMedium)
                ?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: counting ? theme.colorScheme.primary : null,
        ),
      ),
    );
  }

  Widget _tempo(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    // A tempo MAP has no single tempo to edit. Rather than silently flatten it
    // — which would throw away every tempo change the user made — the readout
    // becomes read-only and shows the tempo in force at the playhead.
    final editable = transport.tempo.isConstant;
    final label = '${transport.bpm.round()}';
    if (!editable) {
      return Tooltip(
        message: l10n.transportTempo,
        child: Text(label, style: theme.textTheme.bodyMedium),
      );
    }
    return SizedBox(
      width: 84,
      child: Tooltip(
        message: l10n.transportTempo,
        child: TextField(
          key: const ValueKey('transport-tempo'),
          controller: TextEditingController(text: label),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (raw) {
            final value = double.tryParse(raw.trim());
            if (value == null || !value.isFinite) return;
            transport.tempo = TempoMap.constant(
              value.clamp(kMinBpm, kMaxBpm),
            );
          },
        ),
      ),
    );
  }
}
