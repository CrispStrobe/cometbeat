// lib/features/games/composition/advanced_tracker_screen_panels.dart
//
// The Advanced Tracker's menus, command bar, settings and arrangement sheets, and the pattern grid.
//
// A `part` of advanced_tracker_screen.dart, split out so the screen's state class is not one
// enormous body. The same methods, moved verbatim into an extension: they still
// read and write the state's private fields. The one mechanical change is
// `setState` → `_rebuild` (a forwarder on the state; extensions cannot call the
// protected `setState`).

part of 'advanced_tracker_screen.dart';

extension _AdvancedTrackerPanels on _AdvancedTrackerScreenState {
  /// The classic block-editing menu (touch-friendly; the same ops have keyboard
  /// shortcuts on desktop — see the ⓘ legend). Mark begin/drag-select, select
  /// track/pattern, copy/cut/paste/paste-mix, transpose, clear, unmark.
  PopupMenuItem<String> _menuRow(
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) =>
      PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            // Expanded, not a bare Text: an unconstrained label overflowed this
            // popup by up to 368px (measured), which throws during layout and
            // clips the wording. German labels are the worst case — several are
            // half again as long as the English.
            Expanded(child: Text(label)),
          ],
        ),
      );

  PopupMenuItem<String> _menuSection(String label) => PopupMenuItem<String>(
        enabled: false,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );

  Widget _blockMenu(AppLocalizations l10n) => PopupMenuButton<String>(
        icon: Icon(
          _marking || _hasSelection ? Icons.select_all : Icons.highlight_alt,
        ),
        tooltip: l10n.trackerBlock,
        onSelected: (v) {
          switch (v) {
            case 'mark':
              _rebuild(() {
                _marking = !_marking;
                if (_marking) {
                  _anchorChannel = _cursorChannel;
                  _anchorRow = _cursorRow;
                } else {
                  _unmark();
                }
              });
            case 'track':
              _selectTrack();
            case 'pattern':
              _selectPattern();
            case 'copy':
              _copyBlock();
            case 'cut':
              _cutBlock();
            case 'paste':
              _pasteBlock();
            case 'pasteMix':
              _pasteBlock(mix: true);
            case 'up':
              _transposeBlock(1);
            case 'down':
              _transposeBlock(-1);
            case 'octUp':
              _transposeBlock(12);
            case 'octDown':
              _transposeBlock(-12);
            case 'interp':
              _interpolateBlock();
            case 'interpNotes':
              _interpolateNotesBlock();
            case 'fillVoice':
              _fillInstrumentBlock();
            case 'insRow':
              _insertRow();
            case 'delRow':
              _deleteRow();
            case 'clear':
              _clearBlock();
            case 'unmark':
              _unmark();
          }
        },
        itemBuilder: (ctx) => [
          CheckedPopupMenuItem(
            value: 'mark',
            checked: _marking,
            child: Text(l10n.trackerBlockMark),
          ),
          PopupMenuItem(value: 'track', child: Text(l10n.trackerBlockTrack)),
          PopupMenuItem(
            value: 'pattern',
            child: Text(l10n.trackerBlockPattern),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'copy', child: Text(l10n.trackerBlockCopy)),
          PopupMenuItem(value: 'cut', child: Text(l10n.trackerBlockCut)),
          PopupMenuItem(
            enabled: _clipboard != null,
            value: 'paste',
            child: Text(l10n.trackerBlockPaste),
          ),
          PopupMenuItem(
            enabled: _clipboard != null,
            value: 'pasteMix',
            child: Text(l10n.trackerBlockPasteMix),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'up', child: Text(l10n.trackerBlockTransUp)),
          PopupMenuItem(value: 'down', child: Text(l10n.trackerBlockTransDown)),
          PopupMenuItem(value: 'octUp', child: Text(l10n.trackerBlockOctUp)),
          PopupMenuItem(
            value: 'octDown',
            child: Text(l10n.trackerBlockOctDown),
          ),
          PopupMenuItem(value: 'interp', child: Text(l10n.trackerInterpolate)),
          PopupMenuItem(
            value: 'interpNotes',
            child: Text(l10n.trackerInterpNotes),
          ),
          PopupMenuItem(
            value: 'fillVoice',
            child: Text(l10n.trackerBlockFillVoice),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'insRow', child: Text(l10n.trackerInsertRow)),
          PopupMenuItem(value: 'delRow', child: Text(l10n.trackerDeleteRow)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'clear', child: Text(l10n.trackerBlockClear)),
          if (_hasSelection)
            PopupMenuItem(
              value: 'unmark',
              child: Text(l10n.trackerBlockUnmark),
            ),
        ],
      );

  /// The classic transport row: Play/Pause · Back · Stop · Forward · Play-song ·
  /// Loop + a position readout — all inline (no floating button over the grid).
  /// The master oscilloscope strip — the current pattern's mixed waveform with a
  /// red playhead sweeping across it during playback.
  Widget _scopeStrip(BuildContext context) {
    if (_scopeDirty || _scopePcm == null) {
      _scopePcm = _song.engine.renderLoopPcm();
      _scopeDirty = false;
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: RepaintBoundary(
        child: ValueListenableBuilder<int>(
          valueListenable: _row,
          builder: (context, row, _) => CustomPaint(
            size: Size.infinite,
            painter: _ScopePainter(
              pcm: _scopePcm!,
              progress: row < 0 ? -1.0 : row / _song.rows,
              wave: _classic ? const Color(0xFF6EE787) : scheme.primary,
              bg: _classic
                  ? const Color(0xFF08120A)
                  : scheme.surfaceContainerLowest,
            ),
          ),
        ),
      ),
    );
  }

  /// The single top command bar: transport + song tempo/length + pattern +
  /// settings, consolidating what used to be three separate rows (toolbar,
  /// arrangement, transport). Overflow scrolls horizontally on narrow screens.
  Widget _commandBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final playing = _clock.isRunning && !_paused;
    Widget sep() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: scheme.outlineVariant,
        );
    // Play/Stop stay pinned left and Pattern/Settings pinned right, so the
    // primary controls are always reachable; the rest scrolls in the middle.
    return Container(
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton.filledTonal(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            tooltip: playing ? l10n.trackerPause : l10n.trackerPlay,
            onPressed: _togglePlay,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: l10n.trackerStop,
            onPressed: _clock.isRunning || _paused ? _stop : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  sep(),
                  IconButton(
                    icon: const Icon(Icons.fiber_manual_record),
                    color: _recording ? scheme.error : null,
                    tooltip: l10n.trackerRecordLive,
                    onPressed: () => _setRecording(!_recording),
                  ),
                  IconButton(
                    key: const ValueKey('tracker-pads'),
                    icon: const Icon(Icons.grid_view),
                    tooltip: l10n.trackerPads,
                    onPressed: _showPads,
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_play),
                    tooltip: l10n.trackerPlaySong,
                    onPressed: _playSong,
                  ),
                  IconButton(
                    icon: Icon(_loopOn ? Icons.repeat_on : Icons.repeat),
                    tooltip: l10n.trackerLoop,
                    color: _loopOn ? scheme.primary : null,
                    onPressed: () => _rebuild(() => _loopOn = !_loopOn),
                  ),
                  sep(),
                  // Tempo (BPM).
                  Tooltip(
                    message: l10n.trackerTempo,
                    child: Row(
                      children: [
                        const Icon(Icons.speed, size: 16),
                        const SizedBox(width: 2),
                        DropdownButton<int>(
                          value: _kTempoOptions.contains(_song.timing.tempoBpm)
                              ? _song.timing.tempoBpm
                              : null,
                          hint: Text('${_song.timing.tempoBpm}'),
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final b in _kTempoOptions)
                              DropdownMenuItem(value: b, child: Text('$b')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              _rebuild(() => _song.setTempo(v));
                              _syncPlayback();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  sep(),
                  // Length (rows).
                  Tooltip(
                    message: l10n.trackerLength,
                    child: Row(
                      children: [
                        const Icon(Icons.straighten, size: 16),
                        const SizedBox(width: 2),
                        DropdownButton<int>(
                          value: _kLengthOptions.contains(_song.rows)
                              ? _song.rows
                              : -1,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final n in _kLengthOptions)
                              DropdownMenuItem(value: n, child: Text('$n')),
                            DropdownMenuItem(
                              value: -1,
                              child: Text(
                                _kLengthOptions.contains(_song.rows)
                                    ? l10n.trackerCustomLength
                                    : '${_song.rows} ✎',
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            if (v == -1) {
                              _promptCustomLength(l10n);
                            } else {
                              _setPatternLength(v);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  sep(),
                  // Position readout.
                  AnimatedBuilder(
                    animation: Listenable.merge([_row, _playingOrder]),
                    builder: (context, _) {
                      final row = _row.value;
                      final rowStr =
                          row < 0 ? '··' : row.toString().padLeft(2, '0');
                      final total = _song.rows.toString().padLeft(2, '0');
                      final pos = _songMode && _playingOrder.value >= 0
                          ? '${(_playingOrder.value + 1).toString().padLeft(2, '0')}'
                              '/${_song.order.length.toString().padLeft(2, '0')} · '
                          : '';
                      return Text(
                        '$pos$rowStr/$total',
                        style: TextStyle(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          // Pattern / song arrangement → sheet (pinned right).
          ActionChip(
            avatar: const Icon(Icons.view_agenda_outlined, size: 16),
            label: Text('${_song.current.name} ▾'),
            tooltip: l10n.trackerPattern,
            onPressed: () => _showArrangementSheet(l10n),
          ),
          const SizedBox(width: 4),
          // Everything else → settings sheet (pinned right).
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => _showTrackerSettingsSheet(l10n),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet holding the song settings that used to sit on the toolbar:
  /// swing, edit-step, playback toggles, view, and the add-track / chord tools.
  void _showTrackerSettingsSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final scheme = Theme.of(ctx).colorScheme;
          void toggle(void Function() f) {
            _rebuild(f);
            setSheet(() {});
          }

          Widget dropRow(String label, IconData icon, Widget dropdown) => Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label)),
                  dropdown,
                ],
              );
          Widget toggleChip(
            String label,
            IconData icon,
            bool on,
            void Function() onTap,
          ) =>
              FilterChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: on,
                onSelected: (_) => toggle(onTap),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsTitle,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    // Groove.
                    dropRow(
                      l10n.trackerSwing,
                      Icons.waves,
                      DropdownButton<double>(
                        value: _kSwingOptions.contains(_song.timing.swing)
                            ? _song.timing.swing
                            : null,
                        hint: Text('${(_song.timing.swing * 100).round()}%'),
                        items: [
                          for (final s in _kSwingOptions)
                            DropdownMenuItem(
                              value: s,
                              child: Text(
                                s == 0
                                    ? l10n.trackerSwingOff
                                    : '${(s * 100).round()}%',
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            _rebuild(() => _song.setSwing(v));
                            _syncPlayback();
                            setSheet(() {});
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    dropRow(
                      l10n.trackerEditStep,
                      Icons.south,
                      DropdownButton<int>(
                        value: _editStep,
                        items: [
                          for (final n in const [0, 1, 2, 4])
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) => toggle(() => _editStep = v ?? 1),
                      ),
                    ),
                    const Divider(height: 20),
                    // Native module HEADER settings (S3M/IT/XM). Global volume
                    // and initial speed are carried from the imported header and
                    // now editable here; they round-trip through the S3M/IT
                    // writers. Tempo and per-channel pan are edited by the tempo
                    // control and the channel pan sliders; master volume,
                    // ultraClick, flags and createdWith are not retained by the
                    // editable model (documented import-loss in mod_pending.md).
                    Text(
                      l10n.trackerModuleHeader,
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.volume_up, size: 18),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 96,
                          child: Text(l10n.trackerGlobalVolume),
                        ),
                        Expanded(
                          child: Slider(
                            value: _song.globalVolume.clamp(0.0, 1.0),
                            label: '${(_song.globalVolume * 100).round()}%',
                            divisions: 128,
                            onChanged: (v) {
                              _rebuild(() => _song.setGlobalVolume(v));
                              _syncPlayback();
                              setSheet(() {});
                            },
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${(_song.globalVolume * 100).round()}%',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    dropRow(
                      l10n.trackerInitialSpeed,
                      Icons.speed,
                      DropdownButton<int>(
                        value: _song.initialSpeed.clamp(1, 31),
                        items: [
                          for (var n = 1; n <= 31; n++)
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _rebuild(() => _song.setInitialSpeed(v));
                          _syncPlayback();
                          setSheet(() {});
                        },
                      ),
                    ),
                    const Divider(height: 20),
                    // Playback toggles.
                    Text(
                      l10n.trackerPlay,
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        toggleChip(
                          l10n.trackerMetronome,
                          Icons.av_timer,
                          _metronome,
                          () => _metronome = !_metronome,
                        ),
                        toggleChip(
                          l10n.trackerQuantize,
                          Icons.grid_on,
                          _quantize,
                          () => _quantize = !_quantize,
                        ),
                        toggleChip(
                          l10n.trackerFollow,
                          Icons.my_location,
                          _followPlay,
                          () => _followPlay = !_followPlay,
                        ),
                        toggleChip(
                          l10n.trackerScope,
                          Icons.graphic_eq,
                          _showScope,
                          () => _showScope = !_showScope,
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // View + tools.
                    Row(
                      children: [
                        Icon(
                          Icons.zoom_out_map,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(l10n.trackerZoomIn)),
                        IconButton(
                          icon: const Icon(Icons.zoom_out),
                          tooltip: l10n.trackerZoomOut,
                          onPressed: () => toggle(
                            () => _zoom = (_zoom - 0.15).clamp(0.75, 1.6),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.zoom_in),
                          tooltip: l10n.trackerZoomIn,
                          onPressed: () => toggle(
                            () => _zoom = (_zoom + 0.15).clamp(0.75, 1.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        toggleChip(
                          l10n.trackerClassicSkin,
                          Icons.dark_mode,
                          _classic,
                          () => _classic = !_classic,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(l10n.trackerAddTrack),
                          onPressed: () {
                            addTrack();
                            setSheet(() {});
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.queue_music, size: 18),
                          label: Text(l10n.trackerChord),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showChordSheet();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Bottom sheet: the pattern selector + song-order editor (moved off the old
  /// always-on arrangement row). Patterns choose which grid you edit; the order
  /// list is the play sequence. Local [setSheet] keeps the chips live.
  void _showArrangementSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final scheme = Theme.of(ctx).colorScheme;
          void refresh() => setSheet(() {});
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.trackerPattern,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < _song.patterns.length; i++)
                          GestureDetector(
                            onLongPress: () async {
                              await _promptRenamePattern(i);
                              refresh();
                            },
                            child: ChoiceChip(
                              label: Text(_song.patterns[i].name),
                              selected: i == _song.currentIndex,
                              onSelected: (_) {
                                selectPattern(i);
                                refresh();
                              },
                            ),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(l10n.trackerPatternNew),
                          onPressed: () {
                            _addEmptyPattern();
                            refresh();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.copy, size: 16),
                          label: Text(l10n.trackerPatternClone),
                          onPressed: () {
                            _clonePattern();
                            refresh();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.edit_outlined, size: 16),
                          label: Text(l10n.trackerRenamePattern),
                          onPressed: () async {
                            await _promptRenamePattern(_song.currentIndex);
                            refresh();
                          },
                        ),
                        if (_song.patterns.length > 1)
                          ActionChip(
                            avatar: const Icon(Icons.delete_outline, size: 16),
                            label: Text(l10n.trackerRemoveTrack),
                            onPressed: () {
                              _rebuild(
                                () => _song.removePattern(_song.currentIndex),
                              );
                              refresh();
                            },
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      l10n.trackerSong,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: _playingOrder,
                      builder: (context, playing, _) => Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < _song.order.length; i++)
                            InputChip(
                              label: Text(_song.patterns[_song.order[i]].name),
                              selected: playing >= 0
                                  ? i == playing
                                  : i == _orderCursor,
                              side: (playing < 0 && i == _orderCursor)
                                  ? BorderSide(
                                      color: scheme.primary,
                                      width: 1.5,
                                    )
                                  : null,
                              onPressed: () {
                                _rebuild(() => _orderCursor = i);
                                selectPattern(_song.order[i]);
                                refresh();
                              },
                              onDeleted: () {
                                _orderDelete(i);
                                refresh();
                              },
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(_song.current.name),
                            onPressed: () {
                              addToOrder(_song.currentIndex);
                              refresh();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      children: [
                        // WS-T2 — the bird's-eye. At sixty-four patterns the
                        // chip strip beside this is a wall to scroll through.
                        IconButton(
                          icon: const Icon(Icons.grid_view, size: 18),
                          tooltip:
                              AppLocalizations.of(context)!.trackerSongOverview,
                          onPressed: _showOrderOverview,
                        ),
                        // WS-T4 — the same channel, made legible.
                        IconButton(
                          icon: const Icon(Icons.piano, size: 18),
                          tooltip:
                              AppLocalizations.of(context)!.trackerPianoRoll,
                          onPressed: _showPianoRoll,
                        ),
                        // WS-T6 — where the bar lines go. Previously not
                        // settable at all, and hardcoded to four beats.
                        IconButton(
                          icon: const Icon(Icons.straighten, size: 18),
                          tooltip:
                              AppLocalizations.of(context)!.trackerBeatsAndBars,
                          onPressed: _pickMeter,
                        ),
                        IconButton(
                          icon: const Icon(Icons.expand_more, size: 18),
                          tooltip: l10n.trackerOrderPrevPat,
                          onPressed: () {
                            _orderRetarget(-1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.expand_less, size: 18),
                          tooltip: l10n.trackerOrderNextPat,
                          onPressed: () {
                            _orderRetarget(1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          tooltip: l10n.trackerOrderMoveLeft,
                          onPressed: () {
                            _orderMove(-1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20),
                          tooltip: l10n.trackerOrderMoveRight,
                          onPressed: () {
                            _orderMove(1);
                            refresh();
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.control_point_duplicate,
                            size: 18,
                          ),
                          tooltip: l10n.trackerOrderInsert,
                          onPressed: () {
                            _orderInsert();
                            refresh();
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 20),
                          tooltip: l10n.trackerBack,
                          onPressed: _song.patterns.length > 1 || _songMode
                              ? () {
                                  _step(-1);
                                  refresh();
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 20),
                          tooltip: l10n.trackerForward,
                          onPressed: _song.patterns.length > 1 || _songMode
                              ? () {
                                  _step(1);
                                  refresh();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _promptCustomLength(AppLocalizations l10n) async {
    final controller = TextEditingController(text: '${_song.rows}');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerCustomLength),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.trackerCustomLengthPrompt),
          onSubmitted: (t) => Navigator.of(ctx).pop(int.tryParse(t)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.trackerCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: Text(l10n.trackerOk),
          ),
        ],
      ),
    );
    if (value != null && value > 0) _setPatternLength(value);
  }

  /// Renames pattern [index] to a song-section label (Intro / Verse / Chorus …).
  Future<void> _promptRenamePattern(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _song.patterns[index].name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackerRenamePattern),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.trackerRenamePatternHint),
          onSubmitted: (t) => Navigator.of(ctx).pop(t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.trackerCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.trackerOk),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      _rebuild(() => _song.renamePattern(index, name));
    }
  }

  Widget _grid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepsPerBeat = _song.timing.stepsPerBeat;
    final gridWidth = _rowNumWidth + _song.channelCount * _cellWidth;

    final grid = ColoredBox(
      color: _classic ? const Color(0xFF0A130A) : Colors.transparent,
      child: Scrollbar(
        controller: _vScroll,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: Column(
              children: [
                _headerRow(scheme),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _row,
                    builder: (context, activeRow, _) => ListView.builder(
                      controller: _vScroll,
                      itemExtent: _rowHeight,
                      itemCount: _song.rows,
                      itemBuilder: (context, row) =>
                          _rowWidget(row, activeRow, stepsPerBeat, scheme),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 🔍 On desktop, the corner card shows the hovered cell's note + row chord;
    // leaving the grid clears it. No-op on touch.
    return MouseRegion(
      onExit: _inspect
          ? (_) {
              if (_hoverInfo != null) _rebuild(() => _hoverInfo = null);
            }
          : null,
      child: DragTarget<MusicDragPayload>(
        onWillAcceptWithDetails: (d) => _dropDecision(d.data).canDrop,
        onAcceptWithDetails: (d) => unawaited(_dropHere(d.data)),
        builder: (context, candidate, rejected) => Stack(
          children: [
            grid,
            if (_inspect && _hoverInfo != null)
              Positioned(top: 8, right: 8, child: _hoverInspectCard()),
            if (candidate.isNotEmpty && candidate.first != null)
              Positioned(
                left: 12,
                top: 8,
                child: Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    // Say what a release would do, while the finger is down.
                    child: Text(
                      dropSummary(_dropDecision(candidate.first!)),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
