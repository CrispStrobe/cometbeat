// lib/features/games/composition/daw_screen_mixing.dart
//
// The Multitrack DAW's mixing surface: the track menu, track / clip / master
// FX editors, buses and the bus mixer, loudness, range gain and automation,
// takes, and the clip generator dialog.
//
// A `part` of daw_screen.dart, split out so the screen's state class is not one
// 6,500-line body. These are the same methods, moved verbatim into an
// extension — they still read and write the state's private fields directly.
// The one mechanical change: `setState` is protected and cannot be called from
// an extension, so it is `_rebuild` here (a one-line forwarder on the state).

part of 'daw_screen.dart';

extension _DawScreenMixing on _DawScreenState {
  /// Track name → a small menu to rename the lane or remove it.
  Future<void> _trackMenu(int i) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _daw.trackName(i));
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawTrackTitle),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(labelText: l10n.dawTrackName),
                    onSubmitted: (_) => Navigator.of(ctx).pop('rename'),
                  ),
                  const SizedBox(height: 16),
                  _trackFxEditor(ctx, i, setDialog),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('instrument'),
            child: Text(l10n.dawTrackInstrument),
          ),
          TextButton(
            onPressed: _daw.timeline.tracks.length <= 1
                ? null
                : () => Navigator.of(ctx).pop('remove'),
            child: Text(l10n.dawRemoveTrack),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('rename'),
            child: Text(l10n.dawRename),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = controller.text.trim();
      if (name.isNotEmpty) renameTrack(i, name);
    } else if (action == 'remove') {
      removeTrack(i);
    } else if (action == 'instrument') {
      await _assignTrackInstrument(i);
    }
  }

  Widget _trackFxEditor(
    BuildContext ctx,
    int track,
    StateSetter setDialog,
  ) {
    final effects = _daw.trackEffects(track);
    final selectedTargets = _selectedTrackTargets(track);
    final hasSelectedTargets = _selectedTracks.any(
      (i) => i >= 0 && i < _daw.timeline.tracks.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)!.dawTrackFx,
              style: Theme.of(ctx).textTheme.labelLarge,
            ),
            const Spacer(),
            Text(
              hasSelectedTargets
                  ? AppLocalizations.of(context)!
                      .dawNSelected(selectedTargets.length)
                  : 'This track',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 2,
          children: [
            IconButton(
              tooltip:
                  AppLocalizations.of(context)!.dawCopyChainToSelectedTracks,
              icon: const Icon(Icons.checklist),
              onPressed: effects.isEmpty || !hasSelectedTargets
                  ? null
                  : () {
                      _daw.copyTrackEffectsToTracks(track, selectedTargets);
                      setDialog(() {});
                      if (_playing) play();
                    },
            ),
            IconButton(
              tooltip: AppLocalizations.of(context)!.dawCopyChainToAllTracks,
              icon: const Icon(Icons.copy_all),
              onPressed: effects.isEmpty || _daw.timeline.tracks.length < 2
                  ? null
                  : () {
                      _daw.copyTrackEffectsToTracks(
                        track,
                        Iterable<int>.generate(_daw.timeline.tracks.length),
                      );
                      setDialog(() {});
                      if (_playing) play();
                    },
            ),
            PopupMenuButton<DawClipEffectPreset>(
              tooltip:
                  AppLocalizations.of(context)!.dawApplyPresetToSelectedTracks,
              icon: const Icon(Icons.playlist_add_check),
              enabled: hasSelectedTargets,
              onSelected: (preset) {
                _daw.applyTrackEffectPresetToTracks(selectedTargets, preset);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final preset in DawClipEffectPreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(_clipEffectPresetLabel(preset)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectType>(
              tooltip:
                  AppLocalizations.of(context)!.dawAddEffectToSelectedTracks,
              icon: const Icon(Icons.add_task),
              enabled: hasSelectedTargets,
              onSelected: (type) {
                _daw.addTrackEffectToTracks(selectedTargets, type);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final type in kDawClipEffectTypes)
                  PopupMenuItem(
                    value: type,
                    child: Text(_clipEffectLabel(type)),
                  ),
              ],
            ),
            _chainClipboardActions(ctx, _daw.trackEffects(track), (chain) {
              _daw.setTrackEffects(track, chain);
              setDialog(() {});
            }),
            PopupMenuButton<DawClipEffectPreset>(
              tooltip: AppLocalizations.of(context)!.dawApplyPreset,
              icon: const Icon(Icons.auto_fix_high),
              onSelected: (preset) {
                _daw.applyTrackEffectPreset(track, preset);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final preset in DawClipEffectPreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(_clipEffectPresetLabel(preset)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectType>(
              tooltip: AppLocalizations.of(context)!.dawAddEffect,
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (type) {
                _daw.addTrackEffect(track, type);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final type in kDawClipEffectTypes)
                  PopupMenuItem(
                    value: type,
                    child: Text(_clipEffectLabel(type)),
                  ),
              ],
            ),
          ],
        ),
        if (effects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              AppLocalizations.of(context)!.dawNoTrackEffects,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
        for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
          _fxTile(
            ctx,
            effects: effects,
            fxIndex: fxIndex,
            onToggle: () {
              _daw.toggleTrackEffect(track, fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onMove: (delta) {
              _daw.moveTrackEffect(track, fxIndex, delta);
              setDialog(() {});
              if (_playing) play();
            },
            onRemove: () {
              _daw.removeTrackEffect(track, fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onParam: (key, value) {
              setDialog(() {
                _daw.setTrackEffectParam(track, fxIndex, key, value);
              });
              if (_playing) play();
            },
            onAutomate: (key, startValue, endValue) async {
              setDialog(() {
                _daw.setTrackEffectAutomation(
                  track,
                  fxIndex,
                  key,
                  _projectRangeAutomationPoints(startValue, endValue),
                );
              });
              if (_playing) play();
            },
            onSetAutomation: (key, points) async {
              setDialog(() {
                _daw.setTrackEffectAutomation(track, fxIndex, key, points);
              });
              if (_playing) play();
            },
          ),
      ],
    );
  }

  /// F3 — the chain string as a copy/paste preset.
  ///
  /// The same text `bin/fxproc.dart --chain` takes, so a chain tuned by ear in
  /// the app pastes straight into a terminal or a test, and one found in a test
  /// pastes back. That round trip is the whole reason the codec exists; without
  /// these two buttons it only ever ran in one direction.
  Widget _chainClipboardActions(
    BuildContext ctx,
    List<DawClipEffect> effects,
    void Function(List<DawClipEffect> chain) onReplace,
  ) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // WS-W6 — saved chains, beside the clipboard actions because they are
          // the same idea with a longer memory: the clipboard holds one chain
          // until you copy the next, this holds the ones worth keeping.
          IconButton(
            key: const ValueKey('daw-fx-presets'),
            tooltip: AppLocalizations.of(context)!.dawSavedChains,
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () async {
              final picked = await showFxPresetSheet(context, current: effects);
              if (picked == null) return;
              onReplace(picked);
              if (_playing) play();
            },
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.dawCopyChain,
            icon: const Icon(Icons.content_copy),
            onPressed: effects.isEmpty
                ? null
                : () async {
                    final text = formatFxChain(effects);
                    await Clipboard.setData(ClipboardData(text: text));
                    // The State's `mounted`, because the snackbar goes through
                    // the State's context — guarding the dialog's context would
                    // be checking the wrong thing.
                    if (!mounted) return;
                    // Automation has no syntax in the string form, so say so
                    // rather than let it vanish silently on the way back.
                    final lossy = !fxChainStringIsLossless(effects);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          lossy ? '$text\n(automation is not copied)' : text,
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.dawPasteChain,
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text?.trim() ?? '';
              if (!mounted || text.isEmpty) return;
              final parsed = parseFxChain(text);
              if (!parsed.ok || parsed.isEmpty) {
                // Report rather than silently doing nothing: the user just
                // pasted something they believed was a chain.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      parsed.errors.isEmpty
                          ? 'That is not an effect chain.'
                          : parsed.errors.first,
                    ),
                  ),
                );
                return;
              }
              onReplace(parsed.chain);
              if (_playing) play();
            },
          ),
        ],
      );

  /// WS-A9 — choose how low the warp has to hold.
  ///
  /// Presented as "the lowest note it keeps" rather than a quality level,
  /// because that is the axis the measurements support: a longer WSOLA frame
  /// holds lower pitches and costs time, and the transient trade this was
  /// scoped around did not reproduce. See `StretchQuality`.
  Future<void> _pickWarpQuality(int track, int index) async {
    final chosen = await showModalBottomSheet<StretchQuality>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              AppLocalizations.of(context)!.dawStretchQuality,
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'A longer window keeps low notes in tune when the clip is '
                'stretched, and takes longer to work out. Below its lowest '
                'note, a stretch drops the pitch rather than just sounding '
                'rougher.',
              ),
            ),
            for (final q in StretchQuality.values)
              ListTile(
                leading: Icon(
                  _daw.clipWarpQuality(track, index) == q
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  switch (q) {
                    StretchQuality.light => 'Light',
                    StretchQuality.balanced => 'Balanced',
                    StretchQuality.deep => 'Deep — for bass',
                  },
                ),
                subtitle: Text(
                  'Keeps notes down to '
                  '${q.lowestReliableHz(kDawSampleRate.toDouble()).round()} Hz',
                ),
                onTap: () => Navigator.of(sheetCtx).pop(q),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _daw.setClipWarpQuality(track, index, chosen);
  }

  /// WS-A7 — turn "follow the project tempo" on or off for one clip.
  ///
  /// A symbolic clip already knows the tempo it is in (a drum pattern carries
  /// its grid), so it just toggles. A RECORDING cannot know, and that is the
  /// case warping most exists for — so it asks, rather than hiding the feature
  /// exactly where it is most wanted or guessing a number that would shift the
  /// arrangement's timing invisibly.
  Future<void> _toggleClipWarp(int track, int index) async {
    if (_daw.clipWarps(track, index)) {
      _daw.setClipWarp(track, index, false);
      return;
    }
    var bpm = _daw.clipNativeBpm(track, index);
    if (bpm == null) {
      bpm = await _askNativeBpm();
      if (bpm == null) return; // cancelled — do nothing at all
    }
    _daw.setClipWarp(track, index, true, nativeBpm: bpm);
  }

  /// Ask what tempo a recording was played at.
  Future<double?> _askNativeBpm() async {
    final controller = TextEditingController(text: _daw.bpm.round().toString());
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.dawClipTempoQuestion),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The tempo it was played at. Following the project tempo '
              'stretches it from there, without changing its pitch.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'BPM'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              // An unparseable or out-of-range tempo returns nothing rather
              // than a clamped guess: the number IS the feature here.
              Navigator.of(ctx).pop(
                value != null && value >= kMinBpm && value <= kMaxBpm
                    ? value
                    : null,
              );
            },
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  /// WS-A5 — measure the mix and say what the numbers MEAN.
  ///
  /// Measures the marked range when there is one, because "is the chorus
  /// louder than the verse" is the question people actually have; otherwise the
  /// whole mix. The judgement lives in `loudness_advice.dart` rather than here,
  /// so it can be tested — a meter that renders beautifully and reasons wrongly
  /// is worse than none, because it is trusted.
  Future<void> _showLoudness() async {
    var target = LoudnessTarget.streaming;
    final mix = _daw.bakeStereo();
    if (mix.left.isEmpty) return;

    Float64List slice(Float64List channel) {
      if (!_hasFxRange) return channel;
      final from = (_rangeStartMs * kDawSampleRate / 1000)
          .round()
          .clamp(0, channel.length);
      final to = (_rangeEndMs * kDawSampleRate / 1000)
          .round()
          .clamp(from, channel.length);
      return Float64List.sublistView(channel, from, to);
    }

    final reading = measureLoudness(
      slice(mix.left),
      slice(mix.right),
      sampleRate: kDawSampleRate,
    );
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final notes = loudnessAdvice(reading, target: target);
          final scheme = Theme.of(sheetCtx).colorScheme;
          Color colourFor(LoudnessStatus s) => switch (s) {
                LoudnessStatus.good => scheme.primary,
                LoudnessStatus.note => scheme.onSurfaceVariant,
                LoudnessStatus.warn => scheme.error,
              };
          IconData iconFor(LoudnessStatus s) => switch (s) {
                LoudnessStatus.good => Icons.check_circle_outline,
                LoudnessStatus.note => Icons.info_outline,
                LoudnessStatus.warn => Icons.warning_amber_outlined,
              };
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  _hasFxRange ? 'Loudness — marked range' : 'Loudness — mix',
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                // The target first: every level judgement below depends on it,
                // so choosing it afterwards would read as the meter changing
                // its mind.
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in LoudnessTarget.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: target == t,
                        onSelected: (_) => setSheet(() => target = t),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    target.blurb,
                    style: Theme.of(sheetCtx).textTheme.bodySmall,
                  ),
                ),
                const Divider(),
                for (final note in notes)
                  ListTile(
                    leading: Icon(
                      iconFor(note.status),
                      color: colourFor(note.status),
                    ),
                    title: Text(note.headline),
                    subtitle: Text(note.detail),
                    isThreeLine: true,
                  ),
                const Divider(),
                // The raw numbers stay available underneath the reading of
                // them — the advice is the point, but someone checking a
                // delivery spec needs the figures themselves.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Integrated ${reading.integratedLufs.toStringAsFixed(1)} · '
                    'short ${reading.shortTermLufs.toStringAsFixed(1)} · '
                    'momentary ${reading.momentaryLufs.toStringAsFixed(1)} LUFS'
                    '   ·   ${reading.truePeakDb.toStringAsFixed(2)} dBTP'
                    '   ·   phase ${reading.correlation.toStringAsFixed(2)}',
                    style: Theme.of(sheetCtx).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _masterFxMenu() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.dawMasterFx),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: _masterFxEditor(ctx, setDialog),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx)!.dawCancel),
          ),
        ],
      ),
    );
  }

  Widget _masterFxEditor(BuildContext ctx, StateSetter setDialog) {
    final effects = _daw.masterEffects();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)!.dawOutputBus,
              style: Theme.of(ctx).textTheme.labelLarge,
            ),
            const Spacer(),
            _chainClipboardActions(ctx, effects, (chain) {
              _daw.setMasterEffects(chain);
              setDialog(() {});
            }),
            PopupMenuButton<DawClipEffectPreset>(
              tooltip: AppLocalizations.of(context)!.dawApplyPreset,
              icon: const Icon(Icons.auto_fix_high),
              onSelected: (preset) {
                _daw.applyMasterEffectPreset(preset);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final preset in DawClipEffectPreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(_clipEffectPresetLabel(preset)),
                  ),
              ],
            ),
            PopupMenuButton<DawClipEffectType>(
              tooltip: AppLocalizations.of(context)!.dawAddEffect,
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (type) {
                _daw.addMasterEffect(type);
                setDialog(() {});
                if (_playing) play();
              },
              itemBuilder: (_) => [
                for (final type in kDawClipEffectTypes)
                  PopupMenuItem(
                    value: type,
                    child: Text(_clipEffectLabel(type)),
                  ),
              ],
            ),
          ],
        ),
        if (effects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              AppLocalizations.of(context)!.dawNoMasterEffects,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
        for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
          _fxTile(
            ctx,
            effects: effects,
            fxIndex: fxIndex,
            onToggle: () {
              _daw.toggleMasterEffect(fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onMove: (delta) {
              _daw.moveMasterEffect(fxIndex, delta);
              setDialog(() {});
              if (_playing) play();
            },
            onRemove: () {
              _daw.removeMasterEffect(fxIndex);
              setDialog(() {});
              if (_playing) play();
            },
            onParam: (key, value) {
              setDialog(() => _daw.setMasterEffectParam(fxIndex, key, value));
              if (_playing) play();
            },
            onAutomate: (key, startValue, endValue) async {
              setDialog(() {
                _daw.setMasterEffectAutomation(
                  fxIndex,
                  key,
                  _projectRangeAutomationPoints(startValue, endValue),
                );
              });
              if (_playing) play();
            },
            onSetAutomation: (key, points) async {
              setDialog(() {
                _daw.setMasterEffectAutomation(fxIndex, key, points);
              });
              if (_playing) play();
            },
          ),
      ],
    );
  }

  Future<void> _busMenu() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.dawBuses),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          _daw.addBus();
                          setDialog(() {});
                        },
                        icon: const Icon(Icons.add),
                        label: Text(AppLocalizations.of(context)!.dawAddBus),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _explicitSelectedTracks().isEmpty
                            ? null
                            : () {
                                _daw.setTrackBusForTracks(
                                  _explicitSelectedTracks(),
                                  null,
                                );
                                setDialog(() {});
                                _rebuild(() {});
                                if (_playing) play();
                              },
                        icon: const Icon(Icons.output),
                        label: Text(
                          AppLocalizations.of(context)!
                              .dawRouteSelectedToMaster,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_daw.buses().isEmpty)
                    Text(
                      AppLocalizations.of(context)!.dawNoBuses,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  if (_daw.buses().isNotEmpty) ...[
                    _busMixerMatrix(ctx, setDialog),
                    const SizedBox(height: 12),
                  ],
                  for (var bus = 0; bus < _daw.buses().length; bus++)
                    _busEditor(ctx, bus, setDialog),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx)!.dawCancel),
          ),
        ],
      ),
    );
  }

  Widget _busMixerMatrix(BuildContext ctx, StateSetter setDialog) {
    final buses = _daw.buses();
    final tracks = _daw.timeline.tracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.mixerConsoleTitle,
          style: Theme.of(ctx).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (var track = 0; track < tracks.length; track++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tracks[track].name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.labelMedium,
                          ),
                        ),
                        DropdownButton<int?>(
                          key: ValueKey('bus-route-$track'),
                          value: _validRouteValue(tracks[track].busIndex),
                          onChanged: (route) {
                            _daw.setTrackBus(track, route);
                            setDialog(() {});
                            _rebuild(() {});
                            if (_playing) play();
                          },
                          items: [
                            DropdownMenuItem<int?>(
                              child:
                                  Text(AppLocalizations.of(context)!.dawMaster),
                            ),
                            for (var bus = 0; bus < buses.length; bus++)
                              DropdownMenuItem<int?>(
                                value: bus,
                                child: Text(_busDisplayName(bus)),
                              ),
                          ],
                        ),
                      ],
                    ),
                    for (var bus = 0; bus < buses.length; bus++)
                      Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              _busDisplayName(bus),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              key: ValueKey('bus-send-$track-$bus'),
                              value: _daw.trackSend(track, bus),
                              max: 1.5,
                              divisions: 30,
                              label:
                                  _daw.trackSend(track, bus).toStringAsFixed(2),
                              onChanged: (value) {
                                setDialog(() {
                                  _daw.setTrackSend(track, bus, value);
                                });
                                _rebuild(() {});
                                if (_playing) play();
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  int? _validRouteValue(int? route) =>
      route != null && route >= 0 && route < _daw.buses().length ? route : null;

  String _busDisplayName(int bus) {
    final buses = _daw.buses();
    if (bus < 0 || bus >= buses.length) {
      return AppLocalizations.of(context)!.dawBusN(bus + 1);
    }
    return buses[bus].name.isEmpty
        ? AppLocalizations.of(context)!.dawBusN(bus + 1)
        : buses[bus].name;
  }

  Future<void> _renameBusDialog(
    BuildContext ctx,
    int bus,
    StateSetter setDialog,
  ) async {
    if (bus < 0 || bus >= _daw.buses().length) return;
    var draft = _busDisplayName(bus);
    final name = await showDialog<String>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.dawRenameBus),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.dawBusName,
          ),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) => Navigator.of(dialogCtx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(AppLocalizations.of(dialogCtx)!.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(draft),
            child: Text(AppLocalizations.of(context)!.dawRenameTrack),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    _daw.renameBus(bus, trimmed);
    setDialog(() {});
    _rebuild(() {});
  }

  Widget _busEditor(BuildContext ctx, int bus, StateSetter setDialog) {
    final buses = _daw.buses();
    final routeTargets = _explicitSelectedTracks();
    if (bus < 0 || bus >= buses.length) return const SizedBox.shrink();
    final routeCount =
        _daw.timeline.tracks.where((track) => track.busIndex == bus).length;
    final name = _busDisplayName(bus);
    final effects = _daw.busEffects(bus);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.dawTrackCount(routeCount),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.dawRenameBus,
                    icon: const Icon(Icons.drive_file_rename_outline),
                    onPressed: () => _renameBusDialog(ctx, bus, setDialog),
                  ),
                  IconButton(
                    tooltip:
                        AppLocalizations.of(context)!.dawRouteSelectedToBus,
                    icon: const Icon(Icons.call_merge),
                    onPressed: routeTargets.isEmpty
                        ? null
                        : () {
                            _daw.setTrackBusForTracks(routeTargets, bus);
                            setDialog(() {});
                            _rebuild(() {});
                            if (_playing) play();
                          },
                  ),
                  PopupMenuButton<DawClipEffectPreset>(
                    tooltip: AppLocalizations.of(context)!.dawApplyPreset,
                    icon: const Icon(Icons.auto_fix_high),
                    onSelected: (preset) {
                      _daw.applyBusEffectPreset(bus, preset);
                      setDialog(() {});
                      if (_playing) play();
                    },
                    itemBuilder: (_) => [
                      for (final preset in DawClipEffectPreset.values)
                        PopupMenuItem(
                          value: preset,
                          child: Text(_clipEffectPresetLabel(preset)),
                        ),
                    ],
                  ),
                  PopupMenuButton<DawClipEffectType>(
                    tooltip: AppLocalizations.of(context)!.dawAddEffect,
                    icon: const Icon(Icons.add_circle_outline),
                    onSelected: (type) {
                      _daw.addBusEffect(bus, type);
                      setDialog(() {});
                      if (_playing) play();
                    },
                    itemBuilder: (_) => [
                      for (final type in kDawClipEffectTypes)
                        PopupMenuItem(
                          value: type,
                          child: Text(_clipEffectLabel(type)),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.dawRemoveBus,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      _daw.removeBus(bus);
                      setDialog(() {});
                      _rebuild(() {});
                      if (_playing) play();
                    },
                  ),
                ],
              ),
              if (effects.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    AppLocalizations.of(context)!.dawNoBusEffects,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              if (routeTargets.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${routeTargets.length} selected send',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    Expanded(
                      child: Slider(
                        value: _averageTrackSend(routeTargets, bus),
                        max: 1.5,
                        divisions: 30,
                        label: _averageTrackSend(
                          routeTargets,
                          bus,
                        ).toStringAsFixed(2),
                        onChanged: (value) {
                          setDialog(() {
                            _daw.setTrackSendForTracks(
                              routeTargets,
                              bus,
                              value,
                            );
                          });
                          _rebuild(() {});
                          if (_playing) play();
                        },
                      ),
                    ),
                  ],
                ),
              ],
              for (var fxIndex = 0; fxIndex < effects.length; fxIndex++)
                _fxTile(
                  ctx,
                  effects: effects,
                  fxIndex: fxIndex,
                  onToggle: () {
                    _daw.toggleBusEffect(bus, fxIndex);
                    setDialog(() {});
                    if (_playing) play();
                  },
                  onMove: (delta) {
                    _daw.moveBusEffect(bus, fxIndex, delta);
                    setDialog(() {});
                    if (_playing) play();
                  },
                  onRemove: () {
                    _daw.removeBusEffect(bus, fxIndex);
                    setDialog(() {});
                    if (_playing) play();
                  },
                  onParam: (key, value) {
                    setDialog(
                      () => _daw.setBusEffectParam(bus, fxIndex, key, value),
                    );
                    if (_playing) play();
                  },
                  onAutomate: (key, startValue, endValue) async {
                    setDialog(() {
                      _daw.setBusEffectAutomation(
                        bus,
                        fxIndex,
                        key,
                        _projectRangeAutomationPoints(startValue, endValue),
                      );
                    });
                    if (_playing) play();
                  },
                  onSetAutomation: (key, points) async {
                    setDialog(() {
                      _daw.setBusEffectAutomation(bus, fxIndex, key, points);
                    });
                    if (_playing) play();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _averageTrackSend(List<int> tracks, int bus) {
    if (tracks.isEmpty) return 0;
    var sum = 0.0;
    for (final track in tracks) {
      sum += _daw.trackSend(track, bus);
    }
    return sum / tracks.length;
  }

  List<int> _explicitSelectedTracks() {
    final targets = [
      for (final i in _selectedTracks)
        if (i >= 0 && i < _daw.timeline.tracks.length) i,
    ]..sort();
    return targets;
  }

  List<int> _selectedTrackTargets(int fallbackTrack) {
    final targets = _explicitSelectedTracks();
    return targets.isEmpty ? [fallbackTrack] : targets;
  }

  bool _validClipSelection(DawClipTarget target) =>
      target.track >= 0 &&
      target.track < _daw.timeline.tracks.length &&
      target.index >= 0 &&
      target.index < _daw.timeline.tracks[target.track].clips.length;

  List<DawClipTarget> _selectedClipTargets(
    int fallbackTrack,
    int fallbackIndex,
  ) {
    final targets = [
      for (final target in _selectedClips)
        if (_validClipSelection(target)) target,
    ]..sort((a, b) {
        final byTrack = a.track.compareTo(b.track);
        return byTrack != 0 ? byTrack : a.index.compareTo(b.index);
      });
    return targets.isEmpty
        ? [(track: fallbackTrack, index: fallbackIndex)]
        : targets;
  }

  bool get _hasSelectedClips => _selectedClips.any(_validClipSelection);

  void _copySelectedClips() {
    final copies = [
      for (final target in _selectedClips)
        if (_validClipSelection(target))
          (
            track: target.track,
            clip: _daw.timeline.tracks[target.track].clips[target.index],
          ),
    ];
    if (copies.isEmpty) return;
    _rebuild(() {
      _clipClipboard
        ..clear()
        ..addAll(copies);
    });
  }

  void _deleteSelectedClips({bool copyFirst = false}) {
    final targets = [
      for (final target in _selectedClips)
        if (_validClipSelection(target)) target,
    ];
    if (targets.isEmpty) return;
    if (copyFirst) _copySelectedClips();
    final removed = _daw.removeClipTargets(targets);
    if (removed == 0) return;
    _rebuild(() {
      _selectedClips
        ..clear()
        ..removeWhere((target) => !_validClipSelection(target));
    });
    if (_playing) play();
  }

  void _pasteClipClipboard() {
    if (_clipClipboard.isEmpty) return;
    final pasted = _daw.pasteClipCopies(_clipClipboard, playheadMs);
    if (pasted.isEmpty) return;
    _rebuild(() {
      _selectedClips
        ..clear()
        ..addAll(pasted);
    });
    if (_playing) play();
  }

  bool get _hasFxRange => _range.isSet;

  double get _rangeStartMs => _range.startMs;
  double get _rangeEndMs => _range.endMs;

  String _rangeLabel() => _range.label();

  List<int> _rangeTargetTracks() => DawMarkedRange.targetTracks(
        _selectedTracks,
        _daw.timeline.tracks.length,
      );

  void _markRangeIn() => _rebuild(() => _range.markIn(playheadMs));

  void _markRangeOut() => _rebuild(() => _range.markOut(playheadMs));

  void _addRangeEffect(DawClipEffectType type) {
    if (!_hasFxRange) return;
    _daw.addClipEffectToRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      type,
    );
    if (_playing) play();
  }

  void _applyRangePreset(DawClipEffectPreset preset) {
    if (!_hasFxRange) return;
    _daw.applyClipEffectPresetToRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      preset,
    );
    if (_playing) play();
  }

  Future<void> _rangeGainDialog() async {
    if (!_hasFxRange) return;
    var multiplier = 0.5;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.dawRangeGain),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel()),
                const SizedBox(height: 8),
                Slider(
                  value: multiplier,
                  max: 2,
                  divisions: 40,
                  label: '${(multiplier * 100).round()}%',
                  onChanged: (value) => setDialog(() => multiplier = value),
                ),
                Text('${(multiplier * 100).round()}%'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(context)!.dawAmplifyApply),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    _daw.multiplyClipGainInRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      multiplier,
    );
    if (_playing) play();
  }

  /// O15 — the clip's frequency content over time. Uses the clip's PLAYED
  /// window (trim folded in), so what you see is what you hear.
  void _showClipSpectrogram(int track, int index) {
    final pcm = _daw.clipWindowPcm(track, index);
    if (pcm.isEmpty) return;
    showSpectrogramDialog(context, pcm: pcm, sampleRate: kDawSampleRate);
  }

  /// O13 — name a marker as it's dropped. An empty name is fine (the flag
  /// alone is a useful "come back here"), so Add is never blocked.
  Future<void> _addMarkerAtPlayhead() async {
    final l10n = AppLocalizations.of(context)!;
    final at = playheadMs;
    // NB: TextFormField, not TextField + our own controller — a controller we
    // dispose right after the pop is still referenced by the field while the
    // dialog animates out, which corrupts the focus tree.
    var text = '';
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawAddMarker),
        content: TextFormField(
          // Keyed since the screen now hosts the shared transport bar, which
          // carries a tempo field of its own: "the screen's only text field" is
          // no longer a way to name this one.
          key: const ValueKey('daw-marker-name'),
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.dawMarkerName),
          onChanged: (v) => text = v,
          onFieldSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(text),
            child: Text(l10n.dawAmplifyApply),
          ),
        ],
      ),
    );
    if (label == null) return;
    _daw.addMarker(at, label.trim());
  }

  /// Tap a marker flag → rename, move it here, or delete it.
  Future<void> _markerMenu(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final marker = _daw.markers[index];
    var text = marker.label;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dawMarkers),
        content: TextFormField(
          autofocus: true,
          initialValue: marker.label,
          decoration: InputDecoration(labelText: l10n.dawMarkerName),
          onChanged: (v) => text = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('delete'),
            child: Text(l10n.dawDelete),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.dawCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('rename'),
            child: Text(l10n.dawAmplifyApply),
          ),
        ],
      ),
    );
    if (action == 'delete') {
      _daw.removeMarker(index);
    } else if (action == 'rename') {
      _daw.renameMarker(index, text.trim());
    }
  }

  /// O12 — a live peak/RMS meter. The filled bar is RMS (how loud it *feels*),
  /// the bright tick is the peak (what actually clips), on a −60…0 dBFS scale.
  /// It repaints off the playhead notifier, so it costs nothing when stopped.
  Widget _levelMeter(AppLocalizations l10n) {
    double norm(double amplitude) {
      if (amplitude <= 0) return 0;
      final db = 20 * math.log(amplitude) / math.ln10;
      return ((db + 60) / 60).clamp(0.0, 1.0);
    }

    return ValueListenableBuilder<double>(
      valueListenable: _positionMs,
      builder: (ctx, _, __) {
        final level = playbackLevel;
        final scheme = Theme.of(ctx).colorScheme;
        final hot = level.peak >= 1;
        return Tooltip(
          message: '${l10n.dawLevel} — RMS / peak dBFS',
          child: SizedBox(
            width: 96,
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: norm(level.rms),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: hot ? scheme.error : scheme.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                // The peak tick rides ahead of the RMS fill.
                Align(
                  alignment: Alignment(2 * norm(level.peak) - 1, 0),
                  child: Container(
                    width: 2,
                    height: 14,
                    color: level.peak <= 0
                        ? Colors.transparent
                        : (hot ? scheme.error : scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _shapeLabel(GeneratorShape shape, AppLocalizations l10n) =>
      switch (shape) {
        GeneratorShape.sine => l10n.dawShapeSine,
        GeneratorShape.square => l10n.dawShapeSquare,
        GeneratorShape.saw => l10n.dawShapeSaw,
        GeneratorShape.triangle => l10n.dawShapeTriangle,
        GeneratorShape.whiteNoise => l10n.dawShapeWhiteNoise,
        GeneratorShape.pinkNoise => l10n.dawShapePinkNoise,
        GeneratorShape.silence => l10n.dawShapeSilence,
        // A7 — left untranslated on purpose, the same call the FX rack makes
        // for its effect names: these are established audio-engineering terms
        // that appear in English in every tool the user will meet, and the
        // alternative is seven new keys in the hot shared ARBs to invent
        // German for "violet noise".
        GeneratorShape.brownNoise => 'Brown noise',
        GeneratorShape.blueNoise => 'Blue noise',
        GeneratorShape.violetNoise => 'Violet noise',
        GeneratorShape.sweep => 'Sweep (linear)',
        GeneratorShape.logSweep => 'Sweep (log)',
        GeneratorShape.pluck => 'Plucked string',
        GeneratorShape.impulse => 'Impulse',
      };

  /// Whether a frequency control means anything for [shape].
  ///
  /// Listed as what IS pitched rather than what is not: a new noise colour
  /// added to the enum should default to hiding the control, not to showing a
  /// frequency slider that does nothing.

  /// O7 — build a tone / noise / silence clip from scratch onto a new lane.
  Future<void> _generateClipDialog() async {
    final l10n = AppLocalizations.of(context)!;
    var shape = GeneratorShape.sine;
    var freq = 440.0;
    var endFreq = 8000.0;
    var seconds = 2.0;
    var amp = 0.5;
    final made = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final pitched = _DawScreenState._shapeIsPitched(shape);
          final sweeping =
              shape == GeneratorShape.sweep || shape == GeneratorShape.logSweep;
          return AlertDialog(
            title: Text(l10n.dawGenerate),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<GeneratorShape>(
                    value: shape,
                    isExpanded: true,
                    onChanged: (v) {
                      if (v != null) setDialog(() => shape = v);
                    },
                    items: [
                      for (final s in GeneratorShape.values)
                        DropdownMenuItem(
                          value: s,
                          child: Text(_shapeLabel(s, l10n)),
                        ),
                    ],
                  ),
                  // Frequency only means something for the tone shapes.
                  if (pitched) ...[
                    Text(
                      '${l10n.dawFrequency} ${freq.round()} Hz'
                      '${sweeping ? ' → ${endFreq.round()} Hz' : ''}',
                    ),
                    Slider(
                      value: freq,
                      min: 20,
                      max: 4000,
                      label: '${freq.round()} Hz',
                      onChanged: (v) => setDialog(() => freq = v),
                    ),
                  ],
                  // A sweep needs somewhere to sweep TO.
                  if (sweeping)
                    Slider(
                      value: endFreq,
                      min: 40,
                      max: 20000,
                      label: '${endFreq.round()} Hz',
                      onChanged: (v) => setDialog(() => endFreq = v),
                    ),
                  Text('${l10n.dawLength} ${seconds.toStringAsFixed(1)} s'),
                  Slider(
                    value: seconds,
                    min: 0.1,
                    max: 30,
                    onChanged: (v) => setDialog(() => seconds = v),
                  ),
                  if (shape != GeneratorShape.silence) ...[
                    Text('${l10n.dawLevel} ${(amp * 100).round()}%'),
                    Slider(
                      value: amp,
                      onChanged: (v) => setDialog(() => amp = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.dawCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.dawAmplifyApply),
              ),
            ],
          );
        },
      ),
    );
    if (made != true) return;
    generateClip(
      shape: shape,
      freq: freq,
      endFreq: endFreq,
      seconds: seconds,
      amp: amp,
    );
  }

  /// Ocenaudio's "Amplify": pick a gain in dB and bake it into the clip.
  Future<void> _amplifyClipDialog(int track, int index) async {
    final l10n = AppLocalizations.of(context)!;
    var db = 3.0;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(l10n.dawAmplify),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB'),
                Slider(
                  value: db,
                  min: -24,
                  max: 24,
                  divisions: 96,
                  label: '${db.toStringAsFixed(1)} dB',
                  onChanged: (value) => setDialog(() => db = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.dawAmplifyApply),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    amplifyClip(track, index, db);
    if (_playing) play();
  }

  Future<void> _trackAutomationDialog() async {
    if (!_hasFxRange) return;
    var startGain = 1.0;
    var endGain = 0.5;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.dawTrackAutomation),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel()),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!
                      .dawStartPercent((startGain * 100).round()),
                ),
                Slider(
                  value: startGain,
                  max: 2,
                  divisions: 40,
                  label: '${(startGain * 100).round()}%',
                  onChanged: (value) => setDialog(() => startGain = value),
                ),
                Text(
                  AppLocalizations.of(context)!
                      .dawEndPercent((endGain * 100).round()),
                ),
                Slider(
                  value: endGain,
                  max: 2,
                  divisions: 40,
                  label: '${(endGain * 100).round()}%',
                  onChanged: (value) => setDialog(() => endGain = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(context)!.dawAmplifyApply),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    _daw.setTrackGainAutomationInRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      startGain,
      endGain,
    );
    if (_playing) play();
  }

  String _fadeCurveLabel(DawFadeCurve curve) => switch (curve) {
        DawFadeCurve.linear => 'Linear',
        DawFadeCurve.exponential => 'Exponential',
        DawFadeCurve.sCurve => 'S-Curve',
      };

  void _applyRangeFade({
    required bool fadeIn,
    DawFadeCurve curve = DawFadeCurve.linear,
  }) {
    if (!_hasFxRange) return;
    if (fadeIn) {
      _daw.applyFadeInToRange(
        _rangeTargetTracks(),
        _rangeStartMs,
        _rangeEndMs,
        curve,
      );
    } else {
      _daw.applyFadeOutToRange(
        _rangeTargetTracks(),
        _rangeStartMs,
        _rangeEndMs,
        curve,
      );
    }
    if (_playing) play();
  }

  void _silenceMarkedRange() {
    if (!_hasFxRange) return;
    silenceRange(_rangeTargetTracks(), _rangeStartMs, _rangeEndMs);
    if (_playing) play();
  }

  void _cropToMarkedRange() {
    if (!_hasFxRange) return;
    cropToRange(_rangeTargetTracks(), _rangeStartMs, _rangeEndMs);
    if (_playing) play();
  }

  /// D1 — remove the marked span AND the time it occupied.
  ///
  /// Deliberately not scoped to the selected lanes, unlike its neighbours in
  /// this menu: rippling some lanes and not others slides the arrangement out
  /// of sync with itself. "Just here" is what Silence is for.
  void _rippleDeleteMarkedRange() {
    if (!_hasFxRange) return;
    _daw.rippleDelete(_rangeStartMs, _rangeEndMs);
    _rebuild(() {});
    if (_playing) play();
  }

  /// D1 — open the marked span as empty time, sliding everything after it.
  void _rippleInsertMarkedRange() {
    if (!_hasFxRange) return;
    _daw.rippleInsert(_rangeStartMs, _rangeEndMs - _rangeStartMs);
    _rebuild(() {});
    if (_playing) play();
  }

  void _setRangeMuted(bool muted) {
    if (!_hasFxRange) return;
    _daw.setClipMutedInRange(
      _rangeTargetTracks(),
      _rangeStartMs,
      _rangeEndMs,
      muted,
    );
    if (_playing) play();
  }

  List<DawAutomationPoint> _projectRangeAutomationPoints(
    double startValue,
    double endValue,
  ) =>
      [
        DawAutomationPoint(ms: _rangeStartMs, value: startValue),
        DawAutomationPoint(ms: _rangeEndMs, value: endValue),
      ];

  List<DawAutomationPoint> _clipRangeAutomationPoints(
    int track,
    int index,
    double startValue,
    double endValue,
  ) {
    final clipStart = _daw.clipStartMs(track, index);
    final clipEnd = clipStart + _daw.clipDurationMs(track, index);
    final from = math.max(_rangeStartMs, clipStart);
    final to = math.min(_rangeEndMs, clipEnd);
    if (to <= from) return const [];
    return [
      DawAutomationPoint(ms: from - clipStart, value: startValue),
      DawAutomationPoint(ms: to - clipStart, value: endValue),
    ];
  }

  Widget _fxTile(
    BuildContext ctx, {
    required List<DawClipEffect> effects,
    required int fxIndex,
    required VoidCallback onToggle,
    required void Function(int delta) onMove,
    required VoidCallback onRemove,
    required void Function(String key, double value) onParam,
    Future<void> Function(String key, double startValue, double endValue)?
        onAutomate,
    Future<void> Function(String key, List<DawAutomationPoint> points)?
        onSetAutomation,
  }) {
    final fx = effects[fxIndex];
    final specs = _clipEffectParams(fx.type);
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      leading: IconButton(
        icon: Icon(fx.enabled ? Icons.power_settings_new : Icons.power_off),
        tooltip: fx.enabled ? 'Bypass' : 'Enable',
        onPressed: onToggle,
      ),
      title: Text(_clipEffectLabel(fx.type)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: AppLocalizations.of(context)!.dawMoveUp,
            onPressed: fxIndex == 0 ? null : () => onMove(-1),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward),
            tooltip: AppLocalizations.of(context)!.dawMoveDown,
            onPressed: fxIndex == effects.length - 1 ? null : () => onMove(1),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: AppLocalizations.of(context)!.dawRemoveEffect,
            onPressed: onRemove,
          ),
        ],
      ),
      children: [
        for (final spec in specs)
          _effectParamSlider(
            spec.label,
            fx.params[spec.key] ??
                defaultDawClipEffect(fx.type).params[spec.key] ??
                spec.min,
            spec.min,
            spec.max,
            spec.step,
            automation: fx.automation[spec.key] ?? const [],
            (v) => onParam(spec.key, v),
            onAutomate: onAutomate == null || !_hasFxRange
                ? null
                : () async {
                    final current = fx.params[spec.key] ??
                        defaultDawClipEffect(fx.type).params[spec.key] ??
                        spec.min;
                    final values = await _fxAutomationDialog(
                      ctx,
                      label: spec.label,
                      min: spec.min,
                      max: spec.max,
                      step: spec.step,
                      startValue: current,
                      endValue: current,
                    );
                    if (values == null) return;
                    await onAutomate(
                      spec.key,
                      values.startValue,
                      values.endValue,
                    );
                  },
            onEditAutomation: onSetAutomation == null ||
                    (fx.automation[spec.key] ?? const []).isEmpty
                ? null
                : () async {
                    final points = fx.automation[spec.key] ?? const [];
                    final edited = await _fxAutomationPointsDialog(
                      ctx,
                      label: spec.label,
                      min: spec.min,
                      max: spec.max,
                      step: spec.step,
                      points: points,
                    );
                    if (edited == null) return;
                    await onSetAutomation(spec.key, edited);
                  },
            onClearAutomation: onSetAutomation == null ||
                    (fx.automation[spec.key] ?? const []).isEmpty
                ? null
                : () async => onSetAutomation(spec.key, const []),
          ),
      ],
    );
  }

  /// D5 — audition the alternative takes of a clip, and fold parallel clips in
  /// as more of them.
  ///
  /// Switching plays immediately rather than on a confirm: the whole reason to
  /// keep alternatives is comparing them by ear, and a dialog that only commits
  /// on OK makes that a chore. The sheet stays open for the same reason.
  Future<void> _pickTake(int track, int index) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final count = _daw.takeCount(track, index);
          final active = _daw.activeTake(track, index);
          // Clips that overlap this one in time are the ones plausibly being
          // ANOTHER PASS at the same passage — the only ones worth offering to
          // stack, and the workflow lanes of takes come from.
          final candidates = _overlappingClips(track, index);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  AppLocalizations.of(context)!.dawTakes,
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (count <= 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'One take. Record the part again on another lane, then '
                      'stack it here to compare them.',
                    ),
                  )
                else
                  RadioGroup<int>(
                    groupValue: active,
                    onChanged: (chosen) {
                      if (chosen == null) return;
                      _daw.selectTake(track, index, chosen);
                      setSheet(() {});
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < count; i++)
                          RadioListTile<int>(
                            value: i,
                            title: Text(
                              AppLocalizations.of(context)!.dawTakeN(i + 1),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (candidates.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    AppLocalizations.of(context)!.dawStackAsTake,
                    style: Theme.of(sheetCtx).textTheme.labelLarge,
                  ),
                  for (final candidate in candidates)
                    ListTile(
                      leading: const Icon(Icons.layers),
                      title: Text(
                        'Lane ${candidate.track + 1} · '
                        '${_clipKind(_daw.timeline.tracks[candidate.track].clips[candidate.index])} '
                        'at ${_daw.timeline.tracks[candidate.track].clips[candidate.index].startMs.round()} ms',
                      ),
                      subtitle: Text(
                        AppLocalizations.of(context)!.dawStackAsTakeHint,
                      ),
                      onTap: () {
                        _daw.stackAsTake(
                          track,
                          index,
                          candidate.track,
                          candidate.index,
                        );
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Clips elsewhere on the timeline whose played window overlaps this one's.
  List<({int track, int index})> _overlappingClips(int track, int index) {
    if (index >= _daw.timeline.tracks[track].clips.length) return const [];
    final start = _daw.timeline.tracks[track].clips[index].startMs;
    final end = start + _daw.clipDurationMs(track, index);
    final out = <({int track, int index})>[];
    for (var t = 0; t < _daw.timeline.tracks.length; t++) {
      final clips = _daw.timeline.tracks[t].clips;
      for (var i = 0; i < clips.length; i++) {
        if (t == track && i == index) continue;
        final otherStart = clips[i].startMs;
        final otherEnd = otherStart + _daw.clipDurationMs(t, i);
        if (otherStart < end && otherEnd > start) {
          out.add((track: t, index: i));
        }
      }
    }
    return out;
  }

  /// D3 — draw a gain envelope over one clip.
  ///
  /// Seeded with a flat line across the clip when it has none, because the
  /// shared points dialog edits an EXISTING curve and returns null for an empty
  /// one — there would otherwise be no way to make a first envelope.
  Future<void> _editClipEnvelope(int track, int index) async {
    final existing = _daw.clipGainAutomation(track, index);
    final duration = _daw.clipDurationMs(track, index);
    final seeded = existing.isNotEmpty
        ? existing
        : [
            const DawAutomationPoint(ms: 0, value: 1),
            DawAutomationPoint(ms: math.max(duration, 1), value: 1),
          ];
    final edited = await _fxAutomationPointsDialog(
      context,
      label: AppLocalizations.of(context)!.dawClipGainLabel,
      min: 0,
      max: 2,
      // A gain multiplier reads in hundredths; the same step the mix and gain
      // sliders use.
      step: 0.01,
      points: seeded,
    );
    if (edited == null) return;
    _daw.setClipGainAutomation(track, index, edited);
    if (_playing) play();
  }

  Future<List<DawAutomationPoint>?> _fxAutomationPointsDialog(
    BuildContext ctx, {
    required String label,
    required double min,
    required double max,
    required double step,
    required List<DawAutomationPoint> points,
  }) async {
    if (points.isEmpty) return null;
    final edited = [...points]..sort((a, b) => a.ms.compareTo(b.ms));
    for (var i = 0; i < edited.length; i++) {
      edited[i] = edited[i].copyWith(
        value: edited[i].value.clamp(min, max).toDouble(),
      );
    }
    final timeMax = math
        .max(
          edited.last.ms,
          math.max(_rangeEndMs, 1000),
        )
        .toDouble();
    return showDialog<List<DawAutomationPoint>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.dawEditAutomation(label)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Draw the shape; the numeric list below stays for precise
                  // values and for anyone who can't drag.
                  AutomationCurveEditor(
                    points: edited,
                    min: min,
                    max: max,
                    timeMax: timeMax,
                    onChanged: (next) => setDialog(() {
                      edited
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(dialogCtx)!.dawCurveHint,
                    style: Theme.of(dialogCtx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.dawPointCount(edited.length),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < edited.length; index++)
                    _automationPointEditor(
                      point: edited[index],
                      index: index,
                      count: edited.length,
                      min: min,
                      max: max,
                      step: step,
                      timeMax: timeMax,
                      onChanged: (point) => setDialog(() {
                        edited[index] = point;
                        edited.sort((a, b) => a.ms.compareTo(b.ms));
                      }),
                      onRemove: edited.length <= 2
                          ? null
                          : () => setDialog(() => edited.removeAt(index)),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setDialog(() {
                      var gapIndex = 0;
                      var gap = -1.0;
                      for (var i = 0; i < edited.length - 1; i++) {
                        final candidate = edited[i + 1].ms - edited[i].ms;
                        if (candidate > gap) {
                          gap = candidate;
                          gapIndex = i;
                        }
                      }
                      final left = edited[gapIndex];
                      final right = edited[gapIndex + 1];
                      edited.insert(
                        gapIndex + 1,
                        DawAutomationPoint(
                          ms: (left.ms + right.ms) / 2,
                          value: (left.value + right.value) / 2,
                          curve: left.curve,
                        ),
                      );
                    }),
                    icon: const Icon(Icons.add),
                    label:
                        Text(AppLocalizations.of(context)!.trackerEnvAddPoint),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(AppLocalizations.of(dialogCtx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () {
                edited.sort((a, b) => a.ms.compareTo(b.ms));
                Navigator.of(dialogCtx).pop(edited);
              },
              child: Text(AppLocalizations.of(context)!.loopMixerSave),
            ),
          ],
        ),
      ),
    );
  }

  Widget _automationPointEditor({
    required DawAutomationPoint point,
    required int index,
    required int count,
    required double min,
    required double max,
    required double step,
    required double timeMax,
    required ValueChanged<DawAutomationPoint> onChanged,
    required VoidCallback? onRemove,
  }) {
    final timeLabel = index == 0
        ? 'Start ms'
        : index == count - 1
            ? 'End ms'
            : 'Point ${index + 1} ms';
    final valueLabel = index == 0
        ? 'Start value'
        : index == count - 1
            ? 'End value'
            : 'Point ${index + 1} value';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(AppLocalizations.of(context)!.dawPointN(index + 1)),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: AppLocalizations.of(context)!.dawRemovePoint,
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
              ),
          ],
        ),
        _effectParamSlider(
          timeLabel,
          point.ms.clamp(0, timeMax).toDouble(),
          0,
          timeMax,
          1,
          (value) => onChanged(point.copyWith(ms: value)),
        ),
        _effectParamSlider(
          valueLabel,
          point.value,
          min,
          max,
          step,
          (value) => onChanged(point.copyWith(value: value)),
        ),
        if (index < count - 1)
          DropdownButtonFormField<DawFadeCurve>(
            initialValue: point.curve,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.dawCurve,
            ),
            items: [
              for (final curve in DawFadeCurve.values)
                DropdownMenuItem(
                  value: curve,
                  child: Text(_fadeCurveLabel(curve)),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(point.copyWith(curve: value));
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<({double startValue, double endValue})?> _fxAutomationDialog(
    BuildContext ctx, {
    required String label,
    required double min,
    required double max,
    required double step,
    required double startValue,
    required double endValue,
  }) async {
    var start = startValue.clamp(min, max).toDouble();
    var end = endValue.clamp(min, max).toDouble();
    return showDialog<({double startValue, double endValue})>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.dawAutomate(label)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel()),
                const SizedBox(height: 8),
                _effectParamSlider(
                  'Start',
                  start,
                  min,
                  max,
                  step,
                  (value) => setDialog(() => start = value),
                ),
                _effectParamSlider(
                  'End',
                  end,
                  min,
                  max,
                  step,
                  (value) => setDialog(() => end = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(AppLocalizations.of(dialogCtx)!.dawCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(
                (startValue: start, endValue: end),
              ),
              child: Text(AppLocalizations.of(context)!.dawAmplifyApply),
            ),
          ],
        ),
      ),
    );
  }

  Widget _effectParamSlider(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged, {
    List<DawAutomationPoint> automation = const [],
    VoidCallback? onAutomate,
    Future<void> Function()? onEditAutomation,
    Future<void> Function()? onClearAutomation,
  }) {
    String fmt(double v) =>
        step >= 1 ? v.round().toString() : v.toStringAsFixed(2);
    String fmtMs(double v) => '${v.round()} ms';
    final automatedPoints = automation.length;
    final automationCurve =
        automation.isEmpty ? DawFadeCurve.linear : automation.first.curve;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                automatedPoints > 0
                    ? '$label — ${fmt(value)} · $automatedPoints auto'
                    : '$label — ${fmt(value)}',
              ),
            ),
            if (onAutomate != null)
              TextButton(
                onPressed: onAutomate,
                child: Text(AppLocalizations.of(context)!.dawAuto),
              ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions:
              step > 0 ? ((max - min) / step).round().clamp(1, 1000) : null,
          label: fmt(value),
          onChanged: onChanged,
        ),
        if (automation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$label automation: '
                        '${fmtMs(automation.first.ms)} ${fmt(automation.first.value)}'
                        ' → ${fmtMs(automation.last.ms)} ${fmt(automation.last.value)}'
                        ' · ${_fadeCurveLabel(automationCurve)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: onEditAutomation == null
                          ? null
                          : () async => onEditAutomation(),
                      child: Text(AppLocalizations.of(context)!.dawEdit),
                    ),
                    TextButton(
                      onPressed: onClearAutomation == null
                          ? null
                          : () async => onClearAutomation(),
                      child: Text(AppLocalizations.of(context)!.trackerClear),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  DrumRowsPattern _demoBeat() {
    final rows = {
      for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
    };
    for (var s = 0; s < kPatternSteps; s += 4) {
      rows[Drum.kick]![s] = true;
    }
    for (var s = 2; s < kPatternSteps; s += 4) {
      rows[Drum.snare]![s] = true;
    }
    for (var s = 0; s < kPatternSteps; s += 2) {
      rows[Drum.hat]![s] = true;
    }
    return DrumRowsPattern(rows);
  }

  Score _demoTune() {
    const q = NoteDuration(DurationBase.quarter);
    return Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c), q),
          NoteElement.note(const Pitch(Step.e), q),
          NoteElement.note(const Pitch(Step.g), q),
          NoteElement.note(const Pitch(Step.c, octave: 5), q),
        ]),
      ],
    );
  }
}
