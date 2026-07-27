// THROWAWAY: can our LilyPond reader parse what the agents wrote, and what did
// they actually claim? Syntactic validity is the first gate on any transcription.
import 'dart:io';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

const dir = '/private/tmp/claude-501/-Users-christianstrobele-code-mus/'
    'f971b814-7740-4387-8e93-ae7a495f8965/scratchpad/vlm_omr';

void main() {
  test('parse agent transcriptions', () {
    for (final name in ['A1_agent1.ly', 'A1_agent2.ly', 'A2_agent1.ly']) {
      final f = File('$dir/$name');
      if (!f.existsSync()) {
        // ignore_for_file: avoid_print
        print('$name: MISSING');
        continue;
      }
      final src = f.readAsStringSync();
      try {
        final score = scoreFromLilyPond(src);
        final notes = score.measures
            .expand((m) => m.elements)
            .whereType<NoteElement>()
            .toList();
        final fingered = notes.where((n) => n.fingerings.isNotEmpty).toList();
        print('$name: PARSED  ${notes.length} notes, '
            '${fingered.length} fingered, ${score.measures.length} measures, '
            'clef ${score.clef}, key ${score.keySignature.fifths}');
        print('   fingerings: ${fingered.map((n) => n.fingerings.join()).join(' ')}');
        print('   unsure markers: ${'%% UNSURE'.allMatches(src).length}');
      } catch (e) {
        print('$name: PARSE FAILED — $e');
      }
    }
  });
}

extension on String {
  Iterable<Match> allMatches(String s) => RegExp(RegExp.escape(this)).allMatches(s);
}
