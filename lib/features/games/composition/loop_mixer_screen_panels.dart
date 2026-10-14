// lib/features/games/composition/loop_mixer_screen_panels.dart
//
// Loop Studio's labels, menus, action bar, sound/harmony inspectors and scene grid.
//
// A `part` of loop_mixer_screen.dart, split out so the screen's state class is not one
// enormous body. The same methods, moved verbatim into an extension: they still
// read and write the state's private fields.

part of 'loop_mixer_screen.dart';

extension _LoopMixerPanels on _LoopMixerScreenState {
  /// A track's name: the player's own if they gave it one, else the app's.
  ///
  /// A duplicate reads as "Bass 2" rather than falling through to the
  /// unknown-id default, which labelled every copy "Sparkle"; an empty track
  /// reads as "Track 2" until it is renamed, which is exactly why renaming
  /// exists — "Track 2" says nothing about what is on it.
  String _trackLabel(AppLocalizations l10n, String id) {
    final given = _engine.trackName(id);
    if (given != null) return given;
    final source = _sourceIdOf(id);
    if (source != id) {
      final n = id.substring(source.length).replaceAll('-', ' ').trim();
      return '${_baseTrackLabel(l10n, source)} $n';
    }
    return _baseTrackLabel(l10n, id);
  }

  String _baseTrackLabel(AppLocalizations l10n, String id) => switch (id) {
        'drums' => l10n.loopMixerTrackDrums,
        'bass' => l10n.loopMixerTrackBass,
        'chords' => l10n.loopMixerTrackChords,
        'melody' => l10n.loopMixerTrackMelody,
        'voice' => l10n.loopMixerTrackVoice,
        'beat' => l10n.loopMixerTrackBeat,
        'track' => l10n.loopMixerTrackEmpty,
        'audio' => l10n.loopMixerTrackAudio,
        _ => l10n.loopMixerTrackSparkle,
      };

  String _kitLabel(AppLocalizations l10n, String id) => switch (id) {
        'deep' => l10n.loopMixerKitDeep,
        'warm' => l10n.loopMixerKitWarm,
        'lofi' => l10n.loopMixerKitLofi,
        'punchy' => l10n.loopMixerKitPunchy,
        'boom' => l10n.loopMixerKitBoom,
        'tight' => l10n.loopMixerKitTight,
        'tape' => l10n.loopMixerKitTape,
        _ => l10n.loopMixerKitClean,
      };

  String _styleLabel(AppLocalizations l10n, String id) => switch (id) {
        'four' => l10n.loopMixerStyleFour,
        'chill' => l10n.loopMixerStyleChill,
        _ => l10n.loopMixerStyleClassic,
      };

  String _challengeLabel(AppLocalizations l10n, String id) => switch (id) {
        'bass' => l10n.loopMixerChallengeBass,
        'melody' => l10n.loopMixerChallengeMelody,
        'layers' => l10n.loopMixerChallengeLayers,
        'fullBand' => l10n.loopMixerChallengeFullBand,
        _ => l10n.loopMixerChallengeSparkle,
      };

  // ===========================================================================
  // Score-Editor-style chrome: a slim action bar + one grouped overflow menu +
  // a docked "Sound & Feel" inspector, replacing the old wall of ~14 toolbar
  // icons and ~8 always-visible setting rows. Transport + undo/redo stay as
  // buttons; everything low-frequency moves into the ⋮ menu; every multi-value
  // song setting moves into the inspector.
  // ===========================================================================

  /// A non-selectable small-caps section label inside the overflow menu (the
  /// Score Workshop's `_menuHeader` pattern).
  PopupMenuItem<String> _menuSectionHeader(String text) =>
      PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  String _sendLabel(AppLocalizations l10n, LoopSend s) => switch (s) {
        LoopSend.none => l10n.loopMixerSendNone,
        LoopSend.reverb => l10n.loopMixerSendReverb,
        LoopSend.delay => l10n.loopMixerSendDelay,
      };

