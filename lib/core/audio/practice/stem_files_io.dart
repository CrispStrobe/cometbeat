// Separated stems kept on DISK and memory-mapped read-only, so a whole song's
// stems cost the process (almost) nothing: a mapped file's pages are clean
// and file-backed — the kernel drops and re-reads them as it likes, and they
// do not count towards phys_footprint, which is what iOS's jetsam kills on.
// Measured on macOS: reading every sample of a mapped 132 MB file moved the
// footprint by 0 MB; an anonymous copy of it by 132 MB.
//
// The stems are written once (StemFileWriter, in the separation worker) and
// then only read (mapStemFiles, on the UI isolate), as planar float32 per
// stem: all left samples, then all right samples. The Float32List views make
// the mapped stems ordinary SeparatedStems for every consumer.
//
// POSIX only (macOS, iOS, Android, Linux) and 64-bit only; elsewhere
// [stemFilesSupported] is false and the caller keeps the stems in memory.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:ffi/ffi.dart';

/// Whether stems can live in mapped files here.
bool get stemFilesSupported =>
    sizeOf<IntPtr>() == 8 &&
    (Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isAndroid ||
        Platform.isLinux);

/// Where a split's stem files go: a fresh folder under the temp directory.
/// Earlier splits' folders are removed first — files still mapped by a live
/// player stay readable until unmapped (POSIX unlink semantics).
Directory newStemFolder() {
  final root = Directory('${Directory.systemTemp.path}/practice_stems');
  try {
    if (root.existsSync()) root.deleteSync(recursive: true);
  } on FileSystemException {
    // A file still open elsewhere: leave it.
  }
  root.createSync(recursive: true);
  return root.createTempSync('split');
}

/// Writes stems block by block, in any order, into one planar file per stem.
class StemFileWriter {
  StemFileWriter(this.folder, this.frames);

  final Directory folder;
  final int frames;
  final _files = <String, RandomAccessFile>{};
  final _paths = <String, String>{};

  /// Writes frames `[start, start + left.length)` of stem [name].
  void write(String name, int start, Float32List left, Float32List right) {
    final f = _files.putIfAbsent(name, () {
      final path = '${folder.path}/${_paths.length}.f32';
      _paths[name] = path;
      return File(path).openSync(mode: FileMode.write)
        ..truncateSync(frames * 8);
    });
    f
      ..setPositionSync(start * 4)
      ..writeFromSync(
        left.buffer.asUint8List(left.offsetInBytes, left.lengthInBytes),
      )
      ..setPositionSync((frames + start) * 4)
      ..writeFromSync(
        right.buffer.asUint8List(right.offsetInBytes, right.lengthInBytes),
      );
  }

  /// Closes every file; the stems' (name, path) pairs, in first-written order.
  List<({String name, String path})> close() {
    for (final f in _files.values) {
      f.closeSync();
    }
    return [for (final e in _paths.entries) (name: e.key, path: e.value)];
  }
}

/// Stems mapped from their files. [release] unmaps them and deletes the
/// files — after it, the stems' samples must not be touched again.
class MappedStems {
  MappedStems._(this.stems, this._maps, this._paths);

  final List<SeparatedStem> stems;
  final List<(Pointer<Void>, int)> _maps;
  final List<String> _paths;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    for (final (p, len) in _maps) {
      _munmap(p, len);
    }
    for (final path in _paths) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // already gone
      }
    }
  }
}

/// Maps [files] (from [StemFileWriter.close]) as stems of [frames] frames at
/// [sampleRate]. Throws [FileSystemException] when a file cannot be mapped;
/// whatever was mapped by then is unmapped again.
MappedStems mapStemFiles(
  List<({String name, String path})> files,
  int frames,
  int sampleRate,
) {
  final maps = <(Pointer<Void>, int)>[];
  final stems = <SeparatedStem>[];
  final bytes = frames * 8;
  try {
    for (final f in files) {
      final cPath = f.path.toNativeUtf8();
      final fd = _open(cPath, 0 /* O_RDONLY */);
      malloc.free(cPath);
      if (fd < 0) throw FileSystemException('open failed', f.path);
      final p =
          _mmap(nullptr, bytes, 1 /* PROT_READ */, 1 /* MAP_SHARED */, fd, 0);
      _close(fd);
      if (p.address == -1 || p == nullptr) {
        throw FileSystemException('mmap failed', f.path);
      }
      maps.add((p, bytes));
      final all = p.cast<Float>().asTypedList(frames * 2);
      stems.add(
        SeparatedStem(
          f.name,
          Float32List.sublistView(all, 0, frames),
          Float32List.sublistView(all, frames),
          sampleRate,
        ),
      );
    }
  } catch (_) {
    for (final (p, len) in maps) {
      _munmap(p, len);
    }
    rethrow;
  }
  return MappedStems._(stems, maps, [for (final f in files) f.path]);
}

final DynamicLibrary _libc = DynamicLibrary.process();
final _open = _libc.lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
    int Function(Pointer<Utf8>, int)>('open');
final _close =
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
final _mmap = _libc.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Size, Int32, Int32, Int32, Int64),
    Pointer<Void> Function(Pointer<Void>, int, int, int, int, int)>('mmap');
final _munmap = _libc.lookupFunction<Int32 Function(Pointer<Void>, Size),
    int Function(Pointer<Void>, int)>('munmap');
