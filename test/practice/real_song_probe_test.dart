// Live probe: peak memory of "practise with your song" on a REAL song, stage by
// stage — decode → separate → mixture-consistent → beats → (slow down) —
// through the same code the screen runs (PROBE_PIPELINE=new, the default), or
// through a verbatim copy of the pipeline before the memory work
// (PROBE_PIPELINE=old, probe_legacy_pipeline.dart), so before and after are
// measured the same way. Skips unless PROBE_SONG names an audio file and
// libcrispasr + the separator model are here.
//
//   COMET_GLINT_LIB=<a glint ≥ 0.8.1 build, e.g. native/glint/src via cmake> \
//   PROBE_SONG="$HOME/Downloads/04 Carpet Crawlers.mp3" \
//   PROBE_MODEL=mini-bs-roformer PROBE_PIPELINE=new PROBE_SLOW=0.5 \
//   flutter test test/practice/real_song_probe_test.dart
//
// Without a glint library MP3 falls back to the pure-Dart decoder, which is
// slow and allocates very differently from the app — set COMET_GLINT_LIB.
//
// Metric: on macOS/iOS, phys_footprint (task_info TASK_VM_INFO) — what jetsam
// kills on. Unlike RSS it counts memory the kernel has COMPRESSED, so it does
// not flatter a run on a machine under memory pressure. Sampled every 20 ms on
// this isolate (the work runs on other isolates); each stage prints its peak,
// and the end prints the kernel's own lifetime peak. RSS is printed beside it.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/practice/practice_mix.dart';
import 'package:comet_beat/core/audio/practice/practice_song_split.dart';
import 'package:comet_beat/core/audio/practice/song_audio_file.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_beats.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'probe_legacy_pipeline.dart';

int _mb(int bytes) => bytes ~/ (1024 * 1024);

typedef _TaskInfoC = Int32 Function(
  Uint32,
  Int32,
  Pointer<Int32>,
  Pointer<Uint32>,
);
typedef _TaskInfo = int Function(int, int, Pointer<Int32>, Pointer<Uint32>);

/// phys_footprint and the kernel's lifetime peak of it, via
/// task_info(TASK_VM_INFO). Null off Apple platforms.
class _Footprint {
  _Footprint._(this._taskInfo, this._task);

  static _Footprint? open() {
    if (!Platform.isMacOS && !Platform.isIOS) return null;
    final lib = DynamicLibrary.process();
    return _Footprint._(
      lib.lookupFunction<_TaskInfoC, _TaskInfo>('task_info'),
      lib.lookup<Uint32>('mach_task_self_').value,
    );
  }

  final _TaskInfo _taskInfo;
  final int _task;
  final _buf = calloc<Int32>(128);
  final _count = calloc<Uint32>();

  // struct task_vm_info: phys_footprint at byte 144 (rev1),
  // ledger_phys_footprint_peak at byte 168 (rev3).
  ({int now, int peak}) read() {
    _count.value = 128;
    if (_taskInfo(_task, 22 /* TASK_VM_INFO */, _buf, _count) != 0) {
      return (now: 0, peak: 0);
    }
    final b = _buf.cast<Int64>();
    return (now: b[144 ~/ 8], peak: _count.value >= 44 ? b[168 ~/ 8] : 0);
  }
}

