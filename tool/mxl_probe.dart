// Compare two MusicXML files through the app's own reader.
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> args) {
  for (final p in args) {
    final xml = readMusicXmlFromMxl(File(p).readAsBytesSync());
    final mp = multiPartScoreFromMusicXml(xml);
    var notes = 0, bars = 0;
    for (final part in mp.parts) {
      bars = part.measures.length > bars ? part.measures.length : bars;
      for (final m in part.measures) {
        for (final v in [m.elements, m.voice2, m.voice3, m.voice4]) {
          notes += v.whereType<NoteElement>().length;
        }
      }
    }
    stdout.writeln('${p.split('/').last}: parts=${mp.parts.length} '
        'bars=$bars notes=$notes');
  }
}
