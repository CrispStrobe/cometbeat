import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> a) {
  final dir = a[0];
  final failLog = File(a[1]).openWrite();
  var ok = 0, fail = 0, nonotes = 0;
  for (final f in Directory(dir).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.krn')) continue;
    final rel = f.path.replaceFirst('$dir/', '');
    try {
      final mp = multiPartScoreFromKern(f.readAsStringSync());
      final has = mp.parts.any(
        (p) => p.measures.any((m) => m.elements.any((e) => e is NoteElement)),
      );
      if (has) {
        ok++;
      } else {
        nonotes++;
        failLog.writeln('$rel\tNO_NOTES');
      }
    } catch (e) {
      fail++;
      var msg = e.toString().replaceAll('\n', ' ');
      if (msg.length > 90) msg = msg.substring(0, 90);
      failLog.writeln('$rel\t$msg');
    }
  }
  failLog.close();
  stdout.writeln('parseable=$ok fail=$fail no_notes=$nonotes');
}
