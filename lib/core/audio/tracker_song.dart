// lib/core/audio/tracker_song.dart
//
// The Advanced Tracker's document model: a full "module" in the ProTracker /
// Scream Tracker 3 / Impulse Tracker / FastTracker 2 sense — an ordered list of
// PATTERNS played through a shared band of channels (instruments), with none of
// the kid-grid limits. Where the Beginner Tracker (tracker_screen.dart) hardcodes
// one 8-step bar × 5 pentatonic rows × 4 slots, a [TrackerSong] has:
//
//   * endless pattern length  (rows: any count, [setRows]),
//   * endless tracks          (channels: add/remove at runtime),
//   * a multi-pattern song    ([patterns] + an [order] list, like the classic
//                              order/sequence editor).
//
// It is a thin arrangement layer over the ALREADY-general [TrackerEngine] — the
// engine mixes one pattern's channels to a loop WAV (mixStems), and [renderSong]
// concatenates a snapshot per order-list entry. Flutter-free, so it unit-tests
// without a device (test/tracker_song_test.dart), exactly like the engine.
//
// Invariants (checked by asserts):
//   * patterns.isNotEmpty and order.isNotEmpty (a song always has something to
//     edit and to play),
//   * every pattern is channel-major with `channelCount` columns, each of length
//     `rows`,
//   * the engine's live channel cells ARE the current pattern's cells — editing
//     the engine edits [current]; [selectPattern] saves/loads snapshots.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart'
    show Instrument, kSampleRate, wavBytes, wavBytesStereo;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';

/// One pattern: a named, channel-major grid of cells (`cells[channel][row]`).
/// A snapshot compatible with [TrackerEngine.exportCells] /
/// [TrackerEngine.importCells].
class TrackerPattern {
  TrackerPattern({required this.name, required this.cells});

  /// A fresh empty pattern sized [channels] × [rows].
  TrackerPattern.empty({
    required this.name,
    required int channels,
    required int rows,
  }) : cells = [
          for (var c = 0; c < channels; c++)
            List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
        ];

  String name;

  /// Channel-major: `cells[channel]` is that channel's column of [rows] cells.
  final List<List<TrackerCell>> cells;

  int get channelCount => cells.length;
  int get rows => cells.isEmpty ? 0 : cells.first.length;

  bool get hasAnyNote => cells.any((col) => col.any((cell) => !cell.isEmpty));

  /// A deep copy (own cell lists) — so cloning a pattern never aliases cells.
  TrackerPattern clone({String? name}) => TrackerPattern(
        name: name ?? this.name,
        cells: [for (final col in cells) List<TrackerCell>.of(col)],
      );
}

/// The Advanced Tracker document. Owns a [TrackerEngine] (the band + the live
/// pattern being edited), the list of [patterns], and the [order] list.
/// The default shared instrument pool ([TrackerSong.instruments]): the four
/// built-in additive voices, so an authored song can reference an instrument
/// number 1..4 out of the box. Module import replaces this with the module's
/// own instruments.
List<TrackerInstrument> defaultInstrumentPool() => <TrackerInstrument>[
      // A GROWABLE list (not const) so a screen can append a loaded voice
      // (e.g. a SoundFont preset) to the pool at runtime.
      const AdditiveInstrument('piano', Instrument.piano),
      const AdditiveInstrument('cello', Instrument.cello),
      const AdditiveInstrument('flute', Instrument.flute),
      const AdditiveInstrument('musicBox', Instrument.musicBox),
    ];

class TrackerSong {
  TrackerSong._(
    this._engine,
    this.patterns,
    this.order,
    this._current,
    this.instruments,
  );

  /// A new song with the default band ([defaultTrackerChannels]) and one empty
  /// pattern of [rows] steps at [timing].
  factory TrackerSong({
    List<TrackerChannel>? channels,
    TrackerTiming? timing,
    int patternCount = 1,
    List<TrackerInstrument>? instruments,
  }) {
    final t = timing ?? const TrackerTiming(rows: 32);
    final band = channels ?? defaultTrackerChannels(rows: t.rows);
    final engine = TrackerEngine(channels: band, timing: t);
    final patterns = [
      for (var i = 0; i < (patternCount < 1 ? 1 : patternCount); i++)
        TrackerPattern.empty(
          name: _patternName(i),
          channels: band.length,
          rows: t.rows,
        ),
    ];
    engine.importCells(patterns.first.cells);
    return TrackerSong._(
      engine,
      patterns,
      [0],
      0,
      instruments ?? defaultInstrumentPool(),
    );
  }

