// lib/core/curriculum/concept_map.dart
//
// The grade-1–10 CONCEPT INVENTORY — the spine the read-through textbook hangs on
// and the input to the coverage gap analysis (see coverage_gaps.dart).
//
// Every entry is re-expressed in our OWN words: it records the underlying fact
// (which concept a school year introduces, and which games train it) — never
// verbatim text, tables, or exercises from any state curriculum. The topic scope
// is distilled from public sources (NRW Grundschule; Schleswig-Holstein Sek I),
// the same footing as core/curriculum/curriculum.dart. See PLAN.md "Textbook mode
// → Curriculum source & licensing".
//
// A `Concept` with an empty [gameIds] is a KNOWN COVERAGE GAP left in on purpose,
// so the analysis and the textbook both make it visible rather than hiding it.

/// School-year bands, coarse on purpose (Klasse 1–2 … 9–10).
enum GradeBand { g12, g34, g56, g78, g910 }

extension GradeBandLabel on GradeBand {
  String get label => switch (this) {
        GradeBand.g12 => 'Grades 1–2',
        GradeBand.g34 => 'Grades 3–4',
        GradeBand.g56 => 'Grades 5–6',
        GradeBand.g78 => 'Grades 7–8',
        GradeBand.g910 => 'Grades 9–10',
      };
}

/// Broad concept areas, for grouping lessons and reading the gap report.
enum ConceptArea {
  pulse,
  reading,
  duration,
  meter,
  dynamics,
  tempo,
  pitch,
  scales,
  intervals,
  chords,
  harmony,
  articulation,
  transpose,
  form,
  timbre,
  technique,
  aural,
  creating,
  repertoire,
}

/// One teachable concept: what it is (our words), when it's introduced, and the
/// games that drill it (empty = a gap we don't yet train).
class Concept {
  const Concept(this.id, this.band, this.area, this.title, this.gameIds);

  final String id;
  final GradeBand band;
  final ConceptArea area;

  /// A short plain-English label (our words). Localised when it becomes a lesson.
  final String title;

  /// Games that train this concept, by registry id.
  final List<String> gameIds;

  bool get isTrained => gameIds.isNotEmpty;
  bool get isThin => gameIds.length == 1;
}

