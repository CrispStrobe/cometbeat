// Loop Studio — the single entry point for making, recording, and arranging
// loops. Simple and Advanced are views over the same Loop Mixer document; the
// editor owns the actual tracks and transport, so changing the view never
// creates a second copy of the music.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class LoopStudioScreen extends StatefulWidget {
  const LoopStudioScreen({super.key});

  @override
  State<LoopStudioScreen> createState() => _LoopStudioScreenState();
}

class _LoopStudioScreenState extends State<LoopStudioScreen> {
  bool _simple = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loopStudioTitle),
        actions: [_viewSwitcher(l10n)],
      ),
      body: LoopMixerScreen(
        key: const ValueKey('loop-studio-editor'),
        showAppBar: false,
        simpleLayout: _simple,
      ),
    );
  }

  Widget _viewSwitcher(AppLocalizations l10n) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return PopupMenuButton<bool>(
        tooltip: l10n.loopStudioAdvanced,
        initialValue: _simple,
        icon: Icon(_simple ? Icons.auto_awesome : Icons.tune),
        onSelected: (value) => setState(() => _simple = value),
        itemBuilder: (context) => [
          PopupMenuItem<bool>(
            value: true,
            child: Text(l10n.loopStudioSimple),
          ),
          PopupMenuItem<bool>(
            value: false,
            child: Text(l10n.loopStudioAdvanced),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(
            value: true,
            icon: const Icon(Icons.auto_awesome),
            label: Text(l10n.loopStudioSimple),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: const Icon(Icons.tune),
            label: Text(l10n.loopStudioAdvanced),
          ),
        ],
        selected: {_simple},
        showSelectedIcon: false,
        onSelectionChanged: (value) => setState(() => _simple = value.first),
      ),
    );
  }
}