  /// Builds a song directly from prepared [channels] + [patterns] + [order] —
  /// the shape a module importer produces (see tracker_song_module.dart). Every
  /// pattern must be channel-major with `channels.length` columns of
  /// `timing.rows` cells.
  factory TrackerSong.fromParts({
    required List<TrackerChannel> channels,
    required TrackerTiming timing,
    required List<TrackerPattern> patterns,
    required List<int> order,
    List<TrackerInstrument>? instruments,
  }) {
    final engine = TrackerEngine(channels: channels, timing: timing);
    final pats = patterns.isEmpty
        ? [
            TrackerPattern.empty(
              name: '00',
              channels: channels.length,
              rows: timing.rows,
            ),
          ]
        : patterns;
    engine.importCells(pats.first.cells);
    final ord = order.isEmpty ? [0] : List<int>.of(order);
    return TrackerSong._(
      engine,
      pats,
      ord,
      0,
      instruments ?? defaultInstrumentPool(),
    );
  }

  TrackerEngine _engine;
  TrackerEngine get engine => _engine;

  /// All patterns (>= 1).
  final List<TrackerPattern> patterns;

  /// The order list: indices into [patterns], in play order (>= 1). May repeat.
  final List<int> order;

  /// The shared INSTRUMENT POOL a cell's [TrackerCell.instrument] indexes
  /// (1-based). Defaults to [defaultInstrumentPool]; module import supplies the
  /// module's instruments. The channel's own instrument is the fallback for a
  /// cell with instrument 0.
  final List<TrackerInstrument> instruments;

  int _current;

  // --- Read-only views ---------------------------------------------------

  int get currentIndex => _current;
  TrackerPattern get current => patterns[_current];
  int get channelCount => _engine.channels.length;
  int get rows => _engine.rows;
  TrackerTiming get timing => _engine.timing;
  List<TrackerChannel> get channels => _engine.channels;

  /// Total song length in ms. Normally one pattern's [TrackerTiming.totalMs] per
  /// order entry; when the song has flow commands (Bxx/Dxx/E6x) it is the
  /// resolved length of the actually-played row sequence ([walkFlow]). A MID-SONG
  /// tempo/speed change ([songUsesVariableTiming]) sums the per-row durations so
  /// the non-uniform length matches the rendered WAV; otherwise an `Fxx`
  /// set-tempo is applied uniformly ([effectiveTiming]). Either way this matches
  /// the rendered WAV and the transport loops/stops at the right time. The common
  /// flow-free, tempo-free case short-circuits with no allocation.
  int get songTotalMs {
    // Persist live engine edits first (like the render methods do) so a just-
    // authored Fxx tempo/speed or flow command is reflected in the length —
    // otherwise the current pattern's snapshot lags and the transport loops at
    // the wrong time. syncCurrent is a cheap shallow copy of the current
    // pattern only.
    syncCurrent();
    if (songUsesVariableTiming(this)) return variableSongTotalMs(this);
    final t = effectiveTiming(this);
    // Uniform tempo throughout (Feature B changes row COUNT, not tempo), so the
    // length is stepMs × the number of played rows. Flow OR variable-length
    // patterns walk the played sequence; the uniform, flow-free case
    // short-circuits with no allocation.
    return songNeedsWalkRender(this)
        ? t.stepMs * walkFlow(this).length
        : t.totalMs * order.length;
  }

  /// The ms offset where the order entry at [orderIndex] begins.
  int patternStartMs(int orderIndex) => timing.totalMs * orderIndex;

  /// The order position (index into [order]) sounding at song-time [ms].
  int orderIndexAtMs(int ms) {
    if (order.isEmpty || timing.totalMs <= 0) return 0;
    final i = ms ~/ timing.totalMs;
    return i < 0 ? 0 : (i >= order.length ? order.length - 1 : i);
  }

  bool get isEmpty => patterns.every((p) => !p.hasAnyNote);

