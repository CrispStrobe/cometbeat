List<PlayedRow> walkFlow(TrackerSong song, {int maxRows = 4096}) {
  final order = song.order;
  final played = <PlayedRow>[];
  var oi = 0;
  var row = 0;
  var loopStartRow = 0; // E6x pattern-loop start (defaults to row 0)
  var loopCount = 0; // remaining E6x repeats
  // Fxx state carried across rows: speed (ticks/row) + tempo (BPM). A value takes
  // effect ON its own row and persists until the next Fxx of that kind.
  var curSpeed = kDefaultTicksPerRow;
  var curTempo = song.timing.tempoBpm;

  // Loop detection: track positions visited before position jumps (Bxx).
  // E6x pattern loops are intentional and should not trigger loop detection.
  final visited = <String, bool>{};
  var loopDetected = false;

  while (oi >= 0 &&
      oi < order.length &&
      played.length < maxRows &&
      !loopDetected) {
    final patternIndex = order[oi];
    final cells = song.patterns[patternIndex].cells;
    // Per-pattern length: each entry uses ITS OWN row count (Feature B). A jump/
    // break landing row is clamped to the TARGET pattern's length here.
    final rows = song.patterns[patternIndex].rows;
    if (row < 0) {
      row = 0;
    } else if (row >= rows) {
      row = rows - 1;
    }

    // Apply any Fxx (set-speed/tempo) or Txx (tempo SLIDE) on this row BEFORE
    // recording it (effect is on its own row): Fxx param < 0x20 → speed (min 1),
    // >= 0x20 → tempo (BPM) (Feature A); Txx steps the tempo by amount×(speed−1),
    // row-granular. First Txx across channels wins.
    var slidThisRow = false;
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxSetSpeed) {
        if (c.fxParam >= 0x20) {
          curTempo = c.fxParam;
        } else if (c.fxParam > 0) {
          curSpeed = c.fxParam; // already >= 1
        }
      } else if (c.fxCmd == kFxTempoSlide && !slidThisRow) {
        slidThisRow = true;
        final up = ((c.fxParam >> 4) & 0xF) == 1;
        final amount = c.fxParam & 0xF;
        final ticks = curSpeed > 1 ? curSpeed - 1 : 1;
        curTempo = (curTempo + (up ? amount : -amount) * ticks).clamp(32, 255);
      }
    }
    played.add(PlayedRow(oi, patternIndex, row, curSpeed, curTempo));

    // EEx pattern delay: repeat THIS row x additional times (x+1 total) before
    // advancing. The extra copies re-run the row (additive voices re-trigger on
    // each), lengthening it consistently across walk → timing → render. First
    // EEx on the row wins; delay of 0 is a no-op.
    int? patternDelay;
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxExtended &&
          ((c.fxParam >> 4) & 0xF) == kExPatternDelay) {
        patternDelay ??= c.fxParam & 0xF;
      }
    }
    if (patternDelay != null && patternDelay > 0) {
      for (var i = 0; i < patternDelay && played.length < maxRows; i++) {
        played.add(PlayedRow(oi, patternIndex, row, curSpeed, curTempo));
      }
    }

    // Scan the row across channels for flow commands (first of each wins).
    int? jumpToOrder;
    int? breakToRow;
    int? loopValue; // E6x low nibble (0 = set the loop start)
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxPositionJump) {
        jumpToOrder ??= c.fxParam;
      } else if (c.fxCmd == kFxPatternBreak) {
        // Decimal row param; clamped to the TARGET pattern's length at landing.
        breakToRow ??= (c.fxParam >> 4) * 10 + (c.fxParam & 0xF);
      } else if (c.fxCmd == kFxExtended &&
          ((c.fxParam >> 4) & 0xF) == kExPatternLoop) {
        loopValue ??= c.fxParam & 0xF;
      }
    }

    void advance() {
      row += 1;
      if (row >= rows) {
        oi += 1;
        row = 0;
      }
    }

    if (jumpToOrder != null) {
      // Position jump - check if this creates a song loop
      final jumpKey = '$jumpToOrder:${breakToRow ?? 0}';
      if (visited.containsKey(jumpKey)) {
        // Jumping to a previously-visited position = song loop
        loopDetected = true;
      } else {
        visited['$oi:$row'] = true; // Mark current position before jumping
        oi = jumpToOrder;
        row = breakToRow ?? 0;
      }
    } else if (breakToRow != null) {
      visited['$oi:$row'] = true; // Mark current position before breaking
      oi += 1;
      row = breakToRow;
    } else if (loopValue == 0) {
      loopStartRow = row; // E60 marks the loop start, then plays on
      advance();
    } else if (loopValue != null && loopValue > 0) {
      if (loopCount == 0) {
        loopCount = loopValue; // arm the loop
        row = loopStartRow;
        // Don't mark as visited - E6x is intentional loop
      } else {
        loopCount -= 1;
        if (loopCount > 0) {
          row = loopStartRow;
        } else {
          advance(); // loop finished
        }
      }
    } else {
      advance();
    }
  }
  return played;
}
