// describeSriItem — turns an opaque SRI item ID (`<module>.<skill>.<detail>`)
// into a readable "tricky spots" label. weak_spot_test hits a couple of arms;
// this drives every module branch (note_values / note_reading / keyboard /
// key_sig / chords / harmony / expression / default) and the _prettify
// fallbacks, asserting the l10n-independent arms exactly.
import 'package:comet_beat/features/progress/sri_item_label.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('labels every SRI namespace', (tester) async {
    final out = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context)!;
            String d(String id) => describeSriItem(l10n, id);
            out['nv.symbol'] = d('note_values.symbol.quarter');
            out['nv.symbol.bad'] = d('note_values.symbol.zzz');
            out['nv.rhythm'] = d('note_values.rhythm');
            out['nv.other'] = d('note_values.foo.bar');
            out['nr.clef'] = d('note_reading.treble.g4');
            out['nr.line_space'] = d('note_reading.line_space');
            out['nr.order'] = d('note_reading.order');
            out['nr.ledger'] = d('note_reading.ledger');
            out['nr.melody'] = d('note_reading.melody');
            out['nr.dictation'] = d('note_reading.dictation');
            out['nr.other'] = d('note_reading.weird.thing');
            out['kb.find'] = d('keyboard.find.c4');
            out['kb.other'] = d('keyboard.scales.major');
            out['key_sig'] = d('key_sig.g');
            out['chords.triad'] = d('chords.triad.c_major');
            out['chords.other'] = d('chords.progression.turnaround');
            out['harmony.dom'] = d('harmony.function.c_dominant');
            out['harmony.tonic'] = d('harmony.function.g_tonic');
            out['harmony.sub'] = d('harmony.function.f_subdominant');
            out['harmony.other'] = d('harmony.function.d_leadingtone');
            out['expression'] = d('expression.crescendo');
            out['default'] = d('unknown_module.some.detail');
            return const SizedBox();
          },
        ),
      ),
    );

    // l10n-independent arms — assert exactly.
    expect(out['nr.clef'], 'G4 · Treble');
    expect(out['kb.find'], 'C4 · Find the Key');
    expect(out['key_sig'], 'G major');
    expect(out['chords.triad'], 'C major');
    expect(out['harmony.dom'], 'C · Dominant');
    expect(out['harmony.other'], 'D · Leadingtone'); // _prettify fallback
    expect(out['nv.symbol.bad'], 'Zzz'); // _prettify fallback
    expect(out['nv.other'], 'Bar');
    expect(out['default'], 'Detail');

    // l10n-backed arms — non-empty and correctly routed.
    expect(out['nv.rhythm'], 'Rhythm Echo');
    expect(out['nr.line_space'], 'Line or Space?');
    expect(out['nr.order'], 'Note Order');
    expect(out['nr.ledger'], 'Ledger Leap');
    expect(out['nr.melody'], 'Melody Echo');
    expect(out['nr.dictation'], 'Melody Dictation');
    expect(out['expression'], 'Fast or Loud?');

    // Everything produced a non-empty label.
    expect(out.values, everyElement(isNotEmpty));
  });
}