  /// Whether any pattern carries an effect-column command (any cell
  /// [TrackerCell.hasCommand]). When true, rendering routes through the
  /// tick-based [replaySong]/[replayPattern] (which honour the pitch/volume
  /// commands) instead of the offline mixer. False → the fast offline path is
  /// unchanged, so command-free songs pay nothing. Reads the pattern snapshots;
  /// the render methods [syncCurrent] first so live edits are seen.
  bool get usesCommands =>
      patterns.any((p) => p.cells.any((col) => col.any((c) => c.hasCommand)));

  /// Whether any cell names a per-cell instrument ([TrackerCell.instrument]) — a
  /// second reason to route rendering through the replayer (which honours it).
  bool get usesInstruments => patterns.any(
        (p) => p.cells.any((col) => col.any((c) => c.instrument != 0)),
      );

  /// Whether the song pans anything — any channel with a non-centre
  /// [TrackerChannel.pan], or any 8xx pan command. When true the render produces
  /// a STEREO WAV ([mixStemsStereo]/[wavBytesStereo]); when false it stays MONO
  /// and byte-identical, so a non-panned song pays nothing.
  bool get usesPan =>
      channels.any(
        (c) => c.pan != 0 || (c.panEnvelope != null && !c.panEnvelope!.isEmpty),
      ) ||
      patterns.any(
        (p) => p.cells.any(
          (col) => col.any(
            (c) => c.fxCmd == kFxSetPan || c.fxCmd == kFxPanSlide,
          ),
        ),
      );

  /// Whether any channel carries a (non-empty) [VolumeEnvelope] — a reason to
  /// route rendering through the replayer (the offline path ignores envelopes).
  bool get usesEnvelopes => channels.any(
        (c) => c.volumeEnvelope != null && !c.volumeEnvelope!.isEmpty,
      );

  // --- Pattern editing (delegates to the engine on the current pattern) ---

  /// Persist the engine's live cells back into the current pattern snapshot.
  void syncCurrent() {
    final live = _engine.exportCells();
    for (var c = 0; c < live.length && c < current.cells.length; c++) {
      current.cells[c] = live[c];
    }
  }

  /// Remove pool instrument [poolIndex] (0-based) and REMAP the per-cell
  /// instrument column across every pattern so notes keep the right voice: a
  /// cell pointing AT the removed instrument falls back to the channel default
  /// (0); a cell pointing at a LATER pool instrument shifts down by one. No-op
  /// for an out-of-range index. Syncs live edits first, then reloads the
  /// (remapped) current pattern into the engine.
  void removeInstrument(int poolIndex) {
    if (poolIndex < 0 || poolIndex >= instruments.length) return;
    syncCurrent();
    final removed = poolIndex + 1; // 1-based value in TrackerCell.instrument
    for (final p in patterns) {
      for (final col in p.cells) {
        for (var r = 0; r < col.length; r++) {
          final c = col[r];
          if (c.instrument == 0 || c.instrument < removed) continue;
          final newInst = c.instrument == removed ? 0 : c.instrument - 1;
          col[r] = c.copyWith(instrument: newInst);
        }
      }
    }
    instruments.removeAt(poolIndex);
    _engine.importCells(current.cells); // the current pattern was remapped
  }

  /// Save the live pattern, then load [index] into the engine for editing.
  /// Re-times the engine to the selected pattern's own row count (Feature B:
  /// patterns may have different lengths), so the engine's per-channel
  /// cell-count assert holds and editing a variable-length pattern works.
  void selectPattern(int index) {
    assert(index >= 0 && index < patterns.length);
    if (index == _current) return;
    syncCurrent();
    _current = index;
    final newRows = current.rows;
    if (newRows != _engine.timing.rows) {
      // _rebuild re-sizes the band to the new timing and imports current.cells.
      _rebuild(_engine.channels, _engine.timing.copyWith(rows: newRows));
    } else {
      _engine.importCells(current.cells);
    }
  }

  // --- Song arrangement --------------------------------------------------