/// The inventory. Ordered by grade band, then by area, so it reads as a syllabus.
const List<Concept> kConcepts = [
  // --- Grades 1–2: pulse, contour, the big opposites; notation as a listening aid.
  Concept(
    'pulse',
    GradeBand.g12,
    ConceptArea.pulse,
    'A steady beat (pulse)',
    ['beat_runner', 'rhythm_tap', 'beat_count'],
  ),
  Concept(
    'high_low',
    GradeBand.g12,
    ConceptArea.pitch,
    'Higher and lower sounds',
    ['pitch_sort', 'pitch_sort_bass'],
  ),
  Concept(
    'melody_direction',
    GradeBand.g12,
    ConceptArea.pitch,
    'A tune that climbs or falls',
    ['direction_ear', 'run_direction'],
  ),
  Concept(
    'same_different',
    GradeBand.g12,
    ConceptArea.pitch,
    'Same sound or different',
    ['same_diff'],
  ),
  Concept(
    'loud_soft',
    GradeBand.g12,
    ConceptArea.dynamics,
    'Loud and soft',
    ['dynamics_duel', 'charades'],
  ),
  Concept(
    'fast_slow',
    GradeBand.g12,
    ConceptArea.tempo,
    'Fast and slow',
    ['tempo_duel', 'charades'],
  ),
  Concept(
    'long_short',
    GradeBand.g12,
    ConceptArea.duration,
    'Long and short notes',
    ['note_value_quiz', 'duration_duel'],
  ),
  Concept(
    'count_sounds',
    GradeBand.g12,
    ConceptArea.pitch,
    'Counting the notes you hear',
    ['count_notes'],
  ),

  // --- Grades 3–4: treble notation, note values, simple metre, C major.
  Concept(
    'treble_staff',
    GradeBand.g34,
    ConceptArea.reading,
    'Notes on the treble staff',
    ['note_reading_treble', 'note_memory', 'note_order', 'line_space'],
  ),
  Concept(
    'ledger_middle_c',
    GradeBand.g34,
    ConceptArea.reading,
    'Ledger lines and middle C',
    ['ledger_leap'],
  ),
  Concept(
    'note_values',
    GradeBand.g34,
    ConceptArea.duration,
    'Whole, half, quarter, eighth notes',
    [
      'note_value_quiz',
      'duration_duel',
      'value_order',
      'connect_symbols',
      'connect_beats',
    ],
  ),
  Concept(
    'rests',
    GradeBand.g34,
    ConceptArea.duration,
    'Rests are silence',
    ['connect_rests'],
  ),
  Concept(
    'dotted_notes',
    GradeBand.g34,
    ConceptArea.duration,
    'The dot adds half again',
    ['dotted_sort'],
  ),
  Concept(
    'beats_per_bar',
    GradeBand.g34,
    ConceptArea.meter,
    'Beats add up to fill a bar',
    ['measure_fill', 'beat_count', 'beat_sort'],
  ),
  Concept(
    'time_signature',
    GradeBand.g34,
    ConceptArea.meter,
    'Reading the time signature',
    ['time_signature', 'which_beat', 'meter_detective'],
  ),
  Concept(
    'strong_weak_beat',
    GradeBand.g34,
    ConceptArea.meter,
    'Strong and weak beats',
    ['strong_beat'],
  ),
  Concept(
    'dynamics_marks',
    GradeBand.g34,
    ConceptArea.dynamics,
    'p and f (piano/forte)',
    ['dynamics_duel', 'connect_dynamics'],
  ),
  Concept(
    'tempo_terms',
    GradeBand.g34,
    ConceptArea.tempo,
    'Italian tempo words',
    ['tempo_duel', 'connect_tempo'],
  ),
  Concept(
    'rhythm_echo',
    GradeBand.g34,
    ConceptArea.duration,
    'Echo a rhythm you heard',
    ['rhythm_tap', 'melody_echo'],
  ),
  Concept(
    'steps_skips',
    GradeBand.g34,
    ConceptArea.pitch,
    'Steps and skips',
    ['step_skip', 'step_skip_bass'],
  ),
  Concept(
    'c_major_scale',
    GradeBand.g34,
    ConceptArea.scales,
    'The C major scale',
    ['scale_detective', 'in_scale'],
  ),
  Concept(
    'major_minor_ear',
    GradeBand.g34,
    ConceptArea.scales,
    'Major sounds bright, minor darker',
    ['major_minor_ear'],
  ),
  Concept(
    'song_form',
    GradeBand.g34,
    ConceptArea.form,
    'Verse and chorus; repeats',
    ['form_read'],
  ), // GAP: no form game

  // --- Grades 5–6: both clefs, accidentals, intervals, I/IV/V triads.
  Concept(
    'bass_clef',
    GradeBand.g56,
    ConceptArea.reading,
    'Notes on the bass staff',
    ['note_reading_bass', 'line_space_bass', 'note_order_bass'],
  ),
  Concept(
    'grand_staff',
    GradeBand.g56,
    ConceptArea.reading,
    'Two staves, two hands',
    ['grand_staff_read'],
  ),
  Concept(
    'clef_signs',
    GradeBand.g56,
    ConceptArea.reading,
    'Treble vs bass clef',
    ['which_clef'],
  ),
  Concept(
    'accidentals',
    GradeBand.g56,
    ConceptArea.pitch,
    'Sharps and flats',
    ['accidental_sort', 'accidental_sort_bass'],
  ),
  Concept(
    'enharmonics',
    GradeBand.g56,
    ConceptArea.pitch,
    'One key, two names (F♯ = G♭)',
    ['enharmonic'],
  ),
  Concept(
    'whole_half_step',
    GradeBand.g56,
    ConceptArea.pitch,
    'Whole steps and half steps',
    ['whole_half'],
  ),
  Concept(
    'key_signatures',
    GradeBand.g56,
    ConceptArea.scales,
    'Key signatures',
    ['key_sig'],
  ),
  Concept(
    'major_scales',
    GradeBand.g56,
    ConceptArea.scales,
    'Building major scales',
    ['scale_detective', 'scale_builder'],
  ),
  Concept(
    'intervals',
    GradeBand.g56,
    ConceptArea.intervals,
    'Intervals: distance between notes',
    [
      'interval_ear',
      'interval_ladder',
      'connect_intervals',
      'connect_line',
      'connect_line_bass',
    ],
  ),
  Concept(
    'triads',
    GradeBand.g56,
    ConceptArea.chords,
    'Major and minor triads',
    [
      'chord_quiz',
      'triad_builder',
      'major_minor_sort',
      'chord_listen_spike',
      'chord_play_along',
    ],
  ),
  Concept(
    'ties_slurs',
    GradeBand.g56,
    ConceptArea.articulation,
    'Ties and slurs',
    ['tie_slur'],
  ),
  Concept(
    'articulation',
    GradeBand.g56,
    ConceptArea.articulation,
    'Staccato and accents',
    ['articulation_read'],
  ),
  Concept(
    'beams',
    GradeBand.g56,
    ConceptArea.duration,
    'Beams and flags',
    ['beam_flag'],
  ),
  Concept(
    'anacrusis',
    GradeBand.g56,
    ConceptArea.meter,
    'The upbeat (anacrusis)',
    ['spot_upbeat'],
  ),
  Concept(
    'compound_meter',
    GradeBand.g56,
    ConceptArea.meter,
    'Compound metre (6/8)',
    ['time_signature'],
  ), // thin: read-only
  Concept(
    'syncopation',
    GradeBand.g56,
    ConceptArea.meter,
    'Off-beat accents (syncopation)',
    ['sync_read'],
  ), // GAP
  Concept(
    'triplets',
    GradeBand.g56,
    ConceptArea.duration,
    'Triplets and tuplets',
    ['triplet_read'],
  ), // GAP

  // --- Grades 7–8: minor keys, chord qualities, cadences, seventh chords.
  Concept(
    'circle_of_fifths',
    GradeBand.g78,
    ConceptArea.scales,
    'The circle of fifths',
    ['key_sig'],
  ), // thin
  Concept(
    'minor_scales',
    GradeBand.g78,
    ConceptArea.scales,
    'Natural and harmonic minor',
    ['scale_detective', 'scale_builder'],
  ),
  Concept(
    'chord_qualities',
    GradeBand.g78,
    ConceptArea.chords,
    'Diminished and augmented',
    ['chord_quiz', 'name_that_chord', 'chord_builder', 'major_minor_sort'],
  ),
  Concept(
    'seventh_chords',
    GradeBand.g78,
    ConceptArea.chords,
    'Seventh chords',
    ['triad_seventh'],
  ),
  Concept(
    'chord_symbols',
    GradeBand.g78,
    ConceptArea.chords,
    'Lead-sheet chord symbols',
    ['chord_chart', 'name_that_chord'],
  ),
  Concept(
    'cadences',
    GradeBand.g78,
    ConceptArea.harmony,
    'How phrases end',
    ['cadence_workshop'],
  ),
  Concept(
    'harmonic_function',
    GradeBand.g78,
    ConceptArea.harmony,
    'Tonic, subdominant, dominant',
    ['harmony_quiz', 'function_ear', 'connect_degrees'],
  ),
  Concept(
    'roman_numerals',
    GradeBand.g78,
    ConceptArea.harmony,
    'Roman numerals',
    ['roman_numeral'],
  ),
  Concept(
    'melodic_dictation',
    GradeBand.g78,
    ConceptArea.reading,
    'Write down a melody you hear',
    ['melody_dictation'],
  ),
  Concept(
    'phrasing_qa',
    GradeBand.g78,
    ConceptArea.form,
    'Question-and-answer phrases',
    ['ending_detective', 'question_answer'],
  ),
  Concept(
    'musical_form',
    GradeBand.g78,
    ConceptArea.form,
    'Form: ABA, rondo, theme & variations',
    ['form_read', 'analysis_view'],
  ),
  Concept(
    'modulation',
    GradeBand.g78,
    ConceptArea.harmony,
    'Changing key (modulation)',
    ['modulation_ear'],
  ),

  // --- Grades 9–10: inversions & 7ths, function, transposition, score reading.
  Concept(
    'inversions',
    GradeBand.g910,
    ConceptArea.chords,
    'Chord inversions',
    ['chord_builder'],
  ),
  Concept(
    'transposing_instruments',
    GradeBand.g910,
    ConceptArea.transpose,
    'Transposing instruments',
    ['concert_pitch', 'transpose_write'],
  ),
  Concept(
    'tenor_clef',
    GradeBand.g910,
    ConceptArea.reading,
    'The tenor clef',
    ['note_reading_tenor'],
  ),
  Concept(
    'satb_voices',
    GradeBand.g910,
    ConceptArea.reading,
    'Reading four-part (SATB) music',
    ['duet', 'read_voice', 'which_voice', 'hear_voice', 'spacing_read'],
  ),
  Concept(
    'voice_leading',
    GradeBand.g910,
    ConceptArea.harmony,
    'Part-writing: parallel fifths & octaves',
    ['spot_parallels'],
  ),
  Concept(
    'score_reading',
    GradeBand.g910,
    ConceptArea.reading,
    'Following a multi-staff score',
    ['staff_runner', 'grand_staff_read'],
  ),
  Concept(
    'ornaments',
    GradeBand.g910,
    ConceptArea.articulation,
    'Ornaments (trill, mordent, turn)',
    ['ornament_read'],
  ), // GAP: reading drill
  Concept(
    'modes',
    GradeBand.g910,
    ConceptArea.scales,
    'Church modes (Dorian, etc.)',
    ['mode_ear'],
  ),
  Concept(
    'instrument_families',
    GradeBand.g910,
    ConceptArea.timbre,
    'Instrument families / the orchestra',
    ['instrument_family'],
  ),
  Concept('reading_fluency', GradeBand.g34, ConceptArea.reading,
      'Reading notes fluently (both clefs)', [
    'place_note_treble',
    'place_note_bass',
    'falling_notes',
    'falling_notes_bass',
    'note_whack',
    'note_whack_bass',
    'note_snake',
    'note_snake_bass',
    'odd_one_out',
    'odd_one_out_bass',
    'staff_runner',
    'staff_runner_bass',
  ]),
  Concept(
    'aural_memory',
    GradeBand.g12,
    ConceptArea.aural,
    'Echo and remember what you hear',
    ['echo_sequence', 'command_caller'],
  ),
  Concept(
    'sing_what_you_hear',
    GradeBand.g34,
    ConceptArea.aural,
    'Sing back a pitch or interval',
    ['sing_back', 'sing_interval', 'free_sing', 'perform_read'],
  ),
  Concept('play_keyboard', GradeBand.g34, ConceptArea.technique,
      'Find and play notes on the keyboard', [
    'key_find',
    'key_find_bass',
    'key_name',
    'key_ear',
    'key_melody',
    'key_chord',
    'keyboard_ode',
    'keyboard_play_along',
    'falling_keys',
    'chord_grip_hero',
  ]),
  Concept('play_cello', GradeBand.g34, ConceptArea.technique,
      'Play the cello: strings, fingers, bowing', [
    'cello_string_quiz',
    'cello_finger_quiz',
    'cello_play_along',
    'cello_play_it',
    'cello_tuner',
    'bowing',
  ]),
  Concept('play_guitar', GradeBand.g34, ConceptArea.technique,
      'Play the guitar: strings, tab, strumming', [
    'guitar_string_quiz',
    'guitar_tab_read',
    'guitar_play_along',
    'strum_toy',
  ]),
  Concept(
    'play_percussion',
    GradeBand.g34,
    ConceptArea.technique,
    'Read and play a drum rhythm',
    ['drum_read'],
  ),
  Concept(
    'compose',
    GradeBand.g34,
    ConceptArea.creating,
    'Make up your own melody',
    ['my_melody', 'grid_composer', 'melody_doodle'],
  ),
  Concept(
    'arrange_loops',
    GradeBand.g56,
    ConceptArea.creating,
    'Layer and arrange loops',
    ['loop_mixer', 'tracker'],
  ),
  Concept(
    'learn_songs',
    GradeBand.g12,
    ConceptArea.repertoire,
    'Learn and recognise real songs',
    ['song_book', 'sing_along', 'sing_mary', 'tune_quiz'],
  ),
];