/// Samples memory every 20 ms and keeps the peak per named stage.
class _Meter {
  _Meter() {
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _sample());
  }

  final _fp = _Footprint.open();
  late final Timer _timer;
  final _sw = Stopwatch()..start();
  String? _stage;
  int _peakFp = 0, _peakRss = 0;

  int get _footprint => _fp?.read().now ?? 0;

  void _sample() {
    final f = _footprint, r = ProcessInfo.currentRss;
    if (f > _peakFp) _peakFp = f;
    if (r > _peakRss) _peakRss = r;
  }

  /// Ends the current stage (printing its peaks) and starts [next].
  void stage(String? next) {
    if (next != null && next == _stage) return;
    _sample();
    if (_stage != null) {
      // ignore: avoid_print
      print('probe: ${_stage!.padRight(11)} footprint peak ${_mb(_peakFp)} MB '
          '(after ${_mb(_footprint)}) · rss peak ${_mb(_peakRss)} MB · '
          '${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    }
    _stage = next;
    _peakFp = _footprint;
    _peakRss = ProcessInfo.currentRss;
    _sw.reset();
  }

  void close() {
    stage(null);
    _timer.cancel();
    // ignore: avoid_print
    print('probe: lifetime footprint peak ${_mb(_fp?.read().peak ?? 0)} MB · '
        'maxRss ${_mb(ProcessInfo.maxRss)} MB');
  }
}

// Top-level: an inline closure would share the test body's context (and the
// meter's Timer, which cannot cross isolates).
Future<StretchPlan?> _plan(Float32List guide, double speed) => Isolate.run(
      () => planStretch(
        Float64List.fromList(guide),
        1 / speed,
        quality: StretchQuality.deep,
      ),
    );

void main() {
  final env = Platform.environment;
  final path = env['PROBE_SONG'];
  final modelName = env['PROBE_MODEL'] ?? 'mini-bs-roformer';
  final legacy = env['PROBE_PIPELINE'] == 'old';
  final slow = double.tryParse(env['PROBE_SLOW'] ?? '');
  // PROBE_INMEMORY=1: keep the stems in memory even where they could be
  // mapped from disk (what Windows and 32-bit devices do).
  final inMemory = env['PROBE_INMEMORY'] == '1';
  final model = CrispasrSeparatorModel.values.firstWhere(
    (m) => m != CrispasrSeparatorModel.auto && m.registryBackend == modelName,
    orElse: () => CrispasrSeparatorModel.miniBsRoformer,
  );

  test(
    'real song: memory per stage '
    '(${model.registryBackend}, '
    '${legacy ? 'old' : inMemory ? 'new, in memory' : 'new'} pipeline)',
    () async {
      if (path == null || !File(path).existsSync()) {
        markTestSkipped('set PROBE_SONG to an audio file');
        return;
      }
      if (!await crispasrSeparatorAvailable(model)) {
        markTestSkipped('${model.registryBackend} not available here');
        return;
      }
      final bytes = File(path).readAsBytesSync();
      final meter = _Meter()..stage('start');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      meter.stage('decode');
      final List<SeparatedStem> stems;
      void Function() release = () {};
      if (legacy) {
        final song = await decodeSongFile(path, bytes);
        expect(song, isNotNull);
        meter.stage('separate');
        final raw = await legacySeparate(
          song!.left,
          song.right,
          song.sampleRate,
          model,
        );
        expect(raw, isNotNull);
        meter.stage('consistent');
        stems = await legacyConsistent(raw!, song);
        meter.stage('beats');
        await crispasrBeatGrid(song.mono(), song.sampleRate);
      } else {
        final s = await splitSongForPractice(
          path,
          bytes,
          model: model,
          inMemory: inMemory,
          onPhase: (phase, _) => meter.stage(
            switch (phase) {
              PracticeSplitPhase.decoding => 'decode',
              PracticeSplitPhase.separating => 'separate',
              PracticeSplitPhase.finishing => 'consistent',
            },
          ),
        );
        stems = s.stems;
        release = s.release;
        meter.stage('beats');
        await crispasrBeatGrid32(s.beatMono, s.beatRate);
      }
      meter.stage('playing');
      // What stays alive while the learner practises.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (slow != null) {
        meter.stage('slow ${(slow * 100).round()}%');
        if (legacy) {
          final out = await legacySlow(stems, slow);
          expect(out.first.frames, greaterThan(stems.first.frames));
        } else {
          final region = StemRegion(stems);
          final guide = await region.stretchGuide();
          final plan = await _plan(guide, slow);
          final slowed = StemRegion(stems, plan: plan);
          expect(slowed.frames, greaterThan(stems.first.frames));
          // What the player renders: its first 6 s, window by window.
          for (var at = 0; at < 6 * slowed.sampleRate; at += 22050) {
            for (var k = 0; k < slowed.count; k++) {
              slowed.window(k, at, 22050);
            }
          }
        }
      }
      meter.close();
      final f = stems.first;
      final frames = f.frames, rate = f.sampleRate, count = stems.length;
      release();
      // ignore: avoid_print
      print('probe: $count stems × $frames frames @ $rate Hz '
          '(${(frames / rate).toStringAsFixed(1)} s)');
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}