  /// Appends a pattern (empty, or a clone of the current one) and returns its
  /// index. Does not touch the order list.
  int addPattern({bool cloneCurrent = false, String? name}) {
    syncCurrent();
    final p = cloneCurrent
        ? current.clone(name: name ?? _patternName(patterns.length))
        : TrackerPattern.empty(
            name: name ?? _patternName(patterns.length),
            channels: channelCount,
            rows: rows,
          );
    patterns.add(p);
    return patterns.length - 1;
  }

  /// Removes pattern [index] (keeping at least one), remapping the order list
  /// (dropped entries removed; higher indices shifted down). The engine reloads
  /// a valid current pattern.
  void removePattern(int index) {
    if (patterns.length <= 1) return;
    assert(index >= 0 && index < patterns.length);
    syncCurrent();
    patterns.removeAt(index);
    order.removeWhere((o) => o == index);
    for (var i = 0; i < order.length; i++) {
      if (order[i] > index) order[i]--;
    }
    if (order.isEmpty) order.add(0);
    _current = _current >= patterns.length
        ? patterns.length - 1
        : (_current > index ? _current - 1 : _current);
    _engine.importCells(current.cells);
  }

  /// Renames pattern [index] to [name] — a song "section" label (Intro, Verse,
  /// Chorus …) shown in the pattern selector + order list. Trims whitespace;
  /// a blank name is ignored (a pattern always has a label). No-op on a bad
  /// index.
  void renamePattern(int index, String name) {
    if (index < 0 || index >= patterns.length) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    patterns[index].name = trimmed;
  }

  /// Appends [patternIndex] to the play order.
  void addToOrder(int patternIndex) {
    assert(patternIndex >= 0 && patternIndex < patterns.length);
    order.add(patternIndex);
  }

  /// Removes the order entry at [position] (keeping at least one).
  void removeFromOrder(int position) {
    if (order.length <= 1) return;
    order.removeAt(position);
  }

  // --- Band editing (endless tracks) -------------------------------------

  /// Adds a channel to the band and an empty column to EVERY pattern, keeping
  /// the channel/pattern shapes consistent. Rebuilds the engine so its caches
  /// and channel-index bookkeeping start clean.
  void addChannel({TrackerInstrument? instrument, double gain = 0.6}) {
    syncCurrent();
    final id = 'track${channelCount + 1}';
    final band = List<TrackerChannel>.of(_engine.channels)
      ..add(
        TrackerChannel(
          id: id,
          instrument: instrument ?? kTrackerInstruments.first.build(),
          gain: gain,
          rows: rows,
        ),
      );
    for (final p in patterns) {
      p.cells.add(
        List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
      );
    }
    _rebuild(band, _engine.timing);
    _applyMute(); // a new channel is suppressed if a solo is active
  }

  /// Removes channel [index] from the band and from every pattern (keeping at
  /// least one channel).
  void removeChannel(int index) {
    if (channelCount <= 1) return;
    assert(index >= 0 && index < channelCount);
    syncCurrent();
    final band = List<TrackerChannel>.of(_engine.channels)..removeAt(index);
    for (final p in patterns) {
      p.cells.removeAt(index);
    }
    // Remap the mute/solo index sets around the removed channel.
    _userMuted = _remapAfterRemove(_userMuted, index);
    _soloed = _remapAfterRemove(_soloed, index);
    _rebuild(band, _engine.timing);
    _applyMute();
  }

  /// Re-voices channel [index] (delegates to the engine; caches invalidate).
  void setChannelInstrument(int index, TrackerInstrument instrument) =>
      _engine.setChannelInstrument(index, instrument);

  /// Sets channel [index]'s mix gain (delegates to the engine).
  void setChannelGain(int index, double gain) =>
      _engine.setChannelGain(index, gain);

  // --- Block operations (classic tracker copy/cut/paste/transpose) -------
  //
  // A block is a rectangle of the CURRENT pattern's cells, returned/consumed as
  // row-major `block[row][col]`. All operate through the engine so caches
  // invalidate. Coordinates are auto-ordered (start/end may be swapped).

  (int, int) _order2(int a, int b) => a <= b ? (a, b) : (b, a);

