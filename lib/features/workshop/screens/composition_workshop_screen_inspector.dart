// lib/features/workshop/screens/composition_workshop_screen_inspector.dart
//
// The Score Workshop's scanning and recording intake, the palette, the analysis banners, the inspector panel and its dialogs.
//
// A `part` of composition_workshop_screen.dart, split out so the screen's state class is not one
// enormous body. The same methods, moved verbatim into an extension: they still
// read and write the state's private fields. The one mechanical change is
// `setState` → `_rebuild` (a forwarder on the state; extensions cannot call the
// protected `setState`).

part of 'composition_workshop_screen.dart';

extension _WorkshopInspector on _CompositionWorkshopScreenState {
  /// Recognise [bytes] via OMR and load the result — the picker-free half of
  /// [_scanImage], shared with the [debugScanBytes] test seam.
  Future<void> _scanBytes(Uint8List bytes) async {
    if (_scanning) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final recognise =
        widget.debugScanImage ?? (b) => recognizeSheetMusic(b, download: true);
    _rebuild(() => _scanning = true);
    messenger.showSnackBar(SnackBar(content: Text(l10n.workshopScanning)));
    try {
      final score = await recognise(bytes);
      if (!mounted) return;
      _rebuild(() => _scanning = false);
      if (score == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.workshopScanUnavailable)),
        );
        return;
      }
      _rebuild(() => _doc.loadScore(score));
      messenger.showSnackBar(SnackBar(content: Text(l10n.importDone)));
    } catch (e) {
      if (mounted) _rebuild(() => _scanning = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailed(e.toString()))),
      );
    }
  }

  /// Transcribe a recording (audio → notes) straight into the editor — the same
  /// engine as the standalone Transcribe tool, offered here as an in-editor
  /// function. Picks a PCM16 WAV and runs the pure-Dart monophonic pipeline
  /// (no model download); the resulting Score loads into the active part, so a
  /// hummed/played phrase becomes editable notation. On empty/degenerate audio
  /// the engine returns an empty score rather than throwing.
  Future<void> _transcribeRecording() async {
    if (_scanning) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Audio (WAV)', extensions: ['wav']),
        ],
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailed(e.toString()))),
      );
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    _rebuild(() => _scanning = true);
    messenger.showSnackBar(SnackBar(content: Text(l10n.workshopTranscribing)));
    try {
      final result = await transcribeRecording(bytes);
      if (!mounted) return;
      _rebuild(() {
        _scanning = false;
        _doc.loadScore(result.score);
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.importDone)));
    } catch (e) {
      if (mounted) _rebuild(() => _scanning = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailed(e.toString()))),
      );
    }
  }

  /// The note-property dropdown (articulations · tie · dynamics), anchored at
  /// its own button. Returns null unless a single editable note is selected.
  Widget? _paletteButton(AppLocalizations l10n) {
    final note = _doc.selected;
    if (note == null || note.isRest) return null;
    return PopupMenuButton<(String, Object?)>(
      icon: const Icon(Icons.expand_less),
      tooltip: l10n.workshopArticulations,
      onSelected: (a) {
        if (a.$1 == 'change') {
          final id = _doc.selectedId;
          if (id != null) _showChangeHereDialog(id);
          return;
        }
        if (a.$1 == 'grace') {
          final id = _doc.selectedId;
          if (id != null) _showGraceDialog(id);
          return;
        }
        _rebuild(() {
          final id = _doc.selectedId;
          switch (a.$1) {
            case 'art':
              _doc.toggleArticulationOfSelected(a.$2! as Articulation);
            case 'tie':
              _doc.toggleTieOfSelected();
            case 'dyn':
              _doc.setDynamicOfSelected(a.$2 as DynamicLevel?);
            case 'repStart':
              if (id != null) _doc.toggleRepeatStartAt(id);
            case 'repEnd':
              if (id != null) _doc.toggleRepeatEndAt(id);
            case 'orn':
              _doc.setOrnamentOfSelected(a.$2 as Ornament?);
          }
        });
      },
      itemBuilder: (ctx) {
        final n = _doc.selected;
        // Categorized insertion palette: a non-selectable header opens each
        // group so the flat list reads as sections (Articulations / Dynamics /
        // Ornament / Structure) instead of one long menu.
        return [
          _menuHeader(l10n.workshopArticulations),
          for (final art in _articulationOptions)
            CheckedPopupMenuItem<(String, Object?)>(
              value: ('art', art),
              checked: n?.articulations.contains(art) ?? false,
              child: Text(_articulationLabel(l10n, art)),
            ),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('tie', null),
            checked: n?.tieToNext ?? false,
            child: Text(l10n.workshopTie),
          ),
          const PopupMenuDivider(),
          _menuHeader(l10n.workshopDynamics),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('dyn', null),
            checked: n?.dynamic == null,
            child: Text(l10n.workshopDynamicNone),
          ),
          for (final d in _dynamicOptions)
            CheckedPopupMenuItem<(String, Object?)>(
              value: ('dyn', d),
              checked: n?.dynamic == d,
              child: Text(d.name),
            ),
          const PopupMenuDivider(),
          _menuHeader(l10n.workshopOrnament),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('orn', null),
            checked: n?.ornament == null,
            child: Text(l10n.workshopDynamicNone),
          ),
          for (final e in _ornamentOptions.entries)
            CheckedPopupMenuItem<(String, Object?)>(
              value: ('orn', e.key),
              checked: n?.ornament == e.key,
              child: Text(e.value),
            ),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('grace', null),
            checked: n?.graceNotes.isNotEmpty ?? false,
            child: Text(l10n.workshopGraceNotes),
          ),
          const PopupMenuDivider(),
          _menuHeader(l10n.workshopStructure),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('repStart', null),
            checked: _selectedIdRepeatStarts,
            child: Text(l10n.workshopRepeatStart),
          ),
          CheckedPopupMenuItem<(String, Object?)>(
            value: const ('repEnd', null),
            checked: _selectedIdRepeatEnds,
            child: Text(l10n.workshopRepeatEnd),
          ),
          PopupMenuItem<(String, Object?)>(
            value: const ('change', null),
            child: Text(l10n.workshopChangeHere),
          ),
        ];
      },
    );
  }

  /// A non-selectable section header for the categorized ⌃ palette (a disabled
  /// item styled as a small caption, so a group reads as a labelled section).
  PopupMenuItem<(String, Object?)> _menuHeader(String label) =>
      PopupMenuItem<(String, Object?)>(
        enabled: false,
        height: 28,
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
        ),
      );

  /// Cause 3: the selection-driven inspector. A docked panel that reflects and
  /// edits whatever is selected — the scalable home for note properties, next to
  /// the (kept) ⌃ palette. Reuses the same `_doc` mutators. Opt-in via the ⋮
  /// menu; off by default so the Sandbox surface is unchanged.
  // ---- live harmonic analysis (Analysis toggle) --------------------------

  Color _functionTint(HarmonicFunction f) => switch (f) {
        HarmonicFunction.tonic => const Color(0xFF59A14F), // green — home
        HarmonicFunction.subdominant => const Color(0xFF4E79A7), // blue — away
        HarmonicFunction.dominant =>
          const Color(0xFFF28E2B), // orange — tension
      };

  HarmonicFunction? _fallbackFunction(Pitch pitch, Key key) {
    final interval = (pitch.midiNumber - key.tonic.midiNumber) % 12;
    return switch (interval) {
      0 => HarmonicFunction.tonic,
      5 => HarmonicFunction.subdominant,
      7 => HarmonicFunction.dominant,
      _ => null,
    };
  }

  String _cadenceLabel(AppLocalizations l10n, CadenceType t) => switch (t) {
        CadenceType.authentic => l10n.cadenceAuthentic,
        CadenceType.half => l10n.cadenceHalf,
        CadenceType.plagal => l10n.cadencePlagal,
        CadenceType.deceptive => l10n.cadenceDeceptive,
      };

  String _analysisKeyName(AppLocalizations l10n, ScoreAnalysis a) {
    final letter = a.key.tonic.step.name.toUpperCase();
    final alter = a.key.tonic.alter;
    final acc = alter > 0 ? '♯' * alter : (alter < 0 ? '♭' * -alter : '');
    return '$letter$acc ${a.key.isMajor ? l10n.modeMajor : l10n.modeMinor}';
  }

  /// SE-C3: a gentle strip naming what the active part cannot play.
  ///
  /// ⚠ It is shown ONLY when there is something to say, which is what keeps it
  /// gentle — an always-present "0 problems" row is noise, and noise is what
  /// makes people stop reading warnings. It never blocks and never edits:
  /// composers write out of range on purpose, and the editor is not the
  /// authority on that.
  Widget _playabilityBanner(
    AppLocalizations l10n,
    List<PlayabilityWarning> warnings,
  ) {
    final theme = Theme.of(context);
    int count(PlayabilityIssue i) => warnings.where((w) => w.issue == i).length;
    final below = count(PlayabilityIssue.belowRange);
    final above = count(PlayabilityIssue.aboveRange);
    final reach = count(PlayabilityIssue.outOfReach);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          Text(
            _mpd.nameOf(_mpd.active),
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
          ),
          if (below > 0)
            Text(
              l10n.workshopPlayBelowRange(below),
              key: const ValueKey<String>('workshop-play-below'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          if (above > 0)
            Text(
              l10n.workshopPlayAboveRange(above),
              key: const ValueKey<String>('workshop-play-above'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          if (reach > 0)
            Text(
              l10n.workshopPlayOutOfReach(reach),
              key: const ValueKey<String>('workshop-play-reach'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
        ],
      ),
    );
  }

  Widget _analysisBanner(AppLocalizations l10n, ScoreAnalysis a) {
    final theme = Theme.of(context);
    final romans = [
      for (final s in a.segments)
        if (s.hasChord) s.roman!.symbol,
    ].join(' – ');
    final cadences = {for (final c in a.cadences) _cadenceLabel(l10n, c.type)};
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: const Icon(Icons.vpn_key, size: 15),
            label: Text(_analysisKeyName(l10n, a)),
            visualDensity: VisualDensity.compact,
          ),
          if (romans.isNotEmpty)
            Text(
              romans,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          _analysisLegendChip(l10n.funcTonic, HarmonicFunction.tonic),
          _analysisLegendChip(
            l10n.funcSubdominant,
            HarmonicFunction.subdominant,
          ),
          _analysisLegendChip(l10n.funcDominant, HarmonicFunction.dominant),
          for (final c in cadences)
            Text('• $c', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _analysisLegendChip(String label, HarmonicFunction function) => Chip(
        avatar: CircleAvatar(
          backgroundColor: _functionTint(function),
          radius: 6,
        ),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );

  Widget _voiceLegend(AppLocalizations l10n) {
    const v1 = Color(0xFF1565C0);
    const v2 = Color(0xFFE65100);
    return Tooltip(
      message: l10n.workshopVoiceOverlapHelp,
      child: Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 5),
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.workshopVoiceLegend,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            _voiceLegendChip(l10n.workshopVoice1Long, v1),
            _voiceLegendChip(l10n.workshopVoice2Long, v2),
            Text(
              l10n.workshopVoiceOverlapHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceLegendChip(String label, Color color) => Chip(
        avatar: CircleAvatar(backgroundColor: color, radius: 6),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );

  Widget _inspectorPanel(AppLocalizations l10n) {
    final theme = Theme.of(context);
    // The selected NOTES (rests carry none of these properties). The controls
    // apply to the whole selection — the `…OfSelected` mutators already do — so
    // the inspector works for a multi-note selection, not just a single note (the
    // ⌃ palette's old limitation, Cause 3).
    final notes = _doc.selectedElements.where((e) => !e.isRest).toList();
    final multi = notes.length > 1;
    bool allHave(bool Function(EditorElement) p) =>
        notes.isNotEmpty && notes.every(p);
    // The shared value across the selection, or null when it's mixed.
    T? common<T>(T? Function(EditorElement) get) {
      final values = notes.map(get).toSet();
      return values.length == 1 ? values.first : null;
    }

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(l10n.workshopInspector, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            _statusText(context, l10n), // "C♯4", "Rest" or "3 selected"
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 20),
          if (notes.isEmpty) ...[
            Text(
              _doc.hasSelection
                  ? l10n.workshopRest
                  : l10n.workshopInspectorEmpty,
              style: theme.textTheme.bodySmall,
            ),
            // A rest carries no articulation/dynamic/etc, but its LENGTH is a
            // real property — give it the same editable home the note gets,
            // instead of leaving a rest selection a dead end.
            if (_doc.hasSelection) ...[
              const SizedBox(height: 12),
              Text(l10n.workshopRestLength, style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              _restLengthControls(l10n),
            ],
          ] else ...[
            Text(
              l10n.workshopArticulations,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final art in _articulationOptions)
                  FilterChip(
                    label: Text(_articulationLabel(l10n, art)),
                    selected: allHave((e) => e.articulations.contains(art)),
                    onSelected: (_) =>
                        _rebuild(() => _doc.toggleArticulationOfSelected(art)),
                  ),
                FilterChip(
                  label: Text(l10n.workshopTie),
                  selected: allHave((e) => e.tieToNext),
                  onSelected: (_) => _rebuild(() => _doc.toggleTieOfSelected()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // SE-C4. Separate from the articulation chips above because a bow
            // direction is not an independent decoration: the strokes form a
            // chain, so choosing one RE-FLOWS the rest of the part. Putting it
            // among the toggles would imply it behaves like them.
            Text(l10n.workshopBowing, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  key: const ValueKey<String>('workshop-bow-down'),
                  label: Text('\u2293  ${l10n.workshopBowDown}'),
                  selected: _bowLockedTo(Articulation.downBow),
                  onSelected: (_) => _lockBow(Articulation.downBow),
                ),
                FilterChip(
                  key: const ValueKey<String>('workshop-bow-up'),
                  label: Text('\u2228  ${l10n.workshopBowUp}'),
                  selected: _bowLockedTo(Articulation.upBow),
                  onSelected: (_) => _lockBow(Articulation.upBow),
                ),
                ActionChip(
                  key: const ValueKey<String>('workshop-bow-auto'),
                  label: Text(l10n.workshopBowAuto),
                  onPressed: _clearBowLocks,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // SE-C1. Also a STATE rather than a toggle: it holds from here
            // until countermanded, so the chips show what is in force at the
            // selection, not what this note "has".
            Text(l10n.workshopPlayingState, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in PlayingState.values)
                  FilterChip(
                    key: ValueKey<String>('workshop-playing-${s.name}'),
                    label: Text(
                      s == PlayingState.pizzicato
                          ? l10n.workshopPizzicato
                          : l10n.workshopArco,
                    ),
                    selected: _playingStateAtSelection() == s,
                    onSelected: (_) => _setPlayingState(s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _inspectorRow(
              l10n.workshopDynamics,
              DropdownButton<DynamicLevel?>(
                isExpanded: true,
                value: common((e) => e.dynamic),
                onChanged: (v) => _rebuild(() => _doc.setDynamicOfSelected(v)),
                items: [
                  DropdownMenuItem(child: Text(l10n.workshopDynamicNone)),
                  for (final d in _dynamicOptions)
                    DropdownMenuItem(value: d, child: Text(d.name)),
                ],
              ),
            ),
            _inspectorRow(
              l10n.workshopOrnament,
              DropdownButton<Ornament?>(
                isExpanded: true,
                value: common((e) => e.ornament),
                onChanged: (v) => _rebuild(() => _doc.setOrnamentOfSelected(v)),
                items: [
                  DropdownMenuItem(child: Text(l10n.workshopDynamicNone)),
                  for (final e in _ornamentOptions.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
              ),
            ),
            const Divider(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              // Grace notes anchor to a single note (rests carry none), so this
              // stays single-note only. "Change from here…" moved to the shared
              // Structure section below, which works for a rest too.
              child: TextButton.icon(
                icon: const Icon(Icons.grade_outlined, size: 18),
                label: Text(l10n.workshopGraceNotes),
                onPressed: multi
                    ? null
                    : () {
                        final id = _doc.selectedId;
                        if (id != null) _showGraceDialog(id);
                      },
              ),
            ),
          ],
          // The bar-anchored "Structure" view: for ANY single selection — note
          // OR rest — summarise the mid-score changes anchored at the focused
          // element and host the "Change from here…" editor, so a rest selection
          // is no longer a dead end.
          if (_doc.selectedIds.length == 1) _inspectorStructure(l10n, theme),
        ],
      ),
    );
  }

  /// Duration + dot chips for the selected rest(s), driving the same
  /// [ScoreDocument.setDurationOfSelected] the input dock uses — so a rest's
  /// length is editable straight from the inspector, in any mode (the dock only
  /// edits the selection in select-mode). A mixed selection shows nothing
  /// selected and the dot toggle is disabled until the base agrees.
  Widget _restLengthControls(AppLocalizations l10n) {
    final rests = _doc.selectedElements.where((e) => e.isRest).toList();
    final bases = rests.map((e) => e.duration.base).toSet();
    final base = bases.length == 1 ? bases.first : null;
    final dotVals = rests.map((e) => e.duration.dots).toSet();
    final dotted = dotVals.length == 1 && dotVals.first > 0;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in _values)
          ChoiceChip(
            label: MusicGlyph(v.glyph, size: 18),
            selected: base == v.base,
            onSelected: (_) => _rebuild(
              () => _doc.setDurationOfSelected(
                NoteDuration(v.base, dots: dotted ? 1 : 0),
              ),
            ),
          ),
        FilterChip(
          label: Text(l10n.workshopDot),
          selected: dotted,
          // A dot needs a single base to attach to; grey it out when mixed.
          onSelected: base == null
              ? null
              : (_) => _rebuild(
                    () => _doc.setDurationOfSelected(
                      NoteDuration(base, dots: dotted ? 0 : 1),
                    ),
                  ),
        ),
      ],
    );
  }

  /// The bar-anchored **Structure** view of the inspector: for a single selected
  /// element (note OR rest) it lists the mid-score changes anchored there — the
  /// same set the "Change from here…" dialog edits — as read-only chips, and
  /// hosts that editor. Shown for a rest too, so a rest selection has actions.
  Widget _inspectorStructure(AppLocalizations l10n, ThemeData theme) {
    final id = _doc.selectedId!;
    final summary = _barChangeSummary(l10n, id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        Text(l10n.workshopStructure, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        if (summary.isEmpty)
          Text(l10n.workshopNoChange, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in summary)
                Chip(
                  label: Text(s),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        const SizedBox(height: 8),
        // The two most-changed bar attributes, editable in place — no need to
        // open "Change from here…" for the common case. They anchor at this
        // element's bar and apply on selection, exactly like the dialog.
        _changeRow<KeySignature>(
          label: l10n.workshopKey,
          value: _doc.keyChanges[id],
          items: {for (final f in _keyChoices) KeySignature(f): _keyLabel(f)},
          noChange: l10n.workshopNoChange,
          onChanged: (v) => _rebuild(() => _doc.setKeyChangeAt(id, v)),
        ),
        _changeRow<TimeSignature>(
          label: l10n.workshopTimeSignature,
          value: _doc.timeChanges[id],
          items: _timeChoices,
          noChange: l10n.workshopNoChange,
          onChanged: (v) => _rebuild(() => _doc.setTimeChangeAt(id, v)),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          // The rest — clef, mid-bar clef, tempo, volta, navigation — stay in
          // the fuller dialog.
          child: TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l10n.workshopChangeHere),
            onPressed: () => _showChangeHereDialog(id),
          ),
        ),
      ],
    );
  }

  /// Short labels for the bar-anchored changes anchored at element [id] — clef,
  /// mid-bar clef, key, time, tempo, repeat start/end, volta and navigation.
  /// Empty when nothing is anchored there (the inspector then shows "No change").
  List<String> _barChangeSummary(AppLocalizations l10n, String id) {
    final out = <String>[];
    final clef = _doc.clefChanges[id];
    if (clef != null) {
      out.add(
        '${l10n.workshopClef}: ${_CompositionWorkshopScreenState._clefGlyph(clef)} ${clef.name}',
      );
    }
    final inlineClef = _doc.inlineClefs[id];
    if (inlineClef != null) {
      out.add(
        '${l10n.workshopClefMidBar}: ${_CompositionWorkshopScreenState._clefGlyph(inlineClef)} ${inlineClef.name}',
      );
    }
    final key = _doc.keyChanges[id];
    if (key != null) out.add('${l10n.workshopKey}: ${_keyLabel(key.fifths)}');
    final time = _doc.timeChanges[id];
    if (time != null) {
      out.add(
        '${l10n.workshopTimeSignature}: '
        '${_timeChoices[time] ?? '${time.beats}/${time.beatUnit}'}',
      );
    }
    final tempo = _doc.tempoChangeAt(id);
    if (tempo != null) {
      out.add('${l10n.workshopTempo}: ♩=${tempo.quarterBpm.round()}');
    }
    if (_doc.repeatStartsAt(id)) out.add(l10n.workshopRepeatStart);
    if (_doc.repeatEndsAt(id)) out.add(l10n.workshopRepeatEnd);
    final volta = _doc.voltaAt(id);
    if (volta != null) out.add('${l10n.workshopVolta}: $volta.');
    final nav = _doc.navigationAt(id);
    if (nav != null) {
      out.add(
        '${l10n.workshopNavigation}: ${_navigationLabels[nav] ?? nav.name}',
      );
    }
    return out;
  }

  /// One labelled inspector row: a caption above a full-width control.
  Widget _inspectorRow(String label, Widget control) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            control,
          ],
        ),
      );

  bool get _selectedIdRepeatStarts {
    final id = _doc.selectedId;
    return id != null && _doc.repeatStartsAt(id);
  }

  bool get _selectedIdRepeatEnds {
    final id = _doc.selectedId;
    return id != null && _doc.repeatEndsAt(id);
  }

  /// A compact picker to set/clear a mid-score **clef, key or time change** at
  /// the bar containing element [id]. Three dropdowns, each defaulting to "No
  /// change" (the current setting is pre-selected); applied together on Apply.
  /// The flat property menu can't hold the 15 key / 10 time options, so this is
  /// a dialog opened from the note's palette button — depth revealed on demand.
  Future<void> _showChangeHereDialog(String id) async {
    final l10n = AppLocalizations.of(context)!;
    var clef = _doc.clefChanges[id];
    var inlineClef = _doc.inlineClefs[id];
    var key = _doc.keyChanges[id];
    var time = _doc.timeChanges[id];
    var tempo = _doc.tempoChangeAt(id);
    var volta = _doc.voltaAt(id);
    var nav = _doc.navigationAt(id);
    const clefOptions = [Clef.treble, Clef.bass, Clef.alto, Clef.tenor];
    final tempoItems = _tempoItems(tempo);

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workshopChangeHereTitle),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _changeRow<Clef>(
                label: l10n.workshopClef,
                value: clef,
                items: {
                  for (final c in clefOptions)
                    c: '${_CompositionWorkshopScreenState._clefGlyph(c)}  ${c.name}',
                },
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => clef = v),
              ),
              _changeRow<Clef>(
                label: l10n.workshopClefMidBar,
                value: inlineClef,
                items: {
                  for (final c in clefOptions)
                    c: '${_CompositionWorkshopScreenState._clefGlyph(c)}  ${c.name}',
                },
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => inlineClef = v),
              ),
              _changeRow<KeySignature>(
                label: l10n.workshopKey,
                value: key,
                items: {
                  for (final f in _keyChoices) KeySignature(f): _keyLabel(f),
                },
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => key = v),
              ),
              _changeRow<TimeSignature>(
                label: l10n.workshopTimeSignature,
                value: time,
                items: _timeChoices,
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => time = v),
              ),
              _changeRow<Tempo>(
                label: l10n.workshopTempo,
                value: tempo,
                items: tempoItems,
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => tempo = v),
              ),
              _changeRow<int>(
                label: l10n.workshopVolta,
                value: volta,
                items: const {1: '1.', 2: '2.', 3: '3.'},
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => volta = v),
              ),
              _changeRow<NavigationMark>(
                label: l10n.workshopNavigation,
                value: nav,
                items: _navigationLabels,
                noChange: l10n.workshopNoChange,
                onChanged: (v) => setLocal(() => nav = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );

    if (apply != true) return;
    _rebuild(() {
      _doc.setClefChangeAt(id, clef);
      _doc.setInlineClefAt(id, inlineClef);
      _doc.setKeyChangeAt(id, key);
      _doc.setTimeChangeAt(id, time);
      _doc.setTempoChangeAt(id, tempo);
      _doc.setVoltaAt(id, volta);
      _doc.setNavigationAt(id, nav);
    });
  }

  /// A small editor for the **grace notes** attached to the selected note: a
  /// run of pitches (drawn as small notes to the left) plus their [GraceStyle].
  /// Notes are appended by tapping C–B at the chosen octave (defaulting to the
  /// host note's octave) and removed by tapping their chip. Grace notes carry
  /// zero bar duration, so nothing here changes bar packing.
  Future<void> _showGraceDialog(String id) async {
    final l10n = AppLocalizations.of(context)!;
    final note = _doc.selected;
    if (note == null || note.isRest) return;
    final pitches = List<Pitch>.of(note.graceNotes);
    var style = note.graceStyle;
    var octave = note.pitch?.octave ?? 4;

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workshopGraceNotes),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The current grace sequence — tap a chip to remove it.
                if (pitches.isEmpty)
                  Text(
                    l10n.workshopGraceEmpty,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  )
                else
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < pitches.length; i++)
                        InputChip(
                          label: Text(pitches[i].toString()),
                          onDeleted: () => setLocal(() => pitches.removeAt(i)),
                        ),
                    ],
                  ),
                const Divider(height: 20),
                // Octave stepper for the notes added below.
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed:
                          octave > 0 ? () => setLocal(() => octave--) : null,
                    ),
                    Text('${l10n.intervalOctave} $octave'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed:
                          octave < 8 ? () => setLocal(() => octave++) : null,
                    ),
                  ],
                ),
                // Tap a note to append it to the grace run.
                Wrap(
                  spacing: 4,
                  children: [
                    for (final s in Step.values)
                      OutlinedButton(
                        onPressed: () => setLocal(
                          () => pitches.add(Pitch(s, octave: octave)),
                        ),
                        child: Text(s.name.toUpperCase()),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Acciaccatura (slashed) vs appoggiatura (leaning).
                SegmentedButton<GraceStyle>(
                  segments: [
                    ButtonSegment(
                      value: GraceStyle.acciaccatura,
                      label: Text(l10n.workshopGraceAcciaccatura),
                    ),
                    ButtonSegment(
                      value: GraceStyle.appoggiatura,
                      label: Text(l10n.workshopGraceAppoggiatura),
                    ),
                  ],
                  selected: {style},
                  onSelectionChanged: (s) => setLocal(() => style = s.first),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );

    if (apply != true) return;
    _rebuild(() => _doc.setGraceNotesOfSelected(pitches, style: style));
  }
}