  /// The one grouped overflow menu that holds every low-frequency action.
  Widget _overflowMenu(AppLocalizations l10n) {
    final canFollow = _jamming && _engravedTrackId != null;
    return PopupMenuButton<String>(
      tooltip: l10n.loopMixerMore,
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'score':
            toggleScorePanel();
          case 'history':
            unawaited(showUndoHistorySheet(context, history: _undo));
          case 'tray':
            putGrooveOnTray();
          case 'infinite':
            toggleInfinite();
          case 'quantize':
            _toggleQuantize();
          case 'smear':
            _toggleSmearPad();
          case 'send':
            setSend(
              LoopSend.values[(send.index + 1) % LoopSend.values.length],
            );
          case 'duplicateSection':
            _duplicateSection(l10n);
          case 'masterFx':
            _showMasterFxSheet();
          case 'jam':
            toggleJam();
          case 'follow':
            toggleFollow();
          case 'findtune':
            unawaited(_findThisTune());
          case 'songbook':
            unawaited(_loadFromSongBook());
          case 'tracker':
            unawaited(_openInTracker());
          case 'workshop':
            _openInWorkshop();
          case 'share':
            _openShareSheet();
        }
      },
      itemBuilder: (ctx) => [
        _menuSectionHeader(l10n.loopMixerGroupView),
        CheckedPopupMenuItem<String>(
          value: 'score',
          checked: _showScore,
          child: Text(l10n.loopMixerScore),
        ),
        // In the MENU rather than the toolbar: that Row has five fixed icon
        // buttons before its scrollable region and has overflowed twice
        // already. A secondary action does not get to be the sixth.
        PopupMenuItem<String>(
          value: 'history',
          child: Text(l10n.loopMixerEditHistory),
        ),
        PopupMenuItem<String>(
          value: 'tray',
          child: Text(l10n.trayPutGroove),
        ),
        const PopupMenuDivider(),
        _menuSectionHeader(l10n.loopMixerGroupPerform),
        CheckedPopupMenuItem<String>(
          value: 'infinite',
          checked: _infinite,
          child: Text(l10n.loopMixerInfinite),
        ),
        CheckedPopupMenuItem<String>(
          value: 'quantize',
          checked: _quantize,
          child: Text(l10n.loopMixerQuantize),
        ),
        CheckedPopupMenuItem<String>(
          value: 'smear',
          checked: _showSmear,
          child: Text(l10n.loopMixerSolo),
        ),
        PopupMenuItem<String>(
          value: 'send',
          child: Text('${l10n.loopMixerSend}: ${_sendLabel(l10n, send)}'),
        ),
        if (!sceneIsEmpty(_chainIndex))
          PopupMenuItem<String>(
            value: 'duplicateSection',
            child: Text(l10n.loopMixerDuplicateSection),
          ),
        PopupMenuItem<String>(
          value: 'masterFx',
          child: Text(l10n.loopMixerMasterFx),
        ),
        CheckedPopupMenuItem<String>(
          value: 'jam',
          checked: _jamming,
          child: Text(l10n.loopMixerJam),
        ),
        if (canFollow)
          CheckedPopupMenuItem<String>(
            value: 'follow',
            checked: isFollowing,
            child: Text(l10n.loopMixerFollow),
          ),
        const PopupMenuDivider(),
        _menuSectionHeader(l10n.loopMixerGroupShare),
        // "What is this tune?" — ask the library about the part being edited,
        // instead of tapping or singing a query that is already on screen.
        PopupMenuItem<String>(
          value: 'findtune',
          enabled: hasPitchedTrack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.travel_explore, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.musicPickerFindThisTune)),
            ],
          ),
        ),
        // The music library, reachable from Loop Studio at last. Every other
        // authoring surface could already pull a score in; this one had no
        // route to the Song Book or the catalog at all, only to instruments.
        PopupMenuItem<String>(
          value: 'songbook',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_music_outlined, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.musicPickerTitle)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'tracker',
          enabled: hasPitchedTrack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_full, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.loopMixerOpenTracker)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'workshop',
          enabled: hasPitchedTrack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_note, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.loopMixerOpenWorkshopEditor)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'share',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ios_share, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.loopMixerShareExport)),
            ],
          ),
        ),
      ],
    );
  }

  /// The slim top action bar: transport + undo/redo pinned left, editing tools
  /// scroll in the middle, and the inspector toggle + overflow + help pin right.
  Widget _actionBar(AppLocalizations l10n) {
    final playing = _clock.isRunning;
    final hasBand = _engine.enabled.isNotEmpty;
    final advanced = !widget.simpleLayout;
    Widget vsep() => const SizedBox(
          height: 24,
          child: VerticalDivider(width: 12, thickness: 1),
        );
    final tools = <Widget>[
      if (advanced)
        IconButton(
          icon: const Icon(Icons.casino),
          tooltip: l10n.loopMixerRoll,
          onPressed: _roll,
          visualDensity: VisualDensity.compact,
        ),
      IconButton(
        icon: Icon(_showBeatEdit ? Icons.grid_on : Icons.grid_view),
        tooltip: l10n.loopMixerBeatEdit,
        isSelected: _showBeatEdit,
        onPressed: toggleBeatEdit,
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: Icon(_showTuneEdit ? Icons.piano : Icons.piano_outlined),
        tooltip: l10n.loopMixerTuneEdit,
        isSelected: _showTuneEdit,
        onPressed: toggleTuneEdit,
        visualDensity: VisualDensity.compact,
      ),
      if (!advanced)
        IconButton(
          icon: Icon(
            _showScore ? Icons.library_music : Icons.library_music_outlined,
          ),
          tooltip: l10n.loopMixerScore,
          isSelected: _showScore,
          onPressed: toggleScorePanel,
          visualDensity: VisualDensity.compact,
        ),
    ];
    return Row(
      children: [
        IconButton(
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: hasBand ? _pauseOrResume : null,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          tooltip: l10n.loopMixerStop,
          onPressed: hasBand ? _stopAll : null,
          visualDensity: VisualDensity.compact,
        ),
        // WS-T3 — this screen has keyboard shortcuts for the first time, so it
        // needs somewhere to say so.
        IconButton(
          icon: const Icon(Icons.keyboard),
          tooltip: AppLocalizations.of(context)!.trackerKeyHelp,
          onPressed: () => showKeymapSheet(
            context,
            keymap: _keymap.keymap,
            supported: kLoopIntents,
            service: _keymap,
          ),
          visualDensity: VisualDensity.compact,
        ),
        vsep(),
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: l10n.loopMixerUndo,
          onPressed: _canUndo ? _undoEdit : null,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: l10n.loopMixerRedo,
          onPressed: _canRedo ? _redoEdit : null,
          visualDensity: VisualDensity.compact,
        ),
        vsep(),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: tools),
          ),
        ),
        if (advanced) ...[
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.loopMixerSoundFeel,
            isSelected: _showInspector,
            onPressed: toggleInspector,
            visualDensity: VisualDensity.compact,
          ),
          _overflowMenu(l10n),
        ],
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: l10n.loopMixerHelp,
          onPressed: () => showTutorial(context, loopMixerPrimer(l10n)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// One titled section inside the inspector (caption above its control).
  Widget _inspectorSection(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  /// A compact labelled dropdown for a single-select option group. Replaces a
  /// Wrap of many ChoiceChips (Style / Harmony / Key / Scale / Kit) so the
  /// "Sound & Feel" sheet fits on a phone instead of overflowing with buttons.
  /// [below] renders extra controls under the dropdown (e.g. Harmony's custom
  /// chips + "Make" button, or the function strip).
  Widget _dropdownSection<T>(
    String label,
    T value,
    List<(T, String)> options,
    ValueChanged<T> onChanged, {
    Widget? below,
  }) {
    return _inspectorSection(
      label,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final (v, l) in options)
                    DropdownMenuItem<T>(
                      value: v,
                      child: Text(l, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
          if (below != null) ...[const SizedBox(height: 6), below],
        ],
      ),
    );
  }

  /// Harmony as a dropdown (Off + built-in progressions) with the custom
  /// progressions + "Make" + the function strip kept below it. A custom
  /// progression can't be a dropdown value (it isn't in the item list), so the
  /// dropdown falls back to Off while the custom's chip shows selected.
  Widget _harmonySection(AppLocalizations l10n) {
    final builtinIds = {for (final p in kProgressions) p.id};
    final curId = _engine.progression?.id;
    final dropdownValue =
        (curId != null && builtinIds.contains(curId)) ? curId : null;
    return _dropdownSection<String?>(
      l10n.loopMixerHarmony,
      dropdownValue,
      [
        (null, l10n.loopMixerHarmonyOff),
        for (final p in kProgressions) (p.id, p.label),
      ],
      (id) => _setProgression(
        id == null ? null : kProgressions.firstWhere((p) => p.id == id),
      ),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_customProgressions.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in _customProgressions)
                  InputChip(
                    label: Text(p.label),
                    selected: _engine.progression?.id == p.id,
                    onSelected: (_) => _setProgression(p),
                    onDeleted: () => _deleteCustomProgression(p),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _makeCustomProgression(l10n),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.loopMixerHarmonyMake),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
          if (_engine.progression != null) ...[
            const SizedBox(height: 6),
            _progressionFunctionStrip(_engine.progression!),
          ],
        ],
      ),
    );
  }

  /// The "Sound & Feel" inspector body — every multi-value song setting that
  /// used to be an always-visible row now lives here (Score-Editor pattern).
  Widget _soundInspectorContent(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inspectorSection(
          l10n.loopMixerTempo,
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('loop-mixer-tempo'),
                  min: kMinTempoBpm.toDouble(),
                  max: kMaxTempoBpm.toDouble(),
                  divisions: kMaxTempoBpm - kMinTempoBpm,
                  value: _engine.tempoBpm.toDouble(),
                  label: '${_engine.tempoBpm} BPM',
                  onChanged: (v) => _setTempo(v.round()),
                ),
              ),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _tempoController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'BPM',
                  ),
                  onSubmitted: (value) {
                    final bpm = int.tryParse(value);
                    if (bpm != null) _setTempo(bpm);
                  },
                ),
              ),
            ],
          ),
        ),
        _dropdownSection<String>(
          l10n.loopMixerStyle,
          _engine.styleId,
          [
            for (final style in kGrooveStyles)
              (style.id, _styleLabel(l10n, style.id)),
          ],
          _setStyle,
        ),
        _harmonySection(l10n),
        _dropdownSection<int>(
          l10n.loopMixerKey,
          _engine.key,
          [
            for (var k = 0; k < LoopMixerScreen._keyNames.length; k++)
              (k, LoopMixerScreen._keyNames[k]),
          ],
          _setKey,
        ),
        _dropdownSection<GrooveScale>(
          l10n.loopMixerScale,
          _engine.scale,
          [
            (GrooveScale.majorPentatonic, l10n.loopMixerScaleMajor),
            (GrooveScale.minorPentatonic, l10n.loopMixerScaleMinor),
          ],
          _setScale,
        ),
        _dropdownSection<String>(
          l10n.loopMixerKit,
          _engine.kitId,
          [for (final kit in kDrumKits) (kit.id, _kitLabel(l10n, kit.id))],
          _setKit,
        ),
        _inspectorSection(
          l10n.loopMixerSwing,
          _captionedSlider(
            low: l10n.loopMixerSwingStraight,
            high: l10n.loopMixerSwingShuffle,
            slider: Slider(
              value: _engine.swing,
              max: 0.6,
              divisions: 12,
              onChanged: _setSwing,
            ),
          ),
        ),
        _inspectorSection(
          l10n.loopMixerSwingPerTrack,
          _trackSwingRow(l10n),
        ),
        _projectRow(l10n),
        _inspectorSection(
          l10n.loopMixerAddTrack,
          _addTrackRow(l10n),
        ),
        _inspectorSection(
          l10n.loopMixerDuplicateTrack,
          _duplicateRow(l10n),
        ),
        _renameRow(l10n),
        _copyPatternRow(l10n),
        _inspectorSection(
          l10n.loopMixerTrackFilter,
          _trackFilterRow(l10n),
        ),
        _inspectorSection(
          l10n.loopMixerAutomation,
          _automationRows(l10n),
        ),
        _inspectorSection(
          l10n.loopMixerFilter,
          _captionedSlider(
            low: l10n.loopMixerFilterDark,
            high: l10n.loopMixerFilterThin,
            slider: Slider(
              value: _engine.masterFilter,
              min: -1,
              divisions: 20,
              onChanged: _setMasterFilter,
              onChangeEnd: (v) {
                if (v.abs() < 0.06) _setMasterFilter(0);
              },
            ),
          ),
        ),
        _inspectorSection(
          l10n.loopMixerArrange,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sceneRow(l10n),
              _arrangementStrip(l10n),
              _sceneGrid(l10n),
            ],
          ),
        ),
      ],
    );
  }

  /// The inspector as a docked panel (wide) — a bordered, independently
  /// scrolling column on the right of the track lane.
  Widget _soundInspectorPanel(AppLocalizations l10n) => Container(
        width: 300,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: _soundInspectorContent(l10n),
        ),
      );

  /// L2 — the session grid: which tracks play in which section.
  ///
  /// The data for this has existed since sections shipped (each `GrooveScene`
  /// stores an enabled set AND a variant per track); it was only ever shown as
  /// four lettered pads, so you could launch a section but never see what was
  /// in it, let alone change one thing about it.
  ///
  /// Hidden until at least one section is captured. An empty 7×4 grid of
  /// nothing is noise on a child's screen, and the pads above already teach
  /// how to make the first one.
  Widget _sceneGrid(AppLocalizations l10n) {
    if (!hasScenes) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // WS-L2 — ONE scroll view around the whole grid rather than one per row.
      // Per-row scrolling would let the rows drift out of step, and a session
      // grid whose columns do not line up is worse than one you cannot see all
      // of. The section count is a layout budget now (`kLoopSectionSlots`), so
      // this is what lets that number be raised again without a redesign.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final track in _engine.tracks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        _trackLabel(l10n, track.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    for (var i = 0; i < _scenes.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          key: Key('loop-cell-${track.id}-$i'),
                          onTap: _scenes[i] == null
                              ? null
                              : () => _toggleSceneTrack(i, track.id),
                          child: Container(
                            width: 30,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _sceneHasTrack(i, track.id)
                                  ? _colorFor(track.id)
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: _sceneHasTrack(i, track.id)
                                ? Text(
                                    String.fromCharCode(
                                      65 +
                                          (_scenes[i]!.variants[track.id] ?? 0),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Repeats: how many times each section plays before the chain moves
            // on. Only meaningful once sections are chained, but shown always so
            // it is discoverable before you turn chaining on.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      l10n.loopMixerRepeats,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  for (var i = 0; i < _scenes.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        key: Key('loop-repeats-$i'),
                        onTap: _scenes[i] == null
                            ? null
                            : () => _cycleSceneRepeats(i),
                        child: SizedBox(
                          width: 30,
                          height: 16,
                          child: Center(
                            child: Text(
                              _scenes[i] == null ? '' : '×${_sceneRepeats[i]}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      ),
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