  /// Copies the rectangle [ch0,row0]..[ch1,row1] as row-major cells.
  List<List<TrackerCell>> copyBlock(int ch0, int row0, int ch1, int row1) {
    final (cLo, cHi) =
        _order2(ch0.clamp(0, channelCount - 1), ch1.clamp(0, channelCount - 1));
    final (rLo, rHi) =
        _order2(row0.clamp(0, rows - 1), row1.clamp(0, rows - 1));
    return [
      for (var r = rLo; r <= rHi; r++)
        [for (var c = cLo; c <= cHi; c++) _engine.cellAt(c, r)],
    ];
  }

  /// Empties every cell in the rectangle.
  void clearBlock(int ch0, int row0, int ch1, int row1) {
    final (cLo, cHi) = _order2(ch0, ch1);
    final (rLo, rHi) = _order2(row0, row1);
    for (var r = rLo; r <= rHi && r < rows; r++) {
      for (var c = cLo; c <= cHi && c < channelCount; c++) {
        _engine.clearCell(c, r);
      }
    }
  }

  /// Pastes [block] with its top-left at [chAt]/[rowAt]. When [mix] is true only
  /// empty target cells are written (merge), else it overwrites. Out-of-range
  /// cells are skipped.
  void pasteBlock(
    List<List<TrackerCell>> block,
    int chAt,
    int rowAt, {
    bool mix = false,
  }) {
    for (var r = 0; r < block.length; r++) {
      for (var c = 0; c < block[r].length; c++) {
        final tc = chAt + c, tr = rowAt + r;
        if (tc < 0 || tc >= channelCount || tr < 0 || tr >= rows) continue;
        if (mix && !_engine.cellAt(tc, tr).isEmpty) continue;
        _engine.setCell(tc, tr, block[r][c]);
      }
    }
  }

  /// Shifts every note in the rectangle by [semitones] (clamped 0..127),
  /// preserving volume/effect. Empty cells are left alone.
  void transposeBlock(int ch0, int row0, int ch1, int row1, int semitones) {
    final (cLo, cHi) = _order2(ch0, ch1);
    final (rLo, rHi) = _order2(row0, row1);
    for (var r = rLo; r <= rHi && r < rows; r++) {
      for (var c = cLo; c <= cHi && c < channelCount; c++) {
        final cur = _engine.cellAt(c, r);
        if (cur.midi == null) continue;
        _engine.setCell(
          c,
          r,
          cur.copyWith(midi: (cur.midi! + semitones).clamp(0, 127)),
        );
      }
    }
  }

  /// Fills a chromatic run down each selected channel: from the note at the
  /// TOP selected row to the note at the BOTTOM selected row, placing a note on
  /// every row in between (linear semitone ramp, rounded, clamped 0..127) — a
  /// glissando/run. Skips a channel whose top or bottom row has no note. The
  /// top note's volume/effect/instrument are carried onto every filled row.
  void interpolateNotesBlock(int ch0, int row0, int ch1, int row1) {
    final (cLo, cHi) = _order2(ch0, ch1);
    final (rLo, rHi) = _order2(row0, row1);
    if (rHi <= rLo) return;
    for (var c = cLo; c <= cHi && c < channelCount; c++) {
      final top = _engine.cellAt(c, rLo);
      final bot = _engine.cellAt(c, rHi);
      if (top.midi == null || bot.midi == null) continue;
      final m0 = top.midi!;
      final m1 = bot.midi!;
      for (var r = rLo; r <= rHi; r++) {
        final t = (r - rLo) / (rHi - rLo);
        final midi = (m0 + (m1 - m0) * t).round().clamp(0, 127);
        _engine.setCell(
          c,
          r,
          top.copyWith(midi: midi),
        );
      }
    }
  }

  /// Lays a chord ACROSS tracks: writes [rootMidi] on [channel] at [row], then
  /// each higher chord tone (root + [intervals]) on the next channels to the
  /// right. Tones past the last channel are dropped. [intervals] are semitone
  /// offsets from the root (e.g. [0,4,7] = major). Each note carries [instrument]
  /// (0 = channel default). Returns how many tones were placed.
  int stampChordAcross(
    int channel,
    int row,
    int rootMidi,
    List<int> intervals, {
    int instrument = 0,
  }) {
    if (row < 0 || row >= rows) return 0;
    var placed = 0;
    for (var i = 0; i < intervals.length; i++) {
      final c = channel + i;
      if (c < 0 || c >= channelCount) break;
      final midi = (rootMidi + intervals[i]).clamp(0, 127);
      _engine.setCell(c, row, TrackerCell(midi: midi, instrument: instrument));
      placed++;
    }
    return placed;
  }

  /// Lays a chord as an ARPEGGIO down one column: writes the chord tones (root +
  /// [intervals]) on [channel] starting at [row], each [step] rows apart
  /// (step≥1). Tones past the pattern end are dropped. Each note carries
  /// [instrument]. Returns how many tones were placed.
  int stampArpeggio(
    int channel,
    int row,
    int rootMidi,
    List<int> intervals, {
    int step = 1,
    int instrument = 0,
  }) {
    if (channel < 0 || channel >= channelCount) return 0;
    final s = step < 1 ? 1 : step;
    var placed = 0;
    for (var i = 0; i < intervals.length; i++) {
      final r = row + i * s;
      if (r < 0 || r >= rows) break;
      final midi = (rootMidi + intervals[i]).clamp(0, 127);
      _engine.setCell(
        channel,
        r,
        TrackerCell(midi: midi, instrument: instrument),
      );
      placed++;
    }
    return placed;
  }

  // --- Mute / solo -------------------------------------------------------

  Set<int> _userMuted = {};
  Set<int> _soloed = {};

  bool isMuted(int channel) => _userMuted.contains(channel);
  bool isSoloed(int channel) => _soloed.contains(channel);

  /// Whether [channel] is heard: not user-muted, and (if any channel is soloed)
  /// itself soloed.
  bool isAudible(int channel) =>
      !_userMuted.contains(channel) &&
      (_soloed.isEmpty || _soloed.contains(channel));

  void toggleMute(int channel) {
    if (!_userMuted.remove(channel)) _userMuted.add(channel);
    _applyMute();
  }

  void toggleSolo(int channel) {
    if (!_soloed.remove(channel)) _soloed.add(channel);
    _applyMute();
  }

  /// Pushes the effective mute (user mute OR solo-suppressed) to every channel.
  void _applyMute() {
    for (var i = 0; i < channelCount; i++) {
      _engine.setChannelMuted(i, !isAudible(i));
    }
  }

  static Set<int> _remapAfterRemove(Set<int> s, int removed) => {
        for (final x in s)
          if (x != removed) (x > removed ? x - 1 : x),
      };

  // --- Timing (endless length) -------------------------------------------

  /// Resizes every pattern to [newRows] steps (truncating or padding with empty
  /// cells) and re-times the engine. This is the direct fix for the Beginner
  /// grid's one-bar ceiling.
  void setRows(int newRows) {
    assert(newRows > 0);
    if (newRows == rows) return;
    syncCurrent();
    for (final p in patterns) {
      for (final col in p.cells) {
        _resizeColumn(col, newRows);
      }
    }
    _rebuild(_engine.channels, _engine.timing.copyWith(rows: newRows));
  }

  /// Resizes ONE pattern (Feature B: per-pattern variable length) to [newRows]
  /// steps — truncating extra rows or padding with [TrackerCell.empty] — leaving
  /// every other pattern untouched. If it resizes the CURRENT pattern, the engine
  /// is re-timed to [newRows] so its per-channel cell-count assert holds and
  /// editing the new rows works. (Contrast [setRows], which resizes ALL patterns.)
  void setPatternRows(int patternIndex, int newRows) {
    assert(patternIndex >= 0 && patternIndex < patterns.length);
    assert(newRows > 0);
    final p = patterns[patternIndex];
    if (p.rows == newRows) return;
    final isCurrent = patternIndex == _current;
    if (isCurrent) syncCurrent(); // capture live edits before resizing
    for (final col in p.cells) {
      _resizeColumn(col, newRows);
    }
    if (isCurrent) {
      _rebuild(_engine.channels, _engine.timing.copyWith(rows: newRows));
    }
  }

  /// Sets the tempo (BPM) — re-times the engine, cells unchanged.
  void setTempo(int bpm) {
    if (bpm == timing.tempoBpm || bpm <= 0) return;
    _engine.timing = timing.copyWith(tempoBpm: bpm);
  }

  /// Sets the swing (0 = straight … up to a triplet shuffle) — re-times the
  /// engine's off-beat onsets, cells unchanged. Clamped to the timing's valid
  /// range [0, 0.9]; the loop length is unaffected.
  void setSwing(double swing) {
    final s = swing.clamp(0.0, 0.9);
    if (s == timing.swing) return;
    _engine.timing = timing.copyWith(swing: s);
  }

  // --- Audio -------------------------------------------------------------

  /// The current pattern mixed to one loop-ready WAV. When the pattern carries
  /// effect commands it renders through the tick [replayPattern]; otherwise the
  /// cached offline mix.
  Uint8List renderCurrentPatternWav() {
    syncCurrent();
    final needsReplayer = usesEnvelopes ||
        current.cells.any(
          (col) => col.any((c) => c.hasCommand || c.instrument != 0),
        );
    if (needsReplayer) {
      return usesPan
          ? wavBytesStereo(
              replayPatternStereo(
                channels,
                current.cells,
                timing,
                pool: instruments,
              ).pcm,
            )
          : wavBytes(
              replayPattern(channels, current.cells, timing, pool: instruments)
                  .pcm,
            );
    }
    if (usesPan) return wavBytesStereo(_engine.renderLoopPcmStereo());
    return _engine.renderLoop();
  }

  /// The whole song (the [order] list) rendered to one WAV, patterns back to
  /// back. Side-effect-free (the engine's live pattern is restored). Routes
  /// through the tick [replaySong] when any pattern [usesCommands].
  Uint8List renderSongWav() {
    syncCurrent();
    // Panned songs render in STEREO; the stereo replayer handles commands /
    // per-cell instruments / flow / variable-length via the same walk.
    if (usesPan) {
      return wavBytesStereo(replaySongStereo(this).pcm);
    }
    // Else route through the mono tick replayer for commands, per-cell
    // instruments, flow, OR variable-length patterns (the offline concatenation
    // assumes one fixed pattern length). A uniform, command-free, unpanned song
    // keeps the fast offline path.
    if (usesCommands ||
        usesInstruments ||
        usesEnvelopes ||
        songNeedsWalkRender(this)) {
      return wavBytes(replaySong(this).pcm);
    }
    return renderSong(_engine, [for (final i in order) patterns[i].cells]);
  }

  /// Total rendered song length in samples (sums each played pattern's own
  /// length under [songTotalMs]).
  int get songTotalSamples => (songTotalMs * kSampleRate) ~/ 1000;

  // --- internals ---------------------------------------------------------

  void _rebuild(List<TrackerChannel> band, TrackerTiming timing) {
    // The engine constructor asserts every channel's cell count == timing.rows,
    // so normalize the band's live cells before building (importCells below then
    // overwrites them with the current pattern's snapshot).
    for (final ch in band) {
      _resizeColumn(ch.cells, timing.rows);
    }
    _engine = TrackerEngine(channels: band, timing: timing);
    _engine.importCells(current.cells);
  }

  static void _resizeColumn(List<TrackerCell> col, int newRows) {
    if (newRows < col.length) {
      col.removeRange(newRows, col.length);
    } else {
      col.addAll(
        List<TrackerCell>.filled(newRows - col.length, TrackerCell.empty),
      );
    }
  }

  /// Classic pattern names: 00, 01, 02, … (two-digit like tracker order lists).
  static String _patternName(int i) => i.toString().padLeft(2, '0');
}

/// Snaps [row] (plus its sub-row fraction [phaseInRow] ∈ [0,1)) to the nearest
/// BEAT boundary — a multiple of [stepsPerBeat] rows — wrapping within
/// [totalRows]. Used by the tracker's live-record quantize so a slightly-off
/// jam hit lands on the beat. A no-op (returns [row]) when [stepsPerBeat] ≤ 1
/// or [totalRows] ≤ 0.
int quantizeRowToBeat(
  int row,
  double phaseInRow,
  int stepsPerBeat,
  int totalRows,
) {
  if (stepsPerBeat <= 1 || totalRows <= 0) return row;
  final nearest = ((row + phaseInRow) / stepsPerBeat).round() * stepsPerBeat;
  final wrapped = nearest % totalRows;
  return wrapped < 0 ? wrapped + totalRows : wrapped;
}
